-- Workshop Planner frontend contract
-- Adds shared reference-data RPCs, an atomic combined booking update, queue reuse,
-- and stronger one-open-booking protection for realtime planner clients.

begin;

create or replace function public.workshop_normalize_work_start(
  p_start timestamptz,
  p_timezone text default 'Australia/Perth'
)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
  v_local timestamp;
  v_day integer;
begin
  if p_start is null then
    raise exception 'Workshop start time is required' using errcode = '22023';
  end if;

  v_local := p_start at time zone p_timezone;
  loop
    v_day := extract(isodow from v_local)::integer;
    if v_day > 5 then
      v_local := (v_local::date + 1) + time '08:00';
    elsif v_local::time < time '08:00' then
      v_local := v_local::date + time '08:00';
    elsif v_local::time >= time '16:00' then
      v_local := (v_local::date + 1) + time '08:00';
    else
      exit;
    end if;
  end loop;

  return v_local at time zone p_timezone;
end;
$$;

create or replace function public.workshop_add_work_minutes(
  p_start timestamptz,
  p_minutes integer,
  p_timezone text default 'Australia/Perth'
)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
  v_cursor timestamp;
  v_remaining integer := greatest(0, coalesce(p_minutes, 0));
  v_available integer;
begin
  v_cursor := public.workshop_normalize_work_start(p_start, p_timezone) at time zone p_timezone;

  while v_remaining > 0 loop
    v_available := greatest(0, floor(extract(epoch from ((v_cursor::date + time '16:00') - v_cursor)) / 60.0)::integer);
    if v_remaining <= v_available then
      v_cursor := v_cursor + make_interval(mins => v_remaining);
      v_remaining := 0;
    else
      v_remaining := v_remaining - v_available;
      v_cursor := public.workshop_normalize_work_start(((v_cursor::date + 1) + time '08:00') at time zone p_timezone, p_timezone) at time zone p_timezone;
    end if;
  end loop;

  return v_cursor at time zone p_timezone;
end;
$$;

create or replace function public.workshop_work_minutes_between(
  p_start timestamptz,
  p_end timestamptz,
  p_timezone text default 'Australia/Perth'
)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_start_local timestamp;
  v_end_local timestamp;
  v_day date;
  v_window_start timestamp;
  v_window_end timestamp;
  v_overlap_start timestamp;
  v_overlap_end timestamp;
  v_total integer := 0;
begin
  if p_start is null or p_end is null or p_end <= p_start then
    return 0;
  end if;

  v_start_local := p_start at time zone p_timezone;
  v_end_local := p_end at time zone p_timezone;
  v_day := v_start_local::date;

  while v_day <= v_end_local::date loop
    if extract(isodow from v_day)::integer between 1 and 5 then
      v_window_start := v_day + time '08:00';
      v_window_end := v_day + time '16:00';
      v_overlap_start := greatest(v_start_local, v_window_start);
      v_overlap_end := least(v_end_local, v_window_end);
      if v_overlap_end > v_overlap_start then
        v_total := v_total + floor(extract(epoch from (v_overlap_end - v_overlap_start)) / 60.0)::integer;
      end if;
    end if;
    v_day := v_day + 1;
  end loop;

  return greatest(0, v_total);
end;
$$;

insert into public.workshop_settings (key, value, scope)
values
  ('business_timezone', to_jsonb('Australia/Perth'::text), 'global'),
  ('frontend_contract_version', to_jsonb(1), 'global')
on conflict (key) do update set value = excluded.value, scope = excluded.scope;

do $$
declare
  v_duplicate_names text;
  v_duplicate_bookings text;
