-- r594 (F208) / sort 364. Handover for the cascade release. Do not apply from this branch.
-- Craig made cascade an absolute rule and gave go-live at 08:30 AWST on 28 Oct 2026.
-- bc-ae6809e2 owns the release, including this resume push.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026 08:13 AWST: resume on Ben Palmer's bay (key 307) was refused
-- because the remaining time ran into key 359. Standing rule: everything cascades.
-- Resume pushes later planned jobs in that bay back-to-back, the same step as
-- r592 place-after (pdc_ops.place_after_live_bay_592) and cascade_workshop_booking_move_pre_116.
-- Those two stay as they are. r593 / F207 / sort 363 is the open hours preview (#578).
-- The Electrical cascade agent was aimed at that same triple, so this takes the next free one.
-- Pin count stays 241. No new pin.
-- Undo: supabase/rollbacks/20261028091500_r594_resume_bay_cascade.down.sql
SET LOCAL lock_timeout = '8s';

CREATE OR REPLACE FUNCTION pdc_ops.push_later_planned_in_bay_594(
  p_booking_id uuid,
  p_bay_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_metadata jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $push594$
DECLARE
  v_plan jsonb := '[]'::jsonb;
  v_cursor timestamptz;
  v_row record;
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_minutes integer;
  v_step jsonb;
  v_before jsonb;
  v_after jsonb;
  v_technician uuid;
  v_pushed jsonb := '[]'::jsonb;
  v_shift integer;
BEGIN
  -- Same back-to-back push as cascade_workshop_booking_move_pre_116 and
  -- pdc_ops.place_after_live_bay_592. Later planned jobs in this bay move
  -- behind p_end. A gap stops the chain. Started and stoppage rows stay put.
  IF p_bay_id IS NULL OR p_start IS NULL OR p_end IS NULL OR p_end <= p_start THEN
    RETURN jsonb_build_object('ok', false, 'error', 'resume_cascade_blocked',
      'message', 'This resume was not saved. Nothing was moved.');
  END IF;

  PERFORM 1 FROM public.workshop_bookings b
  WHERE b.bay_id = p_bay_id
    AND b.id IS DISTINCT FROM p_booking_id
    AND b.status = 'planned'
    AND b.deleted_at IS NULL
    AND public.workshop_booking_effective_end_at(b.id) > p_start
  ORDER BY b.id
  FOR UPDATE;

  v_cursor := p_end;
  FOR v_row IN
    SELECT b.id, b.version, b.scheduled_start_at, b.vehicle_id, b.stage_id, b.bay_id,
           v.key_number::text AS key_number
    FROM public.workshop_bookings b
    LEFT JOIN public.vehicles v ON v.id = b.vehicle_id
    WHERE b.bay_id = p_bay_id
      AND b.id IS DISTINCT FROM p_booking_id
      AND b.status = 'planned'
      AND b.deleted_at IS NULL
      AND public.workshop_booking_effective_end_at(b.id) > p_start
    ORDER BY b.scheduled_start_at, b.id
  LOOP
    EXIT WHEN v_row.scheduled_start_at >= v_cursor;
    v_new_start := public.workshop_admin_next_operational_minute(v_cursor);
    v_minutes := coalesce(
      public.workshop_booking_capacity_duration_minutes(v_row.id, v_row.vehicle_id, v_row.stage_id, v_row.bay_id),
      public.workshop_booking_effective_duration_minutes(v_row.id));
    v_new_end := public.workshop_add_operational_minutes(v_new_start, v_minutes);
    IF v_new_start IS NULL OR v_minutes IS NULL OR v_minutes < 1
       OR v_new_end IS NULL OR v_new_end <= v_new_start THEN
      RETURN jsonb_build_object('ok', false, 'error', 'resume_cascade_blocked',
        'message', 'Resuming would run outside working hours, so nothing was moved.');
    END IF;
    v_shift := public.workshop_operational_minutes_between(v_row.scheduled_start_at, v_new_start);
    v_plan := v_plan || jsonb_build_array(jsonb_build_object(
      'id', v_row.id,
      'version', v_row.version,
      'key_number', v_row.key_number,
      'from_start', v_row.scheduled_start_at,
      'start_at', v_new_start,
      'end_at', v_new_end,
      'duration_minutes', v_minutes,
      'shift_minutes', v_shift));
    v_pushed := v_pushed || jsonb_build_array(jsonb_build_object(
      'id', v_row.id,
      'key_number', v_row.key_number,
      'from_start', v_row.scheduled_start_at,
      'to_start', v_new_start));
    v_cursor := v_new_end;
  END LOOP;

  FOR v_step IN
    SELECT item.value
    FROM jsonb_array_elements(v_plan) WITH ORDINALITY item(value, ordinal)
    ORDER BY item.ordinal DESC
  LOOP
    v_before := public.workshop_booking_snapshot((v_step->>'id')::uuid);
    v_new_start := (v_step->>'start_at')::timestamptz;
    v_new_end := (v_step->>'end_at')::timestamptz;
    UPDATE public.workshop_bookings
    SET scheduled_start_at = v_new_start,
        scheduled_end_at = v_new_end,
        default_duration_minutes = (v_step->>'duration_minutes')::integer,
        updated_by = auth.uid(),
        version = version + 1
    WHERE id = (v_step->>'id')::uuid
      AND version = (v_step->>'version')::integer
      AND bay_id = p_bay_id
      AND status = 'planned'
      AND deleted_at IS NULL;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'resume_cascade_blocked',
        'message', 'The bay changed while the resume was being saved. Nothing was moved. Refresh and try again.');
    END IF;
    SELECT a.technician_id INTO v_technician
    FROM public.workshop_booking_assignments a
    WHERE a.booking_id = (v_step->>'id')::uuid
      AND a.released_at IS NULL
    ORDER BY CASE WHEN a.assignment_type = 'primary' THEN 0 ELSE 1 END, a.assigned_at DESC
    LIMIT 1;
    PERFORM public.workshop_upsert_primary_assignment(
      (v_step->>'id')::uuid, v_technician, v_new_start, v_new_end, 'cascade_move_shifted');
    v_after := public.workshop_booking_snapshot((v_step->>'id')::uuid);
    PERFORM public.workshop_write_history(
      (v_step->>'id')::uuid, 'cascade_move_shifted', v_before, v_after,
      coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object(
        'source', 'resume_cascade_594',
        'cascade_target_id', p_booking_id,
        'signed_shift_minutes', (v_step->>'shift_minutes')::integer,
        'affected_overlap_chain', true));
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'pushed', v_pushed);
END;
$push594$;

