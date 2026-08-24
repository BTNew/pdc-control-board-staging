"""Create/round-trip verify an encrypted backup of every live public staging table.

All plaintext remains in memory. The exact live catalog/count capture is bound into
the encrypted payload and secret-free manifest. Production and unknown targets fail closed.
"""
from __future__ import annotations
import argparse, concurrent.futures, datetime as dt, gzip, hashlib, json, secrets, threading, time, urllib.error, urllib.request
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from pdc_staging_management_migration import STAGING_REF, PRODUCTION_REF, _token

PROFILE_ENV=Path(r"C:\Users\nwmgr\AppData\Local\hermes\profiles\website-development-lead\.env")
AAD=b"pdc-staging-full-public-backup-v2:cdsmnqxtyyoeoznmbidd"
PAGE=100000

def canonical(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')
def load_key():
    values={}
    for raw in PROFILE_ENV.read_text(encoding='utf-8-sig').splitlines():
        line=raw.strip()
        if line and not line.startswith('#') and '=' in line:
            k,v=line.split('=',1); values[k.strip()]=v.strip().strip('"').strip("'")
    if values.get('PDC_STAGING_PROJECT_REF')!=STAGING_REF or STAGING_REF not in values.get('PDC_STAGING_SUPABASE_URL','') or PRODUCTION_REF in values.get('PDC_STAGING_SUPABASE_URL',''):
        raise RuntimeError('PDC_BACKUP_TARGET_GUARD_FAILED')
    secret=values.get('PDC_BACKUP_ENCRYPTION_KEY')
    if not secret: raise RuntimeError('PDC_BACKUP_KEY_MISSING')
    return hashlib.sha256(b'pdc-staging-full-public-backup-v2\x00'+secret.encode()).digest()
_TOKEN=None
_RATE_LOCK=threading.Lock()
_NEXT_REQUEST=0.0
def ro(sql):
    global _TOKEN,_NEXT_REQUEST
    if _TOKEN is None: _TOKEN=_token()
    for attempt in range(8):
        with _RATE_LOCK:
            delay=max(0.0,_NEXT_REQUEST-time.monotonic())
            if delay: time.sleep(delay)
            _NEXT_REQUEST=time.monotonic()+0.55
        request=urllib.request.Request(
            f'https://api.supabase.com/v1/projects/{STAGING_REF}/database/query/read-only',
            data=json.dumps({'query':'SET TRANSACTION READ ONLY;\n'+sql}).encode(),method='POST',
            headers={'Authorization':'Bearer '+_TOKEN,'Content-Type':'application/json','User-Agent':'pdc-staging-full-backup/2.0'})
        try:
            with urllib.request.urlopen(request,timeout=300) as response: return json.load(response)
        except urllib.error.HTTPError as exc:
            if exc.code!=429 or attempt==7: raise
            time.sleep(min(30,2**attempt))
    raise RuntimeError('PDC_BACKUP_READ_RETRIES_EXHAUSTED')
def qident(name): return '"'+name.replace('"','""')+'"'
def read_table(name):
    rows=[]; offset=0
    while True:
        result=ro(f'select to_jsonb(t) as row from public.{qident(name)} t order by to_jsonb(t)::text offset {offset} limit {PAGE};')
        if not isinstance(result,list): raise RuntimeError('PDC_BACKUP_READ_INVALID:'+name)
        page=[x['row'] for x in result]
        rows.extend(page)
        if len(page)<PAGE: return rows
        offset+=PAGE

def verify(encrypted_path,manifest_path):
    manifest=json.loads(Path(manifest_path).read_text(encoding='utf-8'))
    core=dict(manifest); recorded=core.pop('backup_manifest_sha256')
    if hashlib.sha256(canonical(core)).hexdigest()!=recorded: raise RuntimeError('PDC_BACKUP_MANIFEST_HASH_MISMATCH')
    encrypted=Path(encrypted_path).read_bytes()
    if hashlib.sha256(encrypted).hexdigest()!=manifest['encrypted_backup_sha256']: raise RuntimeError('PDC_BACKUP_ENCRYPTED_HASH_MISMATCH')
    raw=gzip.decompress(AESGCM(load_key()).decrypt(encrypted[:12],encrypted[12:],AAD))
    if len(raw)!=manifest['raw_bytes'] or hashlib.sha256(raw).hexdigest()!=manifest['raw_sha256']: raise RuntimeError('PDC_BACKUP_RAW_HASH_MISMATCH')
    payload=json.loads(raw)
    if payload['catalog_sha256']!=manifest['catalog_sha256'] or set(payload['tables'])!=set(manifest['table_counts']): raise RuntimeError('PDC_BACKUP_COVERAGE_MISMATCH')
    for name,rows in payload['tables'].items():
        if len(rows)!=manifest['table_counts'][name] or hashlib.sha256(canonical(rows)).hexdigest()!=manifest['table_sha256'][name]: raise RuntimeError('PDC_BACKUP_TABLE_MISMATCH:'+name)
    return {'status':'BACKUP_ROUND_TRIP_VERIFIED','backup_manifest_sha256':recorded,'encrypted_backup_sha256':manifest['encrypted_backup_sha256'],'table_count':len(payload['tables']),'total_rows':sum(manifest['table_counts'].values())}
def create(catalog_path,output_dir):
    catalog=json.loads(Path(catalog_path).read_text(encoding='utf-8'))
    if catalog.get('project_ref')!=STAGING_REF or not catalog.get('production_sentinel_absent') or catalog.get('staging_sentinel_rows')!=1: raise RuntimeError('PDC_BACKUP_CATALOG_TARGET_INVALID')
    if catalog.get('monitor')!={'active_mailboxes':0,'active_writers':0,'gateway_instance_id':None,'outbound_email_enabled':False,'pilot_enabled':False,'running_status':'stopped'}: raise RuntimeError('PDC_BACKUP_WRITERS_NOT_STOPPED')
    names=sorted(x['name'] for x in catalog['tables'])
    tables={}; counts={}; hashes={}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        future_rows={pool.submit(read_table,name):name for name in names}
        for future in concurrent.futures.as_completed(future_rows):
            name=future_rows[future]; rows=future.result(); tables[name]=rows; counts[name]=len(rows); hashes[name]=hashlib.sha256(canonical(rows)).hexdigest()
    tables={name:tables[name] for name in names}; counts={name:counts[name] for name in names}; hashes={name:hashes[name] for name in names}
    if counts!=catalog['row_counts']: raise RuntimeError('PDC_BACKUP_LIVE_COUNT_DRIFT')
    def live_count(name):
        result=ro(f'select count(*)::bigint as n from public.{qident(name)};')
        return name,int(result[0]['n'])
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        verify_counts=dict(pool.map(live_count,names))
    if verify_counts!=counts: raise RuntimeError('PDC_BACKUP_POSTREAD_COUNT_DRIFT')
    created=dt.datetime.now(dt.timezone.utc).isoformat()
    payload={'schema':'pdc-staging-full-public-backup-v2','project_ref':STAGING_REF,'created_at_utc':created,'catalog_sha256':catalog['catalog_sha256'],'tables':tables}
    raw=canonical(payload); compressed=gzip.compress(raw,compresslevel=9,mtime=0); nonce=secrets.token_bytes(12); encrypted=nonce+AESGCM(load_key()).encrypt(nonce,compressed,AAD)
    core={'schema':'pdc-staging-full-public-backup-manifest-v2','project_ref':STAGING_REF,'created_at_utc':created,'encryption':'AES-256-GCM','aad':AAD.decode(),'catalog_sha256':catalog['catalog_sha256'],'table_count':len(names),'total_rows':sum(counts.values()),'table_counts':counts,'table_sha256':hashes,'raw_bytes':len(raw),'raw_sha256':hashlib.sha256(raw).hexdigest(),'gzip_bytes':len(compressed),'gzip_sha256':hashlib.sha256(compressed).hexdigest(),'encrypted_bytes':len(encrypted),'encrypted_backup_sha256':hashlib.sha256(encrypted).hexdigest()}
    digest=hashlib.sha256(canonical(core)).hexdigest(); manifest=dict(core,backup_manifest_sha256=digest)
    output_dir.mkdir(parents=True,exist_ok=True); ep=output_dir/f'pdc-staging-full-{digest}.json.gz.aesgcm'; mp=output_dir/f'pdc-staging-full-{digest}.manifest.json'
    ep.write_bytes(encrypted); mp.write_text(json.dumps(manifest,indent=2,sort_keys=True),encoding='utf-8')
    result=verify(ep,mp); result.update({'encrypted_path':str(ep.resolve()),'manifest_path':str(mp.resolve()),'raw_bytes':len(raw)})
    return result

def main():
    p=argparse.ArgumentParser(); s=p.add_subparsers(dest='cmd',required=True)
    c=s.add_parser('create'); c.add_argument('--catalog',type=Path,required=True); c.add_argument('--output-dir',type=Path,required=True)
    v=s.add_parser('verify'); v.add_argument('--encrypted',type=Path,required=True); v.add_argument('--manifest',type=Path,required=True)
    a=p.parse_args(); r=create(a.catalog,a.output_dir) if a.cmd=='create' else verify(a.encrypted,a.manifest); print(json.dumps(r,indent=2,sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
