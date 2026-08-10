#!/usr/bin/env python3
"""Rollback-only behavior and privilege rehearsal for staging Migration 144."""
from __future__ import annotations
import hashlib, json, os, sys, uuid
from datetime import datetime, timezone
from pathlib import Path
import psycopg

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/"pdc-control-board"/"_staging_test_tools"))
from staging_env import assert_staging_target,load_local_env  # noqa: E402
MIGRATION=ROOT/"supabase"/"staging_only"/"144_restore_narrow_pdc_monitor_canonical_importer.sql"

def one(cur,sql,params=()):
    cur.execute(sql,params); return cur.fetchone()[0]

def counts(cur):
    cur.execute("""select (select count(*) from public.vehicles),(select count(*) from public.vehicle_work_items),
      (select count(*) from public.pdc_authenticated_email_import_receipts),(select count(*) from public.pdc_authenticated_email_operation_lines),
      (select count(*) from public.workshop_bookings),(select count(*) from public.vehicle_parts_updates)""")
    return cur.fetchone()

def claims(identity):
    return json.dumps({"sub":str(identity[0]),"email":identity[1],"role":"authenticated"})

def set_actor(cur,identity):
    cur.execute("set local role authenticated")
    cur.execute("select set_config('request.jwt.claims',%s,true)",(claims(identity),))

def reset_actor(cur): cur.execute("reset role")

