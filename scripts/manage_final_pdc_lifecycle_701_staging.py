#!/usr/bin/env python3
"""Fail-closed staging repair controller for lifecycle successor 701."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
REF='cdsmnqxtyyoeoznmbidd'; PROD='vjdtsswhroyguxyfjdkt'
MIGRATION=ROOT/'supabase/staging_only/20260827102000_701_final_qc_two_transition_repair.sql'
SHA='84b68d7d17e6b84a5d398dd4d3710aa0622f77c5520567754d15cf7c7dd88523'
APPROVAL='PDC_APPROVE_STAGING_MIGRATION_701'
STATE="""select jsonb_build_object('target',jsonb_build_object('database',current_database(),'current_user',current_user,'session_user',session_user,'staging',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),'production',to_regclass('public.pdc_production_environment_sentinel') is not null),'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),'ledger',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'name',name) order by version),'[]'::jsonb) from supabase_migrations.schema_migrations where version in('20260827101000','20260827102000')),'function_marker',(select position('finalize_pdc_qc_to_rft_701_qc_signoff' in pg_get_functiondef('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure))>0),'security',jsonb_build_object('qc',has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','execute'),'anon',has_function_privilege('anon','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','execute'),'service',has_function_privilege('service_role','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','execute')),'counts',jsonb_build_object('notifications',(select count(*) from public.vehicle_notifications),'outbox_399',(select count(*) from public.pdc_qc_salesperson_update_outbox_399),'outbox_412',(select count(*) from public.pdc_rft_transport_salesperson_outbox_412))) as evidence;"""
def run(sql='', source=None):
    temp=None
    try:
        if source is None:
            f=tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.sql',prefix='hermes-verify-',delete=False); f.write(sql); f.close(); temp=Path(f.name); source=temp
        p=subprocess.run(['npx.cmd','--yes','supabase','db','query','--yes','--linked','--project-ref',REF,'--output-format','json','--file',str(source)],cwd=ROOT,capture_output=True,text=True,timeout=300,check=False)
        if p.returncode: raise RuntimeError(f'management query failed: {p.returncode}')
        start=p.stdout.find('{')
        if start<0: raise RuntimeError('management query returned no JSON')
        return json.JSONDecoder().raw_decode(p.stdout[start:])[0]
    finally:
        if temp: temp.unlink(missing_ok=True)
def state(): return run(STATE)['rows'][0]['evidence']
def pre(s):
    if s['target']!={'database':'postgres','current_user':'postgres','session_user':'postgres','staging':1,'production':False}: raise RuntimeError('EXACT_STAGING_TARGET_PRESTATE_REQUIRED')
    if s['head']!='20260827101000' or s['ledger']!=[{'version':'20260827101000','name':'700_final_authoritative_pdc_lifecycle'}]: raise RuntimeError('EXACT_700_LEDGER_PRESTATE_REQUIRED')
    if s['function_marker'] or s['security']!={'qc':True,'anon':False,'service':False}: raise RuntimeError('EXACT_700_FUNCTION_PRESTATE_REQUIRED')
def post(s):
    if s['target']['production'] or s['head']!='20260827102000' or s['ledger']!=[{'version':'20260827101000','name':'700_final_authoritative_pdc_lifecycle'},{'version':'20260827102000','name':'701_final_qc_two_transition_repair'}]: raise RuntimeError('SUCCESSOR_701_LEDGER_MISMATCH')
    if s['function_marker'] is not True or s['security'].get('qc') is not True or s['security'].get('anon') is not False or s['security'].get('service') is not False: raise RuntimeError('SUCCESSOR_701_SECURITY_MISMATCH')
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('mode',choices=['preflight-701','apply-701','verify-701']); ap.add_argument('--evidence',required=True,type=Path); a=ap.parse_args(); event={'ok':False,'mode':a.mode,'committed':False,'production_touched':False,'mailbox_contacted':False}
    try:
        if not a.evidence.is_absolute() or a.evidence.exists() or a.evidence.resolve().is_relative_to(ROOT): raise RuntimeError('EVIDENCE_PATH_INVALID')
        raw=MIGRATION.read_bytes()
        if hashlib.sha256(raw).hexdigest()!=SHA or REF.encode() not in raw or PROD.encode() in raw: raise RuntimeError('MIGRATION_SOURCE_OR_TARGET_GUARD_FAILED')
        before=state();
        if a.mode in ('preflight-701','apply-701'): pre(before)
        event.update(before=before,migration_sha256=SHA)
        if a.mode=='preflight-701': event['ok']=True
        elif a.mode=='verify-701':
            after=state(); post(after); event.update(after=after,ok=True)
        else:
            if os.environ.get(APPROVAL)!=f'apply migration 701 source {SHA}': raise RuntimeError('APPLY_APPROVAL_MISSING')
            run(source=MIGRATION); event['committed']=True; after=state(); post(after); event.update(after=after,ok=True)
    except Exception as exc: event['error']=str(exc)[:400]
    a.evidence.parent.mkdir(parents=True,exist_ok=True); a.evidence.write_text(json.dumps(event,sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8'); print(json.dumps(event,sort_keys=True,separators=(',',':'))); return 0 if event['ok'] else 1
if __name__=='__main__': raise SystemExit(main())
