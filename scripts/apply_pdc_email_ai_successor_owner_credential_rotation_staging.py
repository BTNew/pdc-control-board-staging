#!/usr/bin/env python3
from pathlib import Path
import hashlib,importlib.util,json,os
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/'supabase/staging_only/20260831360000_pdc_email_ai_successor_owner_credential_rotation.sql'
BOOT=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py'); SEC=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
def main():
 d=hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
 if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_866')!=f'apply migration 866 pdc email ai successor credential rotation source {d}': raise RuntimeError('PDC_SUCCESSOR_3600_APPROVAL_MISSING_OR_HASH_MISMATCH')
 s=importlib.util.spec_from_file_location('b',BOOT);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);v=json.loads(m.unprotect(SEC.read_bytes()).decode());m.validate(v)
 if 'cdsmnqxtyyoeoznmbidd' not in v['PDC_STAGING_DATABASE_URL'] or 'vjdtsswhroyguxyfjdkt' in v['PDC_STAGING_DATABASE_URL']: raise RuntimeError('PDC_SUCCESSOR_NON_STAGING_TARGET')
 import psycopg2
 c=psycopg2.connect(v['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=v['PDC_STAGING_SSLROOTCERT'],application_name='pdc-email-ai-successor-owner-credential-rotation-migration')
 try:
  q=c.cursor();q.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1");
  if tuple(q.fetchone())!=('20260831350000','pdc_email_ai_successor_owner_provisioning'): raise RuntimeError('PDC_SUCCESSOR_3600_UNEXPECTED_LIVE_HEAD')
  q.execute(MIGRATION.read_text(encoding='utf-8'));c.commit();q=c.cursor();q.execute("select version,name from supabase_migrations.schema_migrations where version='20260831360000'");ledger=tuple(q.fetchone() or ());q.execute("select to_regprocedure('public.rotate_pdc_email_ai_successor_runtime_credential(uuid,text,uuid)') is not null");present=bool(q.fetchone()[0]);q.execute("select has_function_privilege('service_role','public.rotate_pdc_email_ai_successor_runtime_credential(uuid,text,uuid)','execute'),has_function_privilege('authenticated','public.rotate_pdc_email_ai_successor_runtime_credential(uuid,text,uuid)','execute')");svc,auth=q.fetchone();q.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null");prod=bool(q.fetchone()[0]);proof={'ok':ledger==('20260831360000','pdc_email_ai_successor_owner_credential_rotation') and present and svc and not auth and not prod,'environment':'staging','project_ref':'cdsmnqxtyyoeoznmbidd','ledger':ledger,'rotate_rpc_present':present,'service_role_execute':svc,'authenticated_execute':auth,'production_contacted':False};print(json.dumps(proof,sort_keys=True));
  if not proof['ok']: raise RuntimeError('PDC_SUCCESSOR_3600_READBACK_FAILED')
 except Exception:c.rollback();raise
 finally:c.close()
if __name__=='__main__':
 try:main()
 except Exception as e: print(json.dumps({'ok':False,'environment':'staging','error':str(e),'production_contacted':False},sort_keys=True)); raise SystemExit(1)
