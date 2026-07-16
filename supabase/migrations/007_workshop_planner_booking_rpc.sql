-- Workshop Planner protected RPC functions
-- Conflict-safe booking mutations with shared audit/history and realtime-friendly writes.

begin;

create or replace function public.workshop_resolve_stage_id(p_stage_code text)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id
  from public.workshop_stages
  where code = upper(trim(coalesce(p_stage_code, '')))
    and active = true
  limit 1;

  if v_id is null then
    raise exception 'Workshop stage % not found', p_stage_code using errcode = 'P0002';
  end if;

  return v_id;
end;
$$;

create or replace function public.workshop_resolve_bay_id(p_stage_code text, p_bay_number integer)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_stage_id uuid;
  v_bay_id uuid;
  v_number integer := greatest(coalesce(p_bay_number, 1), 1);
begin
  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);

  select id into v_bay_id
  from public.workshop_bays
  where stage_id = v_stage_id
    and bay_number = v_number
    and is_active = true
  limit 1;

  if v_bay_id is null then
    raise exception 'Workshop bay % for stage % not found', p_bay_number, p_stage_code using errcode = 'P0002';
  end if;

  return v_bay_id;
end;
$$;

create or replace function public.workshop_lock_resources(p_bay_id uuid, p_technician_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_bay_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('workshop-bay:' || p_bay_id::text, 0));
  end if;
  if p_technician_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('workshop-technician:' || p_technician_id::text, 0));
  end if;
end;
$$;

