"""Transactional staging proof for migration 042. Applies and rolls back every fixture/change."""
import json, os, pathlib, uuid
from datetime import date, timedelta, datetime, timezone
import psycopg2
import psycopg2.extras
psycopg2.extras.register_uuid()

ROOT=pathlib.Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/042_all_station_eligibility_and_sublet_planner_removal.sql').read_text(encoding='utf-8')
STATIONS=['BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION']
ALIASES={'BUS_4X4':'Bus 4x4','TINT':'Window Tint','HOIST':'Lifts','FITTING':'Fit Out','FABRICATION':'Fab','ELECTRICAL':'Elec','TYRE':'Tyre Bay','PIT_INSPECTION':'Pit'}
WORK_KEYS={'BUS_4X4':'bus4x4','TINT':'tint','HOIST':'hoist','FITTING':'fitting','FABRICATION':'fabrication','ELECTRICAL':'electrical','TYRE':'tyre','PIT_INSPECTION':'pitInspection'}

def main():
 c=psycopg2.connect(os.environ['PDC_STAGING_DATABASE_URL']); q=c.cursor(); checks=[]
 try:
  q.execute("set local statement_timeout='120s'"); q.execute(SQL)
  q.execute("select id from auth.users where lower(email)=lower(%s)",(os.environ['PDC_STAGING_ADMIN_EMAIL'],)); admin=q.fetchone()[0]
  q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':os.environ['PDC_STAGING_ADMIN_EMAIL'],'role':'authenticated'}),))
  tomorrow=date.today()+timedelta(days=1); next_week=date.today()+timedelta(days=7)
  fixtures={}
  for stage in STATIONS:
   ids={kind:uuid.uuid4() for kind in ['pmb','yh','it_valid','it_missing','booked','completed','none','alias','wrong']}; fixtures[stage]=ids
   for kind,vid in ids.items():
    loc={'pmb':'PMB','yh':'YH','it_valid':'IT','it_missing':'IT','booked':'PMB','completed':'PMB','none':'PMB','alias':'YH','wrong':'OTHER'}[kind]
    eta=next_week if kind=='it_valid' else None
    q.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,lifecycle_state,visible_on_board,current_location,eta_to_kewdale,created_by,updated_by) values(%s,%s,%s,'active',true,%s,%s,%s,%s)",(vid,f'FIX-{stage}-{kind}',f'FIX-{stage}-{kind}',loc,eta,admin,admin))
   work_key=stage
   for kind in ['pmb','yh','it_valid','it_missing','booked']:
    q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,%s,true,false)",(ids[kind],work_key))
   q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_at,completed_by) values(%s,%s,true,true,now(),%s)",(ids['completed'],work_key,admin))
   q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,%s,true,false)",(ids['alias'],ALIASES[stage]))
   q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,%s,true,false)",(ids['wrong'],work_key))
   q.execute("select s.id,b.id from public.workshop_stages s join public.workshop_bays b on b.stage_id=s.id and b.is_active where s.code=%s order by b.bay_number limit 1",(stage,)); stage_id,bay_id=q.fetchone()
   start=datetime.combine(tomorrow,datetime.min.time(),tzinfo=timezone.utc).replace(hour=1); end=start+timedelta(hours=2)
   q.execute("insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,scheduled_start_at,scheduled_end_at,default_duration_minutes,status,created_by,updated_by) values(%s,%s,%s,%s,%s,120,'planned',%s,%s)",(ids['booked'],stage_id,bay_id,start,end,admin,admin))
   q.execute("select vehicle_id,schedule_enabled,disabled_reason from public.workshop_station_eligibility(%s) order by vehicle_id",(stage,)); rows=q.fetchall()
   candidate_ids={r[0] for r in rows if r[0] in set(ids.values())}; assert candidate_ids=={ids[k] for k in ['pmb','yh','it_valid','it_missing','booked','alias']},(stage,candidate_ids)
   missing=[r for r in rows if r[0]==ids['it_missing']][0]; assert missing[1:] == (False,'missing_eta')
   valid=[r for r in rows if r[0]==ids['it_valid']][0]; assert valid[1] is True
   q.execute("select public.get_workshop_eligibility_snapshot()"); summary=q.fetchone()[0]
   summary_ids={uuid.UUID(c['vehicle']['id']) for c in summary['candidates'] if c['stage_code']==stage and c['vehicle']['stock_number'].startswith('FIX-')}
   assert summary_ids==candidate_ids
   q.execute("select public.get_station_workshop_snapshot(%s,%s,%s)",(stage,tomorrow,tomorrow)); snap=q.fetchone()[0]
   snap_ids={uuid.UUID(v['id']) for v in snap['vehicles'] if v['stock_number'].startswith('FIX-')}; assert snap_ids==candidate_ids
   booking_ids={uuid.UUID(b['vehicle_id']) for b in snap['bookings'] if b['vehicle_id']}; assert ids['booked'] in booking_ids
   q.execute("select public.workshop_current_station_revision(%s)",(stage,)); revision_before=q.fetchone()[0]
   q.execute("update public.vehicles set current_location='YH' where id=%s",(ids['wrong'],))
   q.execute("select count(*) from public.workshop_station_eligibility(%s) where vehicle_id=any(%s)",(stage,list(ids.values()))); assert q.fetchone()[0]==7
   q.execute("select public.workshop_current_station_revision(%s)",(stage,)); assert q.fetchone()[0]>revision_before
   q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,%s,true,false)",(ids['none'],stage))
   q.execute("select count(*) from public.workshop_station_eligibility(%s) where vehicle_id=any(%s)",(stage,list(ids.values()))); assert q.fetchone()[0]==8
   q.execute("select work_key from public.vehicle_work_items where vehicle_id=%s",(ids['alias'],)); assert q.fetchone()[0]==WORK_KEYS[stage]
   checks.append({'stage':stage,'canonical_candidates':6,'after_location_realtime':7,'after_requirement_realtime':8,'booked_present_once':True,'completed_excluded':True,'missing_eta_visible_disabled':True})
  # IT database scheduling gates.
  stage=STATIONS[0]; ids=fixtures[stage]; q.execute("select s.id,b.id from public.workshop_stages s join public.workshop_bays b on b.stage_id=s.id where s.code=%s order by b.bay_number limit 1",(stage,)); sid,bid=q.fetchone()
  q.execute('savepoint it_gate')
  try:
   start=datetime.combine(date.today()+timedelta(days=2),datetime.min.time(),tzinfo=timezone.utc).replace(hour=1)
   q.execute("insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,scheduled_start_at,scheduled_end_at,default_duration_minutes,status,created_by,updated_by) values(%s,%s,%s,%s,%s,60,'planned',%s,%s)",(ids['it_valid'],sid,bid,start,start+timedelta(hours=1),admin,admin))
   raise AssertionError('IT before ETA scheduling unexpectedly succeeded')
  except psycopg2.Error as e:
   assert e.pgcode in ('22023','23514') and ('before ETA' in str(e) or 'booking_before_eta' in str(e)); q.execute('rollback to savepoint it_gate')
  # Sublet remains a requirement but cannot be a planner target.
  sublet_vehicle=uuid.uuid4(); q.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,lifecycle_state,visible_on_board,current_location) values(%s,%s,%s,'active',true,'PMB')",(sublet_vehicle,'FIX-SUBLET','FIX-SUBLET'))
  q.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,'Sublet',true,false)",(sublet_vehicle,))
  q.execute("select work_key from public.vehicle_work_items where vehicle_id=%s",(sublet_vehicle,)); assert q.fetchone()[0]=='sublet'
  q.execute('savepoint sublet_gate')
  try:
   q.execute("select public.get_station_workshop_snapshot('SUBLET',current_date,current_date)"); raise AssertionError('Sublet planner reachable')
  except psycopg2.Error as e:
   assert e.pgcode=='22023'; q.execute('rollback to savepoint sublet_gate')
  print(json.dumps({'stations':checks,'sublet_requirement_preserved':True,'sublet_planner_blocked':True,'transaction_rolled_back':True},default=str))
 finally:
  c.rollback(); c.close()

if __name__=='__main__': main()
