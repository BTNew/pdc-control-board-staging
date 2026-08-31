from __future__ import annotations
import hashlib, importlib.util, json, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; MIGRATION=ROOT/"supabase/staging_only/20260831230000_857_attachment_claim_839_scope_compatibility_successor.sql"
BOOTSTRAP=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py"); SECRETS=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF="cdsmnqxtyyoeoznmbidd"; PROD="vjdtsswhroyguxyfjdkt"; PRE=("20260831220000","856_active_scope_enabled_pilot_compatibility_successor"); TARGET=("20260831230000","857_attachment_claim_839_scope_compatibility_successor")
def row(c,q): c.execute(q); return c.fetchone()
def main():
 spec=importlib.util.spec_from_file_location('b',BOOTSTRAP);m=importlib.util.module_from_spec(spec);assert spec and spec.loader;spec.loader.exec_module(m);d=json.loads(m.unprotect(SECRETS.read_bytes()).decode());m.validate(d)
 if REF not in d['PDC_STAGING_DATABASE_URL'] or PROD in d['PDC_STAGING_DATABASE_URL']: raise RuntimeError('PDC_857_NON_STAGING_TARGET')
 digest=hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
 if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_857')!=f'apply migration 857 attachment claim 839 scope compatibility source {digest}': raise RuntimeError('staging migration approval missing or hash-mismatched')
 import psycopg2;c=psycopg2.connect(d['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=d['PDC_STAGING_SSLROOTCERT'],application_name='pdc-857-attachment-claim-staging-controller');c.autocommit=False
 try:
  cur=c.cursor();head=tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
  if head not in (PRE,TARGET): raise RuntimeError(f'PDC_857_UNEXPECTED_LIVE_HEAD:{head}')
  if row(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]: raise RuntimeError('PDC_857_PRODUCTION_SENTINEL_PRESENT')
  if head!=TARGET:cur.execute(MIGRATION.read_text(encoding='utf-8'));c.commit();cur=c.cursor()
  src=(row(cur,"select pg_get_functiondef('public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)'::regprocedure)") or ('',))[0].lower()
  out={'ok':tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version='20260831230000'") or ())==TARGET,'environment':'staging','project_ref':REF,'migration_sha256':digest,'ledger_head':tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version='20260831230000'") or ()),'scope_839': 'pdc_monitor_authenticated_active_scope_839' in src,'old_scope_674_absent':'pdc_monitor_authenticated_active_scope_674' not in src,'claim_token_guard':'claim_token' in src,'production_sentinel_present':row(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null")[0],'mailbox_contacted':False,'uid514_processed':False}
  if not all((out['ok'],out['scope_839'],out['old_scope_674_absent'],out['claim_token_guard'],out['production_sentinel_present'] is False)):raise RuntimeError('PDC_857_POST_APPLY_READBACK_FAILED:'+json.dumps(out,sort_keys=True,default=str))
  c.commit();print(json.dumps(out,sort_keys=True,default=str))
 except Exception:c.rollback();raise
 finally:c.close()
if __name__=='__main__':
 try:main()
 except Exception as e:print(json.dumps({'ok':False,'error':str(e),'environment':'staging','mailbox_contacted':False,'uid514_processed':False,'production_contacted':False}));raise SystemExit(1)
