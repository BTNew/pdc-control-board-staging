-- r598 (F212) undo. Staging cdsmnqxtyyoeoznmbidd only.
-- Puts the confirmation gate back on the place-after helper and removes the F212 check.
-- It does not rewrite booking rows.

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $undo598$
DECLARE
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
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r598 undo: staging only'; END IF;
  def := pg_get_functiondef('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)'::regprocedure);
  IF strpos(def, new_ask) = 0 OR strpos(def, 'place_after_confirm') > 0 THEN
    RAISE EXCEPTION 'r598 undo: helper is not the r598 body';
  END IF;
  def := replace(def, new_ask, old_ask);
  def := replace(def, '  RETURN jsonb_build_object(''action'', ''snap'', ''start_at'', v_place, ''end_at'', v_place_end);', old_gate || '  RETURN jsonb_build_object(''action'', ''snap'', ''start_at'', v_place, ''end_at'', v_place_end);');
  EXECUTE def;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)'))
     IS DISTINCT FROM 'dfda4b83016feef586cb49699b34475a' THEN
    RAISE EXCEPTION 'r598 undo: helper checksum';
  END IF;
  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql,
        E'  AND strpos(helper, ''place_after_confirm'') = 0\n  AND strpos(helper, ''r598 (F212)'') > 0',
        E'  AND strpos(helper, ''place_after_running'') > 0\n  AND strpos(helper, ''Place this job right after it'') > 0')
  WHERE check_name = 'hoist_place_after_592';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r598 undo: hoist check'; END IF;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'place_after_no_prompt_598' AND fault_id = 'F212' AND added_in = 'r598';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r598 undo: check not removed'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r598 undo: pin count'; END IF;
  IF (SELECT status FROM public.workshop_bookings WHERE id = '12648571-8886-4cfd-bbe3-084d65a00106')::text IS DISTINCT FROM 'stoppage' THEN
    RAISE EXCEPTION 'r598 undo: key 307';
  END IF;
END $undo598$;
