"""Rollback-only staging proof for migration 043 on the applied migration-042 baseline."""
import json,os,pathlib,uuid
from datetime import date,timedelta,datetime,timezone
import psycopg2,psycopg2.extras
psycopg2.extras.register_uuid()
ROOT=pathlib.Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/043_all_station_review_closure.sql').read_text(encoding='utf-8')
ALIASES={
 'BUS_4X4':['BUS4X4','4X4BUS','DEPARTMENT138','DEPT138'],'TINT':['TINT','TINTING','WINDOWTINT'],
 'HOIST':['HOIST','PITSHOIST','PITHOIST','EXPRESSHOIST'],'FITTING':['FITTING','FITMENT','FITOUT','EXPRESSFITOUT'],
 'FABRICATION':['FABRICATION','FAB','FABRICATING'],'ELECTRICAL':['ELECTRICAL','ELEC','AUTOELECTRICAL','AUTOELEC'],
 'TYRE':['TYRE','TYRES','TYREBAY','TIRE','TIREBAY'],'PIT_INSPECTION':['PITINSPECTION','PIT','PITS','INSPECTION'],
 'SUBLET':['SUBLET','OUTSOURCE','OUTSOURCED','EXTERNAL']}
conn=psycopg2.connect(os.environ['PDC_STAGING_DATABASE_URL']); conn.autocommit=False; q=conn.cursor()
try:
 q.execute(SQL)
 for stage,aliases in ALIASES.items():
  q.execute('select alias_normalized from public.workshop_stage_aliases where stage_code=%s',(stage,)); actual={r[0] for r in q.fetchall()}
  assert set(aliases)<=actual,(stage,set(aliases)-actual)
 admin_email=os.environ['PDC_STAGING_ADMIN_EMAIL'].lower(); q.execute('select id from auth.users where lower(email)=%s',(admin_email,)); admin=q.fetchone()[0]
 q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':admin_email,'role':'authenticated'}),))
 vehicle=uuid.uuid4(); stock='FIX043-'+uuid.uuid4().hex[:10].upper()
 q.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,visible_on_board,version,lifecycle_state,updated_by) values(%s,%s,%s,'YH','UNALLOCATED',false,1,'active',%s)",(vehicle,uuid.uuid4(),stock,admin))
 start=datetime.combine(date.today()+timedelta(days=1),datetime.min.time(),tzinfo=timezone.utc)+timedelta(hours=1)
 q.execute("select id from public.workshop_stages where code='SUBLET'"); sublet_stage=q.fetchone()[0]
 q.execute('alter table public.workshop_bookings disable trigger workshop_bookings_planner_enabled_guard')
 q.execute('alter table public.workshop_bookings disable trigger workshop_bookings_require_planner_operator')
 q.execute("insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by) values(%s,%s,null,'planned',%s,%s,60,%s,%s) returning id,version",(vehicle,sublet_stage,start+timedelta(hours=8),start+timedelta(hours=9),admin,admin)); sublet_booking,sublet_version=q.fetchone()
 q.execute('alter table public.workshop_bookings enable trigger workshop_bookings_planner_enabled_guard')
 q.execute('alter table public.workshop_bookings enable trigger workshop_bookings_require_planner_operator')
 q.execute("select public.schedule_vehicle_work(%s,1,'BUS_4X4',1,%s,60,null,null,'{}'::jsonb)",(vehicle,start)); result=q.fetchone()[0]; assert result['ok'] is True,result
 q.execute('select current_location,pmb_stage,visible_on_board from public.vehicles where id=%s',(vehicle,)); assert q.fetchone()==('YH','UNALLOCATED',False)
 q.execute('select count(*) from public.workshop_booking_history where booking_id=%s',(sublet_booking,)); sublet_history_before=q.fetchone()[0]
 q.execute('savepoint sublet_lifecycle_denied')
 try:
  q.execute("select public.start_workshop_work(%s,%s,%s,'{}'::jsonb)",(sublet_booking,sublet_version,start+timedelta(hours=8))); raise AssertionError('historical Sublet booking unexpectedly started')
 except psycopg2.Error as e:
  assert e.pgcode=='22023',e; q.execute('rollback to savepoint sublet_lifecycle_denied')
 q.execute('select status,version from public.workshop_bookings where id=%s',(sublet_booking,)); assert q.fetchone()==('planned',sublet_version)
 q.execute('select count(*) from public.workshop_booking_history where booking_id=%s',(sublet_booking,)); assert q.fetchone()[0]==sublet_history_before
 q.execute("select public.complete_workshop_work(%s,%s,'SUBLET',%s,'{}'::jsonb)",(sublet_booking,sublet_version,start+timedelta(hours=9))); assert q.fetchone()[0]['ok'] is True
 q.execute('select status from public.workshop_bookings where id=%s',(sublet_booking,)); assert q.fetchone()[0]=='completed'
 q.execute("select count(*)>0 from public.vehicle_work_items where vehicle_id=%s and required and completed and public.workshop_stage_code_for_work_key(work_key)='SUBLET'",(vehicle,)); assert q.fetchone()[0] is True
 for signature in [
  'public.workshop_start_booking(uuid,integer,timestamp with time zone,jsonb)',
  'public.workshop_resume_booking(uuid,integer,jsonb)',
  'public.workshop_return_booking_to_queue(uuid,integer,text,jsonb)',
  'public.workshop_delete_booking(uuid,integer,text,jsonb)',
  'public.workshop_restore_booking(uuid,integer,jsonb)']:
  q.execute("select has_function_privilege('authenticated',%s,'EXECUTE')",(signature,)); assert q.fetchone()[0] is False,signature
 importer='fixture-importer-'+uuid.uuid4().hex+'@example.invalid'; q.execute("insert into public.pdc_user_roles(email,display_name,role,active) values(%s,'Fixture Importer','importer',true)",(importer,))
 q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':importer,'role':'authenticated'}),))
 q.execute('savepoint importer_denied')
 try:
  q.execute('select public.get_workshop_eligibility_snapshot()'); raise AssertionError('importer read unexpectedly allowed')
 except psycopg2.Error as e:
  assert e.pgcode=='42501',e; q.execute('rollback to savepoint importer_denied')
 q.execute('savepoint importer_schedule_denied')
 try:
  q.execute("select public.schedule_vehicle_work(%s,2,'BUS_4X4',1,%s,60,null,null,'{}'::jsonb)",(vehicle,start+timedelta(hours=2))); raise AssertionError('importer scheduling unexpectedly allowed')
 except psycopg2.Error as e:
  assert e.pgcode=='42501',e; q.execute('rollback to savepoint importer_schedule_denied')
 q.execute('savepoint importer_direct_booking_denied')
 try:
  q.execute("select public.workshop_create_booking(%s,'BUS_4X4',1,%s,60,null,'{}'::jsonb)",(vehicle,start+timedelta(hours=3))); raise AssertionError('importer direct booking unexpectedly allowed')
 except psycopg2.Error as e:
  assert e.pgcode=='42501',e; q.execute('rollback to savepoint importer_direct_booking_denied')
 q.execute('update public.vehicles set eta_to_kewdale=%s where id=%s',(date.today()+timedelta(days=5),vehicle))
 q.execute("select eta_risk_status from public.workshop_bookings where vehicle_id=%s and status='planned' and deleted_at is null",(vehicle,))
 assert q.fetchone()[0]=='at_risk','importer ETA update must retain nested ETA-risk maintenance'
 q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':admin_email,'role':'authenticated'}),))
 q.execute('savepoint station_disable_revision')
 q.execute("select revision from public.workshop_station_revision where stage_code='HOIST'"); disabled_before=q.fetchone()[0]
 q.execute("update public.workshop_stages set planner_enabled=false where code='HOIST'")
 q.execute("select revision from public.workshop_station_revision where stage_code='HOIST'"); assert q.fetchone()[0]>disabled_before
 try:
  q.execute("select public.get_station_workshop_snapshot('HOIST',current_date,current_date)"); raise AssertionError('disabled station snapshot unexpectedly allowed')
 except psycopg2.Error as e:
  assert e.pgcode=='22023',e; q.execute('rollback to savepoint station_disable_revision')
 q.execute("select revision from public.workshop_station_revision where stage_code='HOIST'"); before=q.fetchone()[0]
 q.execute("insert into public.workshop_stage_aliases(alias_normalized,alias_value,stage_code) values(%s,%s,'HOIST')",('FIXTUREALIAS'+uuid.uuid4().hex.upper(),'Fixture Alias'))
 q.execute("select revision from public.workshop_station_revision where stage_code='HOIST'"); assert q.fetchone()[0]>before
 q.execute("select public.get_station_workshop_snapshot('Pits Hoist',current_date,current_date)"); assert q.fetchone()[0]['stage']=='HOIST'
 print(json.dumps({'migration_043_transactional':True,'yh_without_eta_scheduled':True,'location_stage_visibility_unchanged':True,'importer_snapshot_schedule_and_direct_booking_denied':True,'importer_eta_risk_maintenance_preserved':True,'sublet_lifecycle_denied':True,'sublet_completion_preserved':True,'legacy_low_level_lifecycle_revoked':True,'alias_parity':sum(map(len,ALIASES.values())),'config_revision_bumped':True,'disabled_station_revision_bumped':True,'rolled_back':True}))
finally:
 conn.rollback(); conn.close()
