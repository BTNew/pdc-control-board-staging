-- r469 undo (F82): restores public.cascade_workshop_schedule_pre_087 byte for byte (bbdc1ae1525d7e5060bfda8a8406b8f4; push every later booking by
-- the full duration), drops pdc_cascade_private and its 3 helpers, the 4 r469 pins and check cascade_insert_overlap_chain_469.
-- Run between :02 and :45. Staging only. Changes no booking rows (bookings already moved by the r469 rule stay where they are).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r469 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r469 undo: staging only'; END IF;
 PERFORM set_config('pdc.r469_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r469_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r469_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r469_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r469 undo: clock tick does not match its pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)')) IS DISTINCT FROM '5f76d7e74c9ced8e948beebdee02a250' THEN RAISE EXCEPTION 'r469 undo: public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb) is not the r469 version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer)')) IS DISTINCT FROM 'b7b98893bfc7a04b39330ca689f8f1b1' THEN RAISE EXCEPTION 'r469 undo: pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer) is not the r469 version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone)')) IS DISTINCT FROM 'e3602ba6f9d5973deea4eef09f5077c0' THEN RAISE EXCEPTION 'r469 undo: pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone) is not the r469 version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.validation_rejection_469(text)')) IS DISTINCT FROM '621c8e5756bf4996b416c25b38c783b9' THEN RAISE EXCEPTION 'r469 undo: pdc_cascade_private.validation_rejection_469(text) is not the r469 version'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='cascade_insert_overlap_chain_469' AND added_in='r469') THEN RAISE EXCEPTION 'r469 undo: r469 is not applied'; END IF;
END $g$;

-- Exact previous definition (md5 bbdc1ae1525d7e5060bfda8a8406b8f4).
CREATE OR REPLACE FUNCTION public.cascade_workshop_schedule_pre_087(p_operation text, p_target_id uuid, p_target_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid DEFAULT NULL::uuid, p_shift_minutes integer DEFAULT 0, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  if p_duration_minutes is null or p_duration_minutes < 1 then
    return jsonb_build_object('ok', false, 'error', 'minimum_duration', 'minimum_minutes', 1);
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
      -- Future planning is not physical bay entry. The explicit reason is
  -- still written to workshop_parts_overrides, but any planner operator
  -- may create or move a planned booking before Parts are ready.
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
  where (b.bay_id = v_bay.id or b.vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
    and b.status = 'planned' and b.deleted_at is null
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
    and (b.bay_id = v_bay.id or b.vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
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
      and (b.bay_id = v_bay.id or b.vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
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
        and (bay_id = v_bay.id or vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
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
      and (bay_id = v_bay.id or vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
      and status = 'planned'
      and deleted_at is null
  loop
    v_conflict := public.workshop_find_bay_conflict(
      v_shifted.id, v_shifted.bay_id, v_shifted.scheduled_start_at, v_shifted.scheduled_end_at
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
$function$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='cascade_insert_overlap_chain_469' AND added_in='r469';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r469';
DROP FUNCTION pdc_cascade_private.validation_rejection_469(text);
DROP FUNCTION pdc_cascade_private.overlap_chain_469(uuid[],timestamptz);
DROP FUNCTION pdc_cascade_private.target_end_469(uuid,uuid,timestamptz,integer);
DROP SCHEMA pdc_cascade_private;

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)')) IS DISTINCT FROM 'bbdc1ae1525d7e5060bfda8a8406b8f4' THEN RAISE EXCEPTION 'r469 undo: pre_087 not restored'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r469 undo: pre_087 grants changed'; END IF;
 IF to_regnamespace('pdc_cascade_private') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r469') THEN RAISE EXCEPTION 'r469 undo: leftovers'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r469_pins')::int-4 THEN RAISE EXCEPTION 'r469 undo: pin count'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r469_tick') THEN RAISE EXCEPTION 'r469 undo: clock tick changed'; END IF;
END $g$;
