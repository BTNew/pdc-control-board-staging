-- Workshop Planner authoritative calendar, overlap, lifecycle, and runtime-path enforcement.
-- Additive correction: the approved minimum remains exactly 60 minutes.

begin;

-- The extension already exists from migration 006; retain an idempotent declaration
-- because the exclusion constraints below depend on UUID GiST equality.
create extension if not exists btree_gist;

-- Private, transaction-scoped capabilities for the three exceptional lifecycle
-- transitions. Runtime users have no table privileges; protected wrappers create
-- and consume a marker in the same transaction as the guarded row update.
create table if not exists public.workshop_transition_authorizations (
  txid bigint not null,
  booking_id uuid not null references public.workshop_bookings(id) on delete cascade,
  transition text not null,
  authorized_by uuid,
  created_at timestamptz not null default now(),
  primary key (txid, booking_id, transition),
  constraint workshop_transition_authorizations_name_check
    check (transition in ('restore', 'reopen_completed', 'return_to_queue'))
);
alter table public.workshop_transition_authorizations enable row level security;
revoke all on table public.workshop_transition_authorizations from public, anon, authenticated;

create or replace function public.workshop_authorize_transition(p_booking_id uuid, p_transition text)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if p_transition not in ('restore','reopen_completed','return_to_queue') then
    raise exception 'Unknown Workshop Planner transition authorization' using errcode='22023';
  end if;
  perform public.workshop_require_planner_operator();
  insert into public.workshop_transition_authorizations(txid,booking_id,transition,authorized_by)
  values(txid_current(),p_booking_id,p_transition,auth.uid())
  on conflict do nothing;
end $$;
revoke all on function public.workshop_authorize_transition(uuid,text) from public,anon,authenticated;

create or replace function public.workshop_consume_transition_authorization(p_booking_id uuid,p_transition text)
returns boolean
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_found boolean;
begin
  delete from public.workshop_transition_authorizations
  where txid=txid_current() and booking_id=p_booking_id and transition=p_transition
  returning true into v_found;
  return coalesce(v_found,false);
end $$;
revoke all on function public.workshop_consume_transition_authorization(uuid,text) from public,anon,authenticated;

-- True only when one local calendar minute is available under the shared
-- workshop_settings authority. Dates and clock times are interpreted in AWST.
create or replace function public.workshop_calendar_minute_available(p_at timestamptz)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare
  v_local timestamp := p_at at time zone 'Australia/Perth';
  v_date date := v_local::date;
  v_clock time := v_local::time;
  v_day text := lower(to_char(v_local,'FMDay'));
  v_start time;
  v_end time;
  v_working_week jsonb;
  v_closures jsonb;
  v_breaks jsonb;
  v_overtime jsonb;
  v_workday boolean;
  v_regular boolean;
  v_overtime_ok boolean;
  v_break boolean;
