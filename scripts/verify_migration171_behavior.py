#!/usr/bin/env python3
"""Rollback-only runtime proof for staging Migration 171."""
import json,os,re,sys,uuid
from pathlib import Path
import psycopg2
from psycopg2.extras import Json
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target
MIG=ROOT/'supabase'/'staging_only'/'171_release_safety_corrections.sql'
def body():
 s=MIG.read_text();s,n1=re.subn(r'(?im)^\s*begin;\s*$','',s,count=1);s,n2=re.subn(r'(?im)^\s*commit;\s*$','',s,count=1);assert(n1,n2)==(1,1);return s
def claims(c,uid,email,role='authenticated'):c.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(uid),'email':email,'role':role}),))
def expect_sqlstate(c,sql,params,state):
 c.execute('savepoint expected_failure')
 try:c.execute(sql,params)
 except psycopg2.Error as e:
  assert e.pgcode==state,(e.pgcode,e);c.execute('rollback to savepoint expected_failure')
 else:raise AssertionError(f'expected {state}: {sql}')
 c.execute('release savepoint expected_failure')
def main():
 dsn=os.getenv('PDC_STAGING_DIRECT_DATABASE_URL') or os.getenv('PDC_STAGING_DATABASE_URL');assert_staging_target(database_url=dsn)
 con=psycopg2.connect(dsn);con.autocommit=False
 try:
  with con.cursor() as c:
   c.execute("set local statement_timeout='180s'");c.execute(body())
   c.execute("select auth_user_id,email from public.pdc_user_roles where role::text='administrator' and active and account_status='approved' order by email limit 1");actor,email=c.fetchone();claims(c,actor,email)
   tag=uuid.uuid4().hex[:10];
   def vehicle(label,stock,deleted=False):
    c.execute("""insert into public.vehicles(permanent_vehicle_id,stock_number,lifecycle_state,visible_on_board,current_location,source_payload,deleted_at,deleted_reason,created_by,updated_by)
      values(%s,%s,%s,%s,'PMB','{}'::jsonb,%s,%s,%s,%s) returning id,version""",
      (f'FIX171-{label}-{tag}',stock,'deleted' if deleted else 'active',not deleted,'2026-08-11 00:00:00+00' if deleted else None,'fixture' if deleted else None,actor,actor));return c.fetchone()
   dead,deadver=vehicle('DEAD','81'+tag[:6],True);live,livever=vehicle('LIVE','82'+tag[:6],False)
   expect_sqlstate(c,"insert into public.vehicle_aliases(vehicle_id,alias_type,alias_value,source_system,active,created_by,updated_by) values(%s,'registration',%s,'manual',true,%s,%s)",(dead,'FIXREG'+tag,actor,actor),'23514')
   c.execute("insert into public.vehicle_aliases(vehicle_id,alias_type,alias_value,source_system,active,created_by,updated_by) values(%s,'registration',%s,'manual',true,%s,%s) returning id",(live,'FIXREG'+tag,actor,actor));raw_alias=c.fetchone()[0]
   other,_=vehicle('OTHER','83'+tag[:6],False)
   expect_sqlstate(c,"insert into public.vehicle_aliases(vehicle_id,alias_type,alias_value,source_system,active,created_by,updated_by) values(%s,'registration',%s,'manual',true,%s,%s)",(other,'FIXREG'+tag,actor,actor),'23505')
   conflict_stock='84'+tag[:6]
   c.execute("update public.vehicles set stock_number=%s where id=%s",(conflict_stock,dead))
   c.execute("insert into public.vehicle_aliases(vehicle_id,alias_type,alias_value,source_system,active,created_by,updated_by) values(%s,'stock_number',%s,'manual',true,%s,%s)",(live,conflict_stock,actor,actor))
   expect_sqlstate(c,"update public.vehicles set deleted_at=null,deleted_reason=null,lifecycle_state='active',visible_on_board=true where id=%s",(dead,),'23505')
   c.execute("select version from public.vehicle_aliases where id=%s",(raw_alias,));before_alias_version=c.fetchone()[0]
   c.execute("update public.vehicles set deleted_at=clock_timestamp(),deleted_reason='fixture',lifecycle_state='deleted',visible_on_board=false where id=%s",(live,))
   c.execute("select active,version from public.vehicle_aliases where id=%s",(raw_alias,));active,after_alias_version=c.fetchone();assert active is False and after_alias_version>before_alias_version,(active,before_alias_version,after_alias_version)
   # Historical Navision identity remains deleted and is never recreated by the 169 reconciler.
   c.execute("""select r.id,v.id from public.navision_backend_records r join public.vehicles v on v.id=r.canonical_vehicle_id
     where r.is_current and r.record_status='current' and v.deleted_at is null order by r.id limit 1""");row=c.fetchone()
   historical=True
   if row:
    backend,hv=row;c.execute("update public.vehicles set deleted_at=clock_timestamp(),deleted_reason='fixture',lifecycle_state='deleted',visible_on_board=false where id=%s",(hv,));c.execute("select public.reconcile_navision_operational_record(%s,%s,%s)",(backend,actor,email));res=c.fetchone()[0];assert res.get('ok') is True and res.get('code')=='historical_vehicle_retained',res;c.execute("select deleted_at is not null from public.vehicles where id=%s",(hv,));assert c.fetchone()==(True,)
   # Provider-attested exact replay and altered-payload conflict; explicit cancellation is evidenced.
   booking_vehicle,bv=vehicle('SUBLET','85'+tag[:6],False)
   c.execute("select id,name from public.sublet_providers where active order by name limit 1");provider,pname=c.fetchone();sender=f'qa-{tag}@example.com'
   c.execute("select public.create_pdc_sublet_booking(%s,%s,%s,current_date+10,current_date+12,%s,'fixture')",(booking_vehicle,bv,provider,sender));created=c.fetchone()[0];assert created.get('ok') is True,created;booking=created['data']['booking'];bid=booking['booking_id'];version=booking['version'];replay='fixture-replay-'+tag;received='2026-08-11T12:00:00+00:00';evidence={'fixture':tag}
   args=(replay,booking_vehicle,pname,sender,'eta_confirmed',None,'2026-08-24','fixture-'+tag,None,received,Json(evidence),version)
   c.execute("select public.apply_pdc_sublet_email_update(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",args);first=c.fetchone()[0];assert first.get('ok') is True and first.get('code')=='email_updated',first
   c.execute("select public.apply_pdc_sublet_email_update(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",args);replayed=c.fetchone()[0];assert replayed.get('ok') is True and replayed.get('code')=='replayed',replayed
   bad=list(args);bad[7]='altered-'+tag;c.execute("select public.apply_pdc_sublet_email_update(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",tuple(bad));conflict=c.fetchone()[0];assert conflict.get('ok') is False and conflict.get('code')=='replay_conflict',conflict
   bad_version=list(args);bad_version[11]=version+99;c.execute("select public.apply_pdc_sublet_email_update(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",tuple(bad_version));version_conflict=c.fetchone()[0];assert version_conflict.get('ok') is False and version_conflict.get('code')=='replay_conflict',version_conflict
   c.execute("select public.cancel_pdc_sublet_booking(%s,%s,'fixture cancellation')",(bid,first['data']['version']));cancelled=c.fetchone()[0];assert cancelled.get('ok') is True and cancelled.get('code')=='cancelled',cancelled
   c.execute("select count(*) from public.pdc_sublet_booking_instance_history where booking_id=%s and action='cancelled'",(bid,));assert c.fetchone()==(1,)
   # Adjacent planned bookings cascade latest-first around a new Admin block.
   c.execute("""select s.id,s.code,b.id,b.bay_number,wk.work_key,
     (select b2.id from public.workshop_bays b2 where b2.stage_id=s.id and b2.id<>b.id and b2.is_active and not b2.is_sublet_row order by b2.bay_number limit 1)
     from public.workshop_stages s join public.workshop_bays b on b.stage_id=s.id
     join lateral(select wi.work_key from public.vehicle_work_items wi where public.workshop_stage_code_for_work_key(wi.work_key)=s.code limit 1) wk on true
     where s.active and s.planner_enabled and s.is_physical and b.is_active and not b.is_sublet_row
       and exists(select 1 from public.workshop_bays b2 where b2.stage_id=s.id and b2.id<>b.id and b2.is_active and not b2.is_sublet_row)
     order by s.code,b.bay_number limit 1""");stage,stage_code,bay,bay_no,work_key,other_bay=c.fetchone()
   c.execute("""select ts from generate_series(date_trunc('minute',clock_timestamp())+interval '1 day',date_trunc('minute',clock_timestamp())+interval '30 days',interval '15 minutes') ts
     where public.workshop_calendar_minute_available(ts) and public.workshop_operational_minutes_between(ts,public.workshop_add_operational_minutes(ts,180))=180 order by ts limit 1""");start=c.fetchone()[0]
   v1,_=vehicle('BOOK1','86'+tag[:6],False);v2,_=vehicle('BOOK2','87'+tag[:6],False)
   c.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,%s,true,false),(%s,%s,true,false)",(v1,work_key,v2,work_key))
   c.execute("""insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
     values(%s,%s,'manual',%s,'Migration 171 effective duration fixture',2.00,%s,%s)""",(v1,'manual:fixture:'+tag,stage_code,actor,actor))
   c.execute("select public.workshop_add_operational_minutes(%s,120),public.workshop_add_operational_minutes(%s,180),public.workshop_add_operational_minutes(%s,240)",(start,start,start));end1,end2,external_end=c.fetchone()
   ids=[]
   for veh,st,en,duration in ((v1,start,end1,120),(v2,end1,end2,60)):
    c.execute("""insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by)
      values(%s,%s,%s,'planned',%s,%s,%s,%s,%s) returning id""",(veh,stage,bay,st,en,duration,actor,actor));ids.append(c.fetchone()[0])
   c.execute("""insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by)
     values(%s,%s,%s,'planned',%s,%s,120,%s,%s) returning id""",(v1,stage,other_bay,end1,external_end,actor,actor));external_booking=c.fetchone()[0]
   # Canonical Sublet creation must fail against scheduled Workshop work.
   c.execute('savepoint canonical_sublet_overlap')
   try:
    c.execute("select public.create_pdc_sublet_booking(%s,1,%s,%s,%s,%s,%s)",(v2,provider,start.date(),start.date(),'overlap@example.invalid','fixture overlap'))
    overlap_result=c.fetchone()[0];assert overlap_result.get('ok') is False,overlap_result
   except psycopg2.Error as exc:
    assert exc.pgcode=='23514',exc
    c.execute('rollback to savepoint canonical_sublet_overlap')
   c.execute('release savepoint canonical_sublet_overlap')
   c.execute("select public.workshop_current_revision()");revision=c.fetchone()[0]
   c.execute("select public.create_workshop_admin_block(%s,%s,%s,'admin','Fixture',%s,60,'{}'::jsonb)",(revision,stage_code,bay_no,start));block=c.fetchone()[0];assert block.get('ok') is True,block;assert block['repack']['shifted_count']==2,block
   c.execute("select scheduled_start_at,scheduled_end_at,default_duration_minutes from public.workshop_bookings where id=%s",(ids[0],));first_time=c.fetchone()
   c.execute("select scheduled_start_at,scheduled_end_at,default_duration_minutes from public.workshop_bookings where id=%s",(ids[1],));second_time=c.fetchone()
   assert first_time[0]==external_end and first_time[2]==120,first_time
   assert second_time[0]==first_time[1] and second_time[2]==60,second_time
   print(json.dumps({'ok':True,'migration':171,'alias_live_owner':True,'active_raw_unique':True,'reactivation_guard':True,'alias_versioned_deactivation':True,'historical_identity_retained':historical,'sublet_replay_bound':True,'sublet_expected_version_bound':True,'sublet_cancel_evidenced':True,'canonical_sublet_workshop_conflict':True,'admin_adjacent_cascade':True,'admin_effective_duration':True,'admin_same_vehicle_conflict':True},sort_keys=True))
  con.rollback();return 0
 finally:con.rollback();con.close()
if __name__=='__main__':raise SystemExit(main())
