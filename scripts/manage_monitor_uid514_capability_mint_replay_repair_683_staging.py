#!/usr/bin/env python3
"""Fail-closed staging management controller for exact UID514 replay repair 683."""
from __future__ import annotations
import argparse,hashlib,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];REF='cdsmnqxtyyoeoznmbidd';PROD='vjdtsswhroyguxyfjdkt';MIGRATION=ROOT/'supabase/staging_only/20260828010000_683_uid514_capability_mint_replay_repair.sql';EXPECTED='b8fbdbf163a2acedf5c839da5e7f43af868cc05ff0d7db77fbae2aa9e615761c';APPROVAL='PDC_APPROVE_STAGING_MIGRATION_683';CLI='npx.cmd' if os.name=='nt' else 'npx'
PRE="""select jsonb_build_object('target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260828000000','20260828010000')),'counts',jsonb_build_object('intake',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'vehicle',(select count(*) from public.vehicles where stock_number='13016925'))) as evidence;"""
SQL="""select jsonb_build_object('target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging_sentinel',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null),'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260828000000','20260828010000')),'counts',jsonb_build_object('intake',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),'authorization',(select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401),'selection',(select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401),'vehicle',(select count(*) from public.vehicles where stock_number='13016925')),'repair_history',(select count(*) from public.pdc_uid514_capability_mint_replay_repair_history_683 where event_kind='forward_capability_mint_replay_repair'),'replay_mint_removed',position('IF NOT v_existing THEN' in pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure))=0) as evidence;"""
def q(sql):
 h=tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.sql',prefix='hermes-verify-',delete=False);h.write(sql);h.close();p=Path(h.name)
 try:
  r=subprocess.run([CLI,'--yes','supabase','db','query','--linked','--project-ref',REF,'--output-format','json','--file',str(p)],cwd=ROOT,capture_output=True,text=True,timeout=240)
  if r.returncode:raise RuntimeError(f'management query failed: status {r.returncode}')
  i=r.stdout.find('{');return json.JSONDecoder().raw_decode(r.stdout[i:])[0]
 finally:p.unlink(missing_ok=True)
def main(argv=None):
 p=argparse.ArgumentParser();p.add_argument('mode',choices=('preflight-683','apply-683','readback-683'));p.add_argument('--evidence',required=True,type=Path);a=p.parse_args(argv);e={'ok':False,'mode':a.mode,'committed':False,'production_touched':False,'uid514_processed':False,'task_enabled':False}
 try:
  raw=MIGRATION.read_bytes()
  if not a.evidence.is_absolute() or a.evidence.exists() or a.evidence.resolve().is_relative_to(ROOT) or MIGRATION.is_symlink() or not MIGRATION.is_file() or hashlib.sha256(raw).hexdigest()!=EXPECTED or REF.encode() not in raw or PROD.encode() in raw:raise RuntimeError('SOURCE_OR_EVIDENCE_ATTESTATION_FAILED')
  e['migration_sha256']=hashlib.sha256(raw).hexdigest();s=q(SQL if a.mode=='readback-683' else PRE)['rows'][0]['evidence'];e['before']=s
  if a.mode=='readback-683':
   if s['ledger'][-1]!={'name':'683_uid514_capability_mint_replay_repair','version':'20260828010000'} or s['repair_history']!=1 or s['counts']!={'intake':0,'authorization':0,'selection':0,'vehicle':0} or not s['replay_mint_removed']:raise RuntimeError('683_POSTSTATE_MISMATCH')
  else:
   if not any(x=={'name':'682_uid514_capability_consumption_repair','version':'20260828000000'} for x in s['ledger']) or any(x.get('name')=='683_uid514_capability_mint_replay_repair' for x in s['ledger']) or s['counts']!={'intake':0,'authorization':0,'selection':0,'vehicle':0}:raise RuntimeError('EXACT_682_PRESTATE_REQUIRED')
   if a.mode=='apply-683':
    if os.environ.get(APPROVAL)!=f'apply migration 683 source {EXPECTED}':raise RuntimeError('APPLY_APPROVAL_MISSING')
    qfile=MIGRATION
    h=tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.sql',prefix='hermes-verify-',delete=False);h.close()
    try:
     r=subprocess.run([CLI,'--yes','supabase','db','query','--linked','--project-ref',REF,'--output-format','json','--file',str(qfile)],cwd=ROOT,capture_output=True,text=True,timeout=240)
     if r.returncode:raise RuntimeError(f'management query failed: status {r.returncode}')
    finally:pass
    after=q(SQL)['rows'][0]['evidence'];e['after']=after
    if after['ledger'][-1]!={'name':'683_uid514_capability_mint_replay_repair','version':'20260828010000'} or after['repair_history']!=1 or after['counts']!={'intake':0,'authorization':0,'selection':0,'vehicle':0} or not after['replay_mint_removed']:raise RuntimeError('683_POSTSTATE_MISMATCH')
    e['committed']=True
   else:e['after']=s
  e['ok']=True
 except Exception as x:e['error']=str(x)[:400]
 a.evidence.parent.mkdir(parents=True,exist_ok=True);a.evidence.write_text(json.dumps(e,sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8');print(json.dumps(e,sort_keys=True,separators=(',',':')));return 0 if e['ok'] else 1
if __name__=='__main__':raise SystemExit(main())
