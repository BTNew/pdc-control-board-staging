-- r721 (F331) / sort 471. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 13:22 (13073300, Key 307): Electrical lines would not move to Fitting: "Split or cancel the affected
-- unstarted booking before changing its work category". The car has a finished Fitting booking (26-28 Oct), and
-- set_vehicle_work_category refused any move into or out of a station with ANY finished booking. That is the
-- "even if the fitting stuff has already been complete" case Craig asked for at 06:21 (r680 fixed only the resize).
-- Now a finished booking blocks only when it really did this line (its work_category_scope names the line), and a line
-- moved into a finished station reopens that station's work item, so the moved job shows as still to do.
-- Running / started work and ticked lines stay protected exactly as before.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

CREATE TEMP TABLE r721_green ON COMMIT DROP AS SELECT check_name FROM pdc_ops.regression_checks WHERE false;
DO $pre721$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE enabled AND check_sql LIKE '%set_vehicle_work_category%' LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; END;
    IF ok IS TRUE THEN INSERT INTO r721_green VALUES (r.check_name); END IF;
  END LOOP;
END $pre721$;

DO $r721$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text; v_md5 text; v_new_md5 text; v_n integer;
  a1 text := $a$   OR (b.status='completed' AND s.code IN(src_stage,target) AND (b.work_category IS NULL OR b.work_category_scope ? p_line_identity OR (b.work_category='BUS_WHOLE_JOB' AND b.work_category_scope ? p_line_identity)))$a$;
  b1 text := $b$   OR (b.status='completed' AND s.code IN(src_stage,target) AND b.work_category_scope ? p_line_identity) -- r721 (F331): only a finished job that did this line$b$;
  a2 text := $a$ ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true WHERE NOT public.vehicle_work_items.completed;$a$;
  b2 text := $b$ ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,completed=false,completed_by=NULL,completed_at=NULL,updated_at=clock_timestamp() WHERE public.vehicle_work_items.vehicle_id=excluded.vehicle_id; -- r721 (F331): an open line moved in reopens the station$b$;
  c_sig text := 'public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r721: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r721: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r721: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 471 OR fault_id = 'F331' OR added_in = 'r721' OR check_name = 'move_into_finished_station_721') THEN RAISE EXCEPTION 'r721: sort 471 or F331 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r721: an import job is running'; END IF;
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = c_sig::regprocedure;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r721: finished-booking anchor not found once'; END IF;
  IF (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1 THEN RAISE EXCEPTION 'r721: work item anchor not found once'; END IF;
  v_new := replace(replace(v_old, a1, b1), a2, b2);
  v_def := regexp_replace(pg_get_functiondef(c_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  SELECT md5(prosrc) INTO v_new_md5 FROM pg_proc WHERE oid = c_sig::regprocedure;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_new_md5 WHERE prosrc_md5 = v_md5;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 1 THEN RAISE EXCEPTION 'r721: pin rows %', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, v_new_md5) WHERE strpos(check_sql, v_md5) > 0;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r721: pin count changed'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('move_into_finished_station_721', 'F331',
    'A line can move into or out of a station whose job already finished (only a finished job that did that line blocks), and the moved line reopens the station.',
    $chk$
SELECT strpos(s, 'b.work_category_scope ? p_line_identity) -- r721') > 0 AND strpos(s, 'an open line moved in reopens the station') > 0
   AND strpos(s, 'category_booking_exists') > 0
 AS ok, 'move into a finished station allowed' AS detail
FROM (SELECT prosrc s FROM pg_proc WHERE oid = to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) x
$chk$, true, 471, 'r721');
END $r721$;

DO $post721$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT c.check_name, c.check_sql FROM pdc_ops.regression_checks c WHERE c.check_name IN (SELECT g.check_name FROM r721_green g) OR c.check_name = 'move_into_finished_station_721' LOOP
    EXECUTE r.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r721: check % red: %', r.check_name, detail; END IF;
  END LOOP;
END $post721$;
