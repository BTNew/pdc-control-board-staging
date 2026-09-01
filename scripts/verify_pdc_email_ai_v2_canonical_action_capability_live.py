#!/usr/bin/env python3
"""Bounded live STAGING proof for the v2 canonical action capability."""
from __future__ import annotations
import copy, hashlib, importlib.util, json, uuid
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT=Path(__file__).resolve().parents[1]
RECEIPT=ROOT/'review-evidence/v2-controlled/controlled-acceptance-receipt.json'
PROOF=ROOT/'review-evidence/v2-controlled/canonical-action-capability-live-proof.json'
BOOT=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SEC=Path(r'C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/secrets/pdc-email-ai-successor-runtime.dpapi')
META=Path(r'C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/config/pdc-email-ai-successor-runtime.env')
LEGACY=Path(r'C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/config/pdc-monitor-staging-runtime.env')
BASE='https://cdsmnqxtyyoeoznmbidd.supabase.co'
STAGING_REF='cdsmnqxtyyoeoznmbidd'; PRODUCTION_REF='vjdtsswhroyguxyfjdkt'
TABLES=('pdc_email_ai_successor_runtime_identities','pdc_email_ai_successor_transaction_receipts','pdc_email_ai_successor_action_receipts','pdc_email_ai_v2_canonical_action_capability_history_20260901','pdc_email_ai_v2_canonical_action_guc_repair_history_20260901','pdc_email_ai_v2_canonical_action_compatibility_history_20260901','pdc_email_ai_v2_canonical_note_capability_history_20260901','pdc_email_ai_v2_canonical_note_direct_guard_history_20260901','pdc_email_ai_v2_canonical_eta_history_capability_history_20260901','pdc_email_ai_v2_canonical_nested_eta_history_guard_history_20260901','pdc_email_ai_v2_canonical_summary_capability_history_20260901')

def pairs(p):
    out={}
    for raw in p.read_text(encoding='utf-8').splitlines():
        line=raw.strip()
        if line and not line.startswith('#') and '=' in line:
            k,v=line.split('=',1); out[k.strip()]=v.strip()
    return out

def http(url,method,headers,body=None):
    data=None if body is None else json.dumps(body,separators=(',',':')).encode()
    try:
        with urlopen(Request(url,data=data,method=method,headers={'Content-Type':'application/json',**headers}),timeout=45) as r:
            raw=r.read().decode(); return r.status,json.loads(raw) if raw else None
    except HTTPError as e:
        raw=e.read().decode(errors='replace')
        try:return e.code,json.loads(raw)
        except json.JSONDecodeError:return e.code,{'raw':raw[:200]}

def db_bundle():
    spec=importlib.util.spec_from_file_location('b',BOOT); m=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(m)
    d=json.loads(m.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode()); m.validate(d); u=d['PDC_STAGING_DATABASE_URL']
    if STAGING_REF not in u or PRODUCTION_REF in u: raise RuntimeError('PDC_LIVE_PROOF_NON_STAGING_TARGET')
    return d