begin
  select (value #>> '{}')::time into v_start from public.workshop_settings where key='day_start_time';
  select (value #>> '{}')::time into v_end from public.workshop_settings where key='day_end_time';
  select value into v_working_week from public.workshop_settings where key='working_week';
  select value into v_closures from public.workshop_settings where key='closures';
  select value into v_breaks from public.workshop_settings where key='break_windows';
  select value into v_overtime from public.workshop_settings where key='overtime_windows';
  if v_start is null or v_end is null or v_start>=v_end
     or jsonb_typeof(v_working_week)<>'array' or jsonb_typeof(v_closures)<>'array'
     or jsonb_typeof(v_breaks)<>'array' or jsonb_typeof(v_overtime)<>'array' then
    return false;
  end if;
  select exists(select 1 from jsonb_array_elements_text(v_working_week) d where lower(d)=v_day) into v_workday;
  if not v_workday or exists(
    select 1 from jsonb_array_elements(v_closures) c where c->>'date'=v_date::text
  ) then return false; end if;
  v_regular := v_clock>=v_start and v_clock<v_end;
  select exists(
    select 1 from jsonb_array_elements(v_overtime) w
    where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
      and ((w ? 'date' and w->>'date'=v_date::text)
        or (not (w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in ('global','working_day',v_day)))
  ) into v_overtime_ok;
  select exists(
    select 1 from jsonb_array_elements(v_breaks) w
    where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
      and ((w ? 'date' and w->>'date'=v_date::text)
        or (not (w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in ('global','working_day',v_day)))
  ) into v_break;
  return (v_regular or v_overtime_ok) and not v_break;
exception when others then
  return false;
end $$;
revoke all on function public.workshop_calendar_minute_available(timestamptz) from public,anon,authenticated;

create or replace function public.workshop_calendar_interval_available(p_start timestamptz,p_end timestamptz)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare
  v_start time; v_end time; v_working_week jsonb; v_closures jsonb; v_breaks jsonb; v_overtime jsonb;
  v_minute timestamptz; v_local timestamp; v_date date; v_clock time; v_day text;
  v_workday boolean; v_overtime_ok boolean; v_break boolean;
begin
  if p_start is null or p_end is null or p_end<=p_start then return false; end if;
  select (value #>> '{}')::time into v_start from public.workshop_settings where key='day_start_time';
  select (value #>> '{}')::time into v_end from public.workshop_settings where key='day_end_time';
  select value into v_working_week from public.workshop_settings where key='working_week';
  select value into v_closures from public.workshop_settings where key='closures';
  select value into v_breaks from public.workshop_settings where key='break_windows';
  select value into v_overtime from public.workshop_settings where key='overtime_windows';
  if v_start is null or v_end is null or v_start>=v_end
     or jsonb_typeof(v_working_week)<>'array' or jsonb_typeof(v_closures)<>'array'
     or jsonb_typeof(v_breaks)<>'array' or jsonb_typeof(v_overtime)<>'array' then return false; end if;
  for v_minute in select generate_series(p_start,p_end-interval '1 minute',interval '1 minute') loop
    v_local:=v_minute at time zone 'Australia/Perth'; v_date:=v_local::date; v_clock:=v_local::time;
    v_day:=lower(to_char(v_local,'FMDay'));
    select exists(select 1 from jsonb_array_elements_text(v_working_week)d where lower(d)=v_day) into v_workday;
    if not v_workday or exists(select 1 from jsonb_array_elements(v_closures)c where c->>'date'=v_date::text) then return false; end if;
    select exists(select 1 from jsonb_array_elements(v_overtime)w
      where v_clock>=(w->>'start')::time and v_clock<(w->>'end')::time
        and ((w?'date' and w->>'date'=v_date::text) or (not(w?'date') and lower(coalesce(w->>'scope',w->>'day','global')) in('global','working_day',v_day)))) into v_overtime_ok;
    select exists(select 1 from jsonb_array_elements(v_breaks)w
      where v_clock>=(w->>'start')::time and v_clock<(w->>'end')::time
        and ((w?'date' and w->>'date'=v_date::text) or (not(w?'date') and lower(coalesce(w->>'scope',w->>'day','global')) in('global','working_day',v_day)))) into v_break;
    if not ((v_clock>=v_start and v_clock<v_end) or v_overtime_ok) or v_break then return false; end if;
  end loop;
  return true;
exception when others then return false;
end $$;
revoke all on function public.workshop_calendar_interval_available(timestamptz,timestamptz) from public,anon,authenticated;

create or replace function public.workshop_operational_minutes_between(p_start timestamptz,p_end timestamptz)
returns integer
language sql
stable
security definer
set search_path=pg_catalog,public
as $$
  select case when p_start is null or p_end is null or p_end<=p_start then 0 else count(*)::integer end
  from generate_series(date_trunc('minute',p_start),date_trunc('minute',p_end)-interval '1 minute',interval '1 minute') m
  where public.workshop_calendar_minute_available(m)
$$;
revoke all on function public.workshop_operational_minutes_between(timestamptz,timestamptz) from public,anon,authenticated;

create or replace function public.workshop_next_calendar_window(p_from timestamptz,p_duration_minutes integer)
returns timestamptz
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare v_candidate timestamptz:=date_trunc('minute',p_from); v_limit timestamptz:=p_from+interval '90 days';
begin
  if p_duration_minutes is null or p_duration_minutes<60 then
    raise exception 'Workshop duration must be at least 60 minutes' using errcode='22023';
  end if;
  while v_candidate<v_limit loop
    if not exists(
      select 1 from generate_series(v_candidate,v_candidate+make_interval(mins=>p_duration_minutes-1),interval '1 minute') m
      where not public.workshop_calendar_minute_available(m)
    ) then return v_candidate; end if;
    v_candidate:=v_candidate+interval '1 minute';
  end loop;
  raise exception 'No configured Workshop Planner window is available' using errcode='22023';
end $$;
revoke all on function public.workshop_next_calendar_window(timestamptz,integer) from public,anon,authenticated;

-- One canonical validator for create, move, resize, cascade, restore, and
-- assignment writes. It returns a stable machine-readable error rather than
-- duplicating policy in each RPC.
create or replace function public.workshop_validate_booking(
  p_booking_id uuid,
  p_vehicle_id uuid,
  p_stage_id uuid,
  p_bay_id uuid,
  p_scheduled_start_at timestamptz,
  p_scheduled_end_at timestamptz,
  p_duration_minutes integer,
  p_status public.workshop_booking_status,
  p_technician_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,extensions
as $$
declare
  v_vehicle public.vehicles%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_conflict uuid;
  v_local_date date := (p_scheduled_start_at at time zone 'Australia/Perth')::date;
  v_active boolean := p_status in ('queued','planned','started','stoppage');
begin
  if not v_active then return jsonb_build_object('ok',true); end if;
  if p_duration_minutes is null or p_duration_minutes<60 then
    return jsonb_build_object('ok',false,'error','minimum_duration','minimum_minutes',60);
  end if;
  if p_scheduled_start_at is null or p_scheduled_end_at is null or p_scheduled_end_at<=p_scheduled_start_at
     or date_trunc('minute',p_scheduled_start_at)<>p_scheduled_start_at
     or date_trunc('minute',p_scheduled_end_at)<>p_scheduled_end_at then
    return jsonb_build_object('ok',false,'error','invalid_schedule_interval');
  end if;
  if not public.workshop_calendar_minute_available(p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','calendar_unavailable');
  end if;
  if floor(extract(epoch from(p_scheduled_end_at-p_scheduled_start_at))/60.0)::integer<>p_duration_minutes
     or not public.workshop_calendar_interval_available(p_scheduled_start_at,p_scheduled_end_at) then
    return jsonb_build_object('ok',false,'error','calendar_duration_mismatch');
  end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id and deleted_at is null and lifecycle_state='active';
  if not found then return jsonb_build_object('ok',false,'error','vehicle_inactive_or_missing'); end if;
  select * into v_stage from public.workshop_stages where id=p_stage_id and active and planner_enabled;
  if not found then return jsonb_build_object('ok',false,'error','station_inactive_or_missing'); end if;
  if upper(btrim(coalesce(v_vehicle.current_location,''))) not in ('PMB','YH','IT') then
    return jsonb_build_object('ok',false,'error','location_ineligible');
  end if;
  if upper(btrim(coalesce(v_vehicle.current_location,'')))='IT' then
    if v_vehicle.eta_to_kewdale is null then return jsonb_build_object('ok',false,'error','it_eta_missing'); end if;
    if v_local_date<v_vehicle.eta_to_kewdale then return jsonb_build_object('ok',false,'error','it_before_eta'); end if;
  end if;
  if not exists(
    select 1 from public.vehicle_work_items wi
    where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
      and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage.code
  ) then return jsonb_build_object('ok',false,'error','canonical_requirement_missing_or_completed'); end if;
  if p_status<>'queued' then
    if p_bay_id is null then return jsonb_build_object('ok',false,'error','bay_required'); end if;
    select * into v_bay from public.workshop_bays where id=p_bay_id and stage_id=p_stage_id and is_active;
    if not found then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
  end if;
  if p_bay_id is not null then
    select b.id into v_conflict from public.workshop_bookings b
    where b.id is distinct from p_booking_id and b.deleted_at is null
      and b.status in ('planned','started','stoppage') and b.bay_id=p_bay_id
      and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)') && tstzrange(p_scheduled_start_at,p_scheduled_end_at,'[)')
    order by b.scheduled_start_at,b.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','bay_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  select b.id into v_conflict from public.workshop_bookings b
  where b.id is distinct from p_booking_id and b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage') and b.vehicle_id=p_vehicle_id
    and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)') && tstzrange(p_scheduled_start_at,p_scheduled_end_at,'[)')
  order by b.scheduled_start_at,b.id limit 1;
  if v_conflict is not null then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if;
  if p_technician_id is not null then
    if not exists(select 1 from public.workshop_technicians t where t.id=p_technician_id and t.active) then
      return jsonb_build_object('ok',false,'error','technician_inactive_or_missing');
    end if;
    if public.workshop_technician_leave_date(p_technician_id,p_scheduled_start_at,p_scheduled_end_at) is not null then
      return jsonb_build_object('ok',false,'error','technician_leave_conflict');
    end if;
    select a.booking_id into v_conflict from public.workshop_booking_assignments a
    where a.booking_id is distinct from p_booking_id and a.technician_id=p_technician_id and a.released_at is null
      and tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)') && tstzrange(p_scheduled_start_at,p_scheduled_end_at,'[)')
    order by a.scheduled_start_at,a.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid) from public,anon,authenticated;

create or replace function public.workshop_enforce_booking_lifecycle()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_allowed boolean:=false;
begin
  if tg_op='INSERT' or new.status=old.status then return new; end if;
  v_allowed :=
    (old.status in ('queued','planned') and new.status='started') or
    (old.status='started' and new.status='stoppage') or
    (old.status='stoppage' and new.status='started') or
    (old.status in ('started','stoppage') and new.status='completed') or
    (old.status in ('queued','planned','stoppage') and new.status='deleted');
  if old.status='completed' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'reopen_completed');
  elsif old.status='deleted' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'restore');
  elsif old.status in ('started','stoppage') and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'return_to_queue');
  end if;
  if not v_allowed then
    raise exception 'Invalid Workshop Planner lifecycle transition: % -> %',old.status,new.status using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function public.workshop_enforce_booking_lifecycle() from public,anon,authenticated;

drop trigger if exists workshop_booking_046a_lifecycle_guard on public.workshop_bookings;
create trigger workshop_booking_046a_lifecycle_guard
before update of status on public.workshop_bookings
for each row execute function public.workshop_enforce_booking_lifecycle();

create or replace function public.workshop_enforce_booking_validation()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_result jsonb; v_technician uuid;
begin
  if new.deleted_at is not null or new.status not in ('queued','planned','started','stoppage') then return new; end if;
  -- Serialize the check/write pair per vehicle. Unlike an exclusion constraint,
  -- this can be introduced while a separately-reviewed legacy staging overlap
  -- still exists; every create/move/resize/cascade/restore after migration 046
  -- is nevertheless race-safe and cannot add or revive an overlap.
  perform pg_advisory_xact_lock(hashtextextended('workshop:vehicle:'||new.vehicle_id::text,0));
  select a.technician_id into v_technician from public.workshop_booking_assignments a
  where a.booking_id=new.id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1;
  v_result:=public.workshop_validate_booking(new.id,new.vehicle_id,new.stage_id,new.bay_id,new.scheduled_start_at,
    new.scheduled_end_at,new.default_duration_minutes,new.status,v_technician);
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'Workshop Planner validation rejected booking: %',v_result::text using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function public.workshop_enforce_booking_validation() from public,anon,authenticated;

drop trigger if exists workshop_booking_046b_validation_guard on public.workshop_bookings;
create trigger workshop_booking_046b_validation_guard
before insert or update of vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,deleted_at
on public.workshop_bookings
for each row execute function public.workshop_enforce_booking_validation();

create or replace function public.workshop_enforce_assignment_validation()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_booking public.workshop_bookings%rowtype; v_result jsonb;
begin
  if new.released_at is not null then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('workshop:technician:'||new.technician_id::text,0));
  select * into v_booking from public.workshop_bookings where id=new.booking_id;
  if not found or v_booking.deleted_at is not null or v_booking.status not in ('queued','planned','started','stoppage') then
    raise exception 'Active booking is required for active technician assignment' using errcode='22023';
  end if;
  if new.scheduled_start_at is distinct from v_booking.scheduled_start_at or new.scheduled_end_at is distinct from v_booking.scheduled_end_at then
    raise exception 'Assignment interval must equal booking interval' using errcode='22023';
  end if;
  v_result:=public.workshop_validate_booking(v_booking.id,v_booking.vehicle_id,v_booking.stage_id,v_booking.bay_id,
    v_booking.scheduled_start_at,v_booking.scheduled_end_at,v_booking.default_duration_minutes,v_booking.status,new.technician_id);
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'Workshop Planner validation rejected assignment: %',v_result::text using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function public.workshop_enforce_assignment_validation() from public,anon,authenticated;

