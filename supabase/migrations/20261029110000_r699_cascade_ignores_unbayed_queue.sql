-- r699 (F309) / sort 447. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 09:36: "EVERY JOB MUST CASCADE AND NEVER GO INTO THE PAST. WHY IS THIS JOB BEING OVERLAPPED?" (Hoist 2).
-- workshop_clock_tick stopped moving 12 bays (most since 28 Oct 13:00) with "A dependent current or queued job prevents
-- preserving workshop order". Cause: a booking that was started, then sent back to Unallocated (queued, no bay,
-- actual_start_at set; 12238967 Bus 4x4) stayed in the cascade plan as a fixed obstacle with its old window. The car's
-- next job could not keep order, the whole linked group of bays aborted each minute, and jobs slid into the past and
-- under running jobs. Fix: a queued booking with no bay is never in the cascade plan (it is not on any bay).
-- Rehearsed rolled back: 7 moves, no issues, 0 planned jobs in the past (3 live now), 0 bay overlaps.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

CREATE TEMP TABLE r699_green ON COMMIT DROP AS SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE false;
DO $pre699$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE enabled AND check_sql LIKE '%workshop_clock_tick%' LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; END;
    IF ok IS TRUE THEN INSERT INTO r699_green VALUES (r.check_name, r.check_sql); END IF;
  END LOOP;
END $pre699$;

DO $r699$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_old text := E' AND NOT (b.status=''queued'' AND b.bay_id IS NULL AND b.actual_start_at IS NULL);\n CREATE UNIQUE INDEX ON clock_linked_plan(id);';
  c_new text := E' AND NOT (b.status=''queued'' AND b.bay_id IS NULL); -- r699 (F309): Unallocated work is never a cascade obstacle\n CREATE UNIQUE INDEX ON clock_linked_plan(id);';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r699: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r699: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r699: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 447 OR fault_id = 'F309' OR added_in = 'r699' OR sort_order = 448 OR check_name IN ('cascade_ignores_unbayed_queue_699', 'cascade_not_stuck_699')) THEN RAISE EXCEPTION 'r699: sort 447 or F309 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r699: an import job is running'; END IF;
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r699: anchor not found once'; END IF;
  v_new := replace(v_old, c_old, c_new);
  v_def := regexp_replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) -- release label stays (no_overlapping_active_bookings_600 reads it)
  WHERE prosrc_md5 = v_md5;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r699: pin row not moved (%)', v_n; END IF;
  -- schedule_stale_version_window_552 names the tick's md5: move it with the pin.
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure))
  WHERE strpos(check_sql, v_md5) > 0;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n < 1 THEN RAISE EXCEPTION 'r699: md5 check not moved'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r699: pin count changed'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('cascade_ignores_unbayed_queue_699', 'F309',
    'The clock cascade leaves Unallocated (queued, no bay) work out of its plan, so one returned job cannot freeze linked bays.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')), 'AND NOT (b.status=''queued'' AND b.bay_id IS NULL); -- r699') > 0
 AS ok, 'cascade ignores Unallocated work' AS detail
$chk$, true, 447, 'r699');
  -- Never again: a bay whose cascade keeps failing goes red within 30 minutes (Fault Regression shows it).
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('cascade_not_stuck_699', 'F309',
    'No active bay has had its clock cascade fail for more than 30 minutes, and no planned job sits in the past.',
    $chk$
SELECT count(*) = 0 AS ok, coalesce(string_agg(x, ', '), 'none') AS detail FROM (
  SELECT 'bay ' || left(cs.bay_id::text, 8) || ' stuck since ' || to_char(cs.last_success_at AT TIME ZONE 'Australia/Perth', 'DD HH24:MI') x
  FROM public.workshop_clock_status cs JOIN public.workshop_bays y ON y.id = cs.bay_id
  WHERE y.is_active AND cs.error_code IS NOT NULL AND cs.last_checked_at > clock_timestamp() - interval '10 minutes'
    AND coalesce(cs.last_success_at, '-infinity') < clock_timestamp() - interval '30 minutes'
    AND EXISTS (SELECT 1 FROM public.workshop_bookings b WHERE b.bay_id = cs.bay_id AND b.deleted_at IS NULL AND b.status IN ('planned','started','stoppage'))
  UNION ALL
  SELECT 'planned in the past ' || left(b.id::text, 8)
  FROM public.workshop_bookings b JOIN public.workshop_bays y ON y.id = b.bay_id
  WHERE b.deleted_at IS NULL AND b.status = 'planned' AND b.actual_start_at IS NULL AND y.is_active
    AND b.scheduled_start_at < clock_timestamp() - interval '10 minutes'
) q
$chk$, true, 448, 'r699');
END $r699$;

DO $post699$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT c.check_name, c.check_sql FROM pdc_ops.regression_checks c WHERE c.check_name IN (SELECT g.check_name FROM r699_green g) OR c.check_name = 'cascade_ignores_unbayed_queue_699' LOOP
    EXECUTE r.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r699: check % red: %', r.check_name, detail; END IF;
  END LOOP;
END $post699$;
