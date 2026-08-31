from __future__ import annotations
import hashlib, importlib.util, json, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/"supabase/staging_only/20260831220000_856_active_scope_enabled_pilot_compatibility_successor.sql"
BOOTSTRAP=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF="cdsmnqxtyyoeoznmbidd"; PROD="vjdtsswhroyguxyfjdkt"; PRE=("20260831210000","855_deterministic_inbound_sender_eligibility_successor"); TARGET=("20260831220000","856_active_scope_enabled_pilot_compatibility_successor")
def values():
 spec=importlib.util.spec_from_file_location('pdc_bootstrap',BOOTSTRAP); m=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(m); d=json.loads(m.unprotect(SECRETS.read_bytes()).decode()); m.validate(d)
 if REF not in d['PDC_STAGING_DATABASE_URL'] or PROD in d['PDC_STAGING_DATABASE_URL']: raise RuntimeError('PDC_856_NON_STAGING_TARGET')
 return d
def row(cur,q): cur.execute(q); return cur.fetchone()
def scalar(cur,q): x=row(cur,q); return x[0] if x else None
def main():
 digest=hashlib.sha256(MIGRATION.read_bytes()).hexdigest(); expected=f'apply migration 856 active scope enabled pilot compatibility source {digest}'
 if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_856')!=expected: raise RuntimeError('staging migration approval missing or hash-mismatched')
 d=values(); import psycopg2; c=psycopg2.connect(d['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=d['PDC_STAGING_SSLROOTCERT'],application_name='pdc-856-active-scope-staging-controller'); c.autocommit=False
 try:
  cur=c.cursor(); head=tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
  if head not in (PRE,TARGET): raise RuntimeError(f'PDC_856_UNEXPECTED_LIVE_HEAD:{head}')
  if scalar(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null"): raise RuntimeError('PDC_856_PRODUCTION_SENTINEL_PRESENT')
  if head!=TARGET: cur.execute(MIGRATION.read_text(encoding='utf-8')); c.commit(); cur=c.cursor()
  src=(scalar(cur,"select pg_get_functiondef('public.pdc_monitor_authenticated_active_scope_839()'::regprocedure)") or '').lower()
  result={'ok':tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version='20260831220000'") or ())==TARGET,'environment':'staging','project_ref':REF,'migration_sha256':digest,'ledger_head':tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version='20260831220000'") or ()),'pilot_enabled':scalar(cur,'select enabled and automatic_rule_application and automatic_authenticated_jobcards and not outbound_email_enabled from public.pdc_email_monitor_pilot where singleton'),'scope_enabled_predicate':'enabled and automatic_rule_application and automatic_authenticated_jobcards' in src,'production_sentinel_present':scalar(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null"),'mailbox_contacted':False,'uid514_processed':False}
  if not all((result['ok'],result['pilot_enabled'],result['scope_enabled_predicate'],result['production_sentinel_present'] is False)): raise RuntimeError('PDC_856_POST_APPLY_READBACK_FAILED:'+json.dumps(result,sort_keys=True,default=str))
  c.commit(); print(json.dumps(result,sort_keys=True,default=str))
 except Exception: c.rollback(); raise
 finally: c.close()
if __name__=='__main__':
 try: main()
 except Exception as e: print(json.dumps({'ok':False,'error':str(e),'environment':'staging','mailbox_contacted':False,'uid514_processed':False,'production_contacted':False})); raise SystemExit(1)
