-- r499 undo (F112). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Only needed if 20261023040000_r499_sales_pmb_stations.sql was applied.
-- Drops the two read-only functions, their two pins and check sales_pmb_stations_499. No data rows are touched (the release wrote none).
-- Revert the r499 PR as well (the Sales page then shows the PMB status text only; with the PR still live and this undone, the page
-- simply shows no icons - the RPC failure is caught and logged once).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r499 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r499 undo: staging only'; END IF;
 PERFORM set_config('pdc.r499_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r499_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.pmb_stations_499(uuid[])')) IS DISTINCT FROM 'ec5161da807d08c71fe4f59c2cd78c11'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_pmb_stations(uuid[])')) IS DISTINCT FROM 'cbd4b27bcd6202dc3038dee145d5da00' THEN RAISE EXCEPTION 'r499 undo: the r499 functions are not the r499 versions; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r499')<>2 OR NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_pmb_stations_499' AND added_in='r499') THEN RAISE EXCEPTION 'r499 undo: r499 is not fully applied; not undoing'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='sales_pmb_stations_499' AND added_in='r499';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r499' AND signature IN ('pdc_sales_private.pmb_stations_499(uuid[])','public.get_broome_sales_pmb_stations(uuid[])');
DROP FUNCTION public.get_broome_sales_pmb_stations(uuid[]);
DROP FUNCTION pdc_sales_private.pmb_stations_499(uuid[]);
DO $g$ BEGIN
 IF to_regprocedure('pdc_sales_private.pmb_stations_499(uuid[])') IS NOT NULL OR to_regprocedure('public.get_broome_sales_pmb_stations(uuid[])') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r499') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r499')
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r499_pins')::int-2 THEN RAISE EXCEPTION 'r499 undo: did not fully undo'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r499_tick') THEN RAISE EXCEPTION 'r499 undo: clock tick changed'; END IF;
END $g$;
