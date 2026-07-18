-- Stage 2A final independent-review remediation only.
-- Viewer direct reads are active-only; configuration dates/UUIDs are exact;
-- new technician assignment is blocked server-side during configured leave.

begin;

-- Direct REST and Realtime SELECT now match the active-only viewer RPCs.
drop policy if exists workshop_technicians_select_approved on public.workshop_technicians;
create policy workshop_technicians_select_by_role on public.workshop_technicians
for select to authenticated
using (public.is_pdc_role('operator') or (public.current_pdc_user_role() = 'viewer' and active));

drop policy if exists salespeople_select_approved on public.salespeople;
create policy salespeople_select_by_role on public.salespeople
for select to authenticated
using (public.is_pdc_role('operator') or (public.current_pdc_user_role() = 'viewer' and active));

drop policy if exists sublet_providers_select_approved on public.sublet_providers;
create policy sublet_providers_select_by_role on public.sublet_providers
for select to authenticated
using (public.is_pdc_role('operator') or (public.current_pdc_user_role() = 'viewer' and active));

drop policy if exists workshop_bays_select_approved on public.workshop_bays;
create policy workshop_bays_select_by_role on public.workshop_bays
for select to authenticated
using (public.is_pdc_role('operator') or (public.current_pdc_user_role() = 'viewer' and is_active));

create or replace function public.workshop_is_exact_iso_date(p_value text)
returns boolean language plpgsql immutable set search_path = pg_catalog as $$
declare v_date date;
begin
  if p_value is null or p_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;
  begin v_date := p_value::date; exception when others then return false; end;
  return to_char(v_date, 'YYYY-MM-DD') = p_value;
end;
$$;
revoke all on function public.workshop_is_exact_iso_date(text) from public, anon, authenticated;

create or replace function public.workshop_technician_leave_date(
  p_technician_id uuid, p_start timestamptz, p_end timestamptz
) returns date language sql stable security definer set search_path = public as $$
  select (item->>'date')::date
  from public.workshop_settings s
  cross join lateral jsonb_array_elements(case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end) item
  where s.key = 'technician_leave'
    and item->>'technician_id' = p_technician_id::text
    and public.workshop_is_exact_iso_date(item->>'date')
    and (item->>'date')::date between (p_start at time zone 'Australia/Brisbane')::date
      and ((p_end - interval '1 microsecond') at time zone 'Australia/Brisbane')::date
  order by (item->>'date')::date limit 1;
$$;
revoke all on function public.workshop_technician_leave_date(uuid, timestamptz, timestamptz) from public, anon, authenticated;

