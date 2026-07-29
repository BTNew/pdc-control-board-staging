#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
EXPECTED_REF='cdsmnqxtyyoeoznmbidd'; PRODUCTION_REF='vjdtsswhroyguxyfjdkt'; EXPECTED_BRANCH='qa/workshop-bulletproof-20260728'
VERSION='110'; NAME='restore_parts_eta_snapshot_authority'; MIGRATION=ROOT/'supabase'/'staging_only'/'110_restore_parts_eta_snapshot_authority.sql'
ROLLBACK_ONLY=os.getenv('PDC_MIGRATION_ROLLBACK_ONLY','1').lower() not in {'0','false','no'}
PROTECTED=('vehicles','vehicle_work_items','vehicle_parts_updates','pdc_sublet_bookings','pdc_authenticated_email_operation_lines','workshop_bookings')
def scalar(cur,q,p=()): cur.execute(q,p); r=cur.fetchone(); return r[0] if r else None
def body(s):
 s=s.strip(); s=s[6:].lstrip() if s.lower().startswith('begin;') else s; s=s[:-7].rstrip() if s.lower().endswith('commit;') else s; return s
def sig(cur,t):
 cur.execute(f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)),'')) from public.{t} x"); n,d=cur.fetchone(); return int(n),str(d)
def checks(cur):
 definition=scalar(cur,"select pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure)") or ''
 for token in ("'operation_line_id'","'estimated_hours'","'estimated_hours_source'","'parts_update'","'previous_worst_eta'","'sublet_booking'","'provider_names'"):
  if token not in definition: raise RuntimeError(f'snapshot definition missing {token}')
 if scalar(cur,"select to_regprocedure('public.update_pdc_parts_eta(uuid,integer,date)')") is None: raise RuntimeError('Parts ETA mutation RPC missing')
 uid=scalar(cur,"select auth_user_id from public.pdc_user_roles where role in ('administrator','operator') and active and auth_user_id is not null order by case role when 'administrator' then 0 else 1 end limit 1")
 if uid is None: raise RuntimeError('no staging operator available for snapshot verification')
 scalar(cur,"select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(uid),'role':'authenticated'}),))
 payload=scalar(cur,'select public.get_pdc_email_vehicle_location_snapshot()') or {}
 if not payload.get('ok'): raise RuntimeError(f'snapshot failed: {payload}')
 rows=payload.get('data',{}).get('vehicles',[]); by_id={str(row.get('id')):row for row in rows}
 cur.execute("""select v.id::text,v.stock_number,pu.worst_eta::text from public.vehicles v join lateral(
   select p.worst_eta from public.vehicle_parts_updates p where p.vehicle_id=v.id order by p.updated_at desc,p.id desc limit 1
 ) pu on true where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
 and exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v.id)
 and pu.worst_eta is not null order by v.id""")
 expected=cur.fetchall()
 if not expected: raise RuntimeError('staging has no authoritative Parts ETA fixture to verify')
 for vehicle_id,stock,worst_eta in expected:
  actual=(by_id.get(vehicle_id,{}).get('parts_update') or {}).get('worst_eta')
  if str(actual)!=str(worst_eta): raise RuntimeError(f'Parts ETA projection mismatch for {stock}: {actual!r} != {worst_eta!r}')
 if not all('operation_lines' in row and 'parts_update' in row and 'sublet_booking' in row for row in rows): raise RuntimeError('snapshot projection shape incomplete')
 return {'snapshotVehicles':len(rows),'authoritativePartsEtasVerified':len(expected),'operationIdentityPreserved':True,'subletProjectionRestored':True}
def main():
 branch=subprocess.check_output(['git','-C',str(ROOT),'branch','--show-current'],text=True).strip()
 if branch!=EXPECTED_BRANCH: raise RuntimeError(f'refusing migration 110 from branch {branch!r}')
 load_local_env(); url=required('PDC_STAGING_DATABASE_URL'); assert_staging_target(database_url=url)
 if PRODUCTION_REF in url.lower() or EXPECTED_REF not in url.lower(): raise RuntimeError('refusing endpoint outside staging')
 source=MIGRATION.read_text(encoding='utf-8'); sha=hashlib.sha256(source.encode()).hexdigest(); conn=get_conn(); conn.autocommit=False
 try:
  with conn.cursor() as cur:
   cur.execute("set local statement_timeout='120s'"); cur.execute('lock table supabase_migrations.schema_migrations in exclusive mode')
   if scalar(cur,'select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s',(EXPECTED_REF,))!=1: raise RuntimeError('PDC_STAGING_SENTINEL_MISMATCH')
   existing=scalar(cur,'select count(*) from supabase_migrations.schema_migrations where version=%s',(VERSION,))
   if existing:
    cur.execute('select name,statements from supabase_migrations.schema_migrations where version=%s',(VERSION,)); name,statements=cur.fetchone(); recorded=(statements or [''])[0]
    if name!=NAME or hashlib.sha256(recorded.encode()).hexdigest()!=sha: raise RuntimeError('migration 110 ledger checksum/name mismatch')
    result=checks(cur); conn.rollback(); print(json.dumps({'status':'already_applied','migration':VERSION,'sourceSha256':sha,**result,'productionChanged':False},sort_keys=True)); return 0
   head=str(scalar(cur,'select version from supabase_migrations.schema_migrations order by version::int desc limit 1'))
   if head!='109': raise RuntimeError(f'migration head must be 109, found {head}')
   before={t:sig(cur,t) for t in PROTECTED}; cur.execute(body(source)); result=checks(cur); after={t:sig(cur,t) for t in PROTECTED}
   if before!=after: raise RuntimeError('protected operational signatures changed')
   if ROLLBACK_ONLY:
    conn.rollback(); print(json.dumps({'status':'rollback_verified','migration':VERSION,'sourceSha256':sha,**result,'protectedOperationalSignaturesUnchanged':True,'productionChanged':False},sort_keys=True)); return 0
   cur.execute('insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)',(VERSION,[source],NAME)); conn.commit(); print(json.dumps({'status':'applied','migration':VERSION,'sourceSha256':sha,**result,'protectedOperationalSignaturesUnchanged':True,'productionChanged':False},sort_keys=True)); return 0
 finally: conn.close()
if __name__=='__main__':
 try: raise SystemExit(main())
 except Exception as e: print(f'MIGRATION_110_FAILED: {e}',file=sys.stderr); raise SystemExit(1)
