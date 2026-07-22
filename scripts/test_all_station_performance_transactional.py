"""Rollback-only 500-vehicle/1000-work-item/500-booking staging stress proof."""
import json, os, time, uuid
from pathlib import Path
import psycopg2

ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/044_blocker_only_all_station_release_closure.sql').read_text()
conn=psycopg2.connect(os.environ['PDC_STAGING_DATABASE_URL']); conn.autocommit=False; q=conn.cursor()
metrics={}
try:
 q.execute("set local statement_timeout='30s'")
 q.execute(SQL)
 q.execute("select email from public.pdc_user_roles where active and role='administrator' order by created_at limit 1")
 admin_email=q.fetchone()[0]
 q.execute('select id from auth.users where lower(email)=lower(%s)',(admin_email,)); admin=q.fetchone()[0]
 q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':admin_email,'role':'authenticated'}),))
 prefix='PERF'+uuid.uuid4().hex[:10].upper()
 t=time.perf_counter()
 q.execute("""insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,lifecycle_state,visible_on_board,version,created_by,updated_by)
 select gen_random_uuid(),gen_random_uuid(),%s||lpad(g::text,4,'0'),'PMB','UNALLOCATED','active',false,1,%s,%s
 from generate_series(1,500)g""",(prefix,admin,admin))
 q.execute("select array_agg(id order by stock_number) from public.vehicles where stock_number like %s",(prefix+'%',)); vehicles=q.fetchone()[0]
 q.execute("""insert into public.vehicle_work_items(vehicle_id,work_key,required,completed)
 select v.id,k,true,false from unnest(%s::uuid[])v(id) cross join (values('BUS4X4'),('TINT'))x(k)""",(vehicles,))
 q.execute("select id from public.workshop_stages where code='BUS_4X4'"); stage=q.fetchone()[0]
 q.execute("""insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by)
 select v.id,%s,null,'queued',date_trunc('day',now())+interval '1 day 8 hours',date_trunc('day',now())+interval '1 day 9 hours',60,%s,%s
 from unnest(%s::uuid[])v(id)""",(stage,admin,admin,vehicles))
 metrics['fixture_insert_ms']=round((time.perf_counter()-t)*1000,2)
 q.execute('select count(*) from public.vehicles where stock_number like %s',(prefix+'%',)); assert q.fetchone()[0]==500
 q.execute('select count(*) from public.vehicle_work_items where vehicle_id=any(%s)',(vehicles,)); assert q.fetchone()[0]==1000
 q.execute('select count(*) from public.workshop_bookings where vehicle_id=any(%s)',(vehicles,)); assert q.fetchone()[0]==500
 t=time.perf_counter(); q.execute('select public.get_workshop_eligibility_snapshot()'); aggregate=q.fetchone()[0]; metrics['aggregate_snapshot_ms']=round((time.perf_counter()-t)*1000,2)
 perf_candidates=[c for c in aggregate['candidates'] if str(c['vehicle']['stock_number']).startswith(prefix)]
 assert len(perf_candidates)==1000,len(perf_candidates)
 t=time.perf_counter(); q.execute("select public.get_station_workshop_snapshot('BUS_4X4',current_date,current_date+2)"); station=q.fetchone()[0]; metrics['station_snapshot_ms']=round((time.perf_counter()-t)*1000,2)
 perf_vehicles=[v for v in station['vehicles'] if str(v['stock_number']).startswith(prefix)]
 perf_ids={str(v['id']) for v in perf_vehicles}
 perf_work=[w for w in station['work_items'] if str(w['vehicle_id']) in perf_ids]
 perf_bookings=[b for b in station['bookings'] if str(b['vehicle_id']) in perf_ids]
 assert (len(perf_vehicles),len(perf_work),len(perf_bookings))==(500,500,500),(len(perf_vehicles),len(perf_work),len(perf_bookings))
 # Eight planner snapshots exercise the maximum approved planner count.
 t=time.perf_counter()
 for code in ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION'):
  q.execute('select public.get_station_workshop_snapshot(%s,current_date,current_date+2)',(code,)); assert q.fetchone()[0]['scope']['stage_code']==code
 metrics['eight_planners_ms']=round((time.perf_counter()-t)*1000,2)
 assert metrics['aggregate_snapshot_ms']<5000 and metrics['station_snapshot_ms']<5000 and metrics['eight_planners_ms']<10000,metrics
 metrics.update({'vehicles':500,'work_items':1000,'bookings':500,'planner_count':8,'rolled_back':True})
 print(json.dumps(metrics))
finally:
 conn.rollback(); conn.close()
