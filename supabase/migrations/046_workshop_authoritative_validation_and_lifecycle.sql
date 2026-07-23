-- Workshop Planner authoritative calendar, overlap, lifecycle, and runtime-path enforcement.
-- Additive correction: the approved minimum remains exactly 60 minutes.

begin;

-- The extension already exists from migration 006; retain an idempotent declaration
-- because the exclusion constraints below depend on UUID GiST equality.
create extension if not exists btree_gist;

-- Do not silently grandfather ambiguous active vehicle schedules. Operational
-- rows must be adjudicated separately; this migration never rewrites them.
do $$
begin
  if exists (
    select 1
    from public.workshop_bookings a
    join public.workshop_bookings b
      on b.vehicle_id=a.vehicle_id and b.id>a.id
     and b.deleted_at is null and b.status in ('queued','planned','started','stoppage')
     and tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')
         && tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)')
    where a.deleted_at is null and a.status in ('queued','planned','started','stoppage')
  ) then
    raise exception 'Existing active same-vehicle booking overlaps require adjudication before migration 046'
      using errcode='23514';
  end if;
end $$;

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
    if public.workshop_calendar_minute_available(v_candidate) then
      perform public.workshop_add_operational_minutes(v_candidate,p_duration_minutes);
      return v_candidate;
    end if;
    v_candidate:=v_candidate+interval '1 minute';
  end loop;
  raise exception 'No configured Workshop Planner window is available' using errcode='22023';
end $$;
revoke all on function public.workshop_next_calendar_window(timestamptz,integer) from public,anon,authenticated;

-- Cascade shifts must consume the same configured minutes as the canonical
-- validator. This supersedes migration 040's weekday/hour-only helper so a
-- shift skips closures and breaks and may consume configured overtime.
create or replace function public.workshop_add_operational_minutes(p_start timestamptz,p_duration_minutes integer)
returns timestamptz
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare
  v_cursor timestamptz:=date_trunc('minute',p_start);
  v_remaining integer:=p_duration_minutes;
  v_limit timestamptz:=date_trunc('minute',p_start)+interval '90 days';
begin
  if p_start is null or p_duration_minutes is null or p_duration_minutes<0 then
    raise exception 'Operational minutes must be non-negative' using errcode='22023';
  end if;
  if p_duration_minutes=0 then return p_start; end if;
  while v_remaining>0 and v_cursor<v_limit loop
    if public.workshop_calendar_minute_available(v_cursor) then
      v_remaining:=v_remaining-1;
    end if;
    v_cursor:=v_cursor+interval '1 minute';
  end loop;
  if v_remaining>0 then
    raise exception 'Operational duration exceeded canonical calendar guard' using errcode='22023';
  end if;
  return v_cursor;
end $$;
revoke all on function public.workshop_add_operational_minutes(timestamptz,integer) from public,anon,authenticated;

-- Supersede the Brisbane-date legacy helper: the authoritative workshop
-- calendar and leave dates are both interpreted in Australia/Perth.
create or replace function public.workshop_technician_leave_date(
  p_technician_id uuid,p_start timestamptz,p_end timestamptz
) returns date language sql stable security definer set search_path=pg_catalog,public as $$
  select (item->>'date')::date
  from public.workshop_settings s
  cross join lateral jsonb_array_elements(case when jsonb_typeof(s.value)='array' then s.value else '[]'::jsonb end) item
  where s.key='technician_leave'
    and item->>'technician_id'=p_technician_id::text
    and public.workshop_is_exact_iso_date(item->>'date')
    and (item->>'date')::date between (p_start at time zone 'Australia/Perth')::date
      and ((p_end-interval '1 microsecond') at time zone 'Australia/Perth')::date
  order by (item->>'date')::date limit 1
$$;
revoke all on function public.workshop_technician_leave_date(uuid,timestamptz,timestamptz) from public,anon,authenticated;

