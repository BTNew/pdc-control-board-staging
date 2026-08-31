from pathlib import Path
import hashlib,importlib.util,json,os
R=Path(__file__).resolve().parents[1];M=R/'supabase/staging_only/20260831240000_858_runtime_authority_839_scope_compatibility_successor.sql';B=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py');S=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi');REF='cdsmnqxtyyoeoznmbidd';PROD='vjdtsswhroyguxyfjdkt';PRE=('20260831230000','857_attachment_claim_839_scope_compatibility_successor');T=('20260831240000','858_runtime_authority_839_scope_compatibility_successor')
def row(c,q):c.execute(q);return c.fetchone()
def main():
 sp=importlib.util.spec_from_file_location('b',B);m=importlib.util.module_from_spec(sp);assert sp and sp.loader;sp.loader.exec_module(m);d=json.loads(m.unprotect(S.read_bytes()).decode());m.validate(d)
 if REF not in d['PDC_STAGING_DATABASE_URL'] or PROD in d['PDC_STAGING_DATABASE_URL']:raise RuntimeError('PDC_858_NON_STAGING_TARGET')
 h=hashlib.sha256(M.read_bytes()).hexdigest()
 if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_858')!=f'apply migration 858 runtime authority 839 scope compatibility source {h}':raise RuntimeError('staging migration approval missing or hash-mismatched')
 import psycopg2;c=psycopg2.connect(d['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=d['PDC_STAGING_SSLROOTCERT'],application_name='pdc-858-runtime-authority-staging-controller');c.autocommit=False
 try:
  cur=c.cursor();head=tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
  if head not in(PRE,T):raise RuntimeError(f'PDC_858_UNEXPECTED_LIVE_HEAD:{head}')
  if row(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:raise RuntimeError('PDC_858_PRODUCTION_SENTINEL_PRESENT')
  if head!=T:cur.execute(M.read_text(encoding='utf-8'));c.commit();cur=c.cursor()
  src=(row(cur,"select pg_get_functiondef('public.pdc_email_monitor_runtime_authorized_502(text)'::regprocedure)") or ('',))[0].lower();o={'ok':tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version='20260831240000'") or ())==T,'environment':'staging','project_ref':REF,'migration_sha256':h,'ledger_head':tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version='20260831240000'") or ()),'scope_839':'pdc_monitor_authenticated_active_scope_839' in src,'scope_674_absent':'pdc_monitor_authenticated_active_scope_674' not in src,'production_sentinel_present':row(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null")[0],'mailbox_contacted':False,'uid514_processed':False}
  if not all((o['ok'],o['scope_839'],o['scope_674_absent'],o['production_sentinel_present'] is False)):raise RuntimeError('PDC_858_POST_APPLY_READBACK_FAILED:'+json.dumps(o,sort_keys=True,default=str))
  c.commit();print(json.dumps(o,sort_keys=True,default=str))
 except Exception:c.rollback();raise
 finally:c.close()
if __name__=='__main__':
 try:main()
 except Exception as e:print(json.dumps({'ok':False,'error':str(e),'environment':'staging','mailbox_contacted':False,'uid514_processed':False,'production_contacted':False}));raise SystemExit(1)
