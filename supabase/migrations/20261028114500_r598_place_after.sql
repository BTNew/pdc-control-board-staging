-- r598 (F212) / sort 368. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- A drop onto a bay with a running job places itself after that job's real end
-- and the later jobs move back in the same step. There is no OK dialog.
-- Key 460 is not booked. Pin count stays 241. Only this helper's text changes.
-- Undo: supabase/rollbacks/20261028114500_r598_place_after.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $r598$
DECLARE
  awst time;
  def text;
  old_ask text := 'The planner confirms first.';
  new_ask text := 'r598 (F212): the same drop places it there. There is no question.';
  old_gate text := $gate$  IF coalesce(p_metadata #>> '{place_after_confirm,plan_hash}', '') IS DISTINCT FROM v_hash THEN
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
$gate$;
  n integer;
  ok boolean;
  detail text;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r598: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r598: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
    RAISE EXCEPTION 'r598: pin count is not 241';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pdc_ops.regression_checks
    WHERE sort_order = 368 OR fault_id = 'F212' OR added_in = 'r598' OR check_name = 'place_after_no_prompt_598'
  ) THEN
    RAISE EXCEPTION 'r598: sort 368 or F212 is taken';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)'))
     IS DISTINCT FROM 'dfda4b83016feef586cb49699b34475a' THEN
    RAISE EXCEPTION 'r598: place-after helper is not the r592 body';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
     IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
    RAISE EXCEPTION 'r598: department 135 changed';
  END IF;

  def := pg_get_functiondef('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)'::regprocedure);
  IF (length(def) - length(replace(def, old_ask, ''))) <> length(old_ask) THEN
    RAISE EXCEPTION 'r598: confirm sentence is not unique';
  END IF;
  IF (length(def) - length(replace(def, old_gate, ''))) <> length(old_gate) THEN
    RAISE EXCEPTION 'r598: confirm gate is not unique';
  END IF;
  def := replace(replace(def, old_ask, new_ask), old_gate, '');
  EXECUTE def;

  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql,
        E'  AND strpos(helper, ''place_after_running'') > 0\n  AND strpos(helper, ''Place this job right after it'') > 0',
        E'  AND strpos(helper, ''place_after_confirm'') = 0\n  AND strpos(helper, ''r598 (F212)'') > 0')
  WHERE check_name = 'hoist_place_after_592'
    AND check_sql LIKE '%Place this job right after it%';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r598: hoist check was not retargeted'; END IF;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES (
    'place_after_no_prompt_598',
    'F212',
    'A drop onto a running job places itself after that job. The helper does not ask for confirmation.',
    $chk598$
SELECT
  pg_catalog.strpos(helper.prosrc, 'place_after_confirm') = 0
  AND pg_catalog.strpos(helper.prosrc, 'r598 (F212)') > 0
  AND pg_catalog.strpos(helper.prosrc, 'action'', ''snap''') > 0
  AND pg_catalog.strpos(helper.prosrc, 'action'', ''warn''') = 0
  AND pg_catalog.strpos(helper.prosrc, 'workshop_booking_effective_end_at') > 0
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
  AND (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
  AND (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'))
      = (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)')
 AS ok,
 'place after' AS detail
FROM pg_catalog.pg_proc helper
WHERE helper.oid = pg_catalog.to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)')
$chk598$,
    true, 368, 'r598'
  );

  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'place_after_no_prompt_598') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r598: place-after check red: %', left(coalesce(detail, ''), 200); END IF;
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'hoist_place_after_592') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r598: hoist check red: %', left(coalesce(detail, ''), 200); END IF;
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'key460_drag_597') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r598: key 460 check red: %', left(coalesce(detail, ''), 200); END IF;

  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r598: pin count changed'; END IF;
  IF (SELECT status FROM public.workshop_bookings WHERE id = '0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd')::text IS DISTINCT FROM 'queued'
     OR (SELECT bay_id FROM public.workshop_bookings WHERE id = '0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd') IS NOT NULL THEN
    RAISE EXCEPTION 'r598: key 460 hoist was booked';
  END IF;
  IF (SELECT status FROM public.workshop_bookings WHERE id = '12648571-8886-4cfd-bbe3-084d65a00106')::text IS DISTINCT FROM 'stoppage' THEN
    RAISE EXCEPTION 'r598: key 307 was resumed';
  END IF;
END $r598$;