def main():
    load_local_env(); dsn=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL')
    assert_staging_target(database_url=dsn)
    sql=MIGRATION.read_text(encoding='utf-8'); body=sql.replace('begin;','',1).rsplit('commit;',1)[0]
    report={}
    conn=psycopg.connect(dsn)
    try:
      with conn.cursor() as cur:
        baseline=counts(cur)
        cur.execute(body)
        cur.execute("""select w.user_id,u.email from public.pdc_monitor_stage_activation_writers w
          join auth.users u on u.id=w.user_id join public.pdc_user_roles r on r.email=lower(u.email)
          where w.active and w.revoked_at is null and r.role='viewer' and r.active and r.account_status='approved'
            and (r.auth_user_id is null or r.auth_user_id=w.user_id) order by w.granted_at desc limit 1""")
        viewer=cur.fetchone()
        cur.execute("""select r.auth_user_id,u.email from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id
          where r.role='administrator' and r.active and r.account_status='approved' order by r.approved_at desc nulls last limit 1""")
        admin=cur.fetchone()
        if not viewer or not admin: raise RuntimeError('Viewer and Administrator identities are required')
        cur.execute("""select r.id,r.normalized_data->>'batch' from public.navision_backend_records r
          where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047') and r.is_current and r.record_status='current'
            and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
            and public.navision_operational_location(r.normalized_data)<>'Completed'
            and not exists(select 1 from public.navision_board_activations a where a.backend_record_id=r.id)
            and not exists(select 1 from public.vehicles v where v.stock_number_normalized=public.normalize_vehicle_stock_number(r.normalized_data->>'batch'))
            and not exists(select 1 from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=public.normalize_vehicle_stock_number(r.normalized_data->>'batch'))
          order by r.id limit 1 for update""")
        nav=cur.fetchone()
        if not nav: raise RuntimeError('No unused exact current Navision Stock is available for rollback fixture')
        backend_id,stock=nav
        marker=uuid.uuid4().hex; source=hashlib.sha256(('source-'+marker).encode()).hexdigest(); evidence=hashlib.sha256(('evidence-'+marker).encode()).hexdigest()
        source_uid='qa-144-'+marker[:20]; key='pdc-email-import-'+marker; jc='QA-JC-144-'+marker[:8].upper()
        cur.execute("update public.navision_backend_records set normalized_data=(normalized_data-'jobCardNumber')||%s::jsonb where id=%s",(json.dumps({'client':'QA 144 Customer','modelDescription':'QA 144 Vehicle','navisionLocationStatus':'In Transit'}),backend_id))
        cur.execute("insert into public.pdc_email_source_claims(source_hash,contract_name,proposal_ref) values(%s,'pdc_ai_intake_063',%s)",(source,source_uid))
        auth={'dkim_aligned':True,'dmarc_aligned':True,'gmail_authentication_results':True,'sender_domain':'pmgwa.com.au','spf_aligned':True}
        vehicle={'cancelled':False,'conflicts':[],'customer_name':'Untrusted Email Customer','eta_to_kewdale':None,'job_card_number':jc,'registration':None,'stock_numbers':[stock],'toyota_order_number':None,'vehicle_description':'Untrusted Email Vehicle','vins':['MR0REBHV100548367']}
        required=['fitting','electrical','tint']
        received=datetime.now(timezone.utc).isoformat()
        params=(key,source,evidence,source_uid,'qa@pmgwa.com.au',json.dumps(auth),received,'QA 144 canonical import',json.dumps(vehicle),json.dumps(required))
        call="select public.import_pdc_authenticated_vehicle_email(%s,%s,%s,%s,%s,%s::jsonb,%s::timestamptz,%s,%s::jsonb,%s::jsonb)"
        set_actor(cur,admin); denied=one(cur,call,params); reset_actor(cur)
        if denied.get('code')!='unauthorized': raise RuntimeError(f'Administrator was not denied: {denied}')
        set_actor(cur,viewer)
        cur.execute('savepoint direct_write')
        try:
          cur.execute("insert into public.pdc_authenticated_email_import_receipts(actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,stock_number,vehicle_id,identity_source,required_work,response) values(%s,'forbidden',repeat('a',64),repeat('b',64),repeat('c',64),'forbidden','qa@pmgwa.com.au',clock_timestamp(),%s,gen_random_uuid(),'navision_exact','[]','{}')",(viewer[0],stock))
        except psycopg.errors.InsufficientPrivilege:
          cur.execute('rollback to savepoint direct_write')
        else:
          raise RuntimeError('Viewer direct receipt write unexpectedly succeeded')
        cur.execute('release savepoint direct_write')
        revision_before=one(cur,"select revision from public.pdc_email_vehicle_revision where singleton")
        imported=one(cur,call,params)
        if not imported.get('ok') or imported.get('code')!='canonical_imported': raise RuntimeError(f'canonical import failed: {imported}')
        vehicle_id=imported['data']['vehicle_id']
        replay_vehicle=one(cur,call,params)
        if replay_vehicle!=imported: raise RuntimeError('vehicle replay response drift')
        operations=[]
        keys=['fitting','electrical','tint']
        for i in range(1,17):
          operations.append({'description':f'QA operation {i:02d}','estimated_hours':1,'estimated_hours_source':'job_card','operation_no':f'OP{i}','work_key':keys[(i-1)%3]})
        op_call="select public.import_pdc_authenticated_email_operations_with_hours(%s,%s,%s::jsonb)"
        op_result=one(cur,op_call,(source,source_uid,json.dumps(operations)))
        if not op_result.get('ok') or op_result['data']['operation_lines_added']!=16: raise RuntimeError(f'operation import failed: {op_result}')
        revision_after=one(cur,"select revision from public.pdc_email_vehicle_revision where singleton")
        op_replay=one(cur,op_call,(source,source_uid,json.dumps(operations)))
        revision_replay=one(cur,"select revision from public.pdc_email_vehicle_revision where singleton")
        if op_replay.get('code')!='operation_lines_and_hours_already_imported' or revision_replay!=revision_after: raise RuntimeError('operation replay was not idempotent')
        reset_actor(cur)
        cur.execute("select stock_number,job_card_number,visible_on_board,current_location from public.vehicles where id=%s",(vehicle_id,)); readback=cur.fetchone()
        if readback!=(stock,jc,True,'IT'): raise RuntimeError(f'vehicle readback mismatch: {readback}')
        cur.execute("select work_key,required,completed from public.vehicle_work_items where vehicle_id=%s order by work_key",(vehicle_id,)); work=cur.fetchall()
        if work!=[('electrical',True,False),('fitting',True,False),('tint',True,False)]: raise RuntimeError(f'work readback mismatch: {work}')
        if one(cur,"select count(*) from public.pdc_authenticated_email_import_receipts where source_hash=%s",(source,))!=1: raise RuntimeError('receipt count mismatch')
        if one(cur,"select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=%s",(source,))!=16: raise RuntimeError('operation line count mismatch')
        if one(cur,"select count(*) from public.workshop_bookings where vehicle_id=%s",(vehicle_id,))!=0: raise RuntimeError('booking was created')
        snapshot=one(cur,"select public.get_pdc_email_vehicle_location_snapshot()")
        if not any(str(v.get('id'))==str(vehicle_id) and len(v.get('operation_lines',[]))==16 for v in snapshot.get('data',{}).get('vehicles',[])): raise RuntimeError('snapshot/realtime readback missing')
        report={'ok':True,'transaction':'rolled_back','stock_exact':True,'canonical_vehicle':True,'job_card_linked':True,'operation_lines':16,'work_items':3,'fitting':True,'electrical':True,'tint':True,'receipt_count':1,'viewer_direct_write_denied':True,'administrator_denied':True,'vehicle_replay_idempotent':True,'operation_replay_idempotent':True,'realtime_revision_advanced':revision_after>revision_before,'booking_created':False,'completed_work_reopened':False}
        conn.rollback()
      with conn.cursor() as cur:
        if counts(cur)!=baseline: raise RuntimeError('rollback did not restore baseline counts')
        if one(cur,"select exists(select 1 from supabase_migrations.schema_migrations where version='144')"): raise RuntimeError('rollback leaked ledger 144')
      conn.rollback(); report['rollback_verified']=True
    except Exception:
      conn.rollback(); raise
    finally: conn.close()
    print(json.dumps(report,sort_keys=True))
if __name__=='__main__': main()
