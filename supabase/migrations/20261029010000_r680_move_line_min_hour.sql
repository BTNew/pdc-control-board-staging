-- r680 (F290) / sort 426. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 06:21: moving Electrical lines into the Fitting bays (13047383, Chelsea does both) failed with
-- "The category was not saved. The unstarted booking could not be lengthened." The Fitting lines were already done,
-- so the open work left in that booking came to 15 minutes, and the booking guard (r372) refuses anything under
-- 60 minutes; and the booking's start (28 Oct 14:15) had already passed, which the planner refuses (past_start).
-- set_vehicle_work_category now never resizes an unstarted booking below 60 minutes, and leaves an unstarted booking
-- whose start has passed at its current length (the line still moves; the planner reflows it). Shorten and lengthen.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $r680$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_sig text := 'set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)';
  c_at text := E'     new_end:=public.workshop_add_operational_minutes(rec.scheduled_start_at,mins);';
  c_if text := E'     IF mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at THEN';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r680: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r680: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r680: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 426 OR fault_id = 'F290' OR added_in = 'r680' OR check_name = 'move_line_min_hour_680') THEN RAISE EXCEPTION 'r680: sort 426 or F290 is taken'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = c_sig::regprocedure;
  IF md5(v_old) <> '240e25e96467490d71744490c7a4d75c' THEN RAISE EXCEPTION 'r680: set_vehicle_work_category is not the pinned text'; END IF;
  v_old := replace(v_old, E'\r\n', E'\n');
  IF (length(v_old) - length(replace(v_old, c_at, ''))) / length(c_at) <> 2 THEN RAISE EXCEPTION 'r680: resize anchor not found twice'; END IF;
  IF (length(v_old) - length(replace(v_old, c_if, ''))) / length(c_if) <> 2 THEN RAISE EXCEPTION 'r680: resize condition not found twice'; END IF;
  v_new := replace(v_old, c_at, E'     IF mins<60 THEN mins:=60; END IF; -- r680 (F290): bookings are never under 60 minutes (r372 guard)\n' || c_at);
  v_new := replace(v_new, c_if, E'     -- r680 (F290): a start that has passed cannot be resized (planner past_start); keep its length.\n'
    || E'     IF rec.scheduled_start_at >= clock_timestamp() AND (mins IS DISTINCT FROM rec.default_duration_minutes OR new_end IS DISTINCT FROM rec.scheduled_end_at) THEN');
  v_def := regexp_replace(pg_get_functiondef(c_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid = c_sig::regprocedure;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_md5, release = 'r680' WHERE prosrc_md5 = '240e25e96467490d71744490c7a4d75c';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r680: pin row not moved (%)', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, '240e25e96467490d71744490c7a4d75c', v_md5)
  WHERE strpos(check_sql, '240e25e96467490d71744490c7a4d75c') > 0;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r680: pin count changed'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('move_line_min_hour_680', 'F290',
    'Moving a line between stations never resizes an unstarted booking below 60 minutes or one whose start has passed (it failed with "could not be lengthened").',
    $chk$
SELECT (SELECT count(*) FROM regexp_matches(a, 'IF mins<60 THEN mins:=60; END IF;', 'g')) = 2
   AND (SELECT count(*) FROM regexp_matches(a, 'IF rec\.scheduled_start_at >= clock_timestamp\(\) AND', 'g')) = 2
 AS ok, 'move line keeps 60 min minimum and skips passed starts' AS detail
FROM (SELECT prosrc a FROM pg_proc WHERE oid = to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) x
$chk$, true, 426, 'r680');
END $r680$;
