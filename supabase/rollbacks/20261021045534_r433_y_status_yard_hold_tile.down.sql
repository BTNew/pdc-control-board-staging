-- r433 undo (F44). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Drops the r433 check, pin and
-- pdc_sales_private.sales_tracker_tile (nothing else uses it). r433 changed no other function, table or row.
-- Revert the PR as well so the Sales screen goes back to YH-only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r433 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r433 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r433 undo: clock tick changed (this release must not touch it; r431 is the clock release)'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_sales_private.sales_tracker_tile(jsonb)') AND md5(p.prosrc)='dea0658ecc8ec486568cc6d354a5bce2')<>1 THEN RAISE EXCEPTION 'r433 undo: sales_tracker_tile is not the r433 version'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='navision_y_status_maps_to_yard_hold' AND added_in='r433') IS DISTINCT FROM '13a9f786621910cc3ea3f64a9ce3f5bc' THEN RAISE EXCEPTION 'r433 undo: check is not the r433 version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r433')<>1 THEN RAISE EXCEPTION 'r433 undo: expected exactly one r433 pin'; END IF;
 IF EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid=to_regprocedure('pdc_sales_private.sales_tracker_tile(jsonb)') AND d.deptype='n') THEN RAISE EXCEPTION 'r433 undo: something depends on sales_tracker_tile'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='navision_y_status_maps_to_yard_hold' AND added_in='r433';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r433' AND signature='pdc_sales_private.sales_tracker_tile(jsonb)';
DROP FUNCTION pdc_sales_private.sales_tracker_tile(jsonb);
DO $g$ BEGIN
 IF to_regprocedure('pdc_sales_private.sales_tracker_tile(jsonb)') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r433')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r433') THEN RAISE EXCEPTION 'r433 undo: did not fully undo'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_sales_private.yard_hold_stage_rank(text,text)'::regprocedure)<>'a441a598a1a6477e36d0a73ad7c5d354' THEN RAISE EXCEPTION 'r433 undo: r427 rank changed'; END IF;
END $g$;
