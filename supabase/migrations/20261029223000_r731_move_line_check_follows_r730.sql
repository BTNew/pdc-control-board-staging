-- r731 (F341): the r680 regression check move_line_min_hour_680 asserted the 60 minute clamp that r730 removed on
-- purpose, so it went red the moment r730 was applied (29 Oct 21:4x AWST). It now asserts the r730 shape: no clamp,
-- the validator's minutes in both resize blocks, the passed-start rule kept in both, and the planner cascade present.
-- Behaviour is unchanged. Staging cdsmnqxtyyoeoznmbidd only. Production never touched.
-- Rollback: supabase/rollbacks/20261029223000_r731_move_line_check_follows_r730.down.sql

DO $pre731$
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r731: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'move_line_min_hour_680' AND strpos(check_sql, 'IF mins<60 THEN mins:=60; END IF;') > 0) <> 1 THEN
    RAISE EXCEPTION 'r731: move_line_min_hour_680 is not the r680 text; nothing changed';
  END IF;
  IF (SELECT strpos(prosrc, 'r730 (F341)') FROM pg_proc WHERE oid = to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) = 0 THEN
    RAISE EXCEPTION 'r731: run r730 first';
  END IF;
END $pre731$;

UPDATE pdc_ops.regression_checks
SET description = 'Moving a line between stations resizes an unstarted booking to the validator''s minutes (no 60 minute clamp since r730, F341), never one whose start has passed, and pushes the bay with the planner cascade before refusing a lengthen.',
    check_sql = $chk$
SELECT (SELECT count(*) FROM regexp_matches(a, 'IF mins<60 THEN mins:=60; END IF;', 'g')) = 0
   AND (SELECT count(*) FROM regexp_matches(a, 'workshop_booking_capacity_duration_minutes\(rec\.id,v\.id,rec\.stage_id,rec\.bay_id\)', 'g')) = 2
   AND (SELECT count(*) FROM regexp_matches(a, 'IF rec\.scheduled_start_at >= clock_timestamp\(\) AND', 'g')) = 2
   AND pg_catalog.strpos(a, 'pdc_bay_seq_private.plan_for_move(rec.id,rec.bay_id,rec.scheduled_start_at)') > 0
 AS ok, 'move line uses the validator minutes, skips passed starts, cascades before refusing (r730)' AS detail
FROM (SELECT prosrc a FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) x
$chk$
WHERE check_name = 'move_line_min_hour_680';

DO $post731$
DECLARE r record; v_red text := ''; v_n integer := 0;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('move_line_min_hour_680','category_move_full_bay_730','regression_checks_self_test') LOOP
    v_n := v_n + 1;
    IF NOT r.ok THEN v_red := v_red || r.check_name || ' (' || left(r.detail, 160) || '); '; END IF;
  END LOOP;
  IF v_n <> 3 THEN RAISE EXCEPTION 'r731: expected 3 checks, saw %', v_n; END IF;
  IF v_red <> '' THEN RAISE EXCEPTION 'r731: red after apply, rolled back: %', v_red; END IF;
END $post731$;