begin
  select string_agg(name_key || ' (' || duplicate_count || ')', ', ' order by name_key)
  into v_duplicate_names
  from (
    select lower(name) as name_key, count(*) as duplicate_count
    from public.workshop_technicians
    group by lower(name)
    having count(*) > 1
  ) duplicates;

  if v_duplicate_names is not null then
    raise exception 'Workshop migration stopped: duplicate technician/provider names must be reconciled first: %', v_duplicate_names
      using errcode = '23505';
  end if;

  select string_agg(vehicle_id::text || '/' || stage_id::text || ' (' || duplicate_count || ')', ', ' order by vehicle_id::text, stage_id::text)
  into v_duplicate_bookings
  from (
    select vehicle_id, stage_id, count(*) as duplicate_count
    from public.workshop_bookings
    where status in ('queued', 'planned', 'started', 'stoppage')
    group by vehicle_id, stage_id
    having count(*) > 1
  ) duplicates;

  if v_duplicate_bookings is not null then
    raise exception 'Workshop migration stopped: multiple open bookings exist for the same vehicle/stage and must be reconciled first: %', v_duplicate_bookings
      using errcode = '23505';
  end if;
end;
$$;

create unique index if not exists workshop_technicians_name_ci_idx
on public.workshop_technicians (lower(name));

create unique index if not exists workshop_bookings_one_open_vehicle_stage_idx
on public.workshop_bookings (vehicle_id, stage_id)
where status in ('queued', 'planned', 'started', 'stoppage');

