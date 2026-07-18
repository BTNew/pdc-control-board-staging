-- Workshop transactional business actions
-- Each RPC here is the single atomic entry point for one complete workshop
-- business action. It wraps the lower-level booking primitives from
-- migration 007 and adds: Parts-incomplete gating, atomic vehicle-pointer
-- updates (active_workshop_booking_id / workshop_status), shared revision
-- increment on success only, and audited Parts overrides.
--
-- Non-null optimistic version is required on every mutation. Postgres
-- comparisons must use explicit checks (not `<> null`) so a missing/NULL
-- version is always rejected, never silently treated as a match.

begin;

create or replace function public.workshop_require_version(p_expected_version integer)
returns void
language plpgsql
set search_path = public
as $$
begin
  if p_expected_version is null then
    raise exception 'Expected version is required' using errcode = '22004';
  end if;
end;
$$;

-- SQL-side equivalent of the frontend's workshop working-day/hours model
-- (see workshop-planner.js WORKSHOP_START_HOUR/END_HOUR). Reads the current
-- global settings so both sides share one source of truth for the workday
-- window; falls back to 08:00-16:00 Mon-Fri if settings are missing.
create or replace function public.workshop_normalize_start_date(p_value timestamptz)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start_time text;
  v_end_time text;
  v_start_hour integer;
  v_end_hour integer;
  v_working_week jsonb;
  v_local timestamptz := p_value;
  v_dow integer;
  v_local_time time;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_guard integer := 0;
begin
  select value into v_start_time from public.workshop_settings where key = 'day_start_time';
  select value into v_end_time from public.workshop_settings where key = 'day_end_time';
  select value into v_working_week from public.workshop_settings where key = 'working_week';

  v_start_hour := coalesce(split_part(trim(both '"' from coalesce(v_start_time::text, '"08:00"')), ':', 1)::integer, 8);
  v_end_hour := coalesce(split_part(trim(both '"' from coalesce(v_end_time::text, '"16:00"')), ':', 1)::integer, 16);
  if v_working_week is null then
    v_working_week := '["monday","tuesday","wednesday","thursday","friday"]'::jsonb;
  end if;

  loop
    v_guard := v_guard + 1;
    exit when v_guard > 30;

    v_dow := extract(isodow from v_local)::integer; -- 1=Mon .. 7=Sun
    if not (v_working_week ? (array['monday','tuesday','wednesday','thursday','friday','saturday','sunday'])[v_dow]) then
      v_local := date_trunc('day', v_local) + interval '1 day' + make_time(v_start_hour, 0, 0);
      continue;
    end if;

    v_day_start := date_trunc('day', v_local) + make_time(v_start_hour, 0, 0);
    v_day_end := date_trunc('day', v_local) + make_time(v_end_hour, 0, 0);

    if v_local < v_day_start then
      return v_day_start;
    elsif v_local >= v_day_end then
      v_local := date_trunc('day', v_local) + interval '1 day' + make_time(v_start_hour, 0, 0);
      continue;
    else
      return v_local;
    end if;
  end loop;

  return date_trunc('day', p_value) + make_time(v_start_hour, 0, 0);
end;
$$;

