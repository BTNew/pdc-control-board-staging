from __future__ import annotations
import hashlib,importlib.util,json,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];MIGRATION=ROOT/'supabase/staging_only/20260829151000_752_reactivate_exact_email_monitor_after_751.sql';BOOTSTRAP=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py');SECRETS=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi');REF='cdsmnqxtyyoeoznmbidd'
def main():
 d=hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
 if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_752')!='apply migration 752 source '+d: raise RuntimeError('staging migration approval missing')
 s=importlib.util.spec_from_file_location('b',BOOTSTRAP);m=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(m);v=json.loads(m.unprotect(SECRETS.read_bytes()).decode());m.validate(v);import psycopg2
 c=psycopg2.connect(v['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=v['PDC_STAGING_SSLROOTCERT'],application_name='pdc-monitor-752-controller');c.autocommit=True
 try:
  q=c.cursor();q.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1");head=q.fetchone()
  if head!=('20260829144000','751_authenticated_parts_received_contract'): raise RuntimeError('unexpected live head before 752: '+str(head))
  q.execute(MIGRATION.read_text(encoding='utf-8'));q.execute("select version,name from supabase_migrations.schema_migrations where version='20260829151000'");print(json.dumps({'ok':True,'project_ref':REF,'head':q.fetchone(),'migration_sha256':d,'production_contacted':False},sort_keys=True))
 finally:c.close()
if __name__=='__main__':
 try:main()
 except Exception as e:print(json.dumps({'ok':False,'error':str(e),'production_contacted':False},sort_keys=True));raise SystemExit(1)
