"""Rollback-only migration-046 functional matrix against staging.

The migration and every fixture run in one transaction and are always rolled back.
No production endpoint is used.
"""
import json, os, pathlib, re, uuid
from datetime import datetime, timedelta, timezone
import psycopg2, psycopg2.extras
psycopg2.extras.register_uuid()

ROOT=pathlib.Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/046_workshop_authoritative_validation_and_lifecycle.sql').read_text(encoding='utf-8')
# Execute the migration body inside this harness's outer transaction. Never run
# the migration's BEGIN/COMMIT wrapper here: every schema and fixture change
# must remain rollback-only until the four source-review gates pass.
SQL_BODY=SQL.strip()
SQL_BODY,n_begin=re.subn(r'(?im)^\s*begin;\s*','',SQL_BODY,count=1)
SQL_BODY,n_commit=re.subn(r'(?im)\s*commit;\s*$','',SQL_BODY,count=1)
assert n_begin==1 and n_commit==1
PREFLIGHT=re.search(r"do \$\$\s*begin\s*if exists \([\s\S]*?before migration 046'[\s\S]*?end \$\$;",SQL,re.I).group(0)
SQL_BODY=SQL_BODY.replace(PREFLIGHT,'',1)
STAGES=['BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION']
conn=psycopg2.connect(os.environ['PDC_STAGING_DATABASE_URL']); conn.autocommit=False; q=conn.cursor()
counts={'accepted':0,'rejected':0,'stations':0,'lifecycle_valid':0,'lifecycle_invalid':0}

def savepoint(name): q.execute(f'savepoint {name}')
def rollback(name): q.execute(f'rollback to savepoint {name}'); q.execute(f'release savepoint {name}')
def expect_reject(name,statement,args=(),expected=None):
    savepoint(name)
    try:
        q.execute(statement,args); row=q.fetchone(); result=row[0] if row else None
        if isinstance(result,dict) and result.get('ok') is False:
            if expected: assert result.get('error') in expected,(name,result)
            counts['rejected']+=1; rollback(name); return result
        raise AssertionError(f'{name} unexpectedly accepted: {result}')
    except psycopg2.Error as exc:
        assert exc.pgcode in ('22023','23P01'),(name,exc.pgcode,exc)
        counts['rejected']+=1; rollback(name); return {'sqlstate':exc.pgcode}

def expect_ok(statement,args=()):
    q.execute(statement,args); result=q.fetchone()[0]
    assert isinstance(result,dict) and result.get('ok') is True,result
    counts['accepted']+=1
    return result

def create_vehicle(admin,stage_code,location='PMB',eta=None,completed=False,extra_stage=None):
    vehicle=uuid.uuid4(); stock='M046-'+uuid.uuid4().hex[:12].upper()
    q.execute("""insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,
      visible_on_board,version,lifecycle_state,eta_to_kewdale,updated_by)
      values(%s,%s,%s,%s,'UNALLOCATED',false,1,'active',%s,%s)""",
      (vehicle,uuid.uuid4(),stock,location,eta,admin))
    codes=[stage_code]+([extra_stage] if extra_stage else [])
    for code in codes:
        q.execute('select work_key from public.workshop_stages where code=%s and active and planner_enabled',(code,)); row=q.fetchone(); assert row,(code,'missing')
        q.execute('insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,%s,true,%s)',(vehicle,row[0],completed))
    return vehicle

def version(booking_id): q.execute('select version from public.workshop_bookings where id=%s',(booking_id,)); return q.fetchone()[0]