-- schedule_vehicle_work: create a booking AND set the vehicle's authoritative
-- workshop pointer/status atomically. Enforces the Parts gate unless an
-- approved override is supplied.
create or replace function public.schedule_vehicle_work(
  p_vehicle_id uuid,
  p_vehicle_expected_version integer,
  p_stage_code text,
  p_bay_number integer,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer default 180,
  p_technician_id uuid default null,
  p_override_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vehicle public.vehicles%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_result jsonb;
  v_booking jsonb;
  v_override_id uuid;
  v_before_vehicle jsonb;
  v_after_vehicle jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_vehicle_expected_version);

  select * into v_vehicle from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if v_vehicle.version <> p_vehicle_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;

  select * into v_stage from public.workshop_stages where code = upper(trim(coalesce(p_stage_code, ''))) and active = true;
  if not found then
    raise exception 'Workshop stage % not found', p_stage_code using errcode = 'P0002';
  end if;

  -- Parts gate: a vehicle must not enter a Parts-protected physical
  -- production bay when Parts work is incomplete unless an explicit,
  -- audited override is supplied by an authorised operator/administrator.
  if v_stage.is_physical and not public.workshop_parts_ready(p_vehicle_id) then
    if p_override_reason is null or trim(p_override_reason) = '' then
      return jsonb_build_object('ok', false, 'error', 'parts_incomplete');
    end if;
    perform public.require_pdc_role('administrator');
  end if;

  v_before_vehicle := to_jsonb(v_vehicle);

  v_booking := public.workshop_create_booking(
    p_vehicle_id, p_stage_code, p_bay_number, p_scheduled_start_at,
    p_duration_minutes, p_technician_id, p_metadata
  );
  if not (v_booking->>'ok')::boolean then
    return v_booking;
  end if;

  update public.vehicles
  set active_workshop_booking_id = (v_booking->'booking'->>'booking_id')::uuid,
      workshop_status = 'scheduled',
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      current_location = coalesce(current_location, 'PMB'),
      pmb_stage = p_stage_code,
      visible_on_board = true,
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning to_jsonb(vehicles.*) into v_after_vehicle;

  if p_override_reason is not null and trim(p_override_reason) <> '' then
    insert into public.workshop_parts_overrides (
      vehicle_id, booking_id, work_key, intended_stage_id, reason,
      previous_state, resulting_state, approved_by, approved_by_email
    ) values (
      p_vehicle_id, (v_booking->'booking'->>'booking_id')::uuid, 'PARTS', v_stage.id,
      trim(p_override_reason), v_before_vehicle, v_after_vehicle, auth.uid(), public.current_actor_email()
    ) returning id into v_override_id;
  end if;

  perform public.audit_pdc_event('move', 'vehicles', p_vehicle_id, p_vehicle_id, v_before_vehicle, v_after_vehicle,
    jsonb_build_object('action', 'schedule_vehicle_work', 'override_id', v_override_id));

  v_revision := public.workshop_bump_revision();

  return jsonb_build_object('ok', true, 'booking', v_booking->'booking', 'vehicle', v_after_vehicle,
    'override_id', v_override_id, 'revision', v_revision);
end;
$$;

-- Generic wrapper macro pattern: each action below performs the underlying
-- booking mutation, then atomically synchronises the vehicle pointer/status,
-- and bumps the shared revision only on success. All run in one transaction.

