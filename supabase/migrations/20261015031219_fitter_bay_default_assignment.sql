-- Unstarted bay-default work follows its new bay; explicit teams and live work stay assigned.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF md5(pg_get_functiondef('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)'::regprocedure))
 IS DISTINCT FROM 'a161918c5df096ec2d7ecf0e11ee181d'
 THEN RAISE EXCEPTION 'Reviewed workshop move function changed'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.workshop_move_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT NULL::integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true);
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
  -- Unstarted work inherited from the old bay follows the destination's default.
  -- Preserve deliberate team choices, helpers and any work already performed.
  if v_bay_id is distinct from v_before.bay_id
     and v_before.status in ('queued','planned') and v_before.actual_start_at is null
     and not exists(select 1 from pdc_fitter_private.operation_progress where booking_id=p_booking_id)
     and not exists(select 1 from public.workshop_booking_history
       where booking_id=p_booking_id and event_type in ('team_changed','reassigned','technician_assigned','technician_changed','assigned'))
     and (v_technician_id is null or v_technician_id = (
       select default_technician_id from public.workshop_bays where id=v_before.bay_id))
     and exists(select 1 from public.workshop_bays bay
       join public.workshop_technicians t on t.id=bay.default_technician_id and t.active
       where bay.id=v_bay_id) then
    select default_technician_id into v_technician_id from public.workshop_bays where id=v_bay_id;
  end if;

  v_duration := CASE WHEN v_before.status IN('queued','planned') AND (v_bay_id IS DISTINCT FROM v_before.bay_id OR v_stage_id IS DISTINCT FROM v_before.stage_id) THEN public.workshop_booking_capacity_duration_minutes(p_booking_id,v_before.vehicle_id,v_stage_id,v_bay_id) ELSE coalesce(p_duration_minutes,v_before.default_duration_minutes) END;
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

  perform set_config('pdc.workshop_capacity_manual',jsonb_build_object('actor',auth.uid(),'booking',p_booking_id,'version',p_expected_version,'duration',v_duration)::text,true);
  update public.workshop_bookings
  set stage_id = v_stage_id,
      bay_id = v_bay_id,
      scheduled_start_at = p_scheduled_start_at,
      scheduled_end_at = v_end,
      default_duration_minutes = v_duration,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
  perform public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, p_scheduled_start_at, v_end, 'moved');

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'moved', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
EXCEPTION WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
 RAISE;
end;
$function$
;
NOTIFY pgrst,'reload schema';
