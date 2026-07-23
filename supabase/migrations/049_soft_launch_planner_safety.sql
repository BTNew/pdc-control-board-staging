-- Soft-launch planner safety closure.
-- Enforce no-past scheduling on the authoritative database clock and restore
-- a catalog-first search path on the browser-callable atomic cascade RPC.

create or replace function public.workshop_validate_booking(
  p_booking_id uuid,
  p_vehicle_id uuid,
  p_stage_id uuid,
  p_bay_id uuid,
  p_scheduled_start_at timestamptz,
  p_scheduled_end_at timestamptz,
  p_duration_minutes integer,
  p_status public.workshop_booking_status,
  p_technician_id uuid,
  p_allow_unchanged_past boolean
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
  if not p_allow_unchanged_past
     and p_status in ('queued','planned')
     and p_scheduled_start_at < date_trunc('minute',statement_timestamp()) then
    return jsonb_build_object('ok',false,'error','past_start');
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

revoke all on function public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean) from public,anon,authenticated;

-- Keep the existing public/internal nine-argument contract strict. Only the
-- booking trigger below can opt into historical status-transition validation.
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
language sql
security definer
set search_path=pg_catalog,public
as $$
  select public.workshop_validate_booking(
    p_booking_id,p_vehicle_id,p_stage_id,p_bay_id,p_scheduled_start_at,
    p_scheduled_end_at,p_duration_minutes,p_status,p_technician_id,false
  )
$$;
revoke all on function public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid) from public,anon,authenticated;

-- Reopen/restore/status-only lifecycle actions must keep historical timestamps
-- exactly as recorded, while every creation/move/resize/assignment path still
-- receives the strict queued/planned no-past check above. For an unchanged
-- persisted interval, validate the row as an active started interval so all
-- eligibility, bay, calendar, overlap and technician checks still run; only
-- the queued/planned no-past branch is bypassed.
create or replace function public.workshop_enforce_booking_validation()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_result jsonb;
  v_technician uuid;
  v_allow_unchanged_past boolean:=false;
begin
  if new.deleted_at is not null or new.status not in ('queued','planned','started','stoppage') then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('workshop:vehicle:'||new.vehicle_id::text,0));
  select a.technician_id into v_technician from public.workshop_booking_assignments a
  where a.booking_id=new.id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1;
  if tg_op='UPDATE'
     and new.scheduled_start_at is not distinct from old.scheduled_start_at
     and new.scheduled_end_at is not distinct from old.scheduled_end_at then
    v_allow_unchanged_past:=true;
  end if;
  v_result:=public.workshop_validate_booking(new.id,new.vehicle_id,new.stage_id,new.bay_id,new.scheduled_start_at,
    new.scheduled_end_at,new.default_duration_minutes,new.status,v_technician,v_allow_unchanged_past);
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'Workshop Planner validation rejected booking: %',v_result::text using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function public.workshop_enforce_booking_validation() from public,anon,authenticated;

ALTER FUNCTION public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)
  SET search_path = pg_catalog, public;
