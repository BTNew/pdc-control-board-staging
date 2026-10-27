-- r592 (F206) / sort 360. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- r588 / F202 is the side-panel tick grid (#573) and inserted no check. r589 / F203 / sort 361 is the open Parts ETA release (#571).
-- r590 / F204 is the QC sign-off label named by the Revolution preview. r591 / F205 / sort 362 is that preview (#575).
-- Sort 356 / r584 / F198 stays with #498. This release takes the free sort 360 with the next free r and F.
-- Craig, 28 Oct 2026 06:31 AWST: fix the Hoist drop. Key 460 (stock 13071838) onto Jason Ranoco
-- was refused before any later job moved. Key 328 is running and its real end is later than the
-- chip, so the 12 hour window overlaps that running job and the mover returns live_booking_conflict.
-- Place the dropped job at the next working minute at or after that running job, and push the
-- later planned jobs in the bay. The planner asks first. Nothing in this migration books Key 460.
-- PR #498 keeps r584 / F198 / sort 356. r587 / F201 / sort 359 is the QC nesting release.
-- Pin count stays 241. No pin is inserted. administrator_move stays the r571 pin.
-- Department 135 fitter_job_command stays fd05b9eef69498002ac06dd68e01cdff.
-- Kajel rows stay 9be0883b1a555f48f3c1ba9fa111c891 and apply stays b62fb7c29ffd2a1629f214f696e5cb14.
-- Undo: supabase/rollbacks/20261028081000_r592_hoist_place_after.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$
DECLARE awst time;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF (awst >= time '06:50' AND awst < time '07:30')
     OR (awst >= time '12:20' AND awst < time '12:40')
     OR (awst >= time '17:50' AND awst < time '18:10') THEN
    RAISE EXCEPTION 'r592: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r592: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r592: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r592: pin count is not 241'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='board_qc_nesting_587' AND fault_id='F201' AND sort_order=359 AND added_in='r587') THEN RAISE EXCEPTION 'r592: r587 / F201 sort 359 is not present'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=356 OR fault_id='F198' OR added_in='r584') THEN RAISE EXCEPTION 'r592: sort 356 / F198 is taken; leave that preview its number'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=360 OR fault_id='F206' OR check_name='hoist_place_after_592' OR added_in='r592') THEN RAISE EXCEPTION 'r592: sort 360 / F206 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)')) IS DISTINCT FROM 'fa78dfb941af8fd86ca705890d4bf798' THEN RAISE EXCEPTION 'r592: cascade mover is not the live body'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '6a02115d30578e8eb3807a283b1d60ea' THEN RAISE EXCEPTION 'r592: administrator move changed'; END IF;
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)' AND release='r571') IS DISTINCT FROM '6a02115d30578e8eb3807a283b1d60ea' THEN RAISE EXCEPTION 'r592: move pin is not r571'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r592: department 135 changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r592: fitter command changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r592: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r592: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r592: clock tick changed'; END IF;
  IF to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r592: helper already exists'; END IF;
END $g$;