create or replace function public.update_workshop_configuration(
  p_key text,
  p_expected_version integer,
  p_value jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.workshop_settings%rowtype;
  v_after public.workshop_settings%rowtype;
  v_allowed_keys text[] := array[
    'day_start_time', 'day_end_time', 'scheduling_increment_minutes',
    'default_booking_duration_minutes', 'working_week', 'closures',
    'break_windows', 'overtime_windows', 'technician_leave'
  ];
  v_allowed_days text[] := array['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
  v_elem jsonb;
  v_seen text[] := array[]::text[];
  v_day text;
  v_start_minutes integer;
  v_end_minutes integer;
begin
  perform public.require_pdc_role('administrator');

  if p_key is null or not (p_key = any(v_allowed_keys)) then
    return jsonb_build_object('ok', false, 'error', 'unknown_setting_key', 'allowed_keys', to_jsonb(v_allowed_keys));
  end if;

  -- HH:MM string validation (day_start_time / day_end_time), and
  -- start-before-end cross-check against the OTHER stored time value.
  if p_key in ('day_start_time', 'day_end_time') then
    if jsonb_typeof(p_value) <> 'string' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'string (HH:MM)');
    end if;
    if not (trim(both '"' from p_value::text) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      return jsonb_build_object('ok', false, 'error', 'invalid_time_format', 'expected', 'HH:MM 24-hour, 00:00-23:59');
    end if;
    v_start_minutes := case when p_key = 'day_start_time'
      then (split_part(trim(both '"' from p_value::text), ':', 1)::integer * 60 + split_part(trim(both '"' from p_value::text), ':', 2)::integer)
      else (select (split_part(trim(both '"' from value::text), ':', 1)::integer * 60 + split_part(trim(both '"' from value::text), ':', 2)::integer) from public.workshop_settings where key = 'day_start_time')
    end;
    v_end_minutes := case when p_key = 'day_end_time'
      then (split_part(trim(both '"' from p_value::text), ':', 1)::integer * 60 + split_part(trim(both '"' from p_value::text), ':', 2)::integer)
      else (select (split_part(trim(both '"' from value::text), ':', 1)::integer * 60 + split_part(trim(both '"' from value::text), ':', 2)::integer) from public.workshop_settings where key = 'day_end_time')
    end;
    if v_start_minutes is not null and v_end_minutes is not null and v_start_minutes >= v_end_minutes then
      return jsonb_build_object('ok', false, 'error', 'start_time_not_before_end_time', 'day_start_time', v_start_minutes, 'day_end_time', v_end_minutes);
    end if;
  end if;

  -- Positive, bounded integer minutes (scheduling_increment_minutes,
  -- default_booking_duration_minutes).
  if p_key in ('scheduling_increment_minutes', 'default_booking_duration_minutes') then
    if jsonb_typeof(p_value) <> 'number' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'number (minutes)');
    end if;
    if (p_value::text)::numeric <> floor((p_value::text)::numeric) then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'must_be_integer');
    end if;
    if (p_value::text)::integer <= 0 then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'must_be_positive');
    end if;
    if p_key = 'scheduling_increment_minutes' and (p_value::text)::integer > 240 then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'exceeds_max_240_minutes');
    end if;
    if p_key = 'default_booking_duration_minutes' and (p_value::text)::integer > 1440 then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'exceeds_max_1440_minutes');
    end if;
  end if;

  -- working_week: array of allowed day names, no duplicates, at least
  -- one day.
  if p_key = 'working_week' then
    if jsonb_typeof(p_value) <> 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
    end if;
    if jsonb_array_length(p_value) = 0 then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'must_have_at_least_one_day');
    end if;
    for v_elem in select * from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_elem) <> 'string' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'day_must_be_string');
      end if;
      v_day := lower(trim(both '"' from v_elem::text));
      if not (v_day = any(v_allowed_days)) then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'unknown_day_name', 'value', v_day, 'allowed', to_jsonb(v_allowed_days));
      end if;
      if v_day = any(v_seen) then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'duplicate_day', 'value', v_day);
      end if;
      v_seen := v_seen || v_day;
    end loop;
  end if;

  -- closures: array of objects, each must have a valid 'date' field
  -- (ISO date), rejects malformed entries.
  if p_key = 'closures' then
    if jsonb_typeof(p_value) <> 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
    end if;
    for v_elem in select * from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_elem) <> 'object' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'closure_must_be_object');
      end if;
      if not (v_elem ? 'date') or jsonb_typeof(v_elem->'date') <> 'string' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'closure_missing_date');
      end if;
      if not public.workshop_is_exact_iso_date(v_elem->>'date') then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'closure_date_not_valid_iso_date', 'value', v_elem->'date');
      end if;
    end loop;
  end if;

  -- break_windows / overtime_windows: array of objects, each must
  -- have valid HH:MM 'start' and 'end' with start < end.
  if p_key in ('break_windows', 'overtime_windows') then
    if jsonb_typeof(p_value) <> 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
    end if;
    for v_elem in select * from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_elem) <> 'object'
         or not (v_elem ? 'start') or jsonb_typeof(v_elem->'start') <> 'string'
         or not (v_elem ? 'end') or jsonb_typeof(v_elem->'end') <> 'string' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'window_missing_start_or_end');
      end if;
      if not (trim(both '"' from (v_elem->'start')::text) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
         or not (trim(both '"' from (v_elem->'end')::text) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'window_time_not_hhmm');
      end if;
      if (split_part(trim(both '"' from (v_elem->'start')::text), ':', 1)::integer * 60 + split_part(trim(both '"' from (v_elem->'start')::text), ':', 2)::integer)
         >= (split_part(trim(both '"' from (v_elem->'end')::text), ':', 1)::integer * 60 + split_part(trim(both '"' from (v_elem->'end')::text), ':', 2)::integer) then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'window_start_not_before_end');
      end if;
    end loop;
  end if;

  -- technician_leave: array of objects, each must reference an
  -- existing technician_id and a valid ISO date.
  if p_key = 'technician_leave' then
    if jsonb_typeof(p_value) <> 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
    end if;
    for v_elem in select * from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_elem) <> 'object'
         or not (v_elem ? 'technician_id') or jsonb_typeof(v_elem->'technician_id') <> 'string'
         or not (v_elem ? 'date') or jsonb_typeof(v_elem->'date') <> 'string' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'leave_missing_technician_id_or_date');
      end if;
      if not public.workshop_is_exact_iso_date(v_elem->>'date') then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'leave_date_not_valid_iso_date', 'value', v_elem->'date');
      end if;
      if not ((v_elem->>'technician_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'leave_technician_id_not_valid_uuid', 'technician_id', v_elem->'technician_id');
      end if;
      if not exists (
        select 1 from public.workshop_technicians
        where id = (v_elem->>'technician_id')::uuid
      ) then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'leave_technician_not_found', 'technician_id', v_elem->'technician_id');
      end if;
    end loop;
  end if;

  select * into v_before from public.workshop_settings where key = p_key for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;

  update public.workshop_settings
  set value = p_value,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where key = p_key
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'workshop_settings', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'update_workshop_configuration', 'key', p_key));

  return jsonb_build_object('ok', true, 'setting', to_jsonb(v_after));