try:
    q.execute("""select count(*) from public.workshop_bookings a join public.workshop_bookings b
      on b.vehicle_id=a.vehicle_id and b.id>a.id and b.deleted_at is null
      and b.status in('queued','planned','started','stoppage')
      and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)')
      where a.deleted_at is null and a.status in('queued','planned','started','stoppage')""")
    preexisting_overlap_count=q.fetchone()[0]
    q.execute('savepoint migration_preflight')
    try:
        q.execute(PREFLIGHT)
        assert preexisting_overlap_count==0
    except psycopg2.Error as exc:
        assert preexisting_overlap_count>0 and exc.pgcode=='23514',exc
    finally:
        q.execute('rollback to savepoint migration_preflight')
    q.execute("""select count(*) from public.workshop_bookings a join public.workshop_bookings b
      on b.vehicle_id=a.vehicle_id and b.id>a.id and b.deleted_at is null
      and b.status in('queued','planned','started','stoppage')
      and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)')
      where a.deleted_at is null and a.status in('queued','planned','started','stoppage')""")
    assert q.fetchone()[0]==preexisting_overlap_count,'preflight must never rewrite operational rows'
    if preexisting_overlap_count:
        q.execute("""update public.workshop_bookings set status='deleted',deleted_at=now(),
          deleted_reason='rollback-only migration-046 matrix isolation'
          where id in (
            select b.id from public.workshop_bookings a join public.workshop_bookings b
              on b.vehicle_id=a.vehicle_id and b.id>a.id and b.deleted_at is null
             and b.status in('queued','planned','started','stoppage')
             and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)')
            where a.deleted_at is null and a.status in('queued','planned','started','stoppage')
          )""")
    q.execute(SQL_BODY)
    admin_email=os.environ['PDC_STAGING_ADMIN_EMAIL'].strip().lower()
    q.execute('select id from auth.users where lower(email)=%s',(admin_email,)); admin=q.fetchone()[0]
    q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':admin_email,'role':'authenticated'}),))
    # Pick the first future regular hour accepted by the canonical AWST authority.
    q.execute("""select m from generate_series(date_trunc('day',now())+interval '1 day',date_trunc('day',now())+interval '90 days',interval '15 minutes') m
      where public.workshop_calendar_minute_available(m)
        and public.workshop_operational_minutes_between(m,m+interval '60 minutes')=60
        and not exists(select 1 from public.workshop_bookings b where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
          and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(m,m+interval '3 hours','[)'))
      order by m limit 1""")
    base=q.fetchone()[0]
    stage_rows={}
    for code in STAGES:
        q.execute("""select s.id,s.work_key,b.bay_number from public.workshop_stages s join public.workshop_bays b on b.stage_id=s.id
          where s.code=%s and s.active and s.planner_enabled and b.is_active and b.bay_number is not null order by b.bay_number limit 1""",(code,))
        stage_rows[code]=q.fetchone(); assert stage_rows[code],code

    slots=[]
    for i in range(len(STAGES)):
        q.execute("""select m from generate_series(%s::timestamptz,%s::timestamptz+interval '10 days',interval '15 minutes') m
          where public.workshop_calendar_minute_available(m)
            and public.workshop_operational_minutes_between(m,m+interval '2 hours')=120
            and not exists(select 1 from public.workshop_bookings b where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
              and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(m,m+interval '2 hours','[)'))
          order by m limit 1""",(base+timedelta(days=i*7),base+timedelta(days=i*7)))
        slots.append(q.fetchone()[0])
    primary=[]; secondary=[]
    for i,code in enumerate(STAGES):
        nxt=STAGES[(i+1)%len(STAGES)]; bay=stage_rows[code][2]; slot=slots[i]
        vehicle=create_vehicle(admin,code,'PMB' if i%2==0 else 'YH',extra_stage=nxt)
        expect_reject(f'min59_{i}',"select public.schedule_vehicle_work(%s,1,%s,%s,%s,59,null,null,'{}'::jsonb)",(vehicle,code,bay,slot),{'minimum_duration'})
        result=expect_ok("select public.schedule_vehicle_work(%s,1,%s,%s,%s,60,null,null,'{}'::jsonb)",(vehicle,code,bay,slot))
        booking=uuid.UUID(result['booking']['booking_id']); primary.append((vehicle,booking,code))
        expect_reject(f'resize59_{i}',"select public.resize_workshop_booking(%s,%s,59,'{}'::jsonb)",(booking,version(booking)),{'minimum_duration'})
        conflict_vehicle=create_vehicle(admin,code,'PMB')
        expect_reject(f'bay_overlap_{i}',"select public.schedule_vehicle_work(%s,1,%s,%s,%s,60,null,null,'{}'::jsonb)",(conflict_vehicle,code,bay,slot),{'bay_overlap'})
        next_bay=stage_rows[nxt][2]
        expect_reject(f'vehicle_overlap_{i}',"select public.schedule_vehicle_work(%s,1,%s,%s,%s,60,null,null,'{}'::jsonb)",(vehicle,nxt,next_bay,slot),{'vehicle_overlap'})
        second=expect_ok("select public.schedule_vehicle_work(%s,1,%s,%s,%s,60,null,null,'{}'::jsonb)",(vehicle,nxt,next_bay,slot+timedelta(hours=1)))
        second_booking=uuid.UUID(second['booking']['booking_id']); secondary.append((second_booking,nxt,next_bay))
        expect_reject(f'resize_vehicle_overlap_{i}',"select public.resize_workshop_booking(%s,%s,120,'{}'::jsonb)",(booking,version(booking)),{'vehicle_overlap'})
        expect_reject(f'move_vehicle_overlap_{i}',"select public.move_workshop_booking(%s,%s,%s,%s,%s,60,null,'{}'::jsonb)",(second_booking,version(second_booking),nxt,next_bay,slot),{'vehicle_overlap'})
        counts['stations']+=1

    # Invalid working day/hour/closure/break and valid configured overtime.
    q.execute("""select m from generate_series(%s::timestamptz,%s::timestamptz+interval '14 days',interval '15 minutes') m
      where public.workshop_calendar_minute_available(m)
        and public.workshop_operational_minutes_between(m,m+interval '2 hours')=120
        and not exists(select 1 from public.workshop_bookings b where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
          and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(m,m+interval '2 hours','[)'))
      order by m limit 1""",(slots[-1]+timedelta(days=14),slots[-1]+timedelta(days=14)))
    cal_base=q.fetchone()[0]
    calendar_vehicle=create_vehicle(admin,'BUS_4X4','PMB'); bus_bay=stage_rows['BUS_4X4'][2]
    q.execute("select (value#>>'{}')::time from public.workshop_settings where key='day_start_time'"); day_start=q.fetchone()[0]
    q.execute("select (value#>>'{}')::time from public.workshop_settings where key='day_end_time'"); day_end=q.fetchone()[0]
    q.execute("select d::date from generate_series((%s at time zone 'Australia/Perth')::date,(%s at time zone 'Australia/Perth')::date+14,interval '1 day') d where extract(isodow from d) in(6,7) limit 1",(base,base)); weekend=q.fetchone()[0]
    q.execute("select (%s::date+%s::time) at time zone 'Australia/Perth'",(weekend,day_start)); weekend_at=q.fetchone()[0]
    expect_reject('weekend',"select public.schedule_vehicle_work(%s,1,'BUS_4X4',%s,%s,60,null,null,'{}'::jsonb)",(calendar_vehicle,bus_bay,weekend_at),{'calendar_unavailable'})
    local_base=cal_base.astimezone(timezone(timedelta(hours=8))).date()
    q.execute("select (%s::date+(%s::time+interval '1 hour')) at time zone 'Australia/Perth'",(local_base,day_end)); after_hours=q.fetchone()[0]
    expect_reject('after_hours',"select public.schedule_vehicle_work(%s,1,'BUS_4X4',%s,%s,60,null,null,'{}'::jsonb)",(calendar_vehicle,bus_bay,after_hours),{'calendar_unavailable'})
    q.execute("select value from public.workshop_settings where key='closures' for update"); closures=q.fetchone()[0]
    q.execute("update public.workshop_settings set value=value||%s::jsonb where key='closures'",(json.dumps([{'date':local_base.isoformat(),'reason':'M046 rollback fixture'}]),))
    expect_reject('closure',"select public.schedule_vehicle_work(%s,1,'BUS_4X4',%s,%s,60,null,null,'{}'::jsonb)",(calendar_vehicle,bus_bay,cal_base),{'calendar_unavailable'})
    q.execute("update public.workshop_settings set value=%s::jsonb where key='closures'",(json.dumps(closures),))
    q.execute("select value from public.workshop_settings where key='break_windows' for update"); breaks=q.fetchone()[0]
    start_clock=cal_base.astimezone(timezone(timedelta(hours=8))).strftime('%H:%M'); end_clock=(cal_base+timedelta(hours=1)).astimezone(timezone(timedelta(hours=8))).strftime('%H:%M')
    q.execute("update public.workshop_settings set value=%s::jsonb where key='break_windows'",(json.dumps([{'date':local_base.isoformat(),'start':start_clock,'end':end_clock}]),))
    expect_reject('break',"select public.schedule_vehicle_work(%s,1,'BUS_4X4',%s,%s,60,null,null,'{}'::jsonb)",(calendar_vehicle,bus_bay,cal_base),{'calendar_unavailable'})
    q.execute("update public.workshop_settings set value=%s::jsonb where key='break_windows'",(json.dumps([{'date':local_base.isoformat(),'start':'12:00','end':'13:00'}]),))
    q.execute("select public.workshop_add_operational_minutes((%s::date+time '11:30') at time zone 'Australia/Perth',60) at time zone 'Australia/Perth'",(local_base,))
    assert q.fetchone()[0].time().strftime('%H:%M')=='13:30','cascade helper must skip configured break'
    q.execute("update public.workshop_settings set value=%s::jsonb where key='break_windows'",(json.dumps(breaks),))
    q.execute("""select m from generate_series(%s::timestamptz,%s::timestamptz+interval '14 days',interval '15 minutes')m
      where public.workshop_calendar_interval_available(m,m+interval '4 hours')
        and not exists(select 1 from public.workshop_bookings b where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
          and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(m,m+interval '4 hours','[)')) order by m limit 1""",(cal_base+timedelta(days=42),cal_base+timedelta(days=42)))
    cascade_base=q.fetchone()[0]; cascade_day=cascade_base.astimezone(timezone(timedelta(hours=8))).date()
    cascade_break_start=(cascade_base+timedelta(hours=2)).astimezone(timezone(timedelta(hours=8))).strftime('%H:%M')
    cascade_break_end=(cascade_base+timedelta(hours=3)).astimezone(timezone(timedelta(hours=8))).strftime('%H:%M')
    target_vehicle=create_vehicle(admin,'BUS_4X4','PMB'); trailing_vehicle=create_vehicle(admin,'BUS_4X4','PMB')
    target_result=expect_ok("select public.schedule_vehicle_work(%s,1,'BUS_4X4',%s,%s,60,null,null,'{}'::jsonb)",(target_vehicle,bus_bay,cascade_base))
    trailing_result=expect_ok("select public.schedule_vehicle_work(%s,1,'BUS_4X4',%s,%s,60,null,null,'{}'::jsonb)",(trailing_vehicle,bus_bay,cascade_base+timedelta(hours=1)))
    target_booking=uuid.UUID(target_result['booking']['booking_id']); trailing_booking=uuid.UUID(trailing_result['booking']['booking_id'])
    q.execute("update public.workshop_settings set value=%s::jsonb where key='break_windows'",(json.dumps([{'date':cascade_day.isoformat(),'start':cascade_break_start,'end':cascade_break_end}]),))
    expect_ok("select public.cascade_workshop_schedule('extend',%s,%s,'BUS_4X4',%s,%s,120,null,60,null,'{}'::jsonb)",(target_booking,version(target_booking),bus_bay,cascade_base))
    q.execute('select scheduled_start_at,scheduled_end_at from public.workshop_bookings where id=%s',(trailing_booking,)); shifted_start,shifted_end=q.fetchone()
    assert shifted_start==cascade_base+timedelta(hours=3) and shifted_end==cascade_base+timedelta(hours=4),'cascade RPC must skip the configured break and preserve duration'
    q.execute("update public.workshop_settings set value=%s::jsonb where key='break_windows'",(json.dumps(breaks),))
    q.execute("select value from public.workshop_settings where key='overtime_windows' for update"); overtime=q.fetchone()[0]
    overtime_start=(datetime.combine(local_base,day_end)+timedelta(hours=1)).time().replace(second=0,microsecond=0)
    overtime_end=(datetime.combine(local_base,overtime_start)+timedelta(hours=1)).time()
    q.execute("update public.workshop_settings set value=%s::jsonb where key='overtime_windows'",(json.dumps([{'date':local_base.isoformat(),'start':overtime_start.strftime('%H:%M'),'end':overtime_end.strftime('%H:%M')}]),))
    q.execute("select (%s::date+%s::time) at time zone 'Australia/Perth'",(local_base,overtime_start)); overtime_at=q.fetchone()[0]
    overtime_vehicle=create_vehicle(admin,'BUS_4X4','PMB')
    expect_ok("select public.schedule_vehicle_work(%s,1,'BUS_4X4',%s,%s,60,null,null,'{}'::jsonb)",(overtime_vehicle,bus_bay,overtime_at))
    q.execute("update public.workshop_settings set value=%s::jsonb where key='overtime_windows'",(json.dumps([{'date':local_base.isoformat(),'start':day_end.strftime('%H:%M'),'end':(datetime.combine(local_base,day_end)+timedelta(hours=1)).time().strftime('%H:%M')}]),))
    q.execute("select public.workshop_add_operational_minutes((%s::date+(%s::time-interval '30 minutes')) at time zone 'Australia/Perth',60) at time zone 'Australia/Perth'",(local_base,day_end))
    assert q.fetchone()[0].time()==(datetime.combine(local_base,day_end)+timedelta(minutes=30)).time(),'cascade helper must consume configured overtime'
    q.execute("update public.workshop_settings set value=%s::jsonb where key='overtime_windows'",(json.dumps(overtime),))

    # Behavioural technician-leave rejection through the protected create RPC.
    tech=uuid.uuid4(); q.execute("insert into public.workshop_technicians(id,name,role_type,active) values(%s,%s,'technician',true)",(tech,f'M046 rollback tech {tech}'))
    q.execute("select value from public.workshop_settings where key='technician_leave' for update"); leave=q.fetchone()[0]
    q.execute("""select m from generate_series(%s::timestamptz,%s::timestamptz+interval '14 days',interval '15 minutes')m
      where public.workshop_calendar_interval_available(m,m+interval '1 hour')
        and not exists(select 1 from public.workshop_bookings b where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
          and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(m,m+interval '1 hour','[)')) order by m limit 1""",(cal_base+timedelta(days=21),cal_base+timedelta(days=21)))
    leave_slot=q.fetchone()[0]; leave_date=leave_slot.astimezone(timezone(timedelta(hours=8))).date()
    q.execute("update public.workshop_settings set value=%s::jsonb where key='technician_leave'",(json.dumps([{'technician_id':str(tech),'date':leave_date.isoformat()}]),))
    leave_vehicle=create_vehicle(admin,'BUS_4X4','PMB')
    expect_reject('technician_leave',"select public.schedule_vehicle_work(%s,1,'BUS_4X4',%s,%s,60,%s,null,'{}'::jsonb)",(leave_vehicle,bus_bay,leave_slot,tech),{'technician_on_leave','technician_leave_conflict'})
    q.execute("update public.workshop_settings set value=%s::jsonb where key='technician_leave'",(json.dumps(leave),))

    # Canonical requirement and IT ETA rules.
    missing=create_vehicle(admin,'TINT','PMB'); q.execute('delete from public.vehicle_work_items where vehicle_id=%s',(missing,))
    expect_reject('missing_requirement',"select public.schedule_vehicle_work(%s,1,'TINT',%s,%s,60,null,null,'{}'::jsonb)",(missing,stage_rows['TINT'][2],cal_base+timedelta(days=7)),{'vehicle_not_eligible_for_station'})
    completed=create_vehicle(admin,'TINT','PMB',completed=True)
    expect_reject('completed_requirement',"select public.schedule_vehicle_work(%s,1,'TINT',%s,%s,60,null,null,'{}'::jsonb)",(completed,stage_rows['TINT'][2],cal_base+timedelta(days=7)),{'vehicle_not_eligible_for_station'})
    it_missing=create_vehicle(admin,'HOIST','IT')
    expect_reject('it_missing_eta',"select public.schedule_vehicle_work(%s,1,'HOIST',%s,%s,60,null,null,'{}'::jsonb)",(it_missing,stage_rows['HOIST'][2],cal_base+timedelta(days=7)),{'vehicle_not_eligible_for_station','it_eta_missing'})
    before_date=(cal_base.astimezone(timezone(timedelta(hours=8))).date()+timedelta(days=30))
    it_before=create_vehicle(admin,'HOIST','IT',before_date)
    expect_reject('it_before_eta',"select public.schedule_vehicle_work(%s,1,'HOIST',%s,%s,60,null,null,'{}'::jsonb)",(it_before,stage_rows['HOIST'][2],cal_base+timedelta(days=7)),{'vehicle_not_eligible_for_station','it_before_eta'})

    # Valid and invalid lifecycle transitions.
    lifecycle_booking=primary[0][1]
    expect_ok("select public.start_workshop_work(%s,%s,now(),'{}'::jsonb)",(lifecycle_booking,version(lifecycle_booking))); counts['lifecycle_valid']+=1
    expect_ok("select public.stop_workshop_work(%s,%s,'rollback proof','{}'::jsonb)",(lifecycle_booking,version(lifecycle_booking))); counts['lifecycle_valid']+=1
    expect_ok("select public.resume_workshop_work(%s,%s,'{}'::jsonb)",(lifecycle_booking,version(lifecycle_booking))); counts['lifecycle_valid']+=1
    expect_ok("select public.complete_workshop_work(%s,%s,null,now(),'{}'::jsonb)",(lifecycle_booking,version(lifecycle_booking))); counts['lifecycle_valid']+=1
    expect_reject('completed_direct_start',"select public.start_workshop_work(%s,%s,now(),'{}'::jsonb)",(lifecycle_booking,version(lifecycle_booking))); counts['lifecycle_invalid']+=1
    expect_reject('completed_direct_reopen',"with changed as(update public.workshop_bookings set status='queued' where id=%s returning id) select jsonb_build_object('ok',true) from changed",(lifecycle_booking,)); counts['lifecycle_invalid']+=1
    expect_ok("select public.return_completed_work(%s,%s,'authorised reopen','{}'::jsonb)",(lifecycle_booking,version(lifecycle_booking))); counts['lifecycle_valid']+=1
    planned_booking=primary[2][1]
    expect_reject('planned_direct_complete',"select public.complete_workshop_work(%s,%s,null,now(),'{}'::jsonb)",(planned_booking,version(planned_booking))); counts['lifecycle_invalid']+=1

    # Queued start and stoppage cancellation are valid only through protected
    # runtime actions; direct cancellation from started is impossible.
    queued_booking=primary[4][1]
    expect_ok("select public.cancel_workshop_booking(%s,%s,'queued matrix','{}'::jsonb)",(queued_booking,version(queued_booking))); counts['lifecycle_valid']+=1
    expect_ok("select public.restore_workshop_booking(%s,%s,'{}'::jsonb)",(queued_booking,version(queued_booking))); counts['lifecycle_valid']+=1
    expect_ok("select public.change_booking_bay(%s,%s,%s,'{}'::jsonb)",(queued_booking,version(queued_booking),stage_rows[primary[4][2]][2])); counts['lifecycle_valid']+=1
    expect_ok("select public.start_workshop_work(%s,%s,now(),'{}'::jsonb)",(queued_booking,version(queued_booking))); counts['lifecycle_valid']+=1
    expect_reject('started_direct_cancel',"with changed as(update public.workshop_bookings set status='deleted' where id=%s returning id) select jsonb_build_object('ok',true) from changed",(queued_booking,)); counts['lifecycle_invalid']+=1
    expect_ok("select public.stop_workshop_work(%s,%s,'cancel matrix','{}'::jsonb)",(queued_booking,version(queued_booking))); counts['lifecycle_valid']+=1
    expect_ok("select public.cancel_workshop_booking(%s,%s,'stoppage cancellation','{}'::jsonb)",(queued_booking,version(queued_booking))); counts['lifecycle_valid']+=1

    # Restore revalidates current canonical eligibility and cannot revive invalid data.
    restore_booking=primary[3][1]
    expect_ok("select public.cancel_workshop_booking(%s,%s,'rollback proof','{}'::jsonb)",(restore_booking,version(restore_booking)))
    q.execute('update public.vehicle_work_items set completed=true,completed_at=now() where vehicle_id=%s and public.workshop_stage_code_for_work_key(work_key)=%s',(primary[3][0],primary[3][2]))
    expect_reject('invalid_restore',"select public.restore_workshop_booking(%s,%s,'{}'::jsonb)",(restore_booking,version(restore_booking)),{'canonical_requirement_missing_or_completed'})
    overlap_restore=primary[6][1]; overlap_second=secondary[6][0]
    expect_ok("select public.cancel_workshop_booking(%s,%s,'restore overlap proof','{}'::jsonb)",(overlap_restore,version(overlap_restore)))
    expect_ok("select public.move_workshop_booking(%s,%s,%s,%s,%s,60,null,'{}'::jsonb)",(overlap_second,version(overlap_second),secondary[6][1],secondary[6][2],slots[6]))
    expect_reject('vehicle_overlap_restore',"select public.restore_workshop_booking(%s,%s,'{}'::jsonb)",(overlap_restore,version(overlap_restore)),{'vehicle_overlap'})

    # Browser role cannot call weaker paths.
    signatures=['workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)','workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)','workshop_resize_booking(uuid,integer,integer,jsonb)','workshop_restore_booking(uuid,integer,jsonb)']
    for sig in signatures:
        q.execute("select has_function_privilege('authenticated','public.'||%s,'EXECUTE')",(sig,)); assert q.fetchone()[0] is False,sig
    for table in ('workshop_bookings','workshop_booking_assignments','workshop_transition_authorizations'):
        for privilege in ('INSERT','UPDATE','DELETE','TRUNCATE'):
            q.execute("select has_table_privilege('authenticated','public.'||%s,%s)",(table,privilege)); assert q.fetchone()[0] is False,(table,privilege)

    # Manufacture an impossible legacy overlap only inside nested savepoints.
    # The migration preflight must fail and leave both operational rows intact.
    q.execute('savepoint dirty_preflight')
    dirty_vehicle=create_vehicle(admin,'BUS_4X4','PMB',extra_stage='TINT')
    dirty_slot=base+timedelta(days=100)
    q.execute('alter table public.workshop_bookings disable trigger workshop_booking_046b_validation_guard')
    q.execute('alter table public.workshop_bookings drop constraint workshop_bookings_active_vehicle_no_overlap')
    for code in ('BUS_4X4','TINT'):
        stage_id,_,bay_number=stage_rows[code]
        q.execute('select id from public.workshop_bays where stage_id=%s and bay_number=%s',(stage_id,bay_number)); bay_id=q.fetchone()[0]
        q.execute("""insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,
          default_duration_minutes,created_by,updated_by) values(%s,%s,%s,'planned',%s,%s,60,%s,%s)""",
          (dirty_vehicle,stage_id,bay_id,dirty_slot,dirty_slot+timedelta(hours=1),admin,admin))
    q.execute('savepoint preflight_attempt')
    try:
        q.execute(PREFLIGHT)
        raise AssertionError('migration 046 preflight accepted a dirty active vehicle overlap')
    except psycopg2.Error as exc:
        assert exc.pgcode=='23514',exc
        q.execute('rollback to savepoint preflight_attempt')
        q.execute('select count(*) from public.workshop_bookings where vehicle_id=%s',(dirty_vehicle,))
        assert q.fetchone()[0]==2,'preflight must not clean or rewrite operational rows'
    q.execute('rollback to savepoint dirty_preflight')

    # Historical completed fixture is direct-DML only inside this rollback-only
    # harness; it does not need a fake started transition and cannot ship.
    historical_vehicle=create_vehicle(admin,'TYRE','PMB',completed=True)
    q.execute('alter table public.workshop_bookings disable trigger workshop_bookings_planner_enabled_guard')
    q.execute("""insert into public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,
      default_duration_minutes,source,created_by,updated_by) values(%s,%s,null,'completed',%s,%s,60,'transaction_only_fixture',%s,%s)""",
      (historical_vehicle,stage_rows['TYRE'][0],base,base+timedelta(hours=1),admin,admin))
    q.execute('alter table public.workshop_bookings enable trigger workshop_bookings_planner_enabled_guard')

    print(json.dumps({'rollback_only':True,**counts,'minimum_minutes':60,'planner_stations':STAGES,'historical_fixture_isolated':True,'migration_preflight_overlap_pairs':preexisting_overlap_count},sort_keys=True))
finally:
    conn.rollback(); conn.close()