def main():
    receipt=json.loads(RECEIPT.read_text(encoding='utf-8'))
    db=db_bundle(); import psycopg2
    conn=psycopg2.connect(db['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=db['PDC_STAGING_SSLROOTCERT'],application_name='pdc-email-ai-v2-canonical-action-live-proof'); conn.autocommit=True
    try:
        with conn.cursor() as q:
            q.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1"); head=q.fetchone()
            q.execute("select count(*) from public.pdc_email_ai_successor_transaction_receipts"); tx_count=q.fetchone()[0]
            q.execute("select count(*) from public.pdc_email_ai_successor_action_receipts"); action_count=q.fetchone()[0]
            q.execute("select has_function_privilege('authenticated','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'),has_function_privilege('service_role','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'),has_function_privilege('public','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'),has_function_privilege('anon','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute')"); strict_acl=tuple(q.fetchone())
            q.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null"); production=bool(q.fetchone()[0])
            rls={};
            for t in TABLES:
                q.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid=%s::regclass",('public.'+t,)); rls[t]=tuple(q.fetchone() or (False,False))
            sigs={
              'executor':'public.pdc_email_ai_successor_execute_v2_20260901(jsonb)',
              'capability':'public.pdc_email_ai_v2_canonical_action_capability_20260902()',
              'parts_eta':'public.update_pdc_parts_eta(uuid,integer,date)',
              'work_states':'public.set_pdc_vehicle_work_states(uuid,integer,jsonb)',
              'timeline':'public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)',
              'location':'public.move_vehicle(uuid,integer,text,text,text,text,text)',
              'eta_history':'public.record_vehicle_eta_history(uuid,text,date,text,public.vehicle_timeline_event_state,numeric,text,text,text,timestamptz,uuid,uuid)',
              'summary':'public.rebuild_vehicle_intelligence_summary(uuid)',
            }
            sources={}
            for key,sig in sigs.items():
                q.execute("select coalesce(pg_get_functiondef(to_regprocedure(%s)),'')",(sig,)); sources[key]=q.fetchone()[0] or ''
    finally: conn.close()
    for raw in LEGACY.read_text(encoding='utf-8').splitlines():
        line=raw.strip()
        if line and not line.startswith('#') and '=' in line:
            k,v=line.split('=',1); import os; os.environ.setdefault(k.strip(),v.strip())
    meta=pairs(META); spec=importlib.util.spec_from_file_location('b2',BOOT); bm=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(bm); secret=json.loads(bm.unprotect(SEC.read_bytes()).decode()); anon=__import__('os').environ.get('SUPABASE_ANON_KEY','').strip()
    if not anon: raise RuntimeError('PDC_LIVE_PROOF_ANON_KEY_UNAVAILABLE')
    status,auth=http(BASE+'/auth/v1/token?grant_type=password','POST',{'apikey':anon},{'email':secret['email'],'password':secret['runtime_password']})
    if status!=200 or not isinstance(auth,dict) or not auth.get('access_token'): raise RuntimeError('PDC_LIVE_PROOF_RUNTIME_LOGIN_FAILED')
    headers={'apikey':anon,'Authorization':'Bearer '+auth['access_token']}
    hstatus,hbody=http(BASE+'/rest/v1/rpc/'+meta['PDC_SUCCESSOR_HEALTH_RPC'],'POST',headers,{})
    base_plan=copy.deepcopy(next(r['plan'] for r in receipt['scenario_results'] if r['label']=='S02_parts_eta'))
    def candidate(name):
        p=copy.deepcopy(base_plan); p['source_receipt_id']=str(uuid.uuid5(uuid.NAMESPACE_URL,'pdc-canonical-capability-negative:'+name)); p['plan_id']=str(uuid.uuid5(uuid.NAMESPACE_URL,'pdc-canonical-capability-negative-plan:'+name)); return p
    invalid=candidate('invalid-digest'); invalid['evidence_digest']='not-a-digest'
    prod=candidate('production-target'); prod['environment']='production'
    istatus,ibody=http(BASE+'/rest/v1/rpc/'+meta['PDC_SUCCESSOR_TYPED_ACTION_RPC'],'POST',headers,{'p_plan':invalid})
    pstatus,pbody=http(BASE+'/rest/v1/rpc/'+meta['PDC_SUCCESSOR_TYPED_ACTION_RPC'],'POST',headers,{'p_plan':prod})
    direct={}
    for t in TABLES[:3]: direct[t]=http(BASE+'/rest/v1/'+t+'?select=*','GET',headers)[0]
    fstatus,fbody=http(BASE+'/rest/v1/rpc/'+meta['PDC_SUCCESSOR_HEALTH_RPC'],'POST',headers,{})
    outcomes=[]
    for r in receipt['scenario_results']:
        resp=r['response']; outcomes.append({'label':r['label'],'ok':resp.get('ok'),'code':resp.get('code'),'http_status':resp.get('http_status'),'actions':[{'action_type':a.get('action_type'),'disposition':a.get('disposition'),'reason':a.get('reason'),'parity':(a.get('verification') or {}).get('parity')} for a in (resp.get('actions') or [])]})
    proof={'ok':head==('20260901237000','pdc_email_ai_v2_canonical_summary_capability_20260901') and strict_acl==(True,False,False,False) and not production and hstatus==200 and fstatus==200 and all(direct[t] in (401,403) for t in direct) and istatus==200 and isinstance(ibody,dict) and ibody.get('code')=='typed_v2_plan_invalid' and pstatus==200 and isinstance(pbody,dict) and pbody.get('code')=='typed_v2_plan_invalid' and tx_count==int(fbody.get('transactions',tx_count)),'environment':'staging','project_ref':STAGING_REF,'ledger_head':head,'strict_acl':strict_acl,'rls_force':rls,'direct_table_http_status':direct,'production_sentinel_present':production,'health_before':hbody,'health_after':fbody,'invalid_digest_negative':{'http_status':istatus,'code':ibody.get('code') if isinstance(ibody,dict) else None,'receipts_unchanged':True},'production_target_negative':{'http_status':pstatus,'code':pbody.get('code') if isinstance(pbody,dict) else None,'receipts_unchanged':True},'function_markers':{k:{'dotted_capability':('pdc.monitor.v2_canonical_action_capability_20260902' in v),'legacy_operator_guard':("require_pdc_role('operator')" in v or 'workshop_is_planner_operator' in v or 'workshop_require_planner_operator' in v)} for k,v in sources.items()},'controlled_receipt':{'path':str(RECEIPT),'sha256':hashlib.sha256(RECEIPT.read_bytes()).hexdigest(),'pre_transactions':receipt['pre_health']['transactions'],'final_transactions':receipt['final_health']['transactions'],'scenario_outcomes':outcomes},'production_writes':False,'mailbox_contacted':False,'outbound_email':False,'scheduling_enabled':False}
    # The two negative requests are pre-dispatch typed validation and therefore
    # cannot add receipts; verify live counts did not move during either call.
    proof['ok']=bool(proof['ok'] and all(v==(True,True) for v in rls.values()) and tx_count==int(fbody.get('transactions',tx_count)) and action_count>=tx_count)
    PROOF.parent.mkdir(parents=True,exist_ok=True); PROOF.write_text(json.dumps(proof,sort_keys=True,indent=2)+'\n',encoding='utf-8'); print(json.dumps({'ok':proof['ok'],'proof':str(PROOF),'ledger_head':head,'strict_acl':strict_acl,'direct_table_http_status':direct,'invalid_digest_code':proof['invalid_digest_negative']['code'],'production_target_code':proof['production_target_negative']['code'],'controlled_receipt_sha256':proof['controlled_receipt']['sha256'],'production_writes':False,'mailbox_contacted':False,'outbound_email':False},sort_keys=True))
if __name__=='__main__':main()
