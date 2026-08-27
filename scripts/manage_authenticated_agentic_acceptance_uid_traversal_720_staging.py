#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,importlib.util,json,os,sys
from pathlib import Path
from urllib.parse import urlsplit
import psycopg2
ROOT=Path(__file__).resolve().parents[1]; MIGRATION=ROOT/'supabase/staging_only/20260828420000_720_agentic_acceptance_uid_traversal.sql'; SHA='9dbf0951d5140c2c6aad04ee4ac885d5e33c0dae701a154e96052a98406f5690'; REF='cdsmnqxtyyoeoznmbidd'; PROD='vjdtsswhroyguxyfjdkt'; APPROVAL='PDC_APPROVE_STAGING_MIGRATION_720'
def connect():
 spec=importlib.util.spec_from_file_location('b720',Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')); m=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(m); vals=json.loads(m.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode()); m.validate(vals); url=vals['PDC_STAGING_DATABASE_URL']; ep=urlsplit(url)
 if vals.get('PDC_STAGING_PROJECT_REF')!=REF or REF not in url or PROD in url: raise RuntimeError('refusing non-staging endpoint')
 os.environ.update({k:vals[k] for k in ('PDC_STAGING_SSLROOTCERT','PDC_STAGING_SSLROOTCERT_SHA256')}); sys.path.insert(0,str(ROOT)); from scripts.pdc_staging_runtime import trusted_sslrootcert
 return psycopg2.connect(host=ep.hostname,port=ep.port or 5432,user=ep.username,password=ep.password,dbname='postgres',sslmode='verify-full',sslrootcert=trusted_sslrootcert(),connect_timeout=15,application_name='pdc720_uid_traversal_management')
def state(c):
 q=["select max(version) filter(where version~'^[0-9]{14}$') from supabase_migrations.schema_migrations","select to_regclass('public.pdc_production_environment_sentinel') is not null","select to_regclass('public.pdc_authenticated_agentic_acceptance_uid_parity_history_719') is not null","select to_regclass('public.pdc_authenticated_agentic_acceptance_uid_traversal_history_720') is not null","select encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') from pg_proc p where p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure","select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and provider_uid='imap_uid:514' and source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' and status='processing' and queue_attempts=10 and linked_vehicle_id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid","select count(*) from public.pdc_jobcard_attachment_import_receipts where receipt_id='d9eebe4a-1b7b-4c98-97bd-fc49fcd8fa6f'::uuid and estimated_hours_sum=7.46 and operation_count=5","select count(*) from public.vehicles where id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid and public.normalize_vehicle_stock_number(stock_number)='13016925' and lifecycle_state='active' and deleted_at is null","select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id='13cf8ae5-a27c-5c98-859d-3f029ecf9726'::uuid","select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled)","select count(*) from public.monitored_mailboxes where active"]
 with c.cursor() as x:
  vals=[]
  for sql in q:x.execute(sql); vals.append(x.fetchone()[0])
 return dict(zip(('head','production','prior_history','repair_history','function_hash','uid514','uid514_receipt','uid514_vehicle','uid514_ops','writes','mailboxes'),vals))
def main():
 p=argparse.ArgumentParser(); p.add_argument('mode',choices=('preflight','apply','readback')); a=p.parse_args(); c=connect()
 try:
  before=state(c); source=MIGRATION.read_text(encoding='utf-8'); result={'ok':False,'mode':a.mode,'production_touched':False,'migration_sha256':SHA}
  if hashlib.sha256(source.encode()).hexdigest()!=SHA: raise RuntimeError('720 source hash mismatch')
  pre=before['head']=='20260828410000' and not before['production'] and before['prior_history'] and not before['repair_history'] and before['function_hash']=='b3855874fb8cce643367d44755b0cd49a15fe05274d5fbaba3a57ceb4be901e7' and before['uid514']==1 and before['uid514_receipt']==1 and before['uid514_vehicle']==1 and before['uid514_ops']==5 and before['writes']==0 and before['mailboxes']==1
  if a.mode!='readback' and not pre: raise RuntimeError(f'720 exact staging prestate mismatch: {before}')
  if a.mode=='preflight': result.update(ok=True,before=before,committed=False)
  elif a.mode=='apply':
   if os.environ.get(APPROVAL)!=f'apply migration 720 UID traversal source {SHA}': raise RuntimeError('PDC_APPROVE_STAGING_MIGRATION_720 approval phrase missing')
   with c:
    with c.cursor() as x:x.execute(source.removeprefix('BEGIN;\n').removesuffix('COMMIT;\n'))
   after=state(c)
   if after['head']!='20260828420000' or not after['repair_history'] or after['function_hash']=='b3855874fb8cce643367d44755b0cd49a15fe05274d5fbaba3a57ceb4be901e7' or after['production'] or after['uid514']!=1 or after['uid514_receipt']!=1 or after['uid514_vehicle']!=1 or after['uid514_ops']!=5: raise RuntimeError(f'720 poststate mismatch: {after}')
   result.update(ok=True,before=before,after=after,committed=True)
  else:
   if before['head']!='20260828420000' or not before['repair_history'] or before['production']: raise RuntimeError(f'720 readback mismatch: {before}')
   result.update(ok=True,after=before,committed=False)
  print(json.dumps(result,sort_keys=True,separators=(',',':'))); return 0
 except Exception as e:
  c.rollback(); print(json.dumps({'ok':False,'mode':a.mode,'production_touched':False,'migration_sha256':SHA,'error':str(e)[:1200]},sort_keys=True,separators=(',',':'))); return 1
 finally:c.close()
if __name__=='__main__': raise SystemExit(main())
