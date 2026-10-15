-- Exclude retained assignments of deleted/completed work from fitter availability.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF md5(pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure))
 IS DISTINCT FROM '6aea577f8ce3a3017f5acd1ce7502297'
 THEN RAISE EXCEPTION 'Reviewed workshop booking validation changed'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.workshop_validate_booking(p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_preserve_historical_calendar boolean:=false; v_bus_calendar boolean:=false; v_bus_rule jsonb; v_bus_end timestamptz; v_bus_unchanged boolean:=false;
  v_vehicle public.vehicles%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_conflict uuid;
  v_local_date date := (p_scheduled_start_at at time zone 'Australia/Perth')::date;
  v_active boolean := p_status in ('queued','planned','started','stoppage'); v_estimated_duration integer; v_candidate_end timestamptz; v_registered_synthetic boolean := false;
begin
  if not v_active then return jsonb_build_object('ok',true); end if;
 v_bus_calendar:=pdc_bus_private.active_vehicle(p_vehicle_id) AND EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id AND s.code='BUS_4X4');
 IF v_bus_calendar THEN
  v_bus_unchanged:=EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.bay_id=p_bay_id AND b.deleted_at IS NULL
   AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at AND b.default_duration_minutes=p_duration_minutes AND b.status IN('planned','started','stoppage'));
  IF NOT v_bus_unchanged THEN
   v_bus_rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,p_booking_id);
   IF v_bus_rule->>'ok' IS DISTINCT FROM 'true' THEN RETURN v_bus_rule; END IF;
   IF NOT pdc_bus_private.minute_available(p_scheduled_start_at,p_bay_id) THEN RETURN jsonb_build_object('ok',false,'error','bus_shift_outside_hours'); END IF;
   v_bus_end:=pdc_bus_private.add_minutes(p_scheduled_start_at,p_duration_minutes,p_bay_id);
   IF p_scheduled_end_at IS DISTINCT FROM v_bus_end AND p_scheduled_end_at IS DISTINCT FROM public.workshop_add_operational_minutes(p_scheduled_start_at,p_duration_minutes)
   THEN RETURN jsonb_build_object('ok',false,'error','calendar_duration_mismatch'); END IF;
   p_scheduled_end_at:=v_bus_end;
  END IF;
 END IF;
  v_registered_synthetic:=exists(
    select 1
    from public.pdc_overnight_synthetic_fleet_registry_363 r
    join public.vehicles x on x.id=p_vehicle_id
     and r.run_id='HERMES-TEST-RUN-20260824'
     and r.vehicle_id=x.id
     and x.stock_number=r.stock_number
     and x.customer_name=r.customer_name
     and x.job_card_number=r.job_card_number
     and x.vehicle_description=r.vehicle_description
     and x.source_system='hermes_overnight_synthetic'
     and x.source_batch_id=r.run_id
     and x.source_record_id=r.stock_number
     and x.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
  );
  if p_duration_minutes is null or p_duration_minutes<1 then
    return jsonb_build_object('ok',false,'error','minimum_duration','minimum_minutes',1);
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
  -- Stopping work records a real event; changing future hours must not invalidate
  -- the unchanged interval of a job that already started under the old calendar.
  -- This exemption never applies to a move, resize, start, or changed identity.
  v_preserve_historical_calendar:=p_allow_unchanged_past AND p_status='stoppage' AND EXISTS(
    SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id
      AND b.deleted_at IS NULL AND b.status='started' AND b.actual_start_at IS NOT NULL
      AND b.vehicle_id=p_vehicle_id AND b.stage_id=p_stage_id AND b.bay_id=p_bay_id
      AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at
      AND b.default_duration_minutes=p_duration_minutes);
  if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND not public.workshop_calendar_minute_available(p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','calendar_unavailable');
  end if;
  if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at)<>p_duration_minutes then
    return jsonb_build_object('ok',false,'error','calendar_duration_mismatch');
  end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id and deleted_at is null and lifecycle_state='active';
  if not found then return jsonb_build_object('ok',false,'error','vehicle_inactive_or_missing'); end if;
  if exists(select 1 from public.pdc_new_vehicle_reviews r where r.vehicle_id=p_vehicle_id and r.status='pending') then return jsonb_build_object('ok',false,'error','new_vehicle_review_required'); end if;
  select * into v_stage from public.workshop_stages where id=p_stage_id and active and planner_enabled;
  if not found then return jsonb_build_object('ok',false,'error','station_inactive_or_missing'); end if; v_estimated_duration:=coalesce(public.workshop_capacity_manual_minutes(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id,p_duration_minutes),public.workshop_booking_capacity_duration_minutes(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id)); v_candidate_end:=case when p_status in ('queued','planned') and v_estimated_duration is not null then CASE WHEN v_bus_calendar THEN CASE WHEN v_bus_unchanged THEN p_scheduled_end_at ELSE pdc_bus_private.add_minutes(p_scheduled_start_at,v_estimated_duration,p_bay_id) END ELSE public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) END else p_scheduled_end_at end; if p_status in ('queued','planned') and v_estimated_duration is not null and p_duration_minutes<>v_estimated_duration and not v_registered_synthetic then return jsonb_build_object('ok',false,'error','operation_estimate_duration_mismatch','expected_minutes',v_estimated_duration); end if;
  if public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location)) not in ('PMB','YH','IT') then
    return jsonb_build_object('ok',false,'error','location_ineligible');
  end if;
  if public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location))='IT' then
    if v_vehicle.eta_to_kewdale is null then return jsonb_build_object('ok',false,'error','it_eta_missing'); end if;
    if v_local_date<v_vehicle.eta_to_kewdale+7 then return jsonb_build_object('ok',false,'error','it_before_eta_plus_seven','earliest_permitted_date',v_vehicle.eta_to_kewdale+7); end if;
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
      and tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by b.scheduled_start_at,b.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','bay_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  select b.id into v_conflict from public.workshop_bookings b
  where b.id is distinct from p_booking_id and b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage') and b.vehicle_id=p_vehicle_id
    and tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
  order by b.scheduled_start_at,b.id limit 1;
  if v_conflict is not null then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if;
  if p_technician_id is not null then
    IF v_bus_calendar AND NOT (v_bus_unchanged AND EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=p_booking_id AND a.technician_id=p_technician_id AND a.released_at IS NULL)) THEN
      v_bus_rule:=pdc_bus_private.technician_shift_problem(p_technician_id,p_bay_id,p_scheduled_start_at,v_candidate_end);
      IF v_bus_rule IS NOT NULL THEN RETURN v_bus_rule; END IF;
    END IF;
    if not exists(select 1 from public.workshop_technicians t where t.id=p_technician_id and t.active) then
      return jsonb_build_object('ok',false,'error','technician_inactive_or_missing');
    end if;
    if public.workshop_technician_leave_date(p_technician_id,p_scheduled_start_at,v_candidate_end) is not null then
      return jsonb_build_object('ok',false,'error','technician_leave_conflict');
    end if;
    -- Historical assignments only reserve time while their booking is active.
    select a.booking_id into v_conflict from public.workshop_booking_assignments a
    join public.workshop_bookings assigned_booking on assigned_booking.id=a.booking_id
    where a.booking_id is distinct from p_booking_id and a.technician_id=p_technician_id and a.released_at is null
      and assigned_booking.deleted_at is null
      and assigned_booking.status in ('queued','planned','started','stoppage')
      and tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.booking_id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by a.scheduled_start_at,a.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  return jsonb_build_object('ok',true);