end;
$$;


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
set search_path = public
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
  v_end := p_scheduled_start_at + make_interval(mins => p_duration_minutes);

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


create or replace function public.workshop_reassign_booking(
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
  v_booking public.workshop_bookings%rowtype;
  v_conflict_id uuid;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
  v_leave_date date;
begin
  perform public.require_pdc_role('operator');

  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  if p_technician_id is not null then
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id) then
      return jsonb_build_object('ok', false, 'error', 'technician_not_found', 'technician_id', p_technician_id);
    end if;
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id and active) then
      return jsonb_build_object('ok', false, 'error', 'technician_inactive', 'technician_id', p_technician_id);
    end if;
    select public.workshop_technician_leave_date(p_technician_id, v_booking.scheduled_start_at, v_booking.scheduled_end_at) into v_leave_date;
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'technician_id', p_technician_id, 'date', v_leave_date);
    end if;
  end if;

  perform public.workshop_lock_resources(v_booking.bay_id, p_technician_id);

  if p_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, p_technician_id, v_booking.scheduled_start_at, v_booking.scheduled_end_at);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform public.workshop_upsert_primary_assignment(p_booking_id, p_technician_id, v_booking.scheduled_start_at, v_booking.scheduled_end_at, 'reassigned');

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'reassigned', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;


-- Restore the protected RPC model explicitly after function replacement.
revoke all on function public.workshop_create_booking(uuid, text, integer, timestamptz, integer, uuid, jsonb) from public, anon;
grant execute on function public.workshop_create_booking(uuid, text, integer, timestamptz, integer, uuid, jsonb) to authenticated;
revoke all on function public.workshop_reassign_booking(uuid, integer, uuid, jsonb) from public, anon;
grant execute on function public.workshop_reassign_booking(uuid, integer, uuid, jsonb) to authenticated;
revoke all on function public.update_workshop_configuration(text, integer, jsonb) from public, anon;
grant execute on function public.update_workshop_configuration(text, integer, jsonb) to authenticated;

commit;
