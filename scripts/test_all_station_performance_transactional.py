"""Rollback-only 500-vehicle/1000-work-item/500-booking staging stress proof."""
import json, os, re, time, uuid
from pathlib import Path
import psycopg2, psycopg2.extras
psycopg2.extras.register_uuid()

ROOT=Path(__file__).resolve().parents[1]
SQL46=(ROOT/'supabase/migrations/046_workshop_authoritative_validation_and_lifecycle.sql').read_text()
SQL46_BODY,n_begin=re.subn(r'(?im)^\s*begin;\s*','',SQL46.strip(),count=1)
SQL46_BODY,n_commit=re.subn(r'(?im)\s*commit;\s*$','',SQL46_BODY,count=1)
assert n_begin==1 and n_commit==1
PREFLIGHT=re.search(r"do \$\$\s*begin\s*if exists \([\s\S]*?before migration 046'[\s\S]*?end \$\$;",SQL46,re.I).group(0)
SQL46_BODY=SQL46_BODY.replace(PREFLIGHT,'',1)
conn=psycopg2.connect(os.environ['PDC_STAGING_DATABASE_URL']); conn.autocommit=False; q=conn.cursor()
metrics={}
try:
 q.execute("set local statement_timeout='30s'")
 q.execute("""update public.workshop_bookings set status='deleted',deleted_at=now(),
   deleted_reason='rollback-only migration-046 performance isolation'
   where id in(select b.id from public.workshop_bookings a join public.workshop_bookings b
    on b.vehicle_id=a.vehicle_id and b.id>a.id and b.deleted_at is null
   and b.status in('queued','planned','started','stoppage')
   and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)')
   where a.deleted_at is null and a.status in('queued','planned','started','stoppage'))""")
 q.execute(SQL46_BODY)
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
 q.execute("""select m from generate_series(date_trunc('minute',now()),date_trunc('minute',now())+interval '30 days',interval '15 minutes')m
  where public.workshop_calendar_minute_available(m)
    and not exists(select 1 from generate_series(m,m+interval '59 minutes',interval '1 minute')x where not public.workshop_calendar_minute_available(x))
  order by m limit 1"""); booking_start=q.fetchone()[0]
 q.execute('alter table public.workshop_bookings disable trigger workshop_bookings_planner_enabled_guard')
 q.execute('alter table public.workshop_bookings disable trigger workshop_booking_046b_validation_guard')
 q.execute("""insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by)
 select v.id,%s,null,'queued',%s,%s+interval '60 minutes',60,%s,%s
 from unnest(%s::uuid[])v(id)""",(stage,booking_start,booking_start,admin,admin,vehicles))
 q.execute('alter table public.workshop_bookings enable trigger workshop_booking_046b_validation_guard')
 q.execute('alter table public.workshop_bookings enable trigger workshop_bookings_planner_enabled_guard')
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
 q.execute('select id from public.workshop_bookings where vehicle_id=%s',(vehicles[0],)); validation_booking=q.fetchone()[0]
 t=time.perf_counter()
 for _ in range(100):
  q.execute("select public.workshop_validate_booking(%s,%s,%s,null,%s,%s,60,'queued',null)",
            (validation_booking,vehicles[0],stage,booking_start,booking_start+__import__('datetime').timedelta(minutes=60)))
  assert q.fetchone()[0]['ok'] is True
 metrics['canonical_validation_100_ms']=round((time.perf_counter()-t)*1000,2)
 # Eight planner snapshots exercise the maximum approved planner count.
 t=time.perf_counter()
 for code in ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION'):
  q.execute('select public.get_station_workshop_snapshot(%s,current_date,current_date+2)',(code,)); assert q.fetchone()[0]['scope']['stage_code']==code
 metrics['eight_planners_ms']=round((time.perf_counter()-t)*1000,2)
 assert metrics['aggregate_snapshot_ms']<5000 and metrics['station_snapshot_ms']<5000 and metrics['eight_planners_ms']<10000 and metrics['canonical_validation_100_ms']<10000,metrics
 metrics.update({'vehicles':500,'work_items':1000,'bookings':500,'planner_count':8,'rolled_back':True})
 print(json.dumps(metrics))
finally:
 conn.rollback(); conn.close()