end $function$;

-- Release capacity at the lifecycle boundary while retaining every assignment row.
CREATE OR REPLACE FUNCTION pdc_fitter_private.release_inactive_booking_assignments()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog'
AS $function$
BEGIN
 IF (NEW.deleted_at IS NOT NULL OR NEW.status NOT IN ('queued','planned','started','stoppage'))
 AND EXISTS(SELECT 1 FROM public.workshop_stages s WHERE s.id=NEW.stage_id AND s.planner_enabled) THEN
  UPDATE public.workshop_booking_assignments
  SET released_at=clock_timestamp(),updated_at=clock_timestamp()
  WHERE booking_id=NEW.id AND released_at IS NULL;
 END IF;
 RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION pdc_fitter_private.release_inactive_booking_assignments() FROM PUBLIC,anon,authenticated;

CREATE TRIGGER workshop_bookings_release_inactive_assignments
AFTER UPDATE OF status,deleted_at ON public.workshop_bookings
FOR EACH ROW
WHEN (NEW.deleted_at IS NOT NULL OR NEW.status NOT IN ('queued','planned','started','stoppage'))
EXECUTE FUNCTION pdc_fitter_private.release_inactive_booking_assignments();

-- Repair existing orphaned reservations; the active-booking exclusion constraint stays intact.
UPDATE public.workshop_booking_assignments a
SET released_at=clock_timestamp(),updated_at=clock_timestamp()
FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
WHERE a.booking_id=b.id AND a.released_at IS NULL AND s.planner_enabled
AND (b.deleted_at IS NOT NULL OR b.status NOT IN ('queued','planned','started','stoppage'));