CREATE FUNCTION pdc_ops.place_after_live_bay_592(
  p_booking_id uuid,
  p_bay_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_minutes integer,
  p_metadata jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $fn$
DECLARE
  v_live_end timestamptz;
  v_place timestamptz;
  v_place_end timestamptz;
  v_key text;
  v_bay_name text;
  v_bay_number integer;
  v_hash text;
  v_pushes jsonb := '[]'::jsonb;
  v_chain jsonb := '[]'::jsonb;
  v_cursor timestamptz;
  v_row record;
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_row_minutes integer;
BEGIN
  -- r592 (F206): a drop whose window overlaps a started or stopped job in this bay
  -- is placed at the next working minute at or after that job's real end. The running
  -- job stays where it is. Later planned jobs in the bay move back. The planner confirms first.
  SELECT max(public.workshop_booking_effective_end_at(b.id))
    INTO v_live_end
  FROM public.workshop_bookings b
  WHERE b.bay_id = p_bay_id
    AND b.deleted_at IS NULL
    AND b.id IS DISTINCT FROM p_booking_id
    AND b.status IN ('started', 'stoppage')
    AND b.scheduled_start_at < p_end
    AND public.workshop_booking_effective_end_at(b.id) > p_start;
  IF v_live_end IS NULL THEN
    RETURN jsonb_build_object('action', 'none');
  END IF;

  v_place := public.workshop_admin_next_operational_minute(v_live_end);
  IF v_place IS NOT NULL AND v_place < v_live_end THEN
    v_place := public.workshop_admin_next_operational_minute(v_live_end + interval '1 minute');
  END IF;
  IF v_place IS NULL OR v_place < v_live_end THEN
    RETURN jsonb_build_object('action', 'fail', 'body', jsonb_build_object('ok', false, 'error', 'calendar_unavailable'));
  END IF;
  v_place_end := COALESCE(
    CASE WHEN public.workshop_bay_has_hours_570(p_bay_id)
      THEN public.workshop_bay_add_minutes_570(v_place, p_minutes, p_bay_id) END,
    public.workshop_add_operational_minutes(v_place, p_minutes));
  IF v_place_end IS NULL OR v_place_end <= v_place THEN
    RETURN jsonb_build_object('action', 'fail', 'body', jsonb_build_object('ok', false, 'error', 'calendar_unavailable'));
  END IF;

  SELECT v.key_number::text, bay.display_name, bay.bay_number
    INTO v_key, v_bay_name, v_bay_number
  FROM public.workshop_bookings b
  JOIN public.workshop_bays bay ON bay.id = b.bay_id
  LEFT JOIN public.vehicles v ON v.id = b.vehicle_id
  WHERE b.bay_id = p_bay_id
    AND b.deleted_at IS NULL
    AND b.status IN ('started', 'stoppage')
    AND public.workshop_booking_effective_end_at(b.id) = v_live_end
  ORDER BY b.scheduled_start_at, b.id
  LIMIT 1;

  v_cursor := v_place_end;
  FOR v_row IN
    SELECT b.id, b.version, b.scheduled_start_at, b.vehicle_id, b.stage_id, b.bay_id, v.key_number::text AS key_number
    FROM public.workshop_bookings b
    LEFT JOIN public.vehicles v ON v.id = b.vehicle_id
    WHERE b.bay_id = p_bay_id
      AND b.id IS DISTINCT FROM p_booking_id
      AND b.status = 'planned'
      AND b.deleted_at IS NULL
      AND public.workshop_booking_effective_end_at(b.id) > v_place
    ORDER BY b.scheduled_start_at, b.id
  LOOP
    EXIT WHEN v_row.scheduled_start_at >= v_cursor;
    v_new_start := public.workshop_admin_next_operational_minute(v_cursor);
    v_row_minutes := coalesce(
      public.workshop_booking_capacity_duration_minutes(v_row.id, v_row.vehicle_id, v_row.stage_id, v_row.bay_id),
      public.workshop_booking_effective_duration_minutes(v_row.id));
    v_new_end := public.workshop_add_operational_minutes(v_new_start, v_row_minutes);
    IF v_new_start IS NULL OR v_row_minutes IS NULL OR v_row_minutes < 1
       OR v_new_end IS NULL OR v_new_end <= v_new_start THEN
      RETURN jsonb_build_object('action', 'fail', 'body', jsonb_build_object('ok', false, 'error', 'calendar_unavailable'));
    END IF;
    v_pushes := v_pushes || jsonb_build_array(jsonb_build_object(
      'id', v_row.id,
      'key_number', v_row.key_number,
      'bay_number', v_bay_number,
      'from_start', v_row.scheduled_start_at,
      'to_start', v_new_start));
    v_chain := v_chain || jsonb_build_array(jsonb_build_object(
      'id', v_row.id, 'version', v_row.version, 'to', v_new_start));
    v_cursor := v_new_end;
  END LOOP;

  v_hash := md5(jsonb_build_object(
    'booking', p_booking_id, 'bay', p_bay_id, 'place', v_place, 'minutes', p_minutes, 'chain', v_chain)::text);
  IF coalesce(p_metadata #>> '{place_after_confirm,plan_hash}', '') IS DISTINCT FROM v_hash THEN
    RETURN jsonb_build_object('action', 'warn', 'body', jsonb_build_object(
      'ok', false,
      'warning', true,
      'requires_confirmation', true,
      'error', 'place_after_running',
      'plan_hash', v_hash,
      'place_after', v_place,
      'running_until', v_live_end,
      'running_key', v_key,
      'bay_name', v_bay_name,
      'bay_number', v_bay_number,
      'message', format('Key %s is already running in %s until %s. Place this job right after it? Later jobs in this bay move back.',
        coalesce(nullif(v_key, ''), 'a job'),
        coalesce(nullif(btrim(v_bay_name), ''), 'this bay'),
        to_char(v_live_end AT TIME ZONE 'Australia/Perth', 'Dy DD Mon HH24:MI')),
      'pushes', v_pushes));
  END IF;
  RETURN jsonb_build_object('action', 'snap', 'start_at', v_place, 'end_at', v_place_end);
END;
$fn$;

REVOKE ALL ON FUNCTION pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb) FROM PUBLIC, anon, authenticated;

DO $patch$
DECLARE
  def text;
  old text := $old$
  if exists (
    select 1 from public.workshop_bookings b
    where b.bay_id=v_bay.id and b.deleted_at is null
      and b.status in('started','stoppage')
      and b.scheduled_start_at<v_target_end
      and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at
  ) then return jsonb_build_object('ok',false,'error','live_booking_conflict'); end if;$old$;
  new text := $new$
  declare v592 jsonb;
  begin
    v592 := pdc_ops.place_after_live_bay_592(p_booking_id, v_bay.id, p_scheduled_start_at, v_target_end, v_target_duration, p_metadata);
    if v592->>'action' = 'warn' or v592->>'action' = 'fail' then
      return v592->'body';
    elsif v592->>'action' = 'snap' then
      p_scheduled_start_at := (v592->>'start_at')::timestamptz;
      v_target_end := (v592->>'end_at')::timestamptz;
    elsif coalesce(v592->>'action','') <> 'none' then
      return jsonb_build_object('ok',false,'error','calendar_unavailable');
    end if;
  end;$new$;
BEGIN
  SELECT pg_get_functiondef('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure) INTO def;
  IF (length(def) - length(replace(def, old, ''))) / length(old) <> 2 THEN
    RAISE EXCEPTION 'r592: live-job guard was not found twice';
  END IF;
  EXECUTE replace(def, old, new);
  IF (SELECT (length(prosrc) - length(replace(prosrc, 'pdc_ops.place_after_live_bay_592(', ''))) / length('pdc_ops.place_after_live_bay_592(')
      FROM pg_proc WHERE oid = 'public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure) <> 2 THEN
    RAISE EXCEPTION 'r592: place-after call was not patched twice';
  END IF;
  IF (SELECT strpos(prosrc, 'live_booking_conflict') FROM pg_proc WHERE oid = 'public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure) <> 0 THEN
    RAISE EXCEPTION 'r592: the cascade mover still refuses a running job';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '6a02115d30578e8eb3807a283b1d60ea' THEN
    RAISE EXCEPTION 'r592: administrator move changed during the patch';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r592: pin count moved'; END IF;
END $patch$;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('hoist_place_after_592', 'F206', 'A drop onto a running or stopped bay job asks to place the job after it and push the later jobs (r592). Key 460 after Key 328. A valid place-after drop must not come back as live_booking_conflict, the code the planner shows as "This change conflicts with a job already running or on stoppage".',
$chk$
SELECT
  (length(src) - length(replace(src, 'pdc_ops.place_after_live_bay_592(', ''))) / length('pdc_ops.place_after_live_bay_592(') = 2
  AND strpos(src, 'live_booking_conflict') = 0
  AND strpos(helper, 'place_after_running') > 0
  AND strpos(helper, 'Place this job right after it') > 0
  AND strpos(helper, 'conflicts with a job already running') = 0
  AND strpos(helper, 'r592 (F206)') > 0
  AND strpos(mv, 'place_after_running') = 0
  AND md5(mv) = '6a02115d30578e8eb3807a283b1d60ea'
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
  AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
  AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) = '9be0883b1a555f48f3c1ba9fa111c891'
  AND (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) = 'b62fb7c29ffd2a1629f214f696e5cb14'
  AND NOT has_function_privilege('anon', 'pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)', 'EXECUTE')
  AS ok,
  'place-after calls '||((length(src) - length(replace(src, 'pdc_ops.place_after_live_bay_592(', ''))) / length('pdc_ops.place_after_live_bay_592('))::text
  ||', live_booking_conflict '||strpos(src, 'live_booking_conflict')::text AS detail
FROM pg_proc mover
CROSS JOIN LATERAL (SELECT mover.prosrc AS src) s
CROSS JOIN LATERAL (
  SELECT prosrc AS helper FROM pg_proc WHERE oid = 'pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)'::regprocedure
) h
CROSS JOIN LATERAL (
  SELECT prosrc AS mv FROM pg_proc WHERE oid = to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')
) m
WHERE mover.oid = 'public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure
$chk$,
true, 360, 'r592');