create or replace function public.workshop_booking_snapshot(p_booking_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with active_assignment as (
    select a.booking_id, a.technician_id, t.name as technician_name, a.assignment_type
    from public.workshop_booking_assignments a
    join public.workshop_technicians t on t.id = a.technician_id
    where a.booking_id = p_booking_id
      and a.released_at is null
    order by case when a.assignment_type = 'primary' then 0 else 1 end, a.assigned_at desc
    limit 1
  )
  select jsonb_build_object(
    'booking_id', b.id,
    'vehicle_id', b.vehicle_id,
    'vehicle', jsonb_build_object(
      'permanent_vehicle_id', v.permanent_vehicle_id,
      'stock_number', v.stock_number,
      'job_card_number', v.job_card_number,
      'customer_name', v.customer_name,
      'model', v.model
    ),
    'stage', jsonb_build_object(
      'id', s.id,
      'code', s.code,
      'display_name', s.display_name,
      'sort_order', s.sort_order
    ),
    'bay', case when bay.id is null then null else jsonb_build_object(
      'id', bay.id,
      'bay_number', bay.bay_number,
      'code', bay.code,
      'display_name', bay.display_name,
      'is_sublet_row', bay.is_sublet_row
    ) end,
    'status', b.status,
    'scheduled_start_at', b.scheduled_start_at,
    'scheduled_end_at', b.scheduled_end_at,
    'default_duration_minutes', b.default_duration_minutes,
    'actual_start_at', b.actual_start_at,
    'actual_end_at', b.actual_end_at,
    'actual_duration_minutes', b.actual_duration_minutes,
    'stoppage_reason', b.stoppage_reason,
    'stoppage_started_at', b.stoppage_started_at,
    'stoppage_accumulated_minutes', b.stoppage_accumulated_minutes,
    'returned_to_queue_at', b.returned_to_queue_at,
    'deleted_at', b.deleted_at,
    'deleted_reason', b.deleted_reason,
    'version', b.version,
    'assignment', case when aa.technician_id is null then null else jsonb_build_object(
      'technician_id', aa.technician_id,
      'technician_name', aa.technician_name,
      'assignment_type', aa.assignment_type
    ) end,
    'updated_at', b.updated_at,
    'created_at', b.created_at
  )
  from public.workshop_bookings b
  join public.vehicles v on v.id = b.vehicle_id
  join public.workshop_stages s on s.id = b.stage_id
  left join public.workshop_bays bay on bay.id = b.bay_id
  left join active_assignment aa on aa.booking_id = b.id
  where b.id = p_booking_id;
$$;

create or replace function public.workshop_conflict_payload(p_booking_id uuid, p_conflict_type text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'conflict_type', p_conflict_type,
    'existing_booking', public.workshop_booking_snapshot(p_booking_id)
  );
$$;

create or replace function public.workshop_write_history(
  p_booking_id uuid,
  p_event_type text,
  p_before jsonb default null,
  p_after jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_history_id uuid;
  v_action public.audit_action := 'update';
  v_vehicle_id uuid;
begin
  select vehicle_id into v_vehicle_id
  from public.workshop_bookings
  where id = p_booking_id;

  if p_event_type = 'created' then
    v_action := 'insert';
  elsif p_event_type = 'moved' then
    v_action := 'move';
  elsif p_event_type = 'deleted' then
    v_action := 'delete';
  elsif p_event_type = 'restored' then
    v_action := 'restore';
  end if;

  insert into public.workshop_booking_history (
    booking_id,
    event_type,
    before_data,
    after_data,
    metadata,
    actor_user_id,
    actor_email
  ) values (
    p_booking_id,
    p_event_type,
    p_before,
    p_after,
    coalesce(p_metadata, '{}'::jsonb),
    auth.uid(),
    public.current_actor_email()
  ) returning id into v_history_id;

  perform public.audit_pdc_event(
    v_action,
    'workshop_bookings',
    p_booking_id,
    v_vehicle_id,
    p_before,
    p_after,
    jsonb_build_object('event_type', p_event_type) || coalesce(p_metadata, '{}'::jsonb)
  );

  return v_history_id;
end;
$$;

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
    and b.status in ('queued', 'planned', 'started', 'stoppage')
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
    and b.status in ('queued', 'planned', 'started', 'stoppage')
    and tstzrange(a.scheduled_start_at, a.scheduled_end_at, '[)') && tstzrange(p_start, p_end, '[)')
  order by a.scheduled_start_at
  limit 1;
$$;

create or replace function public.workshop_upsert_primary_assignment(
  p_booking_id uuid,
  p_technician_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.workshop_booking_assignments
  set released_at = now(),
      updated_at = now()
  where booking_id = p_booking_id
    and released_at is null
    and (p_technician_id is null or technician_id <> p_technician_id or assignment_type <> 'primary');

  if p_technician_id is null then
    return;
  end if;

  insert into public.workshop_booking_assignments (
    booking_id,
    technician_id,
    assignment_type,
    assigned_by,
    scheduled_start_at,
    scheduled_end_at,
    notes
  ) values (
    p_booking_id,
    p_technician_id,
    'primary',
    auth.uid(),
    p_start,
    p_end,
    p_notes
  )
  on conflict (booking_id) where assignment_type = 'primary' and released_at is null
  do update
  set technician_id = excluded.technician_id,
      assigned_by = excluded.assigned_by,
      scheduled_start_at = excluded.scheduled_start_at,
      scheduled_end_at = excluded.scheduled_end_at,
      notes = excluded.notes,
      released_at = null,
      updated_at = now();
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
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  v_end := p_scheduled_start_at + make_interval(mins => p_duration_minutes);

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
set search_path = public
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
  v_end := p_scheduled_start_at + make_interval(mins => v_duration);

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
set search_path = public
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_end timestamptz;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
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

  select technician_id into v_technician_id
  from public.workshop_booking_assignments
  where booking_id = p_booking_id and released_at is null
  order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc
  limit 1;

  v_end := v_booking.scheduled_start_at + make_interval(mins => p_duration_minutes);
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
begin
  perform public.require_pdc_role('operator');

  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
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
begin
  perform public.require_pdc_role('operator');
  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'started',
      actual_start_at = coalesce(actual_start_at, p_actual_start_at),
      stoppage_reason = null,
      stoppage_started_at = null,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'started', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_record_stoppage(
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
  v_booking public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
begin
  perform public.require_pdc_role('operator');
  if trim(coalesce(p_reason, '')) = '' then
    raise exception 'Workshop stoppage reason is required' using errcode = '22023';
  end if;

  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'stoppage',
      stoppage_reason = trim(p_reason),
      stoppage_started_at = now(),
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'stoppage_recorded', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
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
  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  if v_booking.stoppage_started_at is not null then
    v_extra_minutes := greatest(0, floor(extract(epoch from (now() - v_booking.stoppage_started_at)) / 60.0)::integer);
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
  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  v_start := coalesce(v_booking.actual_start_at, v_booking.scheduled_start_at);
  if v_booking.stoppage_started_at is not null then
    v_open_stoppage_minutes := greatest(0, floor(extract(epoch from (p_actual_end_at - v_booking.stoppage_started_at)) / 60.0)::integer);
  end if;
  v_total_minutes := greatest(0, floor(extract(epoch from (p_actual_end_at - v_start)) / 60.0)::integer) - coalesce(v_booking.stoppage_accumulated_minutes, 0) - v_open_stoppage_minutes;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'completed',
      actual_start_at = coalesce(actual_start_at, v_start),
      actual_end_at = p_actual_end_at,
      actual_duration_minutes = greatest(0, v_total_minutes),
      stoppage_started_at = null,
      stoppage_accumulated_minutes = coalesce(stoppage_accumulated_minutes, 0) + v_open_stoppage_minutes,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  update public.workshop_booking_assignments
  set released_at = coalesce(released_at, p_actual_end_at),
      updated_at = now()
  where booking_id = p_booking_id and released_at is null;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'completed', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_return_booking_to_queue(
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
  v_booking public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
begin
  perform public.require_pdc_role('operator');
  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'queued',
      bay_id = null,
      returned_to_queue_at = now(),
      stoppage_reason = coalesce(nullif(trim(coalesce(p_reason, '')), ''), stoppage_reason),
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  update public.workshop_booking_assignments
  set released_at = coalesce(released_at, now()),
      updated_at = now()
  where booking_id = p_booking_id and released_at is null;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'returned_to_queue', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_delete_booking(
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
  v_booking public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
begin
  perform public.require_pdc_role('operator');
  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'deleted',
      deleted_at = now(),
      deleted_reason = nullif(trim(coalesce(p_reason, '')), ''),
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  update public.workshop_booking_assignments
  set released_at = coalesce(released_at, now()),
      updated_at = now()
  where booking_id = p_booking_id and released_at is null;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'deleted', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_restore_booking(
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
begin
  perform public.require_pdc_role('operator');
  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'queued',
      bay_id = null,
      deleted_at = null,
      deleted_reason = null,
      returned_to_queue_at = now(),
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'restored', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

commit;
