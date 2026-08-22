begin;

-- Staging-only repair: active bay bookings must use canonical operation hours.
do $guard$
declare
  v_project text;
  v_active integer;
  v_mismatch integer;
  v_missing integer;
begin
  if to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'PDC_317_PRODUCTION_SENTINEL_PRESENT';
  end if;
  if not public.pdc_monitor_staging_guard() then
    raise exception 'PDC_317_STAGING_GUARD_FAILED';
  end if;
  select project_ref into v_project from public.pdc_staging_environment_sentinel where singleton;
  if v_project is distinct from 'cdsmnqxtyyoeoznmbidd' then
    raise exception 'PDC_317_PROJECT_MISMATCH';
  end if;

  select count(*) into v_active
  from public.workshop_bookings b
  join public.vehicles v on v.id=b.vehicle_id
  where b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage')
    and v.deleted_at is null and v.lifecycle_state='active';

  select count(*) filter(where e.estimated_minutes is not null and b.default_duration_minutes<>e.estimated_minutes),
         count(*) filter(where e.estimated_minutes is null and b.bay_id is not null)
  into v_mismatch,v_missing
  from public.workshop_bookings b
  join public.vehicles v on v.id=b.vehicle_id
  cross join lateral (
    select public.workshop_vehicle_stage_estimated_duration_minutes(v.id,b.stage_id) estimated_minutes
  ) e
  where b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage')
    and v.deleted_at is null and v.lifecycle_state='active';

  if v_active<>4 or v_mismatch<>2 or v_missing<>1 then
    raise exception 'PDC_317_SCOPE_DRIFT active=% mismatched=% missing=%',v_active,v_mismatch,v_missing;
  end if;
end
$guard$;

create or replace function public.workshop_station_eligibility(p_stage_code text)
returns table(vehicle_id uuid,stage_code text,work_key text,current_location text,eta_to_kewdale date,existing_booking boolean,schedule_enabled boolean,disabled_reason text)
language sql stable security definer set search_path=pg_catalog,public as $eligibility$
 with station as(
  select s.id,s.code,s.work_key from public.workshop_stages s
  where s.code=public.workshop_canonical_stage_code(p_stage_code) and s.active and s.planner_enabled
 ),outstanding as(
  select wi.vehicle_id,st.id stage_id,st.code,st.work_key
  from public.vehicle_work_items wi cross join station st
  where public.workshop_stage_code_for_work_key(wi.work_key)=st.code and wi.required and not wi.completed
  group by wi.vehicle_id,st.id,st.code,st.work_key
 ),active_booking as(
  select distinct b.vehicle_id,st.code from public.workshop_bookings b
  join public.workshop_stages s on s.id=b.stage_id join station st on st.code=s.code
  where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
 )
 select v.id,o.code,o.work_key,upper(btrim(coalesce(v.current_location,''))),v.eta_to_kewdale,
  (ab.vehicle_id is not null),
  (public.workshop_vehicle_stage_estimated_duration_minutes(v.id,o.stage_id) is not null),
  case when public.workshop_vehicle_stage_estimated_duration_minutes(v.id,o.stage_id) is null
       then 'estimated_duration_missing' else null::text end
 from outstanding o join public.vehicles v on v.id=o.vehicle_id
 left join active_booking ab on ab.vehicle_id=v.id and ab.code=o.code
 where v.lifecycle_state='active' and v.deleted_at is null
   and upper(btrim(coalesce(v.current_location,''))) in ('PMB','IT')
   and (upper(btrim(coalesce(v.current_location,'')))='PMB' or v.eta_to_kewdale is not null)
$eligibility$;
revoke all on function public.workshop_station_eligibility(text) from public,anon;
grant execute on function public.workshop_station_eligibility(text) to authenticated,service_role;

create or replace function public.workshop_require_positive_estimate_for_planned_booking_317()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $estimate_guard$
begin
  if new.deleted_at is null and new.status='planned'::public.workshop_booking_status
     and public.workshop_vehicle_stage_estimated_duration_minutes(new.vehicle_id,new.stage_id) is null then
    raise exception 'PDC_317_ESTIMATED_DURATION_REQUIRED' using errcode='22023';
  end if;
  return new;
end
$estimate_guard$;
revoke all on function public.workshop_require_positive_estimate_for_planned_booking_317() from public,anon,authenticated,service_role;

drop trigger if exists workshop_booking_045_estimated_duration_required_317 on public.workshop_bookings;
create trigger workshop_booking_045_estimated_duration_required_317
before insert or update of vehicle_id,stage_id,status,deleted_at on public.workshop_bookings
for each row execute function public.workshop_require_positive_estimate_for_planned_booking_317();

-- Restore the already-defined automatic reconciliation hooks. They were absent
-- from the live trigger catalog, so later source-hour changes could leave stale bookings.
drop trigger if exists pdc_operation_line_booking_duration_317 on public.pdc_authenticated_email_operation_lines;
create trigger pdc_operation_line_booking_duration_317
after insert or update of vehicle_id,work_key,estimated_hours or delete on public.pdc_authenticated_email_operation_lines
for each row execute function public.workshop_reconcile_operation_line_booking_duration();