create or replace function public.workshop_find_bay_conflict(
  p_booking_id uuid,
  p_bay_id uuid,
  p_start timestamptz,
  p_end timestamptz
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select b.id
  from public.workshop_bookings b
  where b.bay_id = p_bay_id
    and b.id <> coalesce(p_booking_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and b.status in ('planned', 'started', 'stoppage')
    and tstzrange(b.scheduled_start_at, b.scheduled_end_at, '[)') && tstzrange(p_start, p_end, '[)')
  order by b.scheduled_start_at
  limit 1;
$$;

create or replace function public.workshop_find_technician_conflict(
  p_booking_id uuid,
  p_technician_id uuid,
  p_start timestamptz,
  p_end timestamptz
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select a.booking_id
  from public.workshop_booking_assignments a
  join public.workshop_bookings b on b.id = a.booking_id
  where a.technician_id = p_technician_id
    and a.released_at is null
    and a.booking_id <> coalesce(p_booking_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and b.status in ('planned', 'started', 'stoppage')
    and tstzrange(a.scheduled_start_at, a.scheduled_end_at, '[)') && tstzrange(p_start, p_end, '[)')
  order by a.scheduled_start_at
  limit 1;
$$;

create or replace function public.workshop_ensure_technician(
  p_name text,
  p_role_type text default 'technician'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := trim(coalesce(p_name, ''));
  v_role_type text := lower(trim(coalesce(p_role_type, 'technician')));
  v_id uuid;
begin
  perform public.require_pdc_role('operator');

  if v_name = '' then
    return null;
  end if;
  if v_role_type not in ('technician', 'provider') then
    raise exception 'Invalid workshop technician role type' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('workshop-technician-name:' || lower(v_name), 0));

  select id into v_id
  from public.workshop_technicians
  where lower(name) = lower(v_name)
  limit 1
  for update;

  if v_id is null then
    insert into public.workshop_technicians (name, role_type, active)
    values (v_name, v_role_type, true)
    returning id into v_id;
  else
    update public.workshop_technicians
    set active = true,
        role_type = v_role_type
    where id = v_id;
  end if;

  return v_id;
end;
$$;

create or replace function public.workshop_set_bay_default_technician(
  p_stage_code text,
  p_bay_number integer,
  p_technician_name text default null,
  p_role_type text default 'technician'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bay_id uuid;
  v_technician_id uuid;
  v_before jsonb;
  v_after jsonb;
begin
  perform public.require_pdc_role('operator');
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);

  select to_jsonb(b) into v_before
  from public.workshop_bays b
  where b.id = v_bay_id
  for update;

  if trim(coalesce(p_technician_name, '')) <> '' then
    v_technician_id := public.workshop_ensure_technician(p_technician_name, p_role_type);
  end if;

  update public.workshop_bays
  set default_technician_id = v_technician_id
  where id = v_bay_id;

  select jsonb_build_object(
    'id', b.id,
    'stage_id', b.stage_id,
    'bay_number', b.bay_number,
    'default_technician_id', b.default_technician_id,
    'updated_at', b.updated_at
  ) into v_after
  from public.workshop_bays b
  where b.id = v_bay_id;

  perform public.audit_pdc_event(
    'update',
    'workshop_bays',
    v_bay_id,
    null,
    v_before,
    v_after,
    jsonb_build_object('event_type', 'default_technician_changed')
  );

  return jsonb_build_object('ok', true, 'bay', v_after);
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
  v_existing public.workshop_bookings%rowtype;
  v_reuse_existing boolean := false;
  v_conflict_id uuid;
  v_history_id uuid;
  v_end timestamptz;
  v_before jsonb;
  v_after jsonb;
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  p_scheduled_start_at := public.workshop_normalize_work_start(p_scheduled_start_at);
  v_end := public.workshop_add_work_minutes(p_scheduled_start_at, p_duration_minutes);

  perform pg_advisory_xact_lock(hashtextextended('workshop-vehicle-stage:' || p_vehicle_id::text || ':' || v_stage_id::text, 0));

  select * into v_existing
  from public.workshop_bookings
  where vehicle_id = p_vehicle_id
    and stage_id = v_stage_id
    and status in ('queued', 'planned', 'started', 'stoppage')
  order by updated_at desc
  limit 1
  for update;

  v_reuse_existing := found;

  if v_reuse_existing and v_existing.status <> 'queued' then
    return jsonb_build_object(
      'ok', false,
      'error', 'booking_exists',
      'conflict', public.workshop_conflict_payload(v_existing.id, 'booking_exists')
    );
  end if;

  perform public.workshop_lock_resources(v_bay_id, p_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(case when v_reuse_existing then v_existing.id else null end, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;

  if p_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(case when v_reuse_existing then v_existing.id else null end, p_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  if v_reuse_existing then
    v_booking_id := v_existing.id;
    v_before := public.workshop_booking_snapshot(v_booking_id);

    update public.workshop_bookings
    set bay_id = v_bay_id,
        status = 'planned',
        scheduled_start_at = p_scheduled_start_at,
        scheduled_end_at = v_end,
        default_duration_minutes = p_duration_minutes,
        returned_to_queue_at = null,
        actual_start_at = null,
        actual_end_at = null,
        actual_duration_minutes = null,
        stoppage_reason = null,
        stoppage_started_at = null,
        stoppage_accumulated_minutes = 0,
        deleted_at = null,
        deleted_reason = null,
        updated_by = auth.uid(),
        version = version + 1
    where id = v_booking_id;

    perform public.workshop_upsert_primary_assignment(v_booking_id, p_technician_id, p_scheduled_start_at, v_end, 'scheduled');
    v_after := public.workshop_booking_snapshot(v_booking_id);
    v_history_id := public.workshop_write_history(v_booking_id, 'scheduled', v_before, v_after, coalesce(p_metadata, '{}'::jsonb));
    return jsonb_build_object('ok', true, 'booking', v_after, 'history_id', v_history_id);
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

create or replace function public.workshop_update_booking(
  p_booking_id uuid,
  p_expected_version integer,
  p_stage_code text,
  p_bay_number integer,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer,
  p_technician_id uuid default null,
  p_event_type text default 'moved',
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_stage_id uuid;
  v_bay_id uuid;
  v_conflict_id uuid;
  v_duplicate_id uuid;
  v_end timestamptz;
  v_history_id uuid;
  v_event_type text := coalesce(nullif(trim(p_event_type), ''), 'moved');
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

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
  if v_before.status in ('completed', 'deleted') then
    raise exception 'Completed or deleted workshop bookings cannot be changed' using errcode = '22023';
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  p_scheduled_start_at := public.workshop_normalize_work_start(p_scheduled_start_at);
  v_end := public.workshop_add_work_minutes(p_scheduled_start_at, p_duration_minutes);

  perform pg_advisory_xact_lock(hashtextextended('workshop-vehicle-stage:' || v_before.vehicle_id::text || ':' || v_stage_id::text, 0));

  select id into v_duplicate_id
  from public.workshop_bookings
  where vehicle_id = v_before.vehicle_id
    and stage_id = v_stage_id
    and id <> p_booking_id
    and status in ('queued', 'planned', 'started', 'stoppage')
  limit 1;

  if v_duplicate_id is not null then
    return jsonb_build_object('ok', false, 'error', 'booking_exists', 'conflict', public.workshop_conflict_payload(v_duplicate_id, 'booking_exists'));
  end if;

  perform public.workshop_lock_resources(v_bay_id, p_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;

  if p_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, p_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set stage_id = v_stage_id,
      bay_id = v_bay_id,
      status = case when status = 'queued' then 'planned' else status end,
      scheduled_start_at = p_scheduled_start_at,
      scheduled_end_at = v_end,
      default_duration_minutes = p_duration_minutes,
      returned_to_queue_at = case when status = 'queued' then null else returned_to_queue_at end,
      actual_start_at = case when status = 'queued' then null else actual_start_at end,
      actual_end_at = case when status = 'queued' then null else actual_end_at end,
      actual_duration_minutes = case when status = 'queued' then null else actual_duration_minutes end,
      stoppage_reason = case when status = 'queued' then null else stoppage_reason end,
      stoppage_started_at = case when status = 'queued' then null else stoppage_started_at end,
      stoppage_accumulated_minutes = case when status = 'queued' then 0 else stoppage_accumulated_minutes end,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform public.workshop_upsert_primary_assignment(p_booking_id, p_technician_id, p_scheduled_start_at, v_end, v_event_type);

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, v_event_type, v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_resume_booking(
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
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
  v_extra_minutes integer := 0;
begin
  perform public.require_pdc_role('operator');
  select * into v_booking
  from public.workshop_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;
  if v_booking.status <> 'stoppage' then
    raise exception 'Only a stopped workshop booking can be resumed' using errcode = '22023';
  end if;

  if v_booking.stoppage_started_at is not null then
    v_extra_minutes := public.workshop_work_minutes_between(v_booking.stoppage_started_at, now());
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'started',
      stoppage_started_at = null,
      stoppage_accumulated_minutes = coalesce(stoppage_accumulated_minutes, 0) + v_extra_minutes,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'resumed', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_complete_booking(
  p_booking_id uuid,
  p_expected_version integer,
  p_actual_end_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
  v_start timestamptz;
  v_total_minutes integer;
  v_open_stoppage_minutes integer := 0;
begin
  perform public.require_pdc_role('operator');
  select * into v_booking
  from public.workshop_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;
  if v_booking.status not in ('started', 'stoppage') then
    raise exception 'Only a started or stopped workshop booking can be completed' using errcode = '22023';
  end if;

  v_start := coalesce(v_booking.actual_start_at, v_booking.scheduled_start_at);
  if v_booking.stoppage_started_at is not null then
    v_open_stoppage_minutes := public.workshop_work_minutes_between(v_booking.stoppage_started_at, p_actual_end_at);
  end if;
  v_total_minutes := greatest(
    0,
    public.workshop_work_minutes_between(v_start, p_actual_end_at)
      - coalesce(v_booking.stoppage_accumulated_minutes, 0)
      - v_open_stoppage_minutes
  );

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'completed',
      actual_start_at = coalesce(actual_start_at, v_start),
      actual_end_at = p_actual_end_at,
      actual_duration_minutes = v_total_minutes,
      stoppage_started_at = null,
      stoppage_accumulated_minutes = coalesce(stoppage_accumulated_minutes, 0) + v_open_stoppage_minutes,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  update public.workshop_booking_assignments
  set released_at = coalesce(released_at, p_actual_end_at),
      updated_at = now()
  where booking_id = p_booking_id
    and released_at is null;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'completed', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_start_booking(
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
  v_booking public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_start timestamptz;
  v_end timestamptz;
begin
  perform public.require_pdc_role('operator');

  select * into v_booking
  from public.workshop_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;
  if v_booking.status <> 'planned' then
    raise exception 'Only a planned workshop booking can be started' using errcode = '22023';
  end if;
  if v_booking.bay_id is null then
    raise exception 'A workshop booking must have a bay before it can be started' using errcode = '22023';
  end if;

  select a.technician_id into v_technician_id
  from public.workshop_booking_assignments a
  where a.booking_id = p_booking_id
    and a.released_at is null
  order by case when a.assignment_type = 'primary' then 0 else 1 end, a.assigned_at desc
  limit 1;

  v_start := public.workshop_normalize_work_start(p_actual_start_at);
  v_end := public.workshop_add_work_minutes(v_start, v_booking.default_duration_minutes);

  perform public.workshop_lock_resources(v_booking.bay_id, v_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_booking.bay_id, v_start, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;

  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, v_start, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'started',
      scheduled_start_at = v_start,
      scheduled_end_at = v_end,
      actual_start_at = v_start,
      stoppage_reason = null,
      stoppage_started_at = null,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, v_start, v_end, 'started');

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'started', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

-- Correct any schedules created by the earlier continuous-clock implementation.
update public.workshop_bookings
set scheduled_start_at = public.workshop_normalize_work_start(scheduled_start_at),
    scheduled_end_at = public.workshop_add_work_minutes(scheduled_start_at, default_duration_minutes)
where status <> 'deleted';

update public.workshop_booking_assignments a
set scheduled_start_at = b.scheduled_start_at,
    scheduled_end_at = b.scheduled_end_at,
    updated_at = now()
from public.workshop_bookings b
where b.id = a.booking_id
  and a.released_at is null;

revoke all on function public.workshop_ensure_technician(text, text) from public, anon;
revoke all on function public.workshop_set_bay_default_technician(text, integer, text, text) from public, anon;
revoke all on function public.workshop_update_booking(uuid, integer, text, integer, timestamptz, integer, uuid, text, jsonb) from public, anon;
revoke all on function public.workshop_normalize_work_start(timestamptz, text) from public, anon, authenticated;
revoke all on function public.workshop_add_work_minutes(timestamptz, integer, text) from public, anon, authenticated;
revoke all on function public.workshop_work_minutes_between(timestamptz, timestamptz, text) from public, anon, authenticated;
revoke execute on function public.workshop_move_booking(uuid, integer, text, integer, timestamptz, uuid, jsonb) from authenticated;
revoke execute on function public.workshop_resize_booking(uuid, integer, integer, jsonb) from authenticated;
revoke execute on function public.workshop_reassign_booking(uuid, integer, uuid, jsonb) from authenticated;

grant execute on function public.workshop_ensure_technician(text, text) to authenticated;
grant execute on function public.workshop_set_bay_default_technician(text, integer, text, text) to authenticated;
grant execute on function public.workshop_create_booking(uuid, text, integer, timestamptz, integer, uuid, jsonb) to authenticated;
grant execute on function public.workshop_start_booking(uuid, integer, timestamptz, jsonb) to authenticated;
grant execute on function public.workshop_resume_booking(uuid, integer, jsonb) to authenticated;
grant execute on function public.workshop_complete_booking(uuid, integer, timestamptz, jsonb) to authenticated;
grant execute on function public.workshop_update_booking(uuid, integer, text, integer, timestamptz, integer, uuid, text, jsonb) to authenticated;

commit;
