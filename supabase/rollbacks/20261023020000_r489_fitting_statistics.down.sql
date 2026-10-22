-- r489 undo (F102). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Only needed if
-- 20261023020000_r489_fitting_statistics.sql was applied. Drops public.get_pdc_fitting_statistics_489(integer), its pin and the
-- check fitting_statistics_489. Nothing else used the function except the Admin > Fitting statistics page (revert the PR as well;
-- the page then shows "Could not load" until reverted). No data is changed by the release or by this undo.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r489 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r489 undo: staging only'; END IF;
 PERFORM set_config('pdc.r489_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r489_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r489_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r489_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r489 undo: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_fitting_statistics_489(integer)')) IS DISTINCT FROM '306a3d7a5ecd306492dcfafe00c70005' THEN RAISE EXCEPTION 'r489 undo: function is not the r489 version; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r489' AND signature='public.get_pdc_fitting_statistics_489(integer)')<>1
    OR NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='fitting_statistics_489' AND added_in='r489') THEN RAISE EXCEPTION 'r489 undo: r489 is not applied'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='fitting_statistics_489' AND added_in='r489';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r489' AND signature='public.get_pdc_fitting_statistics_489(integer)';
DROP FUNCTION public.get_pdc_fitting_statistics_489(integer);
DO $g$ BEGIN
 IF to_regprocedure('public.get_pdc_fitting_statistics_489(integer)') IS NOT NULL THEN RAISE EXCEPTION 'r489 undo: function still there'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r489_tick') THEN RAISE EXCEPTION 'r489 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r489_frc') THEN RAISE EXCEPTION 'r489 undo: fault_regression_check changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r489' OR signature='public.get_pdc_fitting_statistics_489(integer)') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r489')
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r489_pins')::int-1 THEN RAISE EXCEPTION 'r489 undo: did not fully undo'; END IF;
END $g$;