REVOKE ALL ON FUNCTION pdc_ops.push_later_planned_in_bay_594(uuid, uuid, timestamptz, timestamptz, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.resume_workshop_work_pre345(p_booking_id uuid, p_expected_version integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $resume594$
DECLARE
  v_booking public.workshop_bookings%rowtype;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_now timestamptz := now();
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_remaining_minutes integer;
  v_elapsed_minutes integer;
  v_result jsonb;
  v_revision bigint;
  v_push jsonb;
  v_key text;
  v_bay_name text;
  v_tech_name text;
BEGIN
  PERFORM public.workshop_require_planner_operator();
  PERFORM public.workshop_require_version(p_expected_version);
  PERFORM public.workshop_require_booking_active_vehicle(p_booking_id, false);
  SELECT * INTO v_booking FROM public.workshop_bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Workshop booking not found' USING ERRCODE = 'P0002'; END IF;
  IF v_booking.version <> p_expected_version THEN RETURN jsonb_build_object('ok', false, 'error', 'version_conflict'); END IF;
  IF v_booking.status <> 'stoppage' THEN RETURN jsonb_build_object('ok', false, 'error', 'not_stopped'); END IF;
  v_elapsed_minutes := greatest(0, public.workshop_operational_minutes_between(v_booking.scheduled_start_at, coalesce(v_booking.stoppage_started_at, v_now)) - coalesce(v_booking.stoppage_accumulated_minutes, 0));
  v_remaining_minutes := greatest(60, v_booking.default_duration_minutes - greatest(0, v_elapsed_minutes));
  v_new_start := public.workshop_next_calendar_window(v_now, v_remaining_minutes);
  v_new_end := public.workshop_add_operational_minutes(v_new_start, v_remaining_minutes);
  SELECT technician_id INTO v_technician_id
  FROM public.workshop_booking_assignments
  WHERE booking_id = p_booking_id AND released_at IS NULL
  ORDER BY CASE WHEN assignment_type = 'primary' THEN 0 ELSE 1 END, assigned_at DESC
  LIMIT 1;
  PERFORM public.workshop_lock_resources(v_booking.bay_id, v_technician_id);

  BEGIN
    -- r594 (F208): push later planned jobs in this bay, then resume. Do not refuse with an overlap code.
    v_push := pdc_ops.push_later_planned_in_bay_594(p_booking_id, v_booking.bay_id, v_new_start, v_new_end, p_metadata);
    IF coalesce((v_push->>'ok')::boolean, false) IS NOT TRUE THEN
      v_result := v_push;
      RAISE EXCEPTION 'resume cascade blocked' USING ERRCODE = 'P0001';
    END IF;
    v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_booking.bay_id, v_new_start, v_new_end);
    IF v_conflict_id IS NOT NULL THEN
      SELECT coalesce(v.key_number::text, 'another job'), coalesce(nullif(btrim(bay.display_name), ''), 'this bay')
        INTO v_key, v_bay_name
      FROM public.workshop_bookings b
      LEFT JOIN public.vehicles v ON v.id = b.vehicle_id
      LEFT JOIN public.workshop_bays bay ON bay.id = b.bay_id
      WHERE b.id = v_conflict_id;
      v_result := jsonb_build_object('ok', false, 'error', 'resume_cascade_blocked',
        'message', format('Key %s is still in %s, so this resume was not saved. Nothing was moved.', coalesce(v_key, 'another job'), coalesce(v_bay_name, 'this bay')));
      RAISE EXCEPTION 'resume cascade blocked' USING ERRCODE = 'P0001';
    END IF;
    IF v_technician_id IS NOT NULL THEN
      v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, v_new_start, v_new_end);
      IF v_conflict_id IS NOT NULL THEN
        SELECT coalesce(nullif(btrim(t.name), ''), 'This mechanic')
          INTO v_tech_name
        FROM public.workshop_technicians t
        WHERE t.id = v_technician_id;
        v_result := jsonb_build_object('ok', false, 'error', 'resume_cascade_blocked',
          'message', format('%s is already booked on another job then, so this resume was not saved. Nothing was moved.', coalesce(v_tech_name, 'This mechanic')));
        RAISE EXCEPTION 'resume cascade blocked' USING ERRCODE = 'P0001';
      END IF;
    END IF;
    UPDATE public.workshop_bookings
    SET scheduled_start_at = v_new_start,
        scheduled_end_at = v_new_end,
        default_duration_minutes = v_remaining_minutes,
        updated_by = auth.uid(),
        version = version + 1
    WHERE id = p_booking_id;
    PERFORM public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, v_new_start, v_new_end, 'resume_rescheduled');
    v_result := public.workshop_resume_booking(p_booking_id, v_booking.version + 1, p_metadata);
    IF NOT coalesce((v_result->>'ok')::boolean, false) THEN
      RAISE EXCEPTION 'resume not applied' USING ERRCODE = 'P0001';
    END IF;
    v_revision := public.workshop_bump_revision();
    v_result := v_result || jsonb_build_object('revision', v_revision, 'pushed', coalesce(v_push->'pushed', '[]'::jsonb));
  EXCEPTION
    WHEN exclusion_violation THEN
      v_result := jsonb_build_object('ok', false, 'error', 'resume_cascade_blocked',
        'message', 'Resuming would put this vehicle on top of its other booking. Nothing was changed.');
    WHEN SQLSTATE 'P0001' THEN
      IF v_result IS NULL THEN
        v_result := jsonb_build_object('ok', false, 'error', 'resume_cascade_blocked',
          'message', 'This resume was not saved. Nothing was moved.');
      END IF;
  END;
  RETURN v_result;
