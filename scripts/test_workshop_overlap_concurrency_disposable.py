"""Disposable-schema concurrency proof for migration 046's vehicle lock/check.

Creates and drops a uniquely named staging schema. No public operational rows are
read or changed.
"""
import json, os, threading, time, uuid
import psycopg2

DSN=os.environ['PDC_STAGING_DATABASE_URL']
schema='m046_race_'+uuid.uuid4().hex[:12]
vehicle=str(uuid.uuid4())
setup=psycopg2.connect(DSN); setup.autocommit=True
q=setup.cursor()
q.execute(f'create schema {schema}')
q.execute(f'''create table {schema}.bookings(
 id uuid primary key default gen_random_uuid(), vehicle_id uuid not null,
 starts timestamptz not null, ends timestamptz not null,
 check(ends>starts))''')
q.execute(f'''create function {schema}.guard_overlap() returns trigger language plpgsql as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('workshop:vehicle:'||new.vehicle_id::text,0));
 if exists(select 1 from {schema}.bookings b where b.vehicle_id=new.vehicle_id
   and tstzrange(b.starts,b.ends,'[)') && tstzrange(new.starts,new.ends,'[)')) then
  raise exception 'vehicle_overlap' using errcode='22023';
 end if;
 return new;
end $$''')
q.execute(f'create trigger guard before insert on {schema}.bookings for each row execute function {schema}.guard_overlap()')

def run(start,end,hold=0.0):
 c=psycopg2.connect(DSN); c.autocommit=False; cur=c.cursor(); t=time.perf_counter()
 try:
  cur.execute(f'insert into {schema}.bookings(vehicle_id,starts,ends) values(%s,%s,%s)',(vehicle,start,end))
  if hold: time.sleep(hold)
  c.commit(); return {'result':'accepted','elapsed_ms':round((time.perf_counter()-t)*1000,2)}
 except Exception as e:
  c.rollback(); return {'result':'rejected','sqlstate':getattr(e,'pgcode',None),'elapsed_ms':round((time.perf_counter()-t)*1000,2)}
 finally: c.close()

try:
 outcomes={}
 def first(): outcomes['first']=run('2026-09-07T00:00:00Z','2026-09-07T01:00:00Z',1.0)
 def second(): outcomes['second']=run('2026-09-07T00:30:00Z','2026-09-07T01:30:00Z')
 a=threading.Thread(target=first); b=threading.Thread(target=second)
 a.start(); time.sleep(.15); b.start(); a.join(); b.join()
 assert sorted(x['result'] for x in outcomes.values())==['accepted','rejected'],outcomes
 assert next(x for x in outcomes.values() if x['result']=='rejected')['sqlstate']=='22023',outcomes
 q.execute(f'truncate {schema}.bookings')
 back={}
 def left(): back['left']=run('2026-09-07T00:00:00Z','2026-09-07T01:00:00Z',.5)
 def right(): back['right']=run('2026-09-07T01:00:00Z','2026-09-07T02:00:00Z')
 a=threading.Thread(target=left); b=threading.Thread(target=right)
 a.start(); time.sleep(.1); b.start(); a.join(); b.join()
 assert [back[k]['result'] for k in sorted(back)]==['accepted','accepted'],back
 print(json.dumps({'disposable_schema':True,'overlap_race':outcomes,'back_to_back_race':back,'half_open':True},sort_keys=True))
finally:
 q.execute(f'drop schema if exists {schema} cascade'); setup.close()
