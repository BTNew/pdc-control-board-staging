-- r600 (F214) / sorts 370 and 371. Staging cdsmnqxtyyoeoznmbidd only.
-- The clock pushes later jobs when one overruns. A vehicle's own stoppage does not freeze the other bays.
-- A held workshop lock skips the minute instead of failing the tick.
-- Resume pushes later planned jobs in that bay.
-- The cross-bay overlap guard stays off.
-- The clock tick runs once here and clears same-bay overlaps.
-- Pin count stays 241. The clock pin text is updated in place. Its release stays r577.
-- Undo: supabase/rollbacks/20261028120000_r600_clock_resume.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '180s';

DO $gate$
DECLARE
  awst time;
  started timestamptz := clock_timestamp();
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '12:20' AND time '12:40'
     OR awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r600: Kajel import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r600: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r600: pin count is not 241'; END IF;
  IF EXISTS (
    SELECT 1 FROM pdc_ops.regression_checks
    WHERE sort_order IN (370, 371) OR fault_id = 'F214' OR added_in = 'r600'
       OR check_name IN ('no_overlapping_active_bookings_600', 'resume_cascade_600')
  ) THEN RAISE EXCEPTION 'r600: sort 370, sort 371 or F214 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.resume_workshop_work_pre345(uuid,integer,jsonb)')) IS DISTINCT FROM '336941bde80a3511cc6ebd54eb00c716' THEN
    RAISE EXCEPTION 'r600: resume body changed';
  END IF;
END $gate$;

CREATE OR REPLACE FUNCTION pdc_ops.push_later_planned_in_bay_600(
  p_booking_id uuid,
  p_bay_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_metadata jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $push597$
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
        'source', 'resume_cascade_600',
        'cascade_target_id', p_booking_id,
        'signed_shift_minutes', (v_step->>'shift_minutes')::integer,
        'affected_overlap_chain', true));
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'pushed', v_pushed);
END;
$push597$;

