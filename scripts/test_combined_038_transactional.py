#!/usr/bin/env python3
"""Rollback-only staging execution test for migration 038 dealer scope and ETA planning."""
from __future__ import annotations
import json, sys, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'_staging_test_tools')]
from staging_conn import get_conn  # type: ignore
from staging_env import assert_staging_target, required  # type: ignore
SQL=(ROOT/'supabase/migrations/038_combined_staging_dealer_scope_eta_planning.sql').read_text(encoding='utf-8')
SAFE=Path(r'C:\Users\nwmgr\Documents\PDC-Safe-Exports\pdc-browser-local-navision-2026-07-20.json')
def rpc(cur,name,args):
 cur.execute(f"select public.{name}("+','.join(['%s']*len(args))+')',args); return cur.fetchone()[0]
def impersonate(cur,uid,email):
 cur.execute("select set_config('request.jwt.claims',%s,true),set_config('role','authenticated',true)",(json.dumps({'sub':str(uid),'email':email,'role':'authenticated'}),))
def postgres(cur): cur.execute("select set_config('role','postgres',true)")
def preview(cur,rows,dealer,name): return rpc(cur,'preview_navision_backend_import',[json.dumps(rows),'microsoft_navision',dealer,name,None])
def apply(cur,rows,dealer,name,key,p):
 d=p['data']; return rpc(cur,'apply_navision_backend_import',[key,json.dumps(rows),'microsoft_navision',dealer,name,None,d['source_hash'],d['preview_hash'],d['base_revision']])
