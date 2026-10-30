-- r746 rollback. Staging cdsmnqxtyyoeoznmbidd only. Run between :02 and :45.
-- Restores workshop_station_eligibility byte for byte (md5 952da1c6a242d3014d1deae7a0585bac), drops the four
-- triggers, the three functions and the F352 check. Bookings cleared by r746 stay deleted; they are listed in
-- pdc_ops.r746_cleared_bookings (kept) with their full before row, and can be restored one by one from the planner
-- history (Restore) if wanted.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $down746$
DECLARE v_oid oid := to_regprocedure('public.workshop_station_eligibility(text)'); v_def text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r746 down: staging only';
  END IF;
  SELECT def INTO v_def FROM pdc_ops.r746_function_backup WHERE sig = 'public.workshop_station_eligibility(text)';
  IF v_def IS NULL THEN RAISE EXCEPTION 'r746 down: no saved eligibility definition'; END IF;
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid = v_oid), 'done_planner_stations_746') = 0 THEN
    RAISE EXCEPTION 'r746 down: eligibility is not the r746 body';
  END IF;
  EXECUTE v_def;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = v_oid) <> '952da1c6a242d3014d1deae7a0585bac' THEN
    RAISE EXCEPTION 'r746 down: eligibility md5 not restored';
  END IF;
END $down746$;

DROP TRIGGER IF EXISTS zz_station_done_746_ins ON public.pdc_panel_line_completion_565;
DROP TRIGGER IF EXISTS zz_station_done_746_upd ON public.pdc_panel_line_completion_565;
DROP TRIGGER IF EXISTS zz_station_done_746_ins ON public.pdc_station_completion_override_578;
DROP TRIGGER IF EXISTS zz_station_done_746_upd ON public.pdc_station_completion_override_578;
DROP FUNCTION IF EXISTS pdc_work_categories_private.after_station_tick_746();
DROP FUNCTION IF EXISTS pdc_work_categories_private.clear_done_station_bookings_746(uuid[], text);
DROP FUNCTION IF EXISTS pdc_work_categories_private.done_planner_stations_746(uuid[]);
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'done_station_leaves_planner_746';
