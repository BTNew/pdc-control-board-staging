#!/usr/bin/env python3
"""Guarded staging management controller for Email Monitor 685."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; REF='cdsmnqxtyyoeoznmbidd'; PROD='vjdtsswhroyguxyfjdkt'; MIGRATION=ROOT/'supabase/staging_only/20260828060000_685_uid514_exact_attachment_array_guard.sql'; EXPECTED='f450ac57f1d195ea2a3540b2d54e0aca44ae20c6896d88fc38062af5e1263a04'; APPROVAL='PDC_APPROVE_STAGING_MIGRATION_685'; CLI='npx.cmd' if os.name=='nt' else 'npx.cmd'
SQL="""
select jsonb_build_object('target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260828050000','20260828060000')),'counts',jsonb_build_object('intake',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'failed',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and status='failed' and queue_attempts=8),'observations',(select count(*) from public.pdc_provider_email_observations where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'attachments',(select count(*) from public.ai_email_attachments where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'extracted',(select count(*) from public.ai_email_attachments where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and text_extraction_status='extracted'),'vehicles',(select count(*) from public.vehicles where public.normalize_vehicle_stock_number(stock_number)='13016925'),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled))),'array_guard_history',(select count(*) from public.pdc_authenticated_provider_import_agentic_inventory_guard_history_685 where event_kind='forward_inventory_guard'),'helper_sha256',encode(extensions.digest(convert_to((select p.prosrc from pg_proc p where p.oid='public.pdc_monitor_authenticated_uid514_claim_scope_684(text,uuid,uuid,uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex'),'helper_has_ordered_guard',position('c.all_attachment_hashes' in pg_get_functiondef('public.pdc_monitor_authenticated_uid514_claim_scope_684(text,uuid,uuid,uuid,text,text)'::regprocedure))>0,'history_forced_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_authenticated_provider_import_agentic_inventory_guard_history_685'::regclass)) as evidence;
"""
PRE_SQL="""
select jsonb_build_object('target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260828050000','20260828060000')),'counts',jsonb_build_object('intake',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'failed',(select count(*) from public.ai_email_intake where id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and status='failed' and queue_attempts=8),'observations',(select count(*) from public.pdc_provider_email_observations where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'attachments',(select count(*) from public.ai_email_attachments where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid),'extracted',(select count(*) from public.ai_email_attachments where intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid and text_extraction_status='extracted'),'vehicles',(select count(*) from public.vehicles where public.normalize_vehicle_stock_number(stock_number)='13016925'),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),'pilot_enabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled)))) as evidence;
"""
def query(sql,source=None):
 t=None
 if source is None:
  f=tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.sql',prefix='hermes-verify-',delete=False);f.write(sql);f.close();t=Path(f.name);source=t
 try:
  r=subprocess.run([CLI,'--yes','supabase','db','query','--linked','--project-ref',REF,'--output-format','json','--file',str(source)],cwd=ROOT,capture_output=True,text=True,timeout=240,check=False)
  if r.returncode: raise RuntimeError('management query failed: '+' '.join((r.stdout+' '+r.stderr).split())[:1800])
  start=r.stdout.find('{'); return json.JSONDecoder().raw_decode(r.stdout[start:])[0]
 finally:
  if t:t.unlink(missing_ok=True)
def target(e):return e['target']=={'database':'postgres','current_user':'postgres','session_user':'postgres','staging_sentinel':1,'production_sentinel':False}
def check_pre(e):
 if not target(e) or e['head']!='20260828050000' or e['ledger'][-1] != {'name':'684_authenticated_provider_import_agentic_compatibility','version':'20260828050000'}:raise RuntimeError('EXACT_684_PRESTATE_REQUIRED')
 if e['counts']!={'intake':1,'failed':1,'observations':0,'authorization':1,'selection':1,'attachments':7,'extracted':4,'vehicles':0,'active_mailboxes':1,'pilot_enabled':0}:raise RuntimeError('UID514_PRESTATE_MISMATCH')
def check_post(e):
 if not target(e) or e['head']!='20260828060000' or e['ledger'][-1] != {'name':'685_uid514_exact_attachment_array_guard','version':'20260828060000'}:raise RuntimeError('685_LEDGER_MISMATCH')
 if e['counts']!={'intake':1,'failed':1,'observations':0,'authorization':1,'selection':1,'attachments':7,'extracted':4,'vehicles':0,'active_mailboxes':1,'pilot_enabled':0} or e['array_guard_history']!=1 or e['helper_sha256'] is None or not e['helper_has_ordered_guard'] or not e['history_forced_rls']:raise RuntimeError('685_POSTSTATE_MISMATCH')
def main():
 p=argparse.ArgumentParser();p.add_argument('mode',choices=('preflight-685','apply-685','readback-685'));p.add_argument('--evidence',required=True,type=Path);a=p.parse_args();o={'ok':False,'mode':a.mode,'committed':False,'production_touched':False,'task_enabled':False,'uid514_processed':False}
 try:
  if not a.evidence.is_absolute() or a.evidence.exists() or a.evidence.resolve().is_relative_to(ROOT):raise RuntimeError('EVIDENCE_PATH_INVALID')
  raw=MIGRATION.read_bytes()
  if MIGRATION.is_symlink() or hashlib.sha256(raw).hexdigest()!=EXPECTED or REF.encode() not in raw or PROD.encode() in raw:raise RuntimeError('SOURCE_ATTESTATION_FAILED')
  o['migration_sha256']=EXPECTED;e=query(SQL if a.mode=='readback-685' else PRE_SQL)['rows'][0]['evidence']
  if a.mode=='readback-685':check_post(e);o.update(after=e,ok=True)
  else:
   check_pre(e);o['before']=e
   if a.mode=='apply-685':
    if os.environ.get(APPROVAL)!=f'apply migration 685 source {EXPECTED}':raise RuntimeError('APPLY_APPROVAL_MISSING')
    query('',MIGRATION);after=query(SQL)['rows'][0]['evidence'];check_post(after);o.update(after=after,committed=True,ok=True)
   else:o.update(after=e,ok=True)
 except Exception as x:o['error']=str(x)[:400]
 a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(o,sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8');print(json.dumps(o,sort_keys=True,separators=(',',':')));return 0 if o['ok'] else 1
if __name__=='__main__':raise SystemExit(main())
