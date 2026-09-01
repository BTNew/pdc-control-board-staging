#!/usr/bin/env python3
"""Apply the bounded STAGING-only v2 canonical compatibility repair."""
from __future__ import annotations
import hashlib, importlib.util, json, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/'supabase/staging_only/20260901232000_pdc_email_ai_v2_canonical_action_compatibility_20260901.sql'
BOOTSTRAP=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py'); SECRETS=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
STAGING_REF='cdsmnqxtyyoeoznmbidd'; PRODUCTION_REF='vjdtsswhroyguxyfjdkt'; PREDECESSOR=('20260901231000','pdc_email_ai_v2_canonical_action_guc_repair_20260901'); TARGET=('20260901232000','pdc_email_ai_v2_canonical_action_compatibility_20260901'); APPROVAL_ENV='PDC_APPROVE_STAGING_MIGRATION_20260901232000'
TABLES=('public.pdc_email_ai_successor_runtime_identities','public.pdc_email_ai_successor_transaction_receipts','public.pdc_email_ai_successor_action_receipts','public.pdc_email_ai_v2_canonical_action_compatibility_history_20260901'); ROLES=('public','anon','authenticated','service_role')
def one(c,q,p=()): c.execute(q,p); return c.fetchone()
def bundle():
 s=importlib.util.spec_from_file_location('b',BOOTSTRAP); m=importlib.util.module_from_spec(s); assert s and s.loader; s.loader.exec_module(m); d=json.loads(m.unprotect(SECRETS.read_bytes()).decode()); m.validate(d); url=d['PDC_STAGING_DATABASE_URL']
 if STAGING_REF not in url or PRODUCTION_REF in url: raise RuntimeError('PDC_CANONICAL_COMPATIBILITY_NON_STAGING_TARGET')
 return d
def source(c,s): return one(c,'select coalesce(pg_get_functiondef(to_regprocedure(%s)),\'\')',(s,))[0] or ''
def h(c,s): return one(c,"select case when to_regprocedure(%s) is null then null else encode(extensions.digest(convert_to(pg_get_functiondef(to_regprocedure(%s)),'UTF8'),'sha256'),'hex') end",(s,s))[0]
def state(c):
 ex=[t for t in TABLES if one(c,'select to_regclass(%s)',(t,))[0] is not None]
 return {'head':tuple(one(c,"select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1") or ()), 'receipts':tuple(one(c,'select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)')), 'rls':{t:tuple(one(c,'select relrowsecurity,relforcerowsecurity from pg_class where oid=%s::regclass',(t,)) or (False,False)) for t in ex}, 'direct':{t:{r:bool(one(c,"select has_table_privilege(%s,%s,'select')",(r,t))[0]) for r in ROLES} for t in ex}, 'production':bool(one(c,"select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]), 'hashes':{k:h(c,v) for k,v in {'executor':'public.pdc_email_ai_successor_execute_v2_20260901(jsonb)','work_states':'public.set_pdc_vehicle_work_states(uuid,integer,jsonb)','timeline':'public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'}.items()}}
def main():
 digest=hashlib.sha256(MIGRATION.read_bytes()).hexdigest(); expected=f'apply migration 20260901232000 pdc email ai v2 canonical action compatibility source {digest}'
 if os.environ.get(APPROVAL_ENV)!=expected: raise RuntimeError('PDC_CANONICAL_COMPATIBILITY_APPROVAL_MISSING_OR_HASH_MISMATCH')
 import psycopg2
 d=bundle(); c=psycopg2.connect(d['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=d['PDC_STAGING_SSLROOTCERT'],application_name='pdc-email-ai-v2-canonical-compatibility-staging-controller'); c.autocommit=False
 try:
  cur=c.cursor(); before=state(cur)
  if before['head'] not in {PREDECESSOR,TARGET}: raise RuntimeError(f'PDC_CANONICAL_COMPATIBILITY_UNEXPECTED_HEAD:{before["head"]}')
  if before['production']: raise RuntimeError('PDC_CANONICAL_COMPATIBILITY_PRODUCTION_SENTINEL_PRESENT')
  already=before['head']==TARGET
  if not already: cur.execute(MIGRATION.read_text(encoding='utf-8'))
  after=state(cur); exe=source(cur,'public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'); work=source(cur,'public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'); timeline=source(cur,'public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)')
  proof={'ok':after['head']==TARGET and before['receipts']==after['receipts'] and not after['production'] and 'canonical_operation_source_receipt_not_found' in exe and 'jsonb_object_length' not in work and 'pdc.monitor.v2_canonical_action_capability_20260902' in timeline and all(all(bool(x) for x in v) for v in after['rls'].values()) and all(not x for t in after['direct'].values() for x in t.values()),'environment':'staging','project_ref':STAGING_REF,'migration_identity':TARGET,'migration_sha256':digest,'already_applied':already,'before':before,'after':after,'repairs':['jsonb_object_length compatibility','timeline actor-bound capability','operation source-receipt fail-closed result'],'receipts_preserved':before['receipts']==after['receipts'],'production_writes':False,'mailbox_contacted':False,'outbound_email':False,'action_rpc_invoked':False}
  if not proof['ok']: raise RuntimeError('PDC_CANONICAL_COMPATIBILITY_POSTCHECK_FAILED')
  c.commit(); out=ROOT/'review-evidence/v2-controlled/canonical-action-compatibility-apply-proof.json'; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(json.dumps(proof,sort_keys=True,indent=2)+'\n',encoding='utf-8'); print(json.dumps({'ok':True,'proof':str(out),'migration':TARGET,'migration_sha256':digest,'ledger_head':after['head'],'receipts_preserved':proof['receipts_preserved'],'production_writes':False,'mailbox_contacted':False,'outbound_email':False,'action_rpc_invoked':False},sort_keys=True))
 except Exception: c.rollback(); raise
 finally: c.close()
if __name__=='__main__': main()
