"""Rollback-only migration-050 functional contract against staging.
No production endpoint is used and every fixture/schema change is rolled back.
"""
import json, os, pathlib, re, uuid
from datetime import timedelta
import psycopg2, psycopg2.extras
psycopg2.extras.register_uuid()
ROOT=pathlib.Path(__file__).resolve().parents[1]

def body(name):
    text=(ROOT/'supabase/migrations'/name).read_text(encoding='utf-8').strip()
    text=re.sub(r'(?im)^\s*begin;\s*','',text,count=1)
    text=re.sub(r'(?im)\s*commit;\s*$','',text,count=1)
    return text
SQL049=(ROOT/'supabase/migrations/049_soft_launch_planner_safety.sql').read_text(encoding='utf-8')
SQL050=body('050_workshop_tile_completion_and_live_bay.sql')
conn=psycopg2.connect(os.environ['PDC_STAGING_DATABASE_URL']); conn.autocommit=False; q=conn.cursor()
counts={'start_to_now':0,'same_bay_rejected':0,'cross_station_started':0,'fixed_preserved':0,'completed_requirement':0,'rerequired':0,'customer_projected':0}

def rpc(sql,args=()):
    q.execute(sql,args); value=q.fetchone()[0]
    assert isinstance(value,dict),value
    return value

def version(bid):
    q.execute('select version from public.workshop_bookings where id=%s',(bid,)); return q.fetchone()[0]

def make_vehicle(admin,stage,customer):
    vid=uuid.uuid4()
    q.execute("select work_key from public.workshop_stages where code=%s",(stage,)); work=q.fetchone()[0]
    q.execute("""insert into public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,current_location,pmb_stage,visible_on_board,version,lifecycle_state,updated_by)
      values(%s,%s,%s,%s,'PMB','UNALLOCATED',false,1,'active',%s)""",(vid,uuid.uuid4(),'M050-'+uuid.uuid4().hex[:10].upper(),customer,admin))
    q.execute('insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,%s,true,false)',(vid,work))
    return vid