drop trigger if exists workshop_assignment_046_validation_guard on public.workshop_booking_assignments;
create trigger workshop_assignment_046_validation_guard
before insert or update of booking_id,technician_id,scheduled_start_at,scheduled_end_at,released_at
on public.workshop_booking_assignments
for each row execute function public.workshop_enforce_assignment_validation();

-- Authoritative race-safe overlap protection. The validator provides readable
-- errors; these constraints close the concurrent check-then-write race and also
-- cover direct DML, cascade shifts, and restore.
alter table public.workshop_bookings drop constraint if exists workshop_bookings_active_bay_no_overlap;
alter table public.workshop_bookings add constraint workshop_bookings_active_bay_no_overlap
exclude using gist (
  bay_id with =,
  tstzrange(scheduled_start_at,scheduled_end_at,'[)') with &&
) where (deleted_at is null and bay_id is not null and status in ('planned','started','stoppage'));

alter table public.workshop_booking_assignments drop constraint if exists workshop_assignments_active_technician_no_overlap;
alter table public.workshop_booking_assignments add constraint workshop_assignments_active_technician_no_overlap
exclude using gist (
  technician_id with =,
  tstzrange(scheduled_start_at,scheduled_end_at,'[)') with &&
) where (released_at is null);

-- Protected wrappers authorize only the exceptional transition they own.
create or replace function public.resume_workshop_work(p_booking_id uuid,p_expected_version integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_booking public.workshop_bookings%rowtype; v_technician_id uuid; v_conflict_id uuid; v_now timestamptz:=now();
 v_new_start timestamptz; v_new_end timestamptz; v_remaining_minutes integer; v_elapsed_minutes integer; v_result jsonb; v_revision bigint;
begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 if v_booking.status<>'stoppage' then return jsonb_build_object('ok',false,'error','not_stopped'); end if;
 v_elapsed_minutes:=greatest(0,floor(extract(epoch from(coalesce(v_booking.stoppage_started_at,v_now)-v_booking.scheduled_start_at))/60.0)::integer)-coalesce(v_booking.stoppage_accumulated_minutes,0);
 v_remaining_minutes:=greatest(60,v_booking.default_duration_minutes-greatest(0,v_elapsed_minutes));
 v_new_start:=public.workshop_next_calendar_window(v_now,v_remaining_minutes); v_new_end:=v_new_start+make_interval(mins=>v_remaining_minutes);
 select technician_id into v_technician_id from public.workshop_booking_assignments where booking_id=p_booking_id and released_at is null
 order by case when assignment_type='primary' then 0 else 1 end,assigned_at desc limit 1;
 perform public.workshop_lock_resources(v_booking.bay_id,v_technician_id);
 v_conflict_id:=public.workshop_find_bay_conflict(p_booking_id,v_booking.bay_id,v_new_start,v_new_end);
 if v_conflict_id is not null then return jsonb_build_object('ok',false,'error','bay_overlap','conflict',public.workshop_conflict_payload(v_conflict_id,'bay_overlap')); end if;
 if v_technician_id is not null then
  v_conflict_id:=public.workshop_find_technician_conflict(p_booking_id,v_technician_id,v_new_start,v_new_end);
  if v_conflict_id is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict',public.workshop_conflict_payload(v_conflict_id,'technician_overlap')); end if;
 end if;
 update public.workshop_bookings set scheduled_start_at=v_new_start,scheduled_end_at=v_new_end,
  default_duration_minutes=v_remaining_minutes,updated_by=auth.uid(),version=version+1 where id=p_booking_id;
 perform public.workshop_upsert_primary_assignment(p_booking_id,v_technician_id,v_new_start,v_new_end,'resume_rescheduled');
 v_result:=public.workshop_resume_booking(p_booking_id,v_booking.version+1,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision);
end $$;

create or replace function public.return_completed_work(p_booking_id uuid,p_expected_version integer,p_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint;
begin
  perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
  perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
  perform public.workshop_authorize_transition(p_booking_id,'reopen_completed');
  v_result:=public.workshop_return_booking_to_queue(p_booking_id,p_expected_version,p_reason,p_metadata);
  if not (v_result->>'ok')::boolean then return v_result; end if;
  v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision);
end $$;

create or replace function public.return_work_to_queue(p_booking_id uuid,p_expected_version integer,p_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint;
begin
  perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
  perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
  perform public.workshop_authorize_transition(p_booking_id,'return_to_queue');
  v_result:=public.workshop_return_booking_to_queue(p_booking_id,p_expected_version,p_reason,p_metadata);
  if not (v_result->>'ok')::boolean then return v_result; end if;
  v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision);
end $$;

create or replace function public.restore_workshop_booking(p_booking_id uuid,p_expected_version integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint;
begin
  perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
  perform public.workshop_require_booking_active_vehicle(p_booking_id,true);
  perform public.workshop_require_booking_restore_eligibility(p_booking_id);
  perform public.workshop_authorize_transition(p_booking_id,'restore');
  v_result:=public.workshop_restore_booking(p_booking_id,p_expected_version,p_metadata);
  if not (v_result->>'ok')::boolean then return v_result; end if;
  v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision);
end $$;

-- Browser/runtime execution remains limited to protected wrappers. Low-level
-- mutation helpers and every fixture authority remain inaccessible.
revoke execute on function public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_resize_booking(uuid,integer,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_restore_booking(uuid,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_start_booking(uuid,integer,timestamptz,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_record_stoppage(uuid,integer,text,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_resume_booking(uuid,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_complete_booking(uuid,integer,timestamptz,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_return_booking_to_queue(uuid,integer,text,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_delete_booking(uuid,integer,text,jsonb) from public,anon,authenticated;

grant execute on function public.return_completed_work(uuid,integer,text,jsonb) to authenticated;
grant execute on function public.return_work_to_queue(uuid,integer,text,jsonb) to authenticated;
grant execute on function public.restore_workshop_booking(uuid,integer,jsonb) to authenticated;

comment on function public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid) is
'Canonical Workshop Planner validator: 60-minute minimum, AWST calendar, bay/technician availability, PMB/YH/IT ETA, canonical requirement, and half-open bay/vehicle/technician overlap.';
comment on table public.workshop_transition_authorizations is
'Private transaction-scoped capabilities consumed by lifecycle guards; never a fixture/runtime API.';

commit;
