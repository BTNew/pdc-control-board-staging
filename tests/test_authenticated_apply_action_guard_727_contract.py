from __future__ import annotations
import importlib.util,json,os,sys,unittest
from pathlib import Path
from urllib.parse import urlsplit
import psycopg2
ROOT=Path(__file__).resolve().parents[1]
REF='cdsmnqxtyyoeoznmbidd';PROD='vjdtsswhroyguxyfjdkt'
def staging():
 p=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py');s=importlib.util.spec_from_file_location('bootstrap727',p);m=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(m);v=json.loads(m.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode());m.validate(v);u=v['PDC_STAGING_DATABASE_URL'];e=urlsplit(u)
 if v.get('PDC_STAGING_PROJECT_REF')!=REF or REF not in u or PROD in u:raise RuntimeError('non-staging endpoint refused')
 os.environ.update({k:v[k] for k in ('PDC_STAGING_SSLROOTCERT','PDC_STAGING_SSLROOTCERT_SHA256')});sys.path.insert(0,str(ROOT));from scripts.pdc_staging_runtime import trusted_sslrootcert
 return psycopg2.connect(host=e.hostname,port=e.port or 5432,user=e.username,password=e.password,dbname='postgres',sslmode='verify-full',sslrootcert=trusted_sslrootcert(),connect_timeout=15,application_name='pdc727_red_regression')
class ApplyActionGuard727RedTests(unittest.TestCase):
 def test_source_binding_jsonb_guard_is_parenthesized(self):
  c=staging()
  try:
   with c.cursor() as q:
    q.execute("select pg_get_functiondef('public.pdc_agentic_email_action_guard_502()'::regprocedure)");src=q.fetchone()[0]
   self.assertIn("(new.request->'source_binding')-array['claim_token','gateway_instance_id']::text[]",src)
   self.assertIn("(old.request->'source_binding')-array['claim_token','gateway_instance_id']::text[]",src)
  finally:c.rollback();c.close()
 def test_audit_source_binding_jsonb_guard_is_parenthesized(self):
  c=staging()
  try:
   with c.cursor() as q:
    q.execute("select pg_get_functiondef('public.append_pdc_agentic_email_action_audit_502(jsonb)'::regprocedure)");src=q.fetchone()[0]
   self.assertIn("(p_audit->'source_binding')-array['claim_token','gateway_instance_id']::text[]",src)
   self.assertIn("(v_plan.plan->'source_binding')-array['claim_token','gateway_instance_id']::text[]",src)
  finally:c.rollback();c.close()
 def test_finalize_source_binding_jsonb_guard_is_parenthesized(self):
  c=staging()
  try:
   with c.cursor() as q:
    q.execute("select pg_get_functiondef('public.finalize_pdc_agentic_email_plan_502(jsonb)'::regprocedure)");src=q.fetchone()[0]
   self.assertIn("(p_result->'source_binding')-array['claim_token','gateway_instance_id']::text[]",src)
   self.assertIn("(v_plan.plan->'source_binding')-array['claim_token','gateway_instance_id']::text[]",src)
  finally:c.rollback();c.close()
if __name__=='__main__':unittest.main()