create or replace function public.move_workshop_booking(
  p_booking_id uuid,
  p_expected_version integer,
  p_stage_code text,
  p_bay_number integer,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer default null,
  p_override_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_before public.workshop_bookings%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_result jsonb;
  v_vehicle_id uuid;
  v_override_id uuid;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking_before from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  v_vehicle_id := v_booking_before.vehicle_id;

  select * into v_stage from public.workshop_stages where code = upper(trim(coalesce(p_stage_code, ''))) and active = true;
  if not found then
    raise exception 'Workshop stage % not found', p_stage_code using errcode = 'P0002';
  end if;

  if v_stage.is_physical and not public.workshop_parts_ready(v_vehicle_id) then
    if p_override_reason is null or trim(p_override_reason) = '' then
      return jsonb_build_object('ok', false, 'error', 'parts_incomplete');
    end if;
    perform public.require_pdc_role('administrator');
  end if;

  v_result := public.workshop_move_booking(p_booking_id, p_expected_version, p_stage_code, p_bay_number,
    p_scheduled_start_at, p_duration_minutes, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;

  update public.vehicles
  set pmb_stage = p_stage_code,
      updated_by = auth.uid(),
      version = version + 1
  where id = v_vehicle_id;

  if p_override_reason is not null and trim(p_override_reason) <> '' then
    insert into public.workshop_parts_overrides (
      vehicle_id, booking_id, work_key, intended_stage_id, reason, previous_state, resulting_state, approved_by, approved_by_email
    ) values (
      v_vehicle_id, p_booking_id, 'PARTS', v_stage.id, trim(p_override_reason),
      to_jsonb(v_booking_before), v_result->'booking', auth.uid(), public.current_actor_email()
    ) returning id into v_override_id;
  end if;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('override_id', v_override_id, 'revision', v_revision);
end;
$$;

create or replace function public.resize_workshop_booking(
  p_booking_id uuid,
  p_expected_version integer,
  p_duration_minutes integer,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);
  v_result := public.workshop_resize_booking(p_booking_id, p_expected_version, p_duration_minutes, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;
  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.change_booking_bay(
  p_booking_id uuid,
  p_expected_version integer,
  p_bay_number integer,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_stage_code text;
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking from public.workshop_bookings where id = p_booking_id;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  select code into v_stage_code from public.workshop_stages where id = v_booking.stage_id;

  v_result := public.workshop_move_booking(p_booking_id, p_expected_version, v_stage_code, p_bay_number,
    v_booking.scheduled_start_at, v_booking.default_duration_minutes, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;
  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.assign_booking_technician(
  p_booking_id uuid,
  p_expected_version integer,
  p_technician_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);
  v_result := public.workshop_reassign_booking(p_booking_id, p_expected_version, p_technician_id, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;
  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.start_workshop_work(
  p_booking_id uuid,
  p_expected_version integer,
  p_actual_start_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_before public.workshop_bookings%rowtype;
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking_before from public.workshop_bookings where id = p_booking_id;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;

  v_result := public.workshop_start_booking(p_booking_id, p_expected_version, p_actual_start_at, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;

  update public.vehicles
  set workshop_status = 'in_progress',
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      active_workshop_booking_id = p_booking_id,
      updated_by = auth.uid(),
      version = version + 1
  where id = v_booking_before.vehicle_id;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.stop_workshop_work(
  p_booking_id uuid,
  p_expected_version integer,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_before public.workshop_bookings%rowtype;
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking_before from public.workshop_bookings where id = p_booking_id;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;

  v_result := public.workshop_record_stoppage(p_booking_id, p_expected_version, p_reason, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;

  update public.vehicles
  set workshop_status = 'stoppage',
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      updated_by = auth.uid(),
      version = version + 1
  where id = v_booking_before.vehicle_id;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

-- resume_workshop_work: must recompute a valid, non-conflicting booking
-- period (never simply reactivate an old range) and reject new conflicts.
create or replace function public.resume_workshop_work(
  p_booking_id uuid,
  p_expected_version integer,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_now timestamptz := now();
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_remaining_minutes integer;
  v_elapsed_minutes integer;
  v_move_result jsonb;
  v_resume_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;
  if v_booking.status <> 'stoppage' then
    return jsonb_build_object('ok', false, 'error', 'not_stopped');
  end if;

  -- Recompute a fresh valid working-time period starting now, preserving
  -- the remaining planned duration rather than reactivating the stale range.
  v_elapsed_minutes := greatest(0, floor(extract(epoch from (coalesce(v_booking.stoppage_started_at, v_now) - v_booking.scheduled_start_at)) / 60.0)::integer)
    - coalesce(v_booking.stoppage_accumulated_minutes, 0);
  v_remaining_minutes := greatest(15, v_booking.default_duration_minutes - greatest(0, v_elapsed_minutes));
  v_new_start := workshop_normalize_start_date(v_now);
  v_new_end := v_new_start + make_interval(mins => v_remaining_minutes);

  select technician_id into v_technician_id
  from public.workshop_booking_assignments
  where booking_id = p_booking_id and released_at is null
  order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc
  limit 1;

  perform public.workshop_lock_resources(v_booking.bay_id, v_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_booking.bay_id, v_new_start, v_new_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;
  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, v_new_start, v_new_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  update public.workshop_bookings
  set scheduled_start_at = v_new_start,
      scheduled_end_at = v_new_end,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, v_new_start, v_new_end, 'resume_rescheduled');

  v_resume_result := public.workshop_resume_booking(p_booking_id, v_booking.version + 1, p_metadata);
  if not (v_resume_result->>'ok')::boolean then
    return v_resume_result;
  end if;

  update public.vehicles
  set workshop_status = 'in_progress',
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      updated_by = auth.uid(),
      version = version + 1
  where id = v_booking.vehicle_id;

  v_revision := public.workshop_bump_revision();
  return v_resume_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.complete_workshop_work(
  p_booking_id uuid,
  p_expected_version integer,
  p_work_key text default null,
  p_actual_end_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_before public.workshop_bookings%rowtype;
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking_before from public.workshop_bookings where id = p_booking_id;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;

  v_result := public.workshop_complete_booking(p_booking_id, p_expected_version, p_actual_end_at, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;

  update public.vehicles
  set workshop_status = 'completed',
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      updated_by = auth.uid(),
      version = version + 1
  where id = v_booking_before.vehicle_id;

  if p_work_key is not null then
    insert into public.vehicle_work_items (vehicle_id, work_key, required, completed, completed_by, completed_at)
    values (v_booking_before.vehicle_id, upper(trim(p_work_key)), true, true, auth.uid(), p_actual_end_at)
    on conflict (vehicle_id, work_key)
    do update set completed = true, completed_by = auth.uid(), completed_at = p_actual_end_at, updated_at = now();
  end if;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.return_completed_work(
  p_booking_id uuid,
  p_expected_version integer,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_before public.workshop_bookings%rowtype;
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking_before from public.workshop_bookings where id = p_booking_id;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking_before.status <> 'completed' then
    return jsonb_build_object('ok', false, 'error', 'not_completed');
  end if;

  v_result := public.workshop_return_booking_to_queue(p_booking_id, p_expected_version, p_reason, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;

  update public.vehicles
  set workshop_status = 'queued',
      active_workshop_booking_id = null,
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      updated_by = auth.uid(),
      version = version + 1
  where id = v_booking_before.vehicle_id;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.return_work_to_queue(
  p_booking_id uuid,
  p_expected_version integer,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_before public.workshop_bookings%rowtype;
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking_before from public.workshop_bookings where id = p_booking_id;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;

  v_result := public.workshop_return_booking_to_queue(p_booking_id, p_expected_version, p_reason, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;

  update public.vehicles
  set workshop_status = 'queued',
      active_workshop_booking_id = null,
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      updated_by = auth.uid(),
      version = version + 1
  where id = v_booking_before.vehicle_id;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.cancel_workshop_booking(
  p_booking_id uuid,
  p_expected_version integer,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_before public.workshop_bookings%rowtype;
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking_before from public.workshop_bookings where id = p_booking_id;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;

  v_result := public.workshop_delete_booking(p_booking_id, p_expected_version, p_reason, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;

  update public.vehicles
  set active_workshop_booking_id = null,
      workshop_status = 'queued',
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      updated_by = auth.uid(),
      version = version + 1
  where id = v_booking_before.vehicle_id
    and active_workshop_booking_id = p_booking_id;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

create or replace function public.restore_workshop_booking(
  p_booking_id uuid,
  p_expected_version integer,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_before public.workshop_bookings%rowtype;
  v_result jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_expected_version);

  select * into v_booking_before from public.workshop_bookings where id = p_booking_id;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;

  v_result := public.workshop_restore_booking(p_booking_id, p_expected_version, p_metadata);
  if not (v_result->>'ok')::boolean then
    return v_result;
  end if;

  update public.vehicles
  set workshop_status = 'queued',
      active_workshop_booking_id = p_booking_id,
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      updated_by = auth.uid(),
      version = version + 1
  where id = v_booking_before.vehicle_id;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision);
end;
$$;

-- approve_parts_incomplete_override: explicit, standalone override action
-- for cases where an administrator approves entry without a simultaneous
-- schedule/move action already covering it above.
create or replace function public.approve_parts_incomplete_override(
  p_vehicle_id uuid,
  p_vehicle_expected_version integer,
  p_booking_id uuid,
  p_intended_stage_code text,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vehicle_before public.vehicles%rowtype;
  v_vehicle_after public.vehicles%rowtype;
  v_stage_id uuid;
  v_override_id uuid;
  v_revision bigint;
begin
  perform public.require_pdc_role('administrator');
  perform public.workshop_require_version(p_vehicle_expected_version);
  if p_reason is null or trim(p_reason) = '' then
    raise exception 'Override reason is required' using errcode = '22023';
  end if;

  select * into v_vehicle_before from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if v_vehicle_before.version <> p_vehicle_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_intended_stage_code);

  update public.vehicles
  set version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning * into v_vehicle_after;

  insert into public.workshop_parts_overrides (
    vehicle_id, booking_id, work_key, intended_stage_id, reason, previous_state, resulting_state, approved_by, approved_by_email
  ) values (
    p_vehicle_id, p_booking_id, 'PARTS', v_stage_id, trim(p_reason),
    to_jsonb(v_vehicle_before), to_jsonb(v_vehicle_after), auth.uid(), public.current_actor_email()
  ) returning id into v_override_id;

  perform public.audit_pdc_event('update', 'vehicles', p_vehicle_id, p_vehicle_id, to_jsonb(v_vehicle_before), to_jsonb(v_vehicle_after),
    jsonb_build_object('action', 'approve_parts_incomplete_override', 'override_id', v_override_id) || coalesce(p_metadata, '{}'::jsonb));

  v_revision := public.workshop_bump_revision();
  return jsonb_build_object('ok', true, 'override_id', v_override_id, 'vehicle', to_jsonb(v_vehicle_after), 'revision', v_revision);
end;
$$;

commit;
