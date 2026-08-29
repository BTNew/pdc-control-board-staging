from __future__ import annotations
import hashlib,importlib.util,json,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/'supabase/staging_only/20260830040000_765_authenticated_exact_claim_floor_640_successor.sql'
BOOTSTRAP=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
def main():
 digest=hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
 if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_765')!='apply migration 765 source '+digest: raise RuntimeError('staging migration approval missing')
 s=importlib.util.spec_from_file_location('b',BOOTSTRAP);m=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(m);v=json.loads(m.unprotect(SECRETS.read_bytes()).decode());m.validate(v);import psycopg2
 c=psycopg2.connect(v['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=v['PDC_STAGING_SSLROOTCERT'],application_name='pdc-monitor-765-controller');c.autocommit=True
 try:
  q=c.cursor();q.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1");head=q.fetchone()
  if head!=('20260830030000','exact_manual_reimport_manifest_order_alias_fix'): raise RuntimeError('unexpected live head before 765: '+str(head))
  q.execute(MIGRATION.read_text(encoding='utf-8'))
  q.execute("select version,name from supabase_migrations.schema_migrations where version='20260830040000'");applied=q.fetchone()
  q.execute("select minimum_uid,enabled,automatic_rule_application,automatic_authenticated_jobcards,outbound_email_enabled from public.pdc_email_monitor_pilot where singleton");pilot=q.fetchone()
  q.execute("select encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') from pg_proc p where p.oid='public.claim_pdc_email_intake_authenticated_exact_732(integer,text)'::regprocedure");fn=q.fetchone()
  print(json.dumps({'ok':True,'head':applied,'pilot':pilot,'claim_732_sha256':fn[0] if fn else None,'migration_sha256':digest,'production_contacted':False},sort_keys=True))
 finally:c.close()
if __name__=='__main__':
 try:main()
 except Exception as e: print(json.dumps({'ok':False,'error':str(e),'production_contacted':False},sort_keys=True));raise SystemExit(1)
