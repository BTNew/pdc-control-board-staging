#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,importlib.util,json,os,sys
from pathlib import Path
from urllib.parse import urlsplit
import psycopg2
R=Path(__file__).resolve().parents[1];M=R/'supabase/staging_only/20260828510000_729_agentic_finalize_guard_jsonb_precedence.sql';SHA='8d60833cbcd911363c11678424266c5c5a9049f2b34474c756ffec49384cd088';REF='cdsmnqxtyyoeoznmbidd';PROD='vjdtsswhroyguxyfjdkt';APP='PDC_APPROVE_STAGING_MIGRATION_729'
def db():
 s=importlib.util.spec_from_file_location('b',Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py'));m=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(m);v=json.loads(m.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode());m.validate(v);u=v['PDC_STAGING_DATABASE_URL'];e=urlsplit(u)
 if v.get('PDC_STAGING_PROJECT_REF')!=REF or REF not in u or PROD in u:raise RuntimeError('refusing non-staging endpoint')
 os.environ.update({k:v[k] for k in ('PDC_STAGING_SSLROOTCERT','PDC_STAGING_SSLROOTCERT_SHA256')});sys.path.insert(0,str(R));from scripts.pdc_staging_runtime import trusted_sslrootcert
 return psycopg2.connect(host=e.hostname,port=e.port or 5432,user=e.username,password=e.password,dbname='postgres',sslmode='verify-full',sslrootcert=trusted_sslrootcert(),connect_timeout=15,application_name='pdc729_finalize_guard')
def state(c):
 with c.cursor() as x:
  q=["select max(version) filter(where version~'^[0-9]{14}$') from supabase_migrations.schema_migrations","select to_regclass('public.pdc_production_environment_sentinel') is not null","select to_regclass('public.pdc_authenticated_audit_guard_jsonb_history_728') is not null","select to_regclass('public.pdc_authenticated_finalize_guard_jsonb_history_729') is not null","select encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') from pg_proc p where p.oid='public.finalize_pdc_agentic_email_plan_502(jsonb)'::regprocedure","select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and provider_uid='imap_uid:514' and source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' and status='processing' and queue_attempts=10","select count(*) from public.pdc_jobcard_attachment_import_receipts where receipt_id='d9eebe4a-1b7b-4c98-97bd-fc49fcd8fa6f'::uuid and estimated_hours_sum=7.46 and operation_count=5","select count(*) from public.vehicles where id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid","select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid"]
  a=[]
  for s in q:x.execute(s);a.append(x.fetchone()[0])
  return dict(zip(('head','production','prior','repair','finalize_hash','uid514','receipt','vehicle','ops'),a))
def main():
 p=argparse.ArgumentParser();p.add_argument('mode',choices=('preflight','apply','readback'));a=p.parse_args();c=db()
 try:
  b=state(c);src=M.read_text(encoding='utf-8');r={'ok':False,'mode':a.mode,'production_touched':False,'migration_sha256':SHA}
  if hashlib.sha256(src.encode()).hexdigest()!=SHA:raise RuntimeError('729 source hash mismatch')
  pre=b['head']=='20260828500000' and not b['production'] and b['prior'] and not b['repair'] and b['finalize_hash']=='2118db555bf055d92358783b317a5ff4a1e6f28518c3470ffccc73d432d179f9' and b['uid514']==1 and b['receipt']==1 and b['vehicle']==1 and b['ops']==5
  if a.mode!='readback' and not pre:raise RuntimeError(f'729 prestate mismatch: {b}')
  if a.mode=='preflight':r.update(ok=True,before=b,committed=False)
  elif a.mode=='apply':
   if os.environ.get(APP)!=f'apply migration 729 finalize guard source {SHA}':raise RuntimeError('approval phrase missing')
   with c:
    with c.cursor() as x:x.execute(src.removeprefix('BEGIN;\n').removesuffix('COMMIT;\n'))
   after=state(c)
   if after['head']!='20260828510000' or not after['repair'] or after['production'] or after['uid514']!=1 or after['receipt']!=1 or after['vehicle']!=1 or after['ops']!=5:raise RuntimeError(f'729 poststate mismatch: {after}')
   r.update(ok=True,before=b,after=after,committed=True)
  else:
   if b['head']!='20260828510000' or not b['repair'] or b['production']:raise RuntimeError(f'729 readback mismatch: {b}')
   r.update(ok=True,after=b,committed=False)
  print(json.dumps(r,sort_keys=True,separators=(',',':')));return 0
 except Exception as e:c.rollback();print(json.dumps({'ok':False,'mode':a.mode,'production_touched':False,'migration_sha256':SHA,'error':str(e)[:1200]},sort_keys=True,separators=(',',':')));return 1
 finally:c.close()
if __name__=='__main__':raise SystemExit(main())