drop trigger if exists pdc_adjustment_booking_duration_317 on public.vehicle_workshop_line_adjustments;
create trigger pdc_adjustment_booking_duration_317
after insert or update of vehicle_id,stage_code,estimated_hours,active or delete on public.vehicle_workshop_line_adjustments
for each row execute function public.workshop_reconcile_adjustment_booking_duration();

-- Apply the current repair using protected, audited Workshop functions.
do $repair$
declare
  v_actor uuid;
  v_email text;
  v_booking public.workshop_bookings%rowtype;
  v_result jsonb;
  v_cancelled integer:=0;
begin
  select auth_user_id,lower(email) into v_actor,v_email
  from public.pdc_user_roles
  where role='administrator' and active and account_status='approved'
    and lower(email)='craig.watson@broometoyota.com.au'
  limit 1;
  if v_actor is null then raise exception 'PDC_317_OWNER_ADMIN_MISSING'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated','email',v_email)::text,true);

  select b.* into v_booking
  from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
  join public.workshop_stages s on s.id=b.stage_id
  where v.stock_number='IS60252030' and s.code='FITTING'
    and b.deleted_at is null and b.status='planned' and b.bay_id is not null
  for update of b;
  if not found or v_booking.version<>1 then raise exception 'PDC_317_MISSING_ESTIMATE_BOOKING_DRIFT'; end if;
  v_result:=public.cancel_workshop_booking(v_booking.id,v_booking.version,
    'Estimated hours missing; booking removed from bay without inventing hours',
    jsonb_build_object('source','migration_317','reason','Canonical operation lines contain no positive Fitting hours'));
  if not coalesce((v_result->>'ok')::boolean,false) then raise exception 'PDC_317_CANCEL_FAILED %',v_result; end if;

  for v_booking in
    select b.*
    from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
    join public.workshop_stages s on s.id=b.stage_id
    where v.stock_number='13033243' and s.code in ('FITTING','HOIST')
      and v.current_location='Other'
      and b.deleted_at is null and b.status='planned' and b.bay_id is not null
    order by s.code
    for update of b
  loop
    if v_booking.version<>1 then raise exception 'PDC_317_STALE_LOCATION_BOOKING_DRIFT %',v_booking.id; end if;
    v_result:=public.cancel_workshop_booking(v_booking.id,v_booking.version,
      'Vehicle location is Other; stale seeded Workshop booking removed',
      jsonb_build_object('source','migration_317','reason','Legacy seeded booking is no longer location-eligible'));
    if not coalesce((v_result->>'ok')::boolean,false) then raise exception 'PDC_317_STALE_CANCEL_FAILED %',v_result; end if;
    v_cancelled:=v_cancelled+1;
  end loop;
  if v_cancelled<>2 then raise exception 'PDC_317_STALE_CANCEL_COUNT %',v_cancelled; end if;

  perform public.workshop_bump_revision();
end
$repair$;

-- Authoritative postconditions: every occupied active bay has a positive estimate
-- and its booked duration equals that estimate. The zero-hour-only booking is
-- cancelled with history; the requirement remains visible but unschedulable.
do $post$
declare v_bad integer;v_is_cancelled integer;v_stale_cancelled integer;begin
 select count(*) into v_bad
 from public.workshop_bookings b
 join public.vehicles v on v.id=b.vehicle_id
 cross join lateral(select public.workshop_vehicle_stage_estimated_duration_minutes(v.id,b.stage_id) minutes)e
 where b.deleted_at is null and b.status in('planned','started','stoppage') and b.bay_id is not null
   and v.deleted_at is null and v.lifecycle_state='active'
   and (e.minutes is null or b.default_duration_minutes<>e.minutes);
 if v_bad<>0 then raise exception 'PDC_317_BAY_DURATION_POSTCONDITION count=%',v_bad; end if;

 select count(*) into v_is_cancelled
 from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
 join public.workshop_stages s on s.id=b.stage_id
 where v.stock_number='IS60252030' and s.code='FITTING'
   and b.status='deleted' and b.deleted_at is not null
   and b.deleted_reason='Estimated hours missing; booking removed from bay without inventing hours';
 if v_is_cancelled<>1 then raise exception 'PDC_317_MISSING_ESTIMATE_NOT_CANCELLED count=%',v_is_cancelled; end if;

 select count(*) into v_stale_cancelled
 from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
 where v.stock_number='13033243' and b.status='deleted' and b.deleted_at is not null
   and b.deleted_reason='Vehicle location is Other; stale seeded Workshop booking removed';
 if v_stale_cancelled<>2 then raise exception 'PDC_317_STALE_LOCATION_NOT_CANCELLED count=%',v_stale_cancelled; end if;
end
$post$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260822093000','317_enforce_workshop_booking_estimated_hours',array['staging-only booking estimate enforcement and reconciliation'])
on conflict(version) do nothing;

commit;
