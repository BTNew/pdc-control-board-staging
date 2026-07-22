-- 040_atomic_same_bay_booking_cascade.sql
-- Additive scheduling-only RPC: one-hour minimum and atomic same-bay cascade.
-- No RLS, policy, route, publication, or existing grant changes.

begin;

create or replace function public.workshop_add_operational_minutes(
  p_start timestamptz,
  p_duration_minutes integer
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_timezone constant text := 'Australia/Perth';
  v_local timestamp;
  v_day_start time;
  v_day_end time;
  v_working_week jsonb;
  v_closures jsonb;
  v_remaining integer;
  v_available integer;
  v_day_name text;
  v_allowed boolean;
  v_guard integer := 0;
begin
  if p_start is null or p_duration_minutes is null or p_duration_minutes < 0 then
    raise exception 'Operational start and non-negative duration are required' using errcode = '22023';
  end if;

  select trim(both '"' from value::text)::time into v_day_start
  from public.workshop_settings where key = 'day_start_time';
  select trim(both '"' from value::text)::time into v_day_end
  from public.workshop_settings where key = 'day_end_time';
  select value into v_working_week from public.workshop_settings where key = 'working_week';
  select value into v_closures from public.workshop_settings where key = 'closures';

  if v_day_start is null or v_day_end is null or v_day_start >= v_day_end
     or jsonb_typeof(v_working_week) <> 'array' or jsonb_typeof(v_closures) <> 'array' then
    raise exception 'Workshop operational calendar is unavailable or invalid' using errcode = '22023';
  end if;

  v_local := p_start at time zone v_timezone;
  v_remaining := p_duration_minutes;

  loop
    v_guard := v_guard + 1;
    if v_guard > 740 then
      raise exception 'No operational day found within calendar guard' using errcode = '22023';
    end if;

    v_day_name := lower(trim(to_char(v_local, 'Day')));
    v_allowed := v_working_week ? v_day_name
      and not exists (
        select 1 from jsonb_array_elements(v_closures) closure
        where coalesce(closure->>'date', trim(both '"' from closure::text)) = to_char(v_local, 'YYYY-MM-DD')
      );

    if not v_allowed then
      v_local := date_trunc('day', v_local) + interval '1 day' + v_day_start;
      continue;
    end if;
    if v_local::time < v_day_start then v_local := date_trunc('day', v_local) + v_day_start; end if;
    if v_local::time >= v_day_end then
      v_local := date_trunc('day', v_local) + interval '1 day' + v_day_start;
      continue;
    end if;
    exit;
  end loop;

  while v_remaining > 0 loop
    v_available := floor(extract(epoch from ((date_trunc('day', v_local) + v_day_end) - v_local)) / 60.0)::integer;
    if v_remaining <= v_available then
      v_local := v_local + make_interval(mins => v_remaining);
      v_remaining := 0;
    else
      v_remaining := v_remaining - v_available;
      v_local := date_trunc('day', v_local) + interval '1 day' + v_day_start;
      loop
        v_guard := v_guard + 1;
        if v_guard > 740 then
          raise exception 'Operational duration exceeded calendar guard' using errcode = '22023';
        end if;
        v_day_name := lower(trim(to_char(v_local, 'Day')));
        v_allowed := v_working_week ? v_day_name
          and not exists (
            select 1 from jsonb_array_elements(v_closures) closure
            where coalesce(closure->>'date', trim(both '"' from closure::text)) = to_char(v_local, 'YYYY-MM-DD')
          );
        exit when v_allowed;
        v_local := date_trunc('day', v_local) + interval '1 day' + v_day_start;
      end loop;
    end if;
  end loop;

  return v_local at time zone v_timezone;
end;
$$;

revoke all on function public.workshop_add_operational_minutes(timestamptz, integer) from public, anon, authenticated;

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
set search_path = public
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
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_target_expected_version);

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

  -- Use the same namespaced advisory lock as every existing booking mutation.
  -- This serialises queue discovery with create/move/resize RPCs for the bay.
  perform public.workshop_lock_resources(v_bay.id, null);

  select coalesce(array_agg(b.id order by b.scheduled_start_at, b.id), '{}'::uuid[])
    into v_expected_ids
  from public.workshop_bookings b
  where b.bay_id = v_bay.id and b.status = 'planned'
    and (case when v_operation = 'insert' then b.scheduled_start_at >= p_scheduled_start_at
              else b.id <> p_target_id and b.scheduled_start_at > v_target.scheduled_start_at end);

  perform 1 from public.workshop_bookings b where b.id = any(v_expected_ids) order by b.scheduled_start_at, b.id for update;

  -- Keep the target action and every shifted timestamp in one subtransaction.
  -- If the protected target RPC returns a structured business rejection, the
  -- exception block rolls back all shifts and returns that rejection intact.
  begin
  for v_shifted in
    select * from public.workshop_bookings b where b.id = any(v_expected_ids)
    order by b.scheduled_start_at desc, b.id desc
  loop
    v_new_start := public.workshop_add_operational_minutes(v_shifted.scheduled_start_at, p_shift_minutes);
    v_new_end := public.workshop_add_operational_minutes(v_new_start, v_shifted.default_duration_minutes);
    v_before := public.workshop_booking_snapshot(v_shifted.id);
    update public.workshop_bookings
      set scheduled_start_at = v_new_start,
          scheduled_end_at = v_new_end,
          updated_by = auth.uid(),
          version = version + 1
      where id = v_shifted.id;
    select technician_id into v_technician from public.workshop_booking_assignments
      where booking_id = v_shifted.id and released_at is null
      order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc limit 1;
    perform public.workshop_upsert_primary_assignment(v_shifted.id, v_technician, v_new_start, v_new_end, 'cascade_shifted');
    v_after := public.workshop_booking_snapshot(v_shifted.id);
    perform public.workshop_write_history(v_shifted.id, 'cascade_shifted', v_before, v_after,
      coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('cascade_operation', v_operation, 'cascade_target_id', p_target_id));
  end loop;

  -- Validate the final technician allocation after every shifted timestamp is in place.
  for v_shifted in select * from public.workshop_bookings where id = any(v_expected_ids)
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

revoke all on function public.cascade_workshop_schedule(text, uuid, integer, text, integer, timestamptz, integer, uuid, integer, text, jsonb) from public, anon;
grant execute on function public.cascade_workshop_schedule(text, uuid, integer, text, integer, timestamptz, integer, uuid, integer, text, jsonb) to authenticated;

commit;