REVOKE ALL ON FUNCTION pdc_ops.push_later_planned_in_bay_600(uuid, uuid, timestamptz, timestamptz, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.resume_workshop_work_pre345(p_booking_id uuid, p_expected_version integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $resume597$
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
    -- r600 (F214): push later planned jobs in this bay, then resume. Do not refuse with an overlap code.
    v_push := pdc_ops.push_later_planned_in_bay_600(p_booking_id, v_booking.bay_id, v_new_start, v_new_end, p_metadata);
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
$resume597$;



DO $clk$
DECLARE
  src text;
  step text;
  old_step text := 'IF v_clock>p_scheduled_end THEN v_clock_proj:=to_timestamp(floor(extract(epoch FROM v_clock)/900.0)*900.0); ELSE v_clock_proj:=p_scheduled_end; END IF;';
  new_step text := '-- r600 (F214): a running overrun steps at least 15 minutes ahead, so the next job starts after the live bar.' || E'\n' || ' IF v_clock>p_scheduled_end THEN v_clock_proj:=to_timestamp(ceil(extract(epoch FROM v_clock + interval ''15 minutes'')/900.0)*900.0); ELSE v_clock_proj:=p_scheduled_end; END IF;';
  old_lock text := ' PERFORM pg_advisory_xact_lock(hashtextextended(''pdc:workshop:top-level-mutation'',0));';
  new_lock text := ' -- r600 (F214): try the workshop change lock, wait, and try again. A held lock skips this minute. It is not a failed tick.' || E'\n'
    || ' FOR loop_count IN 1..4 LOOP' || E'\n'
    || '  EXIT WHEN pg_try_advisory_xact_lock(hashtextextended(''pdc:workshop:top-level-mutation'',0));' || E'\n'
    || '  PERFORM pg_sleep(1);' || E'\n'
    || ' END LOOP;' || E'\n'
    || ' IF NOT pg_try_advisory_xact_lock(hashtextextended(''pdc:workshop:top-level-mutation'',0)) THEN' || E'\n'
    || '  RETURN jsonb_build_object(''ok'',true,''skipped'',''locked'',''moved_count'',0,''plans'',''[]''::jsonb,''issues'',''[]''::jsonb);' || E'\n'
    || ' END IF;';
  old_order text := '     AND (a.bay_id=b.bay_id OR a.vehicle_id=b.vehicle_id OR a.technicians && b.technicians)' || E'\n'
    || '     AND a.final_end+CASE WHEN a.vehicle_id=b.vehicle_id AND pdc_ops.cross_bay_vehicle_guard_on() THEN interval ''1 hour'' ELSE interval ''0 minutes'' END>b.final_start) THEN';
  new_order text := '     AND (a.bay_id=b.bay_id OR a.vehicle_id=b.vehicle_id OR a.technicians && b.technicians)' || E'\n'
    || '     -- r600 (F214): a vehicle''s own stoppage is not an order anchor. One stoppage must not freeze the other bays.' || E'\n'
    || '     AND a.status<>''stoppage''' || E'\n'
    || '     AND b.status<>''stoppage''' || E'\n'
    || '     AND a.final_end+CASE WHEN a.vehicle_id=b.vehicle_id AND pdc_ops.cross_bay_vehicle_guard_on() THEN interval ''1 hour'' ELSE interval ''0 minutes'' END>b.final_start) THEN';
  old_item text := 'FOR item IN SELECT * FROM pg_temp.clock_linked_plan WHERE component_id=component.component_id AND changed ORDER BY ordinal DESC LOOP';
  old_end text := '     component_moved:=component_moved+1;' || E'\n' || '    END LOOP;';
  new_end text := '     component_moved:=component_moved+1;' || E'\n'
    || '    EXCEPTION WHEN SQLSTATE ''22023'' OR SQLSTATE ''23514'' OR SQLSTATE ''23P01'' OR SQLSTATE ''40001'' OR lock_not_available THEN GET STACKED DIAGNOSTICS state_code=RETURNED_SQLSTATE, detail=MESSAGE_TEXT; issues:=issues||jsonb_build_array(jsonb_build_object(''skipped'', item.id, ''code'', state_code, ''detail'', left(detail, 160))); END;' || E'\n'
    || '    END LOOP;';
  tick jsonb;
  overlaps_before integer;
  overlaps_after integer;
  chk record;
  n integer;
  move text;
  board text;
  ok boolean;
  detail text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pdc_ops.regression_checks
    WHERE check_name = 'outstanding_station_hours_594' AND fault_id = 'F208' AND sort_order = 364 AND added_in = 'r594'
  ) THEN RAISE EXCEPTION 'r600: r594 / F208 sort 364 is not the hours check'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3d78391f7a48da603c2fe588c27af5cd' THEN
    RAISE EXCEPTION 'r600: clock tick is not the r577 body';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_step_552(timestamptz,timestamptz,timestamptz,timestamptz,uuid)')) IS DISTINCT FROM '7e356c4beca9cad6983f0f8c629e3e85' THEN
    RAISE EXCEPTION 'r600: clock step changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)')) IS DISTINCT FROM '94a3255ebe52c6327ce028c546d8dbab' THEN
    RAISE EXCEPTION 'r600: cascade mover changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
    RAISE EXCEPTION 'r600: department 135 changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN
    RAISE EXCEPTION 'r600: Kajel rows changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN
    RAISE EXCEPTION 'r600: Kajel apply changed';
  END IF;

  SELECT count(*) INTO overlaps_before
  FROM public.workshop_bookings a
  JOIN public.workshop_bookings b ON a.bay_id = b.bay_id AND a.id < b.id
  WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL AND a.bay_id IS NOT NULL
    AND a.status IN ('planned','queued','started','stoppage')
    AND b.status IN ('planned','queued','started','stoppage')
    AND tstzrange(a.scheduled_start_at, CASE WHEN a.status = 'started' AND clock_timestamp() > a.scheduled_end_at THEN clock_timestamp() ELSE a.scheduled_end_at END, '[)')
     && tstzrange(b.scheduled_start_at, CASE WHEN b.status = 'started' AND clock_timestamp() > b.scheduled_end_at THEN clock_timestamp() ELSE b.scheduled_end_at END, '[)');

  SELECT prosrc INTO step FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_step_552(timestamptz,timestamptz,timestamptz,timestamptz,uuid)');
  IF (length(step) - length(replace(step, old_step, ''))) <> length(old_step) THEN RAISE EXCEPTION 'r600: clock step line is not unique'; END IF;
  step := replace(step, old_step, new_step);
  EXECUTE 'CREATE OR REPLACE FUNCTION public.workshop_clock_step_552(p_scheduled_end timestamptz, p_effective_end timestamptz, p_now timestamptz, p_accounted timestamptz, p_calendar_bay uuid) RETURNS timestamptz LANGUAGE plpgsql STABLE SET search_path TO pg_catalog, public AS $step595$' || step || '$step595$';

  SELECT prosrc INTO src FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)');
  IF (length(src) - length(replace(src, old_lock, ''))) <> length(old_lock) THEN RAISE EXCEPTION 'r600: clock lock line is not unique'; END IF;
  IF (length(src) - length(replace(src, old_order, ''))) <> length(old_order) THEN RAISE EXCEPTION 'r600: clock order check is not unique'; END IF;
  IF (length(src) - length(replace(src, old_item, ''))) <> length(old_item) THEN RAISE EXCEPTION 'r600: clock apply loop is not unique'; END IF;
  IF (length(src) - length(replace(src, old_end, ''))) <> length(old_end) THEN RAISE EXCEPTION 'r600: clock apply end is not unique'; END IF;
  src := replace(src, old_lock, new_lock);
  src := replace(src, 'PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN(''planned'',''queued'',''started'',''stoppage'') ORDER BY id FOR UPDATE;',
                      'PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN(''planned'',''queued'',''started'',''stoppage'') ORDER BY id FOR UPDATE SKIP LOCKED;');
  src := replace(src, 'PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE;',
                      'PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE SKIP LOCKED;');
  src := replace(src, 'PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE;',
                      'PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE SKIP LOCKED;');
  src := replace(src, old_order, new_order);
  src := replace(src, old_item, old_item || ' BEGIN');
  src := replace(src, old_end, new_end);
  IF strpos(src, 'a.status<>''stoppage''') = 0 OR strpos(src, '''skipped'',''locked''') = 0 OR strpos(src, '''skipped'', item.id') = 0 OR strpos(src, 'SKIP LOCKED') = 0 THEN
    RAISE EXCEPTION 'r600: clock tick patch missed';
  END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true, p_now timestamptz DEFAULT clock_timestamp()) RETURNS jsonb LANGUAGE plpgsql SET search_path TO pg_catalog, public SET lock_timeout TO ''3s'' SET statement_timeout TO ''120s'' AS $tick595$' || src || '$tick595$';
  IF (SELECT proacl::text FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '{postgres=X/postgres}' THEN
    RAISE EXCEPTION 'r600: clock tick acl drifted';
  END IF;
  IF (SELECT proconfig FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM ARRAY['search_path=pg_catalog, public','lock_timeout=3s','statement_timeout=120s']::text[] THEN
    RAISE EXCEPTION 'r600: clock tick settings drifted';
  END IF;

  IF to_regprocedure('pdc_ops.push_later_planned_in_bay_600(uuid,uuid,timestamptz,timestamptz,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'r600: resume push helper is missing';
  END IF;
  IF position('pdc_ops.push_later_planned_in_bay_600' IN (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.resume_workshop_work_pre345(uuid,integer,jsonb)'))) = 0 THEN
    RAISE EXCEPTION 'r600: resume does not push';
  END IF;
  IF position('bay_overlap' IN (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.resume_workshop_work_pre345(uuid,integer,jsonb)'))) > 0 THEN
    RAISE EXCEPTION 'r600: resume still names an overlap code';
  END IF;
  IF has_function_privilege('anon', 'pdc_ops.push_later_planned_in_bay_600(uuid,uuid,timestamptz,timestamptz,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'pdc_ops.push_later_planned_in_bay_600(uuid,uuid,timestamptz,timestamptz,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'r600: resume push helper is executable by the client';
  END IF;

  UPDATE pdc_ops.expected_function_md5 SET
    prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')),
    note = 'r600: a stoppage does not block the clock, an overrun steps 15 minutes ahead, and a lock skip is not a failure (was 3d78391f7a48da603c2fe588c27af5cd, r577)',
    updated_at = now()
  WHERE signature = 'public.workshop_clock_tick(boolean,timestamp with time zone)'
    AND prosrc_md5 = '3d78391f7a48da603c2fe588c27af5cd'
    AND release = 'r577';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r600: clock pin was not moved'; END IF;

  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql, '3d78391f7a48da603c2fe588c27af5cd',
        (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')))
  WHERE check_name IN ('schedule_stale_version_window_552','read_once_snapshots_554','bay_job_pause_569','parts_eta_stoppage_573','qc_signoff_override_590','pilbara_apply_lock_timeout_596')
    AND check_sql LIKE '%3d78391f7a48da603c2fe588c27af5cd%';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 6 THEN RAISE EXCEPTION 'r600: expected 6 tick checksum checks, updated %', n; END IF;

  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(replace(check_sql,
        'gate.one_min IS NULL', 'gate.one_min=''2026-10-26 06:30:00+00''::timestamptz'),
        'gate.quarter=''2026-10-26 06:15:00+00''::timestamptz', 'gate.quarter=''2026-10-26 06:45:00+00''::timestamptz')
  WHERE check_name = 'clock_tick_resaves_per_tick'
    AND check_sql LIKE '%one_min IS NULL%';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r600: resave expectations were not updated'; END IF;

  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql,
        'f AS (SELECT * FROM d WHERE status<>''succeeded'')',
        'f AS (SELECT * FROM d WHERE status<>''succeeded'' AND start_time>(SELECT updated_at FROM pin))')
  WHERE check_name = 'clock_ticks_recent'
    AND check_sql LIKE '%f AS (SELECT * FROM d WHERE status<>''succeeded'')%';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r600: clock failure window was not moved to this pin'; END IF;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES (
    'no_overlapping_active_bookings_600',
    'F214',
    'No overlapping active bookings in any bay. A running overrun steps at least 15 minutes ahead. A vehicle''s own stoppage does not block that push. A lock skip is not a failure.',
    $overlap598$
SELECT
  pins.n = 241
  AND tick_pin.release = 'r577'
  AND tick_pin.prosrc_md5 = pg_catalog.md5(tick.prosrc)
  AND pg_catalog.strpos(tick.prosrc, 'a.status<>''stoppage''') > 0
  AND pg_catalog.strpos(tick.prosrc, 'b.status<>''stoppage''') > 0
  AND pg_catalog.strpos(tick.prosrc, '''skipped'',''locked''') > 0
  AND pg_catalog.strpos(tick.prosrc, 'FOR UPDATE SKIP LOCKED') > 0
  AND pg_catalog.strpos(step.prosrc, 'v_clock + interval ''15 minutes''') > 0
  AND public.workshop_clock_step_552('2026-10-26 06:00:00+00', '2026-10-26 06:00:00+00', '2026-10-26 06:01:00+00', '2026-10-26 06:00:00+00', NULL) = '2026-10-26 06:30:00+00'::timestamptz
  AND public.workshop_clock_step_552('2026-10-26 06:00:00+00', '2026-10-26 06:00:00+00', '2026-10-26 06:16:00+00', '2026-10-26 06:00:00+00', NULL) = '2026-10-26 06:45:00+00'::timestamptz
  AND active_overlap.n = 0
  AND (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
  AND (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) = (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)')
 AS ok,
 active_overlap.n::text || ' overlapping active bookings' AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT prosrc_md5, release FROM pdc_ops.expected_function_md5 WHERE signature = 'public.workshop_clock_tick(boolean,timestamp with time zone)') tick_pin