try:
    q.execute("""select count(*) from (select bay_id from public.workshop_bookings
      where deleted_at is null and status='started' and bay_id is not null group by bay_id having count(*)>1) d""")
    assert q.fetchone()[0]==0,'staging contains multiple started jobs in one physical bay; migration must remain blocked for explicit review'
    q.execute(SQL049)
    q.execute(SQL050)
    q.execute("select indexdef from pg_indexes where schemaname='public' and indexname='workshop_bookings_one_started_per_bay_uidx'")
    indexdef=q.fetchone()[0]; assert '(bay_id)' in indexdef and "status = 'started'" in indexdef

    admin_email=os.environ['PDC_STAGING_ADMIN_EMAIL'].strip().lower()
    q.execute('select id from auth.users where lower(email)=%s',(admin_email,)); admin=q.fetchone()[0]
    q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':admin_email,'role':'authenticated'}),))

    # Deterministic rollback-only clock window: make every minute operational in
    # this transaction so the database-clock Start contract is testable at any CI time.
    q.execute("""create or replace function public.workshop_calendar_minute_available(p_at timestamptz)
      returns boolean language sql stable security definer set search_path=pg_catalog,public as $$ select p_at is not null $$""")

    q.execute("select date_trunc('minute',statement_timestamp()), (statement_timestamp() at time zone 'Australia/Perth')::date") ; now,today=q.fetchone()
    def open_bay(stage):
        q.execute("""select s.id,b.id,b.bay_number from public.workshop_stages s join public.workshop_bays b on b.stage_id=s.id
          where s.code=%s and s.active and s.planner_enabled and b.is_active
            and not exists(select 1 from public.workshop_bookings wb where wb.bay_id=b.id and wb.deleted_at is null and wb.status='started')
            and not exists(select 1 from public.workshop_bookings wb where wb.bay_id=b.id and wb.deleted_at is null
              and wb.status in('planned','stoppage') and tstzrange(wb.scheduled_start_at,wb.scheduled_end_at,'[)')&&tstzrange(%s,%s+interval '1 hour','[)'))
          order by b.bay_number limit 1""",(stage,now,now))
        row=q.fetchone(); assert row,('no_open_bay_now',stage); return row
    fab_stage,fab_bay,fab_num=open_bay('FABRICATION')
    tint_stage,tint_bay,tint_num=open_bay('TINT')
    assert fab_stage!=tint_stage and fab_bay!=tint_bay
    def free_slot(bay_id):
        q.execute("""select m from generate_series(%s::timestamptz+interval '1 day',%s::timestamptz+interval '80 days',interval '1 hour') m
          where not exists(select 1 from public.workshop_bookings b where b.bay_id=%s and b.deleted_at is null
            and b.status in('planned','started','stoppage') and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(m,m+interval '8 hours','[)'))
          order by m limit 1""",(now,now,bay_id))
        row=q.fetchone(); assert row,('no_free_test_slot',bay_id); return row[0]
    fab_slot=free_slot(fab_bay); tint_slot=free_slot(tint_bay)
    va=make_vehicle(admin,'FABRICATION','Alpha Customer')
    vb=make_vehicle(admin,'FABRICATION','Bravo Customer')
    vc=make_vehicle(admin,'TINT','Charlie Customer')
    a=rpc("select public.schedule_vehicle_work(%s,1,'FABRICATION',%s,%s,60,null,null,'{}'::jsonb)",(va,fab_num,fab_slot))
    b=rpc("select public.schedule_vehicle_work(%s,1,'FABRICATION',%s,%s,60,null,null,'{}'::jsonb)",(vb,fab_num,fab_slot+timedelta(hours=2)))
    c=rpc("select public.schedule_vehicle_work(%s,1,'TINT',%s,%s,60,null,null,'{}'::jsonb)",(vc,tint_num,tint_slot))
    assert a.get('ok') and b.get('ok') and c.get('ok'),(a,b,c)
    aid=uuid.UUID(a['booking']['booking_id']); bid=uuid.UUID(b['booking']['booking_id']); cid=uuid.UUID(c['booking']['booking_id'])
    q.execute('select id,stage_id,bay_id from public.workshop_bookings where id in(%s,%s,%s)',(aid,bid,cid)); actual={row[0]:(row[1],row[2]) for row in q.fetchall()}
    assert actual[aid][1]==fab_bay and actual[bid][1]==fab_bay and actual[cid][1]==tint_bay and actual[cid][1]!=actual[aid][1],actual

    starta=rpc("select public.start_workshop_work(%s,%s,null,'{}'::jsonb)",(aid,version(aid)))
    assert starta['ok'] is True and 'signed_shift_minutes' in starta
    q.execute("select status,scheduled_start_at from public.workshop_bookings where id=%s",(aid,)); status,started_at=q.fetchone()
    assert status=='started' and abs((started_at-now).total_seconds())<61; counts['start_to_now']+=1
    startb=rpc("select public.start_workshop_work(%s,%s,null,'{}'::jsonb)",(bid,version(bid)))
    assert startb=={'ok':False,'error':'bay_already_started'}; counts['same_bay_rejected']+=1

    startc=rpc("select public.start_workshop_work(%s,%s,null,'{}'::jsonb)",(cid,version(cid)))
    if startc.get('ok') is not True:
        q.execute("select id,bay_id,stage_id,status from public.workshop_bookings where id=%s or (deleted_at is null and status='started') order by id",(cid,))
        raise AssertionError({'result':startc,'rows':q.fetchall(),'target_bay':tint_bay,'fab_bay':fab_bay})
    counts['cross_station_started']+=1

    # Stoppage releases the live-status lock but remains fixed schedule work; a
    # colliding Start must fail atomically rather than move it.
    stopa=rpc("select public.stop_workshop_work(%s,%s,'test','{}'::jsonb)",(aid,version(aid)))
    assert stopa['ok'] is True
    before_b=version(bid)
    fixed=rpc("select public.start_workshop_work(%s,%s,null,'{}'::jsonb)",(bid,before_b))
    assert fixed['ok'] is False and fixed['error']=='fixed_booking_conflict'
    assert version(bid)==before_b; counts['fixed_preserved']+=1

    complete=rpc("select public.complete_workshop_work(%s,%s,'FABRICATION',now(),'{}'::jsonb)",(aid,version(aid)))
    assert complete['ok'] is True and complete['work_item_completed'] is True
    q.execute("select completed from public.vehicle_work_items where vehicle_id=%s and public.workshop_stage_code_for_work_key(work_key)='FABRICATION'",(va,)); assert q.fetchone()[0] is True
    q.execute("select count(*) from public.workshop_station_eligibility('FABRICATION') where vehicle_id=%s",(va,)); assert q.fetchone()[0]==0
    counts['completed_requirement']+=1

    q.execute("update public.vehicle_work_items set completed=false,completed_by=null,completed_at=null where vehicle_id=%s and public.workshop_stage_code_for_work_key(work_key)='FABRICATION'",(va,))
    q.execute("select count(*) from public.workshop_station_eligibility('FABRICATION') where vehicle_id=%s",(va,)); assert q.fetchone()[0]==1
    counts['rerequired']+=1

    snap=rpc('select public.get_station_workshop_snapshot(%s,%s,%s)',('FABRICATION',today,today))
    vehicle=next(v for v in snap['vehicles'] if v['id']==str(va))
    assert vehicle['customer_name']=='Alpha Customer'; counts['customer_projected']+=1
    print(json.dumps({'ok':True,'rollback_only':True,'counts':counts,'fab_bay_number':fab_num,'tint_bay_number':tint_num},sort_keys=True))
finally:
    conn.rollback(); q.close(); conn.close()
