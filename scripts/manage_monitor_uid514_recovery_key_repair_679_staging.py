#!/usr/bin/env python3
"""Fail-closed Supabase-management controller for staging repair successor 679."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
EXPECTED_REF="cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF="vjdtsswhroyguxyfjdkt"
MIGRATION=ROOT/"supabase/staging_only/20260827113000_679_uid514_recovery_event_key_repair.sql"
EXPECTED_MIGRATION_SHA256="2d11783911adf74070d2e2a15b7eaf628cead126eaf463261247dbcd280b3f9c"
APPROVAL_ENV="PDC_APPROVE_STAGING_MIGRATION_679"
CLI="npx.cmd" if os.name=="nt" else "npx"
PRE="""select jsonb_build_object('target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827111000','20260827112000','20260827113000','20260827114000')),'counts',jsonb_build_object('intake',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'vehicle',(select count(*) from public.vehicles where stock_number='13016925'))) as evidence;"""
POST="""select jsonb_build_object('target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827111000','20260827112000','20260827113000','20260827114000')),'counts',jsonb_build_object('intake',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'vehicle',(select count(*) from public.vehicles where stock_number='13016925')),'repair_history',(select count(*) from public.pdc_uid514_recovery_event_key_repair_history_679 where event_kind='forward_recovery_event_key_repair'),'recovery_key',position('pdc-staging-677-uid514-exact-recovery-successor|recovery|25751401' in pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure))>0,'control_key',position('pdc-staging-677-uid514-exact-recovery-successor|forward|25751401' in pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure))>0) as evidence;"""
def q(sql,source=None):
 t=None
 try:
  if source is None:
   h=tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.sql',prefix='hermes-verify-',delete=False);h.write(sql);h.close();t=Path(h.name);source=t
  r=subprocess.run([CLI,'--yes','supabase','db','query','--linked','--project-ref',EXPECTED_REF,'--output-format','json','--file',str(source)],cwd=ROOT,capture_output=True,text=True,timeout=240)
  if r.returncode: raise RuntimeError(f'management query failed: status {r.returncode}')
  i=r.stdout.find('{')
  if i<0: raise RuntimeError('management query returned no JSON')
  return json.JSONDecoder().raw_decode(r.stdout[i:])[0]
 finally:
  if t:t.unlink(missing_ok=True)
def state(post=False):return q(POST if post else PRE)['rows'][0]['evidence']
def target(v):return v['target']=={'database':'postgres','current_user':'postgres','session_user':'postgres','staging_sentinel':1,'production_sentinel':False}
def main(argv=None):
 p=argparse.ArgumentParser();p.add_argument('mode',choices=('preflight-679','apply-679','readback-679'));p.add_argument('--evidence',required=True,type=Path);a=p.parse_args(argv)
 e={'ok':False,'mode':a.mode,'committed':False,'production_touched':False,'uid514_processed':False,'task_enabled':False}
 try:
  if not a.evidence.is_absolute() or a.evidence.exists() or a.evidence.resolve().is_relative_to(ROOT):raise RuntimeError('EVIDENCE_PATH_INVALID')
  raw=MIGRATION.read_bytes()
  if MIGRATION.is_symlink() or not MIGRATION.is_file() or hashlib.sha256(raw).hexdigest()!=EXPECTED_MIGRATION_SHA256 or EXPECTED_REF.encode() not in raw or PRODUCTION_REF.encode() in raw:raise RuntimeError('MIGRATION_SOURCE_ATTESTATION_FAILED')
  e['migration_sha256']=hashlib.sha256(raw).hexdigest()
  if a.mode=='readback-679':
   after=state(True)
   e['after']=after
   if not target(after) or after['ledger'][-1]!={'name':'679_uid514_recovery_event_key_repair','version':'20260827114000'} or after['repair_history']!=1 or after['counts']!={'intake':0,'authorization':0,'selection':0,'vehicle':0} or not after['recovery_key'] or after['control_key']:raise RuntimeError('679_POSTSTATE_MISMATCH')
   e['ok']=True
  else:
   before=state();e['before']=before
   if not target(before) or not any(row=={'name':'678_uid514_authorize_attachment_count_repair','version':'20260827112000'} for row in before['ledger']) or any(row.get('name')=='679_uid514_recovery_event_key_repair' for row in before['ledger']) or before['counts']!={'intake':0,'authorization':0,'selection':0,'vehicle':0}:raise RuntimeError('EXACT_678_PRESTATE_REQUIRED')
   if a.mode=='apply-679':
    if os.environ.get(APPROVAL_ENV)!=f'apply migration 679 source {EXPECTED_MIGRATION_SHA256}':raise RuntimeError('APPLY_APPROVAL_MISSING')
    q('',source=MIGRATION);e['committed']=True;e['after']=state(True)
    after=e['after']
    if not target(after) or after['ledger'][-1]!={'name':'679_uid514_recovery_event_key_repair','version':'20260827114000'} or after['repair_history']!=1 or after['counts']!={'intake':0,'authorization':0,'selection':0,'vehicle':0} or not after['recovery_key'] or after['control_key']:raise RuntimeError('679_POSTSTATE_MISMATCH')
   else:e['after']=before
   e['ok']=True
 except Exception as x:e['error']=str(x)[:400]
 a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(e,sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8');print(json.dumps(e,sort_keys=True,separators=(',',':')));return 0 if e['ok'] else 1
if __name__=='__main__':raise SystemExit(main())
