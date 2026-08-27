#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,importlib.util,json,os,sys
from pathlib import Path
from urllib.parse import urlsplit
import psycopg2
R=Path(__file__).resolve().parents[1];M=R/'supabase/staging_only/20260828520000_730_acceptance_sublet_window.sql';SHA='0a421140146c3a38831084eebc396ee1f7a4dd0250958774554d57b4dc5d2374';REF='cdsmnqxtyyoeoznmbidd';PROD='vjdtsswhroyguxyfjdkt';APP='PDC_APPROVE_STAGING_MIGRATION_730'
def db():
 s=importlib.util.spec_from_file_location('b',Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py'));m=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(m);v=json.loads(m.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode());m.validate(v);u=v['PDC_STAGING_DATABASE_URL'];e=urlsplit(u)
 if v.get('PDC_STAGING_PROJECT_REF')!=REF or REF not in u or PROD in u:raise RuntimeError('refusing non-staging endpoint')
 os.environ.update({k:v[k] for k in ('PDC_STAGING_SSLROOTCERT','PDC_STAGING_SSLROOTCERT_SHA256')});sys.path.insert(0,str(R));from scripts.pdc_staging_runtime import trusted_sslrootcert
 return psycopg2.connect(host=e.hostname,port=e.port or 5432,user=e.username,password=e.password,dbname='postgres',sslmode='verify-full',sslrootcert=trusted_sslrootcert(),connect_timeout=15,application_name='pdc730_acceptance_sublet_window')
def state(c):
 with c.cursor() as x:
  q=["select max(version) filter(where version~'^[0-9]{14}$') from supabase_migrations.schema_migrations","select to_regclass('public.pdc_production_environment_sentinel') is not null","select to_regclass('public.pdc_authenticated_finalize_guard_jsonb_history_729') is not null","select to_regclass('public.pdc_authenticated_acceptance_sublet_window_history_730') is not null","select encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') from pg_proc p where p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure","select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and provider_uid='imap_uid:514' and source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' and status='processing' and queue_attempts=10","select count(*) from public.pdc_jobcard_attachment_import_receipts where receipt_id='d9eebe4a-1b7b-4c98-97bd-fc49fcd8fa6f'::uuid and estimated_hours_sum=7.46 and operation_count=5","select count(*) from public.vehicles where id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid","select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid"]
  a=[]
  for s in q:x.execute(s);a.append(x.fetchone()[0])
  return dict(zip(('head','production','prior','repair','create_hash','uid514','receipt','vehicle','ops'),a))
def main():
 p=argparse.ArgumentParser();p.add_argument('mode',choices=('preflight','apply','readback'));a=p.parse_args();c=db()
 try:
  b=state(c);src=M.read_text(encoding='utf-8');r={'ok':False,'mode':a.mode,'production_touched':False,'migration_sha256':SHA}
  if hashlib.sha256(src.encode()).hexdigest()!=SHA:raise RuntimeError('730 source hash mismatch')
  pre=b['head']=='20260828510000' and not b['production'] and b['prior'] and not b['repair'] and b['create_hash']=='1a64264717a7db6e73d34a2b1cdaa971d12ca128facefdd51ce69b9d0172c957' and b['uid514']==1 and b['receipt']==1 and b['vehicle']==1 and b['ops']==5
  if a.mode!='readback' and not pre:raise RuntimeError(f'730 prestate mismatch: {b}')
  if a.mode=='preflight':r.update(ok=True,before=b,committed=False)
  elif a.mode=='apply':
   if os.environ.get(APP)!=f'apply migration 730 acceptance sublet window source {SHA}':raise RuntimeError('approval phrase missing')
   with c:
    with c.cursor() as x:x.execute(src.removeprefix('BEGIN;\n').removesuffix('COMMIT;\n'))
   after=state(c)
   if after['head']!='20260828520000' or not after['repair'] or after['production'] or after['uid514']!=1 or after['receipt']!=1 or after['vehicle']!=1 or after['ops']!=5:raise RuntimeError(f'730 poststate mismatch: {after}')
   r.update(ok=True,before=b,after=after,committed=True)
  else:
   if b['head']!='20260828520000' or not b['repair'] or b['production']:raise RuntimeError(f'730 readback mismatch: {b}')
   r.update(ok=True,after=b,committed=False)
  print(json.dumps(r,sort_keys=True,separators=(',',':')));return 0
 except Exception as e:c.rollback();print(json.dumps({'ok':False,'mode':a.mode,'production_touched':False,'migration_sha256':SHA,'error':str(e)[:1200]},sort_keys=True,separators=(',',':')));return 1
 finally:c.close()
if __name__=='__main__':raise SystemExit(main())