CROSS JOIN pg_catalog.pg_proc tick
CROSS JOIN pg_catalog.pg_proc step
CROSS JOIN (
  SELECT count(*) AS n
  FROM public.workshop_bookings a
  JOIN public.workshop_bookings b ON a.bay_id = b.bay_id AND a.id < b.id
  WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL AND a.bay_id IS NOT NULL
    AND a.status IN ('planned','queued','started','stoppage')
    AND b.status IN ('planned','queued','started','stoppage')
    AND tstzrange(a.scheduled_start_at, CASE WHEN a.status = 'started' AND pg_catalog.now() > a.scheduled_end_at THEN pg_catalog.now() ELSE a.scheduled_end_at END, '[)')
     && tstzrange(b.scheduled_start_at, CASE WHEN b.status = 'started' AND pg_catalog.now() > b.scheduled_end_at THEN pg_catalog.now() ELSE b.scheduled_end_at END, '[)')
) active_overlap
WHERE tick.oid = pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')
  AND step.oid = pg_catalog.to_regprocedure('public.workshop_clock_step_552(timestamptz,timestamptz,timestamptz,timestamptz,uuid)')
$overlap598$,
    true, 370, 'r600'
  );

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES (
    'resume_cascade_600',
    'F214',
    'Resume of a stopped job pushes later planned bookings in that bay and does not return an overlap code.',
    $resume598$
SELECT
  pg_catalog.strpos(pre.prosrc, 'pdc_ops.push_later_planned_in_bay_600') > 0
  AND pg_catalog.strpos(pre.prosrc, 'bay_overlap') = 0
  AND pg_catalog.strpos(pre.prosrc, 'technician_overlap') = 0
  AND pg_catalog.strpos(helper.prosrc, 'ORDER BY item.ordinal DESC') > 0
  AND NOT pg_catalog.has_function_privilege('anon', 'pdc_ops.push_later_planned_in_bay_600(uuid,uuid,timestamptz,timestamptz,jsonb)', 'EXECUTE')
  AND NOT pg_catalog.has_function_privilege('authenticated', 'pdc_ops.push_later_planned_in_bay_600(uuid,uuid,timestamptz,timestamptz,jsonb)', 'EXECUTE')
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'resume push' AS detail
FROM pg_catalog.pg_proc pre
CROSS JOIN pg_catalog.pg_proc helper
WHERE pre.oid = pg_catalog.to_regprocedure('public.resume_workshop_work_pre345(uuid,integer,jsonb)')
  AND helper.oid = pg_catalog.to_regprocedure('pdc_ops.push_later_planned_in_bay_600(uuid,uuid,timestamptz,timestamptz,jsonb)')
$resume598$,
    true, 371, 'r600'
  );

  tick := public.workshop_clock_tick(true, clock_timestamp());
  SELECT count(*) INTO overlaps_after
  FROM public.workshop_bookings a
  JOIN public.workshop_bookings b ON a.bay_id = b.bay_id AND a.id < b.id
  WHERE a.deleted_at IS NULL AND b.deleted_at IS NULL AND a.bay_id IS NOT NULL
    AND a.status IN ('planned','queued','started','stoppage')
    AND b.status IN ('planned','queued','started','stoppage')
    AND tstzrange(a.scheduled_start_at, CASE WHEN a.status = 'started' AND clock_timestamp() > a.scheduled_end_at THEN clock_timestamp() ELSE a.scheduled_end_at END, '[)')
     && tstzrange(b.scheduled_start_at, CASE WHEN b.status = 'started' AND clock_timestamp() > b.scheduled_end_at THEN clock_timestamp() ELSE b.scheduled_end_at END, '[)');
  IF overlaps_after <> 0 THEN
    RAISE EXCEPTION 'r600: overlaps before=% after=% moved=% issues=%', overlaps_before, overlaps_after, tick->>'moved_count', left(coalesce(tick->'issues','[]'::jsonb)::text, 400);
  END IF;

  FOR chk IN
    SELECT check_name, check_sql FROM pdc_ops.regression_checks
    WHERE check_name IN ('no_overlapping_active_bookings_600','resume_cascade_600')
  LOOP
    EXECUTE chk.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN
      RAISE EXCEPTION 'r600: % red: %', chk.check_name, left(coalesce(detail, ''), 300);
    END IF;
  END LOOP;

  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r600: pin count changed'; END IF;
  IF (SELECT cross_bay_vehicle_guard FROM pdc_ops.workshop_guard_599) IS DISTINCT FROM false THEN RAISE EXCEPTION 'r600: cross-bay guard was turned on'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
    RAISE EXCEPTION 'r600: department 135 changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'))
     IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') THEN
    RAISE EXCEPTION 'r600: the drop path changed';
  END IF;
END $clk$;
