"""Rollback-only staging proof for corrective migration 044 on the applied migration-042 baseline."""
import json,os,pathlib,uuid
from datetime import date,timedelta,datetime,timezone
import psycopg2,psycopg2.extras
psycopg2.extras.register_uuid()
ROOT=pathlib.Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/044_blocker_only_all_station_release_closure.sql').read_text(encoding='utf-8')
ALIASES={
 'BUS_4X4':['BUS4X4','4X4BUS','DEPARTMENT138','DEPT138'],'TINT':['TINT','TINTING','WINDOWTINT'],
 'HOIST':['HOIST','PITSHOIST','PITHOIST','EXPRESSHOIST'],'FITTING':['FITTING','FITMENT','FITOUT','EXPRESSFITOUT'],
 'FABRICATION':['FABRICATION','FAB','FABRICATING'],'ELECTRICAL':['ELECTRICAL','ELEC','AUTOELECTRICAL','AUTOELEC'],
 'TYRE':['TYRE','TYRES','TYREBAY','TIRE','TIREBAY'],'PIT_INSPECTION':['PITINSPECTION','PIT','PITS','INSPECTION'],
 'SUBLET':['SUBLET','OUTSOURCE','OUTSOURCED','EXTERNAL']}
conn=psycopg2.connect(os.environ['PDC_STAGING_DATABASE_URL']); conn.autocommit=False; q=conn.cursor()
def vehicle_authority(vehicle_id):
 q.execute("""select jsonb_build_object(
  'pmb_stage',v.pmb_stage,'current_location',v.current_location,'pmb_bay_stage',v.pmb_bay_stage,
  'pmb_bay_number',v.pmb_bay_number,'visible_on_board',v.visible_on_board,
  'workshop_status',v.workshop_status,'active_workshop_booking_id',v.active_workshop_booking_id,
  'version',v.version,'requirements',coalesce((select jsonb_agg(jsonb_build_object(
   'work_key',w.work_key,'required',w.required,'completed',w.completed,'completed_at',w.completed_at)
   order by w.work_key) from public.vehicle_work_items w where w.vehicle_id=v.id),'[]'::jsonb))
  from public.vehicles v where v.id=%s""",(vehicle_id,))
 return q.fetchone()[0]

def assert_authority_unchanged(vehicle_id, expected, operation):
 actual=vehicle_authority(vehicle_id)
 assert actual==expected,(operation,expected,actual)