def main():
 assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
 conn=get_conn(); cur=conn.cursor(); ev={}
 try:
  cur.execute("select auth_user_id,email from public.pdc_user_roles where active and account_status='approved' and role::text='administrator' and auth_user_id is not null order by email limit 1")
  admin=cur.fetchone(); assert admin
  cur.execute("select count(*),(select revision from public.navision_backend_revision where singleton),(select count(*) from public.navision_import_batches),(select count(*) from public.navision_operation_receipts) from public.navision_backend_records")
  ev['before_counts']=list(cur.fetchone())
  cur.execute("select md5(coalesce(string_agg(id::text||':'||version::text||':'||coalesce(current_location,'')||':'||coalesce(workshop_status,''),'|' order by id),'')) from public.vehicles where permanent_vehicle_id not like 'TX038-%'")
  vehicles_before=cur.fetchone()[0]
  cur.execute(SQL)
  postgres(cur)
  cur.execute("select auth_user_id,email from public.pdc_user_roles where active and account_status='approved' and auth_user_id is not null and role::text in ('viewer','operator') order by role::text,email limit 1")
  limited_actor=cur.fetchone(); assert limited_actor
  impersonate(cur,*limited_actor); limited_preview=preview(cur,[{'id':'ROLE-CHECK'}],'14450','role-check.json')
  limited_apply=rpc(cur,'apply_navision_backend_import',['role-denied',json.dumps([{'id':'ROLE-CHECK'}]),'microsoft_navision','14450','role-check.json',None,'invalid','invalid',2])
  postgres(cur); cur.execute("update public.pdc_user_roles set role='importer' where auth_user_id=%s",(limited_actor[0],))
  impersonate(cur,*limited_actor); importer_preview=preview(cur,[{'id':'ROLE-CHECK'}],'14450','role-check.json')
  importer_apply=apply(cur,[{'id':'ROLE-CHECK'}],'14450','role-check.json','role-importer-'+str(uuid.uuid4()),importer_preview)
  ev['role_codes']=[limited_preview.get('code'),limited_apply.get('code'),importer_preview.get('code'),importer_apply.get('code')]
  postgres(cur); cur.execute("select count(*) from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='navision_backend_revision'"); revision_realtime=cur.fetchone()[0]
  cur.execute("select count(*) from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename in ('navision_backend_records','navision_import_items')"); payload_realtime=cur.fetchone()[0]
  ev['realtime_scope']=[revision_realtime,payload_realtime]
  cur.execute("insert into public.vehicles(permanent_vehicle_id,stock_number,current_location,eta_to_kewdale) values ('TX038-YH','TX038-YH','YH','2030-07-21') returning id,version")
  eta_vehicle_id, eta_vehicle_version = cur.fetchone()
  impersonate(cur,*admin)
  cur.execute('savepoint eta_before')
  try:
   rpc(cur,'schedule_vehicle_work',[eta_vehicle_id,eta_vehicle_version,'SUBLET',1,'2030-07-20T09:00:00+08:00',180,None,None,json.dumps({})])
   ev['before_eta_rejected']=False
  except Exception as exc:
   cur.execute('rollback to savepoint eta_before'); ev['before_eta_rejected']='booking_before_eta' in str(exc)
  postgres(cur); cur.execute("update public.vehicles set eta_to_kewdale=null where id=%s",(eta_vehicle_id,)); cur.execute("select version from public.vehicles where id=%s",(eta_vehicle_id,)); eta_vehicle_version=cur.fetchone()[0]
  impersonate(cur,*admin); cur.execute('savepoint eta_blank')
  try:
   rpc(cur,'schedule_vehicle_work',[eta_vehicle_id,eta_vehicle_version,'SUBLET',1,'2030-07-21T09:00:00+08:00',180,None,None,json.dumps({})])
   ev['blank_eta_rejected']=False
  except Exception as exc:
   cur.execute('rollback to savepoint eta_blank'); ev['blank_eta_rejected']='missing_or_invalid_eta' in str(exc)
  postgres(cur); cur.execute("update public.vehicles set eta_to_kewdale='2030-07-21' where id=%s",(eta_vehicle_id,)); cur.execute("select version from public.vehicles where id=%s",(eta_vehicle_id,)); eta_vehicle_version=cur.fetchone()[0]
  cur.execute("insert into public.vehicles(permanent_vehicle_id,stock_number,current_location,eta_to_kewdale) values ('TX038-BLANK','TX038-BLANK','YH',null) returning id")
  blank_id=cur.fetchone()[0]
  impersonate(cur,*admin); exact=rpc(cur,'schedule_vehicle_work',[eta_vehicle_id,eta_vehicle_version,'SUBLET',1,'2030-07-21T09:00:00+08:00',180,None,None,json.dumps({})])
  postgres(cur); cur.execute("select current_location,eta_at_booking,eta_risk_status from public.vehicles v join public.workshop_bookings b on b.id=v.active_workshop_booking_id where v.id=%s",(eta_vehicle_id,)); ev['exact_eta_booking']=list(cur.fetchone())
  cur.execute('savepoint vehicle_reassignment');
  try: cur.execute("update public.workshop_bookings set vehicle_id=%s where id=%s",(blank_id,exact['booking']['booking_id'])); ev['vehicle_reassignment_rejected']=False
  except Exception: cur.execute('rollback to savepoint vehicle_reassignment'); ev['vehicle_reassignment_rejected']=True
  cur.execute("update public.vehicles set eta_to_kewdale='2030-07-22' where id=%s",(eta_vehicle_id,)); cur.execute("select eta_risk_status,eta_risk_detected_at is not null from public.workshop_bookings where id=%s",(exact['booking']['booking_id'],)); ev['later_eta_risk']=list(cur.fetchone())
  cur.execute("update public.vehicles set eta_to_kewdale=null where id=%s",(eta_vehicle_id,)); cur.execute("select eta_risk_status,eta_risk_detected_at is not null from public.workshop_bookings where id=%s",(exact['booking']['booking_id'],)); ev['missing_eta_stays_at_risk']=list(cur.fetchone())
  cur.execute("select count(*) from public.workshop_booking_history where booking_id=%s and event_type='eta_risk_changed'",(exact['booking']['booking_id'],)); ev['eta_risk_audit_rows']=cur.fetchone()[0]
  impersonate(cur,*admin)
  bad=preview(cur,[{'id':'BAD'}],'99999','bad.json'); missing=preview(cur,[{'id':'BAD'}],'','missing.json')
  ev['invalid_dealer_codes']=[bad.get('code'),missing.get('code')]
  safe=json.loads(SAFE.read_text(encoding='utf-8')); safe_rows=safe.get('records') or safe.get('vehicles') or safe
  postgres(cur); cur.execute("update public.pdc_user_roles set role='importer' where auth_user_id=%s",(limited_actor[0],)); impersonate(cur,*limited_actor)
  legacy_importer=preview(cur,safe_rows[:1],'37047','legacy-importer-claim.json'); ev['legacy_importer_claim']=[legacy_importer.get('code'),legacy_importer.get('data',{}).get('counts',{}).get('conflict')]
  postgres(cur); impersonate(cur,*admin); normal=preview(cur,safe_rows,'37047','current-normal-daily-210.json')
  ev['normal_daily_counts']=normal.get('data',{}).get('counts')
  ev['normal_daily_blocking']=normal.get('data',{}).get('blocking')
  large=preview(cur,[{'id':f'LARGE-{i:04d}','stock':f'LS{i:05d}'} for i in range(501)],'14450','larger-501.json')
  ev['larger_preview_total']=large.get('data',{}).get('counts',{}).get('total')
  p1=preview(cur,[{'id':'SCOPE-A','stock':'SC-A'},{'id':'SCOPE-B','stock':'SC-B'}],'14450','pilbara.json'); a1=apply(cur,[{'id':'SCOPE-A','stock':'SC-A'},{'id':'SCOPE-B','stock':'SC-B'}],'14450','pilbara.json','tx038-pilbara-1',p1)
  replay=apply(cur,[{'id':'SCOPE-A','stock':'SC-A'},{'id':'SCOPE-B','stock':'SC-B'}],'14450','pilbara.json','tx038-pilbara-1',p1)
  p2=preview(cur,[{'id':'SCOPE-C','stock':'SC-C'}],'37047','broome.json'); a2=apply(cur,[{'id':'SCOPE-C','stock':'SC-C'}],'37047','broome.json','tx038-broome-1',p2)
  d1_rows=[{'id':'SCOPE-A','stock':'SC-A'},{'id':'SCOPE-B','stock':'SC-B'},{'id':'DUPLICATE-SOURCE','stock':'DUP-A'}]; d1=preview(cur,d1_rows,'14450','duplicate-a.json'); apply(cur,d1_rows,'14450','duplicate-a.json','tx038-dup-a',d1)
  d2_rows=[{'id':'SCOPE-C','stock':'SC-C'},{'id':'DUPLICATE-SOURCE','stock':'DUP-B'}]; d2=preview(cur,d2_rows,'37047','duplicate-b.json'); apply(cur,d2_rows,'37047','duplicate-b.json','tx038-dup-b',d2)
  snap_a=rpc(cur,'get_navision_backend_snapshot',['microsoft_navision','14450',None,None,1,None]); snap_b=rpc(cur,'get_navision_backend_snapshot',['microsoft_navision','37047',None,None,1,None]); export_a=rpc(cur,'export_navision_backend_records',['microsoft_navision','14450',None,None,1,None]); ev['scoped_snapshot_dealers']=[snap_a.get('data',{}).get('dealer_code'),snap_b.get('data',{}).get('dealer_code'),export_a.get('data',{}).get('dealer_code')]
  postgres(cur); cur.execute("update public.pdc_user_roles set role='operator' where auth_user_id=%s",(limited_actor[0],)); impersonate(cur,*limited_actor); operator_snapshot=rpc(cur,'get_navision_backend_snapshot',['microsoft_navision','14450',None,None,1,None]); ev['operator_snapshot_code']=operator_snapshot.get('code'); postgres(cur); impersonate(cur,*admin)
  postgres(cur); cur.execute("select dealer_code,source_record_id,is_current,record_status from public.navision_backend_records where source_record_id like 'SCOPE-%' order by source_record_id")
  ev['pilbara_then_broome']=cur.fetchall()
  impersonate(cur,*admin)
  p3=preview(cur,[{'id':'SCOPE-A','stock':'SC-A'}],'14450','pilbara-next.json'); a3=apply(cur,[{'id':'SCOPE-A','stock':'SC-A'}],'14450','pilbara-next.json','tx038-pilbara-2',p3)
  postgres(cur); cur.execute("select dealer_code,source_record_id,is_current,record_status from public.navision_backend_records where source_record_id like 'SCOPE-%' order by source_record_id")
  ev['broome_then_pilbara_missing']=cur.fetchall()
  impersonate(cur,*admin); rolled=rpc(cur,'rollback_navision_backend_import',['tx038-rollback',a3['data']['batch_id'],a3['data']['result_revision']])
  postgres(cur); cur.execute("select dealer_code,source_record_id,is_current,record_status from public.navision_backend_records where source_record_id like 'SCOPE-%' order by source_record_id")
  ev['after_rollback']=cur.fetchall(); ev['replay_same_receipt']=a1==replay; ev['rollback_code']=rolled.get('code')
  cur.execute("select md5(coalesce(string_agg(id::text||':'||version::text||':'||coalesce(current_location,'')||':'||coalesce(workshop_status,''),'|' order by id),'')) from public.vehicles where permanent_vehicle_id not like 'TX038-%'")
  ev['operational_vehicles_unchanged']=vehicles_before==cur.fetchone()[0]
  checks=[ev['role_codes']==['unauthorized','unauthorized','preview_ready','applied'],ev['realtime_scope']==[1,0],ev['before_eta_rejected'],ev['blank_eta_rejected'],ev['vehicle_reassignment_rejected'],ev['exact_eta_booking']==['YH',__import__('datetime').date(2030,7,21),'none'],ev['later_eta_risk']==['at_risk',True],ev['missing_eta_stays_at_risk']==['at_risk',True],ev['eta_risk_audit_rows']==1,ev['invalid_dealer_codes']==['invalid_input','invalid_input'],ev['legacy_importer_claim']==['preview_ready',1],ev['normal_daily_counts']['total']==210,ev['larger_preview_total']==501,ev['scoped_snapshot_dealers']==['14450','37047','14450'],ev['operator_snapshot_code']=='unauthorized',ev['replay_same_receipt'],ev['operational_vehicles_unchanged'],ev['rollback_code']=='rolled_back',ev['pilbara_then_broome']==[('14450','SCOPE-A',True,'current'),('14450','SCOPE-B',True,'current'),('37047','SCOPE-C',True,'current')],ev['broome_then_pilbara_missing']==[('14450','SCOPE-A',True,'current'),('14450','SCOPE-B',False,'not_in_latest_batch'),('37047','SCOPE-C',True,'current')],ev['after_rollback']==[('14450','SCOPE-A',True,'current'),('14450','SCOPE-B',True,'current'),('37047','SCOPE-C',True,'current')]]
  if not all(checks): raise RuntimeError(ev)
 finally:
  conn.rollback(); conn.close()
 print(json.dumps(ev,indent=2,sort_keys=True,default=str))
if __name__=='__main__': main()
