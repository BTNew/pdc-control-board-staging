-- r783 (F389). Staging cdsmnqxtyyoeoznmbidd only. Health check 31 Oct 2026 12:25 AWST (Craig: "do a check of everything").
-- r780 moved the compute_554 md5 pin in 4 checks but missed 2 more (history_board_visibility_453, vehicle_board_snapshot_cache_545);
-- r781 changed the KTA normalize body without moving its pdc_ops.expected_function_md5 pin. Pins only; no function body changes.
DO $r783$
DECLARE v_cur text; v_kta text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r783: staging only'; END IF;
  SELECT md5(prosrc) INTO v_cur FROM pg_proc WHERE oid = 'pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure;
  IF position('r780 (F384)' IN (SELECT prosrc FROM pg_proc WHERE oid = 'pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure)) = 0 THEN RAISE EXCEPTION 'r783: compute_554 is not the r780 body'; END IF;
  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql, $q$='e7f77fad301b8a87ef548472a8f790a6'$q$, $q$='$q$ || v_cur || $q$'$q$)
  WHERE check_name IN ('history_board_visibility_453', 'vehicle_board_snapshot_cache_545');
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name IN ('history_board_visibility_453', 'vehicle_board_snapshot_cache_545') AND position(v_cur IN check_sql) > 0) <> 2 THEN
    RAISE EXCEPTION 'r783: compute pin not moved on both checks'; END IF;
  SELECT md5(prosrc) INTO v_kta FROM pg_proc WHERE oid = 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)'::regprocedure;
  IF position('r781 (F386)' IN (SELECT prosrc FROM pg_proc WHERE oid = 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)'::regprocedure)) = 0 THEN RAISE EXCEPTION 'r783: KTA normalize is not the r781 body'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_kta, updated_at = clock_timestamp(),
    note = note || ' | r781 (F386): website upload passes the mailbox/sender rule while it runs (was ef85e5393c5039ac4e8421f6b058c405)'
  WHERE signature = 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)';
END $r783$;
