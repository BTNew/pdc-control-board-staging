#!/usr/bin/env python3
from __future__ import annotations
import hashlib,importlib.util,json,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; MIGRATION=ROOT/'supabase/staging_only/20260901237000_pdc_email_ai_v2_canonical_summary_capability_20260901.sql'; BOOT=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py'); SEC=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi'); REF='cdsmnqxtyyoeoznmbidd';PROD='vjdtsswhroyguxyfjdkt';PRE=('20260901236000','pdc_email_ai_v2_canonical_nested_eta_history_guard_20260901');TARGET=('20260901237000','pdc_email_ai_v2_canonical_summary_capability_20260901');ENV='PDC_APPROVE_STAGING_MIGRATION_20260901237000'
def one(c,q,p=()):c.execute(q,p);return c.fetchone()
def bundle():
 s=importlib.util.spec_from_file_location('b',BOOT);m=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(m);d=json.loads(m.unprotect(SEC.read_bytes()).decode());m.validate(d);u=d['PDC_STAGING_DATABASE_URL'];
 if REF not in u or PROD in u:raise RuntimeError('PDC_SUMMARY_CAPABILITY_NON_STAGING_TARGET')
 return d
def source(c,s):return one(c,'select coalesce(pg_get_functiondef(to_regprocedure(%s)),\'\')',(s,))[0] or ''
def state(c):return {'head':tuple(one(c,"select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1") or ()),'receipts':tuple(one(c,'select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)')),'production':bool(one(c,"select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])}
def main():
 digest=hashlib.sha256(MIGRATION.read_bytes()).hexdigest();expected=f'apply migration 20260901237000 pdc email ai v2 canonical summary capability source {digest}'
 if os.environ.get(ENV)!=expected:raise RuntimeError('PDC_SUMMARY_CAPABILITY_APPROVAL_MISSING_OR_HASH_MISMATCH')
 import psycopg2
 d=bundle();c=psycopg2.connect(d['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=d['PDC_STAGING_SSLROOTCERT'],application_name='pdc-email-ai-v2-canonical-summary-staging-controller');c.autocommit=False
 try:
  cur=c.cursor();before=state(cur)
  if before['head'] not in {PRE,TARGET}:raise RuntimeError(f'PDC_SUMMARY_CAPABILITY_UNEXPECTED_HEAD:{before["head"]}')
  if before['production']:raise RuntimeError('PDC_SUMMARY_CAPABILITY_PRODUCTION_SENTINEL_PRESENT')
  already=before['head']==TARGET
  if not already:cur.execute(MIGRATION.read_text(encoding='utf-8'))
  after=state(cur);dfn=source(cur,'public.rebuild_vehicle_intelligence_summary(uuid)')
  proof={'ok':after['head']==TARGET and before['receipts']==after['receipts'] and not after['production'] and 'pdc.monitor.v2_canonical_action_capability_20260902' in dfn,'environment':'staging','project_ref':REF,'migration_identity':TARGET,'migration_sha256':digest,'already_applied':already,'before':before,'after':after,'receipts_preserved':before['receipts']==after['receipts'],'production_writes':False,'mailbox_contacted':False,'outbound_email':False,'action_rpc_invoked':False}
  if not proof['ok']:raise RuntimeError('PDC_SUMMARY_CAPABILITY_POSTCHECK_FAILED')
  c.commit();out=ROOT/'review-evidence/v2-controlled/canonical-summary-capability-apply-proof.json';out.write_text(json.dumps(proof,sort_keys=True,indent=2)+'\n',encoding='utf-8');print(json.dumps({'ok':True,'proof':str(out),'migration':TARGET,'migration_sha256':digest,'ledger_head':after['head'],'receipts_preserved':proof['receipts_preserved'],'production_writes':False,'mailbox_contacted':False,'outbound_email':False,'action_rpc_invoked':False},sort_keys=True))
 except Exception:c.rollback();raise
 finally:c.close()
if __name__=='__main__':main()