try:
 q.execute(SQL)
 for stage,aliases in ALIASES.items():
  q.execute('select alias_normalized from public.workshop_stage_aliases where stage_code=%s',(stage,)); actual={r[0] for r in q.fetchall()}
  assert set(aliases)<=actual,(stage,set(aliases)-actual)
 q.execute('select count(*) from public.workshop_stage_aliases'); alias_count=q.fetchone()[0]; assert alias_count==37
 admin_email=os.environ['PDC_STAGING_ADMIN_EMAIL'].lower(); q.execute('select id from auth.users where lower(email)=%s',(admin_email,)); admin=q.fetchone()[0]
 q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':admin_email,'role':'authenticated'}),))
 vehicle=uuid.uuid4(); stock='FIX043-'+uuid.uuid4().hex[:10].upper()
 q.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,visible_on_board,version,lifecycle_state,updated_by) values(%s,%s,%s,'YH','UNALLOCATED',false,1,'active',%s)",(vehicle,uuid.uuid4(),stock,admin))
 q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,'BUS4X4',true,false)",(vehicle,))
 outsider=uuid.uuid4()
 q.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,visible_on_board,version,lifecycle_state,updated_by) values(%s,%s,%s,'OUTSIDE','UNALLOCATED',false,1,'active',%s)",(outsider,uuid.uuid4(),'OUT043-'+uuid.uuid4().hex[:10].upper(),admin))
 q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,'BUS4X4',true,false)",(outsider,))
 start=datetime.combine(date.today()+timedelta(days=1),datetime.min.time(),tzinfo=timezone.utc)+timedelta(hours=1)
 inactive_vehicle,deleted_vehicle,out_window_vehicle,deleted_booking_vehicle=[uuid.uuid4() for _ in range(4)]
 q.execute("""insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,visible_on_board,version,lifecycle_state,deleted_at,updated_by) values
  (%s,%s,%s,'PMB','UNALLOCATED',false,1,'completed',null,%s),
  (%s,%s,%s,'PMB','UNALLOCATED',false,1,'active',now(),%s),
  (%s,%s,%s,'PMB','UNALLOCATED',false,1,'active',null,%s),
  (%s,%s,%s,'PMB','UNALLOCATED',false,1,'active',null,%s)""",
  (inactive_vehicle,uuid.uuid4(),'INACTIVE-'+uuid.uuid4().hex[:8],admin,
   deleted_vehicle,uuid.uuid4(),'DELETED-'+uuid.uuid4().hex[:8],admin,
   out_window_vehicle,uuid.uuid4(),'OUTWINDOW-'+uuid.uuid4().hex[:8],admin,
   deleted_booking_vehicle,uuid.uuid4(),'DELBOOK-'+uuid.uuid4().hex[:8],admin))
 q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,'BUS4X4',true,false),(%s,'BUS4X4',true,false)",(inactive_vehicle,deleted_vehicle))
 q.execute("select id from public.workshop_stages where code='BUS_4X4'"); bus_stage=q.fetchone()[0]
 q.execute('alter table public.workshop_bookings disable trigger workshop_bookings_planner_enabled_guard')
 q.execute("""insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,deleted_at,deleted_reason,created_by,updated_by) values
  (%s,%s,null,'planned',%s,%s,60,null,null,%s,%s),
  (%s,%s,null,'planned',%s,%s,60,null,null,%s,%s),
  (%s,%s,null,'planned',%s,%s,60,null,null,%s,%s),
  (%s,%s,null,'planned',%s,%s,60,now(),'fixture deleted booking',%s,%s)""",
  (inactive_vehicle,bus_stage,start,start+timedelta(hours=1),admin,admin,
   deleted_vehicle,bus_stage,start,start+timedelta(hours=1),admin,admin,
   out_window_vehicle,bus_stage,start+timedelta(days=10),start+timedelta(days=10,hours=1),admin,admin,
   deleted_booking_vehicle,bus_stage,start,start+timedelta(hours=1),admin,admin))
 q.execute('alter table public.workshop_bookings enable trigger workshop_bookings_planner_enabled_guard')
 # Adversarial soft deletion: a whitelisted status must still be excluded.
 # Bayless soft-deleted booking at an ineligible location with no outstanding
 # requirement must never be restorable into aggregate planner authority.
 restore_ineligible_vehicle=uuid.uuid4()
 q.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,visible_on_board,version,lifecycle_state,updated_by) values(%s,%s,%s,'OTHER','UNALLOCATED',false,1,'active',%s)",(restore_ineligible_vehicle,uuid.uuid4(),'RESTORE-'+uuid.uuid4().hex[:8],admin))
 q.execute('alter table public.workshop_bookings disable trigger workshop_bookings_planner_enabled_guard')
 q.execute("insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,deleted_at,deleted_reason,created_by,updated_by) values(%s,%s,null,'planned',%s,%s,60,now(),'fixture restore eligibility',%s,%s) returning id,version",(restore_ineligible_vehicle,bus_stage,start,start+timedelta(hours=1),admin,admin)); restore_ineligible_booking,restore_ineligible_version=q.fetchone()
 q.execute('alter table public.workshop_bookings enable trigger workshop_bookings_planner_enabled_guard')
 q.execute("select id from public.workshop_stages where code='SUBLET'"); sublet_stage=q.fetchone()[0]
 q.execute('alter table public.workshop_bookings disable trigger workshop_bookings_planner_enabled_guard')
 q.execute('alter table public.workshop_bookings disable trigger workshop_bookings_require_planner_operator')
 q.execute("insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by) values(%s,%s,null,'planned',%s,%s,60,%s,%s) returning id,version",(vehicle,sublet_stage,start+timedelta(hours=8),start+timedelta(hours=9),admin,admin)); sublet_booking,sublet_version=q.fetchone()
 q.execute('alter table public.workshop_bookings enable trigger workshop_bookings_planner_enabled_guard')
 q.execute('alter table public.workshop_bookings enable trigger workshop_bookings_require_planner_operator')
 protected=vehicle_authority(vehicle)
 q.execute("select public.schedule_vehicle_work(%s,1,'BUS_4X4',1,%s,60,null,null,'{}'::jsonb)",(vehicle,start)); result=q.fetchone()[0]; assert result['ok'] is True,result
 q.execute('select current_location,pmb_stage,visible_on_board from public.vehicles where id=%s',(vehicle,)); assert q.fetchone()==('YH','UNALLOCATED',False)
 assert_authority_unchanged(vehicle,protected,'create')
 q.execute("select b.id,b.version from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id where b.vehicle_id=%s and s.code='BUS_4X4' and b.deleted_at is null",(vehicle,)); bus_booking,bus_version=q.fetchone()
 q.execute("select public.move_workshop_booking(%s,%s,'BUS_4X4',1,%s,60,null,'{}'::jsonb)",(bus_booking,bus_version,start+timedelta(hours=2))); assert q.fetchone()[0]['ok'] is True
 assert_authority_unchanged(vehicle,protected,'move')
 q.execute('select current_location,pmb_stage,visible_on_board from public.vehicles where id=%s',(vehicle,)); assert q.fetchone()==('YH','UNALLOCATED',False),'booking move changed vehicle authority'
 # A soft-deleted planned bystander that otherwise satisfies every eligibility
 # condition must never enter or be mutated by a same-bay cascade.
 cascade_deleted_vehicle=uuid.uuid4()
 q.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,visible_on_board,version,lifecycle_state,updated_by) values(%s,%s,%s,'PMB','UNALLOCATED',false,1,'active',%s)",(cascade_deleted_vehicle,uuid.uuid4(),'CASDEL-'+uuid.uuid4().hex[:8],admin))
 q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,'BUS4X4',true,false)",(cascade_deleted_vehicle,))
 q.execute("select id from public.workshop_bays where stage_id=%s and bay_number=1",(bus_stage,)); bus_bay=q.fetchone()[0]
 q.execute("insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,deleted_at,deleted_reason,created_by,updated_by) values(%s,%s,%s,'planned',%s,%s,60,now(),'fixture cascade soft delete',%s,%s) returning id,version,scheduled_start_at",(cascade_deleted_vehicle,bus_stage,bus_bay,start+timedelta(hours=6),start+timedelta(hours=7),admin,admin)); cascade_deleted_booking,cascade_deleted_version,cascade_deleted_start=q.fetchone()
 q.execute('savepoint ineligible_cross_station_move_denied')
 try:
  q.execute("select public.move_workshop_booking(%s,%s,'TINT',1,%s,60,'fixture eligibility probe','{}'::jsonb)",(bus_booking,bus_version,start+timedelta(hours=3))); raise AssertionError('move to station without target eligibility unexpectedly allowed')
 except psycopg2.Error as e:
  assert e.pgcode=='22023',e; q.execute('rollback to savepoint ineligible_cross_station_move_denied')
 q.execute('savepoint ineligible_restore_denied')
 try:
  q.execute("select public.restore_workshop_booking(%s,%s,'{}'::jsonb)",(restore_ineligible_booking,restore_ineligible_version)); raise AssertionError('bayless deleted booking without canonical location/requirement unexpectedly restored')
 except psycopg2.Error as e:
  assert e.pgcode=='22023',e; q.execute('rollback to savepoint ineligible_restore_denied')
 q.execute("select id,version from public.workshop_bookings where vehicle_id=%s",(inactive_vehicle,)); inactive_booking,inactive_version=q.fetchone()
 q.execute('savepoint inactive_resize_denied')
 try:
  q.execute("select public.resize_workshop_booking(%s,%s,120,'{}'::jsonb)",(inactive_booking,inactive_version)); raise AssertionError('inactive vehicle booking resize unexpectedly allowed')
 except psycopg2.Error as e:
  assert e.pgcode=='22023',e; q.execute('rollback to savepoint inactive_resize_denied')
 inactive_lifecycle_statements=[
  ('assign',"select public.assign_booking_technician(%s,%s,null,'{}'::jsonb)"),
  ('start',"select public.start_workshop_work(%s,%s,now(),'{}'::jsonb)"),
  ('stop',"select public.stop_workshop_work(%s,%s,'probe','{}'::jsonb)"),
  ('complete',"select public.complete_workshop_work(%s,%s,null,now(),'{}'::jsonb)"),
  ('return_completed',"select public.return_completed_work(%s,%s,'probe','{}'::jsonb)"),
  ('return_queue',"select public.return_work_to_queue(%s,%s,'probe','{}'::jsonb)"),
  ('cancel',"select public.cancel_workshop_booking(%s,%s,'probe','{}'::jsonb)"),
  ('restore',"select public.restore_workshop_booking(%s,%s,'{}'::jsonb)"),
  ('resume',"select public.resume_workshop_work(%s,%s,'{}'::jsonb)"),
 ]
 for label,statement in inactive_lifecycle_statements:
  q.execute('savepoint inactive_lifecycle_denied')
  try:
   q.execute(statement,(inactive_booking,inactive_version)); raise AssertionError(f'inactive vehicle {label} unexpectedly allowed')
  except psycopg2.Error as e:
   assert e.pgcode=='22023',(label,e); q.execute('rollback to savepoint inactive_lifecycle_denied')
 q.execute('select version from public.workshop_bookings where id=%s',(bus_booking,)); bus_version=q.fetchone()[0]
 q.execute("select public.resize_workshop_booking(%s,%s,120,'{}'::jsonb)",(bus_booking,bus_version)); assert q.fetchone()[0]['ok'] is True
 assert_authority_unchanged(vehicle,protected,'resize')
 q.execute('select version,scheduled_start_at from public.workshop_bookings where id=%s',(bus_booking,)); bus_version,bus_start=q.fetchone()
 q.execute("select public.cascade_workshop_schedule('extend',%s,%s,'BUS_4X4',1,%s,180,null,60,null,'{}'::jsonb)",(bus_booking,bus_version,bus_start)); assert q.fetchone()[0]['ok'] is True
 q.execute('select version,scheduled_start_at,deleted_at from public.workshop_bookings where id=%s',(cascade_deleted_booking,)); cascade_after=q.fetchone()
 assert cascade_after[0]==cascade_deleted_version and cascade_after[1]==cascade_deleted_start and cascade_after[2] is not None,'cascade mutated soft-deleted planned bystander'
 assert_authority_unchanged(vehicle,protected,'cascade')
 q.execute('select version from public.workshop_bookings where id=%s',(bus_booking,)); bus_version=q.fetchone()[0]
 q.execute("select public.start_workshop_work(%s,%s,now(),'{}'::jsonb)",(bus_booking,bus_version)); assert q.fetchone()[0]['ok'] is True
 assert_authority_unchanged(vehicle,protected,'start')
 q.execute('select version from public.workshop_bookings where id=%s',(bus_booking,)); bus_version=q.fetchone()[0]
 q.execute("select public.stop_workshop_work(%s,%s,'fixture pause','{}'::jsonb)",(bus_booking,bus_version)); assert q.fetchone()[0]['ok'] is True
 assert_authority_unchanged(vehicle,protected,'stop')
 q.execute('select version from public.workshop_bookings where id=%s',(bus_booking,)); bus_version=q.fetchone()[0]
 q.execute("select public.resume_workshop_work(%s,%s,'{}'::jsonb)",(bus_booking,bus_version)); assert q.fetchone()[0]['ok'] is True
 assert_authority_unchanged(vehicle,protected,'resume')
 q.execute('select version from public.workshop_bookings where id=%s',(bus_booking,)); bus_version=q.fetchone()[0]
 q.execute("select public.return_work_to_queue(%s,%s,'fixture return','{}'::jsonb)",(bus_booking,bus_version)); assert q.fetchone()[0]['ok'] is True
 assert_authority_unchanged(vehicle,protected,'return')
 q.execute('select version from public.workshop_bookings where id=%s',(bus_booking,)); bus_version=q.fetchone()[0]
 q.execute("select public.cancel_workshop_booking(%s,%s,'fixture delete','{}'::jsonb)",(bus_booking,bus_version)); assert q.fetchone()[0]['ok'] is True
 assert_authority_unchanged(vehicle,protected,'delete')
 q.execute('select version from public.workshop_bookings where id=%s',(bus_booking,)); bus_version=q.fetchone()[0]
 q.execute("select public.restore_workshop_booking(%s,%s,'{}'::jsonb)",(bus_booking,bus_version)); assert q.fetchone()[0]['ok'] is True
 assert_authority_unchanged(vehicle,protected,'restore')
 # Put the fixture back in planned state so the approved Navision ETA workflow
 # exercises the nested eta-risk booking update under an importer JWT.
 q.execute("update public.workshop_bookings set status='planned' where id=%s",(bus_booking,))
 q.execute("select public.get_station_workshop_snapshot('BUS_4X4',%s,%s)",(date.today(),date.today()+timedelta(days=2))); snapshot=q.fetchone()[0]
 snapshot_vehicle_ids={row['id'] for row in snapshot['vehicles']}; snapshot_work_item_ids={row['vehicle_id'] for row in snapshot['work_items']}
 excluded_fixture_ids={str(outsider),str(inactive_vehicle),str(deleted_vehicle),str(out_window_vehicle),str(deleted_booking_vehicle),str(restore_ineligible_vehicle)}
 snapshot_booking_vehicle_ids={row['vehicle_id'] for row in snapshot['bookings']}
 assert str(cascade_deleted_vehicle) not in snapshot_booking_vehicle_ids,'soft-deleted cascade bystander leaked into station booking DTO'
 assert not (excluded_fixture_ids & snapshot_vehicle_ids) and not (excluded_fixture_ids & snapshot_work_item_ids) and not (excluded_fixture_ids & snapshot_booking_vehicle_ids),'out-of-scope, inactive, deleted or out-of-window fixture leaked into station DTO'
 q.execute('select public.get_workshop_eligibility_snapshot()'); aggregate=q.fetchone()[0]
 aggregate_vehicle_ids={row['vehicle']['id'] for row in aggregate['candidates']}
 assert str(deleted_booking_vehicle) not in aggregate_vehicle_ids,'soft-deleted active-looking booking leaked into aggregate eligibility DTO'
 assert snapshot_work_item_ids<=snapshot_vehicle_ids,'station DTO work_items must be scoped to returned vehicles'
 assert set(snapshot)=={'revision','generated_at','scope','stages','bays','bookings','vehicles','work_items'},snapshot.keys()
 assert all(set(row)=={'id','code','display_name','is_physical','work_key'} for row in snapshot['stages'])
 assert all(set(row)=={'id','bay_number','code','display_name'} for row in snapshot['bays'])
 assert all(set(row)=={'vehicle_id','work_key','required','completed','completed_at'} for row in snapshot['work_items'])
 booking_keys={'booking_id','vehicle_id','stage','bay','status','scheduled_start_at','scheduled_end_at','default_duration_minutes','actual_start_at','actual_end_at','stoppage_reason','stoppage_started_at','stoppage_accumulated_minutes','version','assignment'}
 assert all(set(row)==booking_keys for row in snapshot['bookings'])
 assert all(set(row['stage'])=={'id','code','display_name','is_physical','work_key'} for row in snapshot['bookings'])
 assert all(row['bay'] is None or set(row['bay'])=={'id','bay_number','code','display_name'} for row in snapshot['bookings'])
 assert all(row['assignment'] is None or set(row['assignment'])=={'technician_id','technician_name','assignment_type'} for row in snapshot['bookings'])
 q.execute('savepoint oversized_date_window_denied')
 try:
  q.execute("select public.get_station_workshop_snapshot('BUS_4X4',current_date,current_date+32)"); raise AssertionError('oversized snapshot date window unexpectedly allowed')
 except psycopg2.Error as e:
  assert e.pgcode=='22023',e; q.execute('rollback to savepoint oversized_date_window_denied')
 fixture_vehicle=next(row for row in snapshot['vehicles'] if row['id']==str(vehicle))
 assert set(fixture_vehicle)=={'id','permanent_vehicle_id','stock_number','toyota_order_number','job_card_number','make','model','registration','current_location','pmb_stage','pmb_bay_stage','pmb_bay_number','eta_to_kewdale','active_workshop_booking_id','workshop_status','version'},fixture_vehicle.keys()
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
 q.execute("select count(*)=0 from public.vehicle_work_items where vehicle_id=%s and required and completed and public.workshop_stage_code_for_work_key(work_key)='SUBLET'",(vehicle,)); assert q.fetchone()[0] is True
 for signature in [
  'public.workshop_start_booking(uuid,integer,timestamp with time zone,jsonb)',
  'public.workshop_resume_booking(uuid,integer,jsonb)',
  'public.workshop_return_booking_to_queue(uuid,integer,text,jsonb)',
  'public.workshop_delete_booking(uuid,integer,text,jsonb)',
  'public.workshop_restore_booking(uuid,integer,jsonb)',
  'public.workshop_complete_booking(uuid,integer,timestamp with time zone,jsonb)']:
  q.execute("select has_function_privilege('authenticated',%s,'EXECUTE')",(signature,)); assert q.fetchone()[0] is False,signature
 q.execute("select has_function_privilege('authenticated','public.get_workshop_snapshot(date,date)','EXECUTE')"); assert q.fetchone()[0] is False,'legacy broad snapshot must be browser-inaccessible'
 q.execute("""select schemaname,tablename,policyname from pg_policies where schemaname in ('public','storage') and
  (coalesce(qual,'') ilike '%is_pdc_role%operator%' or coalesce(with_check,'') ilike '%is_pdc_role%operator%' or
   coalesce(qual,'') ilike '%is_pdc_role%importer%' or coalesce(with_check,'') ilike '%is_pdc_role%importer%' or
   coalesce(qual,'') ilike '%current_pdc_user_role%importer%' or coalesce(with_check,'') ilike '%current_pdc_user_role%importer%')""")
 assert q.fetchall()==[],'inherited importer-permissive direct-table/storage policy remains after migration 044'
 importer='fixture-importer-'+uuid.uuid4().hex+'@example.invalid'; operator=os.environ['PDC_STAGING_CONTROLLER_A_EMAIL'].strip().lower(); viewer=os.environ['PDC_STAGING_VIEWER_EMAIL'].strip().lower()
 q.execute("insert into public.pdc_user_roles(email,display_name,role,active) values(%s,'Fixture Importer','importer',true)",(importer,))
 q.execute("select lower(email),role::text from public.pdc_user_roles where lower(email) in (%s,%s)",(operator,viewer)); real_roles=dict(q.fetchall())
 assert real_roles.get(operator)=='operator' and real_roles.get(viewer)=='viewer',real_roles
 workshop_tables=['vehicles','vehicle_aliases','vehicle_master_revision','vehicle_lifecycle_resolver_revision','vehicle_master_source_records','vehicle_master_operation_receipts','vehicle_master_history','vehicle_master_identity_conflicts','vehicle_movements','vehicle_parts_updates','vehicle_eta_history','vehicle_timeline_events','vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_match_candidates','deleted_completed_vehicles','vehicle_notifications','vehicle_work_items','workshop_stages','workshop_stage_aliases','workshop_technicians','workshop_bays','workshop_settings','workshop_bookings','workshop_booking_assignments','workshop_booking_history','workshop_parts_overrides','workshop_revision','workshop_station_revision','ai_email_analysis_results','ai_email_attachments','ai_email_intake','ai_extracted_fields','ai_intake_config','ai_mapping_rules','ai_proposed_actions','ai_review_items','ai_trusted_senders','ai_undo_actions','ai_workshop_commands','monitored_mailboxes','email_response_drafts','audit_events','import_runs','label_print_events','salespeople','sublet_providers','navision_backend_revision','navision_import_batches','navision_backend_records','navision_import_items','navision_operation_receipts','navision_rollback_items','navision_backend_audit']
 for email,role,allowed in [(admin_email,'administrator',True),(operator,'operator',True),(viewer,'viewer',False),(importer,'importer',False)]:
  q.execute('reset role')
  q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':email,'role':'authenticated'}),))
  q.execute('set local role authenticated')
  for table in workshop_tables:
   q.execute(f'select count(*) from public.{table}')
   count=q.fetchone()[0]
   if not allowed: assert count==0,(role,table,count)
  if allowed:
   q.execute('select count(*) from public.workshop_stage_aliases'); assert q.fetchone()[0]==37,(role,'aliases')
   q.execute('select count(*) from public.workshop_station_revision'); assert q.fetchone()[0]>0,(role,'realtime')
   q.execute("select public.get_station_workshop_snapshot('BUS_4X4',current_date,current_date+2)"); assert q.fetchone()[0]['scope']['stage_code']=='BUS_4X4'
   q.execute('select public.get_workshop_configuration()'); assert isinstance(q.fetchone()[0],dict)
   q.execute('select count(*) from public.list_workshop_bays(false)'); assert q.fetchone()[0]>0
   q.execute('select count(*) from public.list_technicians(false)'); assert q.fetchone()[0]>0
   q.execute('select public.workshop_current_revision()'); assert q.fetchone()[0]>=0
  else:
   q.execute('savepoint role_snapshot_denied')
   try:
    q.execute("select public.get_station_workshop_snapshot('BUS_4X4',current_date,current_date+2)"); raise AssertionError(f'{role} snapshot unexpectedly allowed')
   except psycopg2.Error as e:
    assert e.pgcode=='42501',(role,e); q.execute('rollback to savepoint role_snapshot_denied')
   for label,statement in [('configuration','select public.get_workshop_configuration()'),('bays','select * from public.list_workshop_bays(false)'),('technicians','select * from public.list_technicians(false)'),('revision','select public.workshop_current_revision()')]:
    q.execute('savepoint reference_rpc_denied')
    try:
     q.execute(statement); raise AssertionError(f'{role} {label} RPC unexpectedly allowed')
    except psycopg2.Error as e:
     assert e.pgcode=='42501',(role,label,e); q.execute('rollback to savepoint reference_rpc_denied')
   q.execute('select public.get_vehicle_core_snapshot()'); core_denial=q.fetchone()[0]
   assert 'permission_denied' in json.dumps(core_denial),(role,'vehicle_core_snapshot',core_denial)
   q.execute('select public.resolve_vehicle_lifecycle_identity(null,null,null,null,null,null,null,null)'); resolver_denial=q.fetchone()[0]
   assert resolver_denial.get('outcome')=='unauthorized',(role,'resolve_lifecycle',resolver_denial)
   denied_mutations=[
    ('complete',"select public.complete_workshop_work('00000000-0000-0000-0000-000000000001',0,null,null,'{}'::jsonb)"),
    ('cascade',"select public.cascade_workshop_schedule('extend','00000000-0000-0000-0000-000000000001',0,'BUS_4X4',1,now(),60,null,0,null,'{}'::jsonb)"),
    ('move_vehicle',"select public.move_vehicle('00000000-0000-0000-0000-000000000001',0,null,null,null,null,null)"),
    ('delete_vehicle',"select public.mark_vehicle_deleted('00000000-0000-0000-0000-000000000001',0,null)"),
    ('qc_complete',"select public.qc_complete_vehicle('00000000-0000-0000-0000-000000000001',0,'QC',null)"),
    ('rft_transfer',"select public.rft_transfer_vehicle('00000000-0000-0000-0000-000000000001',0)"),
    ('rft_collect',"select public.rft_collect_vehicle('00000000-0000-0000-0000-000000000001',0)"),
    ('restore_vehicle',"select public.restore_vehicle('00000000-0000-0000-0000-000000000001',0,null)"),
    ('edit_vehicle_master',"select public.edit_vehicle_master('00000000-0000-0000-0000-000000000001',0,'{}'::jsonb,null,null)"),
    ('append_timeline',"select public.append_vehicle_timeline_event('00000000-0000-0000-0000-000000000001','probe')"),
    ('rebuild_intelligence',"select public.rebuild_vehicle_intelligence_summary('00000000-0000-0000-0000-000000000001')"),
    ('create_ai_review',"select public.create_ai_review_item('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001')"),
    ('list_ai_review_queue',"select public.list_ai_review_queue('pending')"),
    ('list_salespeople',"select * from public.list_salespeople(false)"),
    ('list_sublet_providers',"select * from public.list_sublet_providers(false)"),
    ('vehicle_intelligence',"select public.get_vehicle_intelligence_snapshot('00000000-0000-0000-0000-000000000001','desc',10)"),
    ('approve_ai_review',"select public.approve_ai_review_item('00000000-0000-0000-0000-000000000001',null,null,null)"),
    ('reject_ai_review',"select public.reject_ai_review_item('00000000-0000-0000-0000-000000000001',null,false)"),
   ]
   for label,statement in denied_mutations:
    q.execute('savepoint inherited_operator_rpc_denied')
    try:
     q.execute(statement); raise AssertionError(f'{role} {label} unexpectedly allowed')
    except psycopg2.Error as e:
     assert e.pgcode=='42501',(role,label,e); q.execute('rollback to savepoint inherited_operator_rpc_denied')
 q.execute('reset role')
 q.execute("select set_config('request.jwt.claims','{}',true)")
 q.execute('set local role anon')
 q.execute('savepoint anonymous_workshop_denied')
 try:
  q.execute('select count(*) from public.workshop_station_revision')
  assert q.fetchone()[0]==0,'anonymous Realtime rows unexpectedly visible'
 except psycopg2.Error as e:
  assert e.pgcode=='42501',e; q.execute('rollback to savepoint anonymous_workshop_denied')
 q.execute('reset role')
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
 q.execute("select eta_risk_status from public.workshop_bookings where vehicle_id=%s and status in ('queued','planned','started','stoppage') and deleted_at is null",(vehicle,))
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
 q.execute("select public.get_station_workshop_snapshot('Pits Hoist',current_date,current_date)"); assert q.fetchone()[0]['scope']['stage_code']=='HOIST'
 print(json.dumps({'migration_044_transactional':True,'yh_without_eta_scheduled':True,'location_stage_visibility_unchanged':True,'booking_move_preserves_vehicle_authority':True,'station_snapshot_dto_scoped_and_limited':True,'importer_snapshot_schedule_and_direct_booking_denied':True,'importer_eta_risk_maintenance_preserved':True,'sublet_lifecycle_denied':True,'sublet_completion_preserved':True,'legacy_low_level_lifecycle_revoked':True,'alias_parity':alias_count,'config_revision_bumped':True,'disabled_station_revision_bumped':True,'rolled_back':True}))
finally:
 conn.rollback(); conn.close()