-- Keep every effective low-level mutation on the same operational-minute
-- duration semantics as the frontend and canonical validator. These helpers stay
-- non-browser-callable and are reached only through protected wrappers.
create or replace function public.workshop_create_booking(
  p_vehicle_id uuid,
  p_stage_code text,
  p_bay_number integer,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer default 180,
  p_technician_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_stage_id uuid;
  v_bay_id uuid;
  v_booking_id uuid;
  v_conflict_id uuid;
  v_history_id uuid;
  v_end timestamptz;
  v_after jsonb;
  v_leave_date date;
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  v_end := public.workshop_add_operational_minutes(p_scheduled_start_at, p_duration_minutes);

  if p_technician_id is not null then
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id) then
      return jsonb_build_object('ok', false, 'error', 'technician_not_found', 'technician_id', p_technician_id);
    end if;
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id and active) then
      return jsonb_build_object('ok', false, 'error', 'technician_inactive', 'technician_id', p_technician_id);
    end if;
    select public.workshop_technician_leave_date(p_technician_id, p_scheduled_start_at, v_end) into v_leave_date;
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'technician_id', p_technician_id, 'date', v_leave_date);
    end if;
  end if;

  perform public.workshop_lock_resources(v_bay_id, p_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(null, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;

  if p_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(null, p_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  insert into public.workshop_bookings (
    vehicle_id,
    stage_id,
    bay_id,
    status,
    scheduled_start_at,
    scheduled_end_at,
    default_duration_minutes,
    created_by,
    updated_by
  ) values (
    p_vehicle_id,
    v_stage_id,
    v_bay_id,
    'planned',
    p_scheduled_start_at,
    v_end,
    p_duration_minutes,
    auth.uid(),
    auth.uid()
  ) returning id into v_booking_id;

  perform public.workshop_upsert_primary_assignment(v_booking_id, p_technician_id, p_scheduled_start_at, v_end, 'created');

  v_after := public.workshop_booking_snapshot(v_booking_id);
  v_history_id := public.workshop_write_history(v_booking_id, 'created', null, v_after, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_move_booking(
  p_booking_id uuid,
  p_expected_version integer,
  p_stage_code text,
  p_bay_number integer,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_stage_id uuid;
  v_bay_id uuid;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_duration integer;
  v_end timestamptz;
  v_history_id uuid;
  v_leave_date date;
begin
  perform public.require_pdc_role('operator');

  select * into v_before
  from public.workshop_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_before.id, 'version_conflict'));
  end if;
  perform 1 from public.vehicles where id=v_before.vehicle_id for update;

  select technician_id into v_technician_id
  from public.workshop_booking_assignments
  where booking_id = p_booking_id and released_at is null
  order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc
  limit 1;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  v_duration := coalesce(p_duration_minutes, v_before.default_duration_minutes);
  if v_duration <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;
  v_end := public.workshop_add_operational_minutes(p_scheduled_start_at, v_duration);

  perform public.workshop_lock_resources(v_bay_id, v_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;
  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  if v_technician_id is not null then
    v_leave_date := public.workshop_technician_leave_date(v_technician_id, p_scheduled_start_at, v_end);
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'date', v_leave_date, 'technician_id', v_technician_id);
    end if;
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set stage_id = v_stage_id,
      bay_id = v_bay_id,
      scheduled_start_at = p_scheduled_start_at,
      scheduled_end_at = v_end,
      default_duration_minutes = v_duration,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, p_scheduled_start_at, v_end, 'moved');

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'moved', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_resize_booking(
  p_booking_id uuid,
  p_expected_version integer,
  p_duration_minutes integer,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_end timestamptz;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
  v_leave_date date;
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;
  perform 1 from public.vehicles where id=v_booking.vehicle_id for update;

  select technician_id into v_technician_id
  from public.workshop_booking_assignments
  where booking_id = p_booking_id and released_at is null
  order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc
  limit 1;

  v_end := public.workshop_add_operational_minutes(v_booking.scheduled_start_at, p_duration_minutes);
  perform public.workshop_lock_resources(v_booking.bay_id, v_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_booking.bay_id, v_booking.scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;
  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, v_booking.scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  if v_technician_id is not null then
    v_leave_date := public.workshop_technician_leave_date(v_technician_id, v_booking.scheduled_start_at, v_end);
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'date', v_leave_date, 'technician_id', v_technician_id);
    end if;
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set scheduled_end_at = v_end,
      default_duration_minutes = p_duration_minutes,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, v_booking.scheduled_start_at, v_end, 'resized');

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'resized', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

-- Supersede the migration-040 cascade so shifted bookings start on a canonical
-- operating minute and consume configured operating minutes across gaps. The
-- target action remains protected by the
-- same schedule/resize wrappers and the entire cascade remains atomic.
create or replace function public.cascade_workshop_schedule(
  p_operation text,
  p_target_id uuid,
  p_target_expected_version integer,
  p_stage_code text,
  p_bay_number integer,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer,
  p_technician_id uuid default null,
  p_shift_minutes integer default 0,
  p_override_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_target public.workshop_bookings%rowtype;
  v_shifted public.workshop_bookings%rowtype;
  v_expected_ids uuid[] := '{}'::uuid[];
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_result jsonb;
  v_technician uuid;
  v_conflict uuid;
  v_locked_count integer;
begin
  perform public.workshop_require_planner_operator();
  perform public.workshop_require_version(p_target_expected_version);
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:cascade',0));

  if v_operation not in ('insert', 'extend') then
    raise exception 'Cascade operation must be insert or extend' using errcode = '22023';
  end if;
  if p_duration_minutes is null or p_duration_minutes < 60 then
    return jsonb_build_object('ok', false, 'error', 'minimum_duration', 'minimum_minutes', 60);
  end if;
  if p_shift_minutes is null or p_shift_minutes < 0 then
    raise exception 'Cascade shift minutes must be non-negative' using errcode = '22023';
  end if;

  if v_operation = 'insert' then
    select * into v_stage from public.workshop_stages
      where code = upper(trim(coalesce(p_stage_code, ''))) and active;
    if not found then raise exception 'Workshop stage not found' using errcode = 'P0002'; end if;
    select * into v_bay from public.workshop_bays
      where stage_id = v_stage.id and bay_number = p_bay_number and is_active;
    if not found then raise exception 'Workshop bay not found or inactive' using errcode = 'P0002'; end if;
    if p_shift_minutes <> p_duration_minutes then
      raise exception 'Insert cascade shift must equal inserted duration' using errcode = '22023';
    end if;
    perform 1 from public.vehicles where id = p_target_id and version = p_target_expected_version for update;
    if not found then return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict'); end if;
    if v_stage.is_physical and not public.workshop_parts_ready(p_target_id) then
      if p_override_reason is null or trim(p_override_reason) = '' then
        return jsonb_build_object('ok', false, 'error', 'parts_incomplete');
      end if;
      perform public.require_pdc_role('administrator');
    end if;
  else
    select * into v_target from public.workshop_bookings where id = p_target_id for update;
    if not found then raise exception 'Workshop booking not found' using errcode = 'P0002'; end if;
    if v_target.version <> p_target_expected_version then
      return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_target.id, 'version_conflict'));
    end if;
    if v_target.status = 'completed' then return jsonb_build_object('ok', false, 'error', 'completed_booking'); end if;
    if p_duration_minutes <= v_target.default_duration_minutes then
      return public.resize_workshop_booking(p_target_id, p_target_expected_version, p_duration_minutes, coalesce(p_metadata, '{}'::jsonb));
    end if;
    if p_shift_minutes <> p_duration_minutes - v_target.default_duration_minutes then
      raise exception 'Extend cascade shift must equal the duration increase' using errcode = '22023';
    end if;
    select * into v_stage from public.workshop_stages where id = v_target.stage_id;
    select * into v_bay from public.workshop_bays where id = v_target.bay_id;
    if upper(trim(coalesce(p_stage_code, ''))) <> v_stage.code or p_bay_number <> v_bay.bay_number then
      raise exception 'Extend cascade cannot change stage or bay' using errcode = '22023';
    end if;
    p_scheduled_start_at := v_target.scheduled_start_at;
  end if;

  select coalesce(array_agg(b.id order by b.scheduled_start_at, b.id), '{}'::uuid[])
    into v_expected_ids
  from public.workshop_bookings b
  where b.bay_id = v_bay.id and b.status = 'planned' and b.deleted_at is null
    and (case when v_operation = 'insert' then b.scheduled_start_at >= p_scheduled_start_at
              else b.id <> p_target_id and b.scheduled_start_at > v_target.scheduled_start_at end);

  perform 1 from public.workshop_bookings b where b.id = any(v_expected_ids) order by b.scheduled_start_at, b.id for update;

  -- Booking validation locks the vehicle row too. Acquire every affected
  -- vehicle before the bay lock so create/move/cascade share a non-cyclic
  -- booking -> vehicle -> bay order.
  perform 1 from public.vehicles v
  where v.id in (
    select b.vehicle_id from public.workshop_bookings b where b.id=any(v_expected_ids)
    union select case when v_operation='insert' then p_target_id else v_target.vehicle_id end
  )
  order by v.id
  for update;

  -- Lock booking rows before the bay resource everywhere. This matches
  -- move/resize and prevents a bay-lock/row-lock deadlock cycle.
  perform public.workshop_lock_resources(v_bay.id, null);

  -- A move-out RPC can hold a captured booking row while moving it to another
  -- bay because that legacy path locks only its destination bay. Revalidate
  -- every locked row before shifting anything. PostgreSQL rechecks the row
  -- after a concurrent updater commits, so a moved row fails this source-bay
  -- predicate and the whole cascade returns without partial movement.
  select count(*) into v_locked_count
  from public.workshop_bookings b
  where b.id = any(v_expected_ids)
    and b.bay_id = v_bay.id
    and b.status = 'planned'
    and b.deleted_at is null;
  if v_locked_count <> cardinality(v_expected_ids) then
    return jsonb_build_object(
      'ok', false,
      'error', 'concurrent_queue_change',
      'retry', true
    );
  end if;

  -- Keep the target action and every shifted timestamp in one subtransaction.
  -- If the protected target RPC returns a structured business rejection, the
  -- exception block rolls back all shifts and returns that rejection intact.
  begin
  for v_shifted in
    select * from public.workshop_bookings b
    where b.id = any(v_expected_ids)
      and b.bay_id = v_bay.id
      and b.status = 'planned'
      and b.deleted_at is null
    order by b.scheduled_start_at desc, b.id desc
  loop
    v_new_start := public.workshop_next_calendar_window(
      public.workshop_add_operational_minutes(v_shifted.scheduled_start_at, p_shift_minutes),
      v_shifted.default_duration_minutes
    );
    v_new_end := public.workshop_add_operational_minutes(v_new_start,v_shifted.default_duration_minutes);
    v_before := public.workshop_booking_snapshot(v_shifted.id);
    update public.workshop_bookings
      set scheduled_start_at = v_new_start,
          scheduled_end_at = v_new_end,
          updated_by = auth.uid(),
          version = version + 1
      where id = v_shifted.id
        and bay_id = v_bay.id
        and status = 'planned'
        and deleted_at is null;
    if not found then
      v_result := jsonb_build_object('ok', false, 'error', 'concurrent_queue_change', 'retry', true);
      raise exception 'Cascade queue changed' using errcode = 'P0001';
    end if;
    select technician_id into v_technician from public.workshop_booking_assignments
      where booking_id = v_shifted.id and released_at is null
      order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc limit 1;
    perform public.workshop_upsert_primary_assignment(v_shifted.id, v_technician, v_new_start, v_new_end, 'cascade_shifted');
    v_after := public.workshop_booking_snapshot(v_shifted.id);
    perform public.workshop_write_history(v_shifted.id, 'cascade_shifted', v_before, v_after,
      coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('cascade_operation', v_operation, 'cascade_target_id', p_target_id));
  end loop;

  -- Validate the final technician allocation after every shifted timestamp is in place.
  for v_shifted in
    select * from public.workshop_bookings
    where id = any(v_expected_ids)
      and bay_id = v_bay.id
      and status = 'planned'
      and deleted_at is null
  loop
    v_conflict := public.workshop_find_bay_conflict(
      v_shifted.id, v_bay.id, v_shifted.scheduled_start_at, v_shifted.scheduled_end_at
    );
    if v_conflict is not null then
      v_result := jsonb_build_object(
        'ok', false,
        'error', 'bay_overlap',
        'conflict', public.workshop_conflict_payload(v_conflict, 'bay_overlap')
      );
      raise exception 'Cascade bay conflict' using errcode = 'P0001';
    end if;
    select technician_id into v_technician from public.workshop_booking_assignments
      where booking_id = v_shifted.id and released_at is null
      order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc limit 1;
    if v_technician is not null then
      v_conflict := public.workshop_find_technician_conflict(v_shifted.id, v_technician, v_shifted.scheduled_start_at, v_shifted.scheduled_end_at);
      if v_conflict is not null then
        v_result := jsonb_build_object(
          'ok', false,
          'error', 'technician_overlap',
          'conflict', public.workshop_conflict_payload(v_conflict, 'technician_overlap')
        );
        raise exception 'Cascade technician conflict' using errcode = 'P0001';
      end if;
      if public.workshop_technician_leave_date(v_technician, v_shifted.scheduled_start_at, v_shifted.scheduled_end_at) is not null then
        v_result := jsonb_build_object('ok', false, 'error', 'technician_leave_conflict');
        raise exception 'Cascade technician leave conflict' using errcode = 'P0001';
      end if;
    end if;
  end loop;

  if v_operation = 'insert' then
    v_result := public.schedule_vehicle_work(
      p_target_id, p_target_expected_version, v_stage.code, v_bay.bay_number,
      p_scheduled_start_at, p_duration_minutes, p_technician_id, p_override_reason, coalesce(p_metadata, '{}'::jsonb)
    );
  else
    v_result := public.resize_workshop_booking(p_target_id, p_target_expected_version, p_duration_minutes, coalesce(p_metadata, '{}'::jsonb));
  end if;

  if coalesce((v_result->>'ok')::boolean, false) is not true then
    raise exception 'Atomic cascade target action failed' using errcode = 'P0001';
  end if;
  exception when sqlstate 'P0001' then
    if v_result is not null and coalesce((v_result->>'ok')::boolean, false) is not true then
      return v_result;
    end if;
    raise;
  end;

  return v_result || jsonb_build_object(
    'cascade_operation', v_operation,
    'shifted_booking_ids', to_jsonb(v_expected_ids),
    'shifted_count', cardinality(v_expected_ids)
  );
end;
$$;

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
  if public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at)<>p_duration_minutes then
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
  -- Serialize readable validation per vehicle; the exclusion constraint below
  -- remains the final race-safe authority for every mutation path.
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

alter table public.workshop_bookings drop constraint if exists workshop_bookings_active_vehicle_no_overlap;
alter table public.workshop_bookings add constraint workshop_bookings_active_vehicle_no_overlap
exclude using gist (
  vehicle_id with =,
  tstzrange(scheduled_start_at,scheduled_end_at,'[)') with &&
) where (deleted_at is null and status in ('queued','planned','started','stoppage'));

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
 v_elapsed_minutes:=greatest(0,public.workshop_operational_minutes_between(v_booking.scheduled_start_at,coalesce(v_booking.stoppage_started_at,v_now))-coalesce(v_booking.stoppage_accumulated_minutes,0));
 v_remaining_minutes:=greatest(60,v_booking.default_duration_minutes-greatest(0,v_elapsed_minutes));
 v_new_start:=public.workshop_next_calendar_window(v_now,v_remaining_minutes); v_new_end:=public.workshop_add_operational_minutes(v_new_start,v_remaining_minutes);
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
revoke execute on function public.workshop_reassign_booking(uuid,integer,uuid,jsonb) from public,anon,authenticated;
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
