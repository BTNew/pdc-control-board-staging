#!/usr/bin/env python3
from pathlib import Path
import hashlib,importlib.util,json,os
R=Path(__file__).resolve().parents[1];P=R/'supabase/staging_only/20260831380000_pdc_email_ai_successor_actor_first_gate.sql';B=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py');S=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
def main():
 d=hashlib.sha256(P.read_bytes()).hexdigest()
 if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_868')!=f'apply migration 868 pdc email ai successor actor first gate source {d}': raise RuntimeError('PDC_SUCCESSOR_3800_APPROVAL_MISSING_OR_HASH_MISMATCH')
 s=importlib.util.spec_from_file_location('b',B);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);v=json.loads(m.unprotect(S.read_bytes()).decode());m.validate(v)
 if 'cdsmnqxtyyoeoznmbidd' not in v['PDC_STAGING_DATABASE_URL'] or 'vjdtsswhroyguxyfjdkt' in v['PDC_STAGING_DATABASE_URL']: raise RuntimeError('PDC_SUCCESSOR_NON_STAGING_TARGET')
 import psycopg2
 c=psycopg2.connect(v['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=v['PDC_STAGING_SSLROOTCERT'],application_name='pdc-email-ai-successor-actor-first-gate')
 try:
  q=c.cursor();q.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1");
  if tuple(q.fetchone())!=('20260831370000','pdc_email_ai_successor_hostile_action_gate'): raise RuntimeError('PDC_SUCCESSOR_3800_UNEXPECTED_LIVE_HEAD')
  q.execute(P.read_text(encoding='utf-8'));c.commit();q=c.cursor();q.execute("select version,name from supabase_migrations.schema_migrations where version='20260831380000'");led=tuple(q.fetchone() or ());q.execute("select pg_get_functiondef('public.apply_pdc_email_ai_transaction_successor(jsonb)'::regprocedure)");src=q.fetchone()[0] or '';q.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null");prod=bool(q.fetchone()[0]);proof={'ok':led==('20260831380000','pdc_email_ai_successor_actor_first_gate') and 'successor_runtime_identity_denied' in src and 'typed_instruction_invalid' in src and not prod,'environment':'staging','project_ref':'cdsmnqxtyyoeoznmbidd','ledger':led,'actor_first_gate':('successor_runtime_identity_denied' in src and 'typed_instruction_invalid' in src),'production_contacted':False};print(json.dumps(proof,sort_keys=True));
  if not proof['ok']: raise RuntimeError('PDC_SUCCESSOR_3800_READBACK_FAILED')
 except Exception:c.rollback();raise
 finally:c.close()
if __name__=='__main__':
 try:main()
 except Exception as e: print(json.dumps({'ok':False,'environment':'staging','error':str(e),'production_contacted':False},sort_keys=True));raise SystemExit(1)