END;
$resume594$;

DO $g$
DECLARE
  awst time;
  v_tick text;
  v_mover text;
  v_place text;
  v_dept text;
  v_rows text;
  v_apply text;
  v_pins integer;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '12:20' AND time '12:40'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r594: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r594: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r594: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r594: pin count is not 241'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 364 OR fault_id = 'F208' OR check_name = 'resume_cascade_594' OR added_in = 'r594') THEN
    RAISE EXCEPTION 'r594: sort 364 / F208 is taken';
  END IF;
  IF to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'r594: place-after helper is not installed';
  END IF;
  SELECT md5(prosrc) INTO v_tick FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)');
  SELECT md5(prosrc) INTO v_mover FROM pg_proc WHERE oid = to_regprocedure('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)');
  SELECT md5(prosrc) INTO v_place FROM pg_proc WHERE oid = to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)');
  SELECT md5(prosrc) INTO v_dept FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)');
  SELECT md5(prosrc) INTO v_rows FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)');
  SELECT md5(prosrc) INTO v_apply FROM pg_proc WHERE oid = to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)');
  IF v_dept IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r594: department 135 changed'; END IF;
  IF v_rows IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r594: Kajel rows changed'; END IF;
  IF v_apply IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r594: Kajel apply changed'; END IF;
  IF v_mover IS DISTINCT FROM '94a3255ebe52c6327ce028c546d8dbab' THEN RAISE EXCEPTION 'r594: cascade mover is not the r592 body'; END IF;
  IF v_place IS DISTINCT FROM 'dfda4b83016feef586cb49699b34475a' THEN RAISE EXCEPTION 'r594: place-after helper changed'; END IF;
  IF position('pdc_ops.push_later_planned_in_bay_594' IN (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.resume_workshop_work_pre345(uuid,integer,jsonb)'))) = 0 THEN
    RAISE EXCEPTION 'r594: resume does not push';
  END IF;
  IF position('bay_overlap' IN (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.resume_workshop_work_pre345(uuid,integer,jsonb)'))) > 0 THEN
    RAISE EXCEPTION 'r594: resume still returns an overlap code';
  END IF;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES (
    'resume_cascade_594',
    'F208',
    'Resume of a stopped job pushes later planned bookings in that bay and does not return an overlap code. After that push the bay has no overlapping active bookings in the resume window.',
    $chk594$SELECT
  strpos(pre.prosrc, 'pdc_ops.push_later_planned_in_bay_594') > 0
  AND strpos(pre.prosrc, 'bay_overlap') = 0
  AND strpos(pre.prosrc, 'technician_overlap') = 0
  AND strpos(pre.prosrc, 'vehicle_overlap') = 0
  AND strpos(helper.prosrc, 'workshop_admin_next_operational_minute') > 0
  AND strpos(helper.prosrc, 'cascade_move_shifted') > 0
  AND strpos(helper.prosrc, 'affected_overlap_chain') > 0
  AND strpos(helper.prosrc, 'ORDER BY item.ordinal DESC') > 0
  AND strpos(mover.prosrc, 'workshop_admin_next_operational_minute') > 0
  AND strpos(mover.prosrc, 'pdc_ops.place_after_live_bay_592') > 0
  AND strpos(wrap.prosrc, 'resume_workshop_work_pre345') > 0
  AND md5(mover.prosrc) = '94a3255ebe52c6327ce028c546d8dbab'
  AND md5(place.prosrc) = 'dfda4b83016feef586cb49699b34475a'
  AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
  AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) = '9be0883b1a555f48f3c1ba9fa111c891'
  AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) = 'b62fb7c29ffd2a1629f214f696e5cb14'
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
  AND NOT has_function_privilege('anon', 'pdc_ops.push_later_planned_in_bay_594(uuid,uuid,timestamptz,timestamptz,jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'pdc_ops.push_later_planned_in_bay_594(uuid,uuid,timestamptz,timestamptz,jsonb)', 'EXECUTE')
 AS ok,
 'resume push ' || strpos(pre.prosrc, 'pdc_ops.push_later_planned_in_bay_594')::text
   || ' overlap-code ' || strpos(pre.prosrc, 'bay_overlap')::text AS detail
FROM pg_proc pre
CROSS JOIN pg_proc helper ON helper.oid = 'pdc_ops.push_later_planned_in_bay_594(uuid,uuid,timestamptz,timestamptz,jsonb)'::regprocedure
CROSS JOIN pg_proc mover ON mover.oid = 'public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure
CROSS JOIN pg_proc place ON place.oid = 'pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)'::regprocedure
CROSS JOIN pg_proc wrap ON wrap.oid = 'public.resume_workshop_work(uuid,integer,jsonb)'::regprocedure
WHERE pre.oid = 'public.resume_workshop_work_pre345(uuid,integer,jsonb)'::regprocedure
$chk594$,
    true,
    364,
    'r594'
  );

  SELECT count(*) INTO v_pins FROM pdc_ops.expected_function_md5;
  IF v_pins <> 241 THEN RAISE EXCEPTION 'r594: pin count changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM v_tick THEN
    RAISE EXCEPTION 'r594: clock tick changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)')) IS DISTINCT FROM v_mover THEN
    RAISE EXCEPTION 'r594: cascade mover changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)')) IS DISTINCT FROM v_place THEN
    RAISE EXCEPTION 'r594: place-after helper changed';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'resume_cascade_594' AND fault_id = 'F208' AND sort_order = 364 AND added_in = 'r594' AND enabled) <> 1 THEN
    RAISE EXCEPTION 'r594: check missing';
  END IF;
END $g$;
