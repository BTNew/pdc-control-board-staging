-- r737 (F343) / sort 455. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 06:14: "jobs arent cascading again, please fix."
-- workshop_clock_tick moved nothing from 06:00 (every bay sits in one linked group) with "A dependent current or queued
-- job prevents preserving workshop order". Cause: key 242's planned Hoist 03 job (9 Nov 15:15 to 10 Nov 06:39) is
-- pushed by the bay chain and lands behind key 360's queued Hoist 03 slot (10 Nov 06:45 to 13:39). Queued-in-bay is a
-- fixed obstacle, so the planned job can only go behind it, and the order test then read that as a reorder and
-- aborted the whole group every minute. Same shape as F309 (r699), different trigger.
-- Fix: the order test ignores a planned job pushed behind ANOTHER car's fixed slot (started, stoppage or queued in the
-- bay). The obstacle loop already keeps them apart. Same-car stage order is still enforced.
-- Rehearsed rolled back 06:28: 326 moves, no issues, 0 planned jobs in the past, 0 bay overlaps.
-- Rollback: supabase/rollbacks/20261030063000_r737_cascade_leapfrogs_fixed_slot.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $r737$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_old text := E'     AND a.status<>''stoppage''\n     AND b.status<>''stoppage''\n     AND a.final_end+CASE';
  c_new text := E'     AND a.status<>''stoppage''\n     AND b.status<>''stoppage''\n     -- r737 (F343): a planned job pushed behind another car''s fixed slot (started or queued in the bay) keeps no order with it;\n     -- the obstacle loop already keeps them apart. Same-car stage order is still enforced.\n     AND NOT (a.vehicle_id<>b.vehicle_id AND (b.status IN(''started'',''stoppage'',''queued'') OR b.actual_start_at IS NOT NULL))\n     AND a.final_end+CASE';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r737: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r737: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 455 OR fault_id = 'F343' OR added_in = 'r737' OR check_name = 'cascade_leapfrogs_fixed_slot_737') THEN RAISE EXCEPTION 'r737: sort 455 or F343 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r737: an import job is running'; END IF;
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r737: anchor not found once'; END IF;
  v_new := replace(v_old, c_old, c_new);
  v_def := regexp_replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) <> v_new THEN RAISE EXCEPTION 'r737: readback differs'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r737: pin row not moved (%)', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n < 1 THEN RAISE EXCEPTION 'r737: md5 check not moved'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('cascade_leapfrogs_fixed_slot_737', 'F343',
    'The clock cascade lets a planned job land behind another car''s fixed slot (started or queued in the bay) instead of aborting the whole linked group; same-car stage order is still enforced.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')),
  'AND NOT (a.vehicle_id<>b.vehicle_id AND (b.status IN(''started'',''stoppage'',''queued'') OR b.actual_start_at IS NOT NULL))') > 0
 AS ok, 'cascade leapfrogs another car''s fixed slot' AS detail
$chk$, true, 455, 'r737');
END $r737$;

DO $post737$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('cascade_leapfrogs_fixed_slot_737','cascade_ignores_unbayed_queue_699','protected_function_md5s','regression_checks_self_test','schedule_stale_version_window_552') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r737: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
END $post737$;
