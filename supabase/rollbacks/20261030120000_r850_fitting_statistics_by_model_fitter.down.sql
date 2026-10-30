-- r850 undo (F400). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Only needed if
-- 20261030120000_r850_fitting_statistics_by_model_fitter.sql was applied. Drops public.get_pdc_fitting_statistics_850(integer,uuid),
-- its pin and the check fitting_statistics_850. The page falls back to get_pdc_fitting_statistics_489 by itself (no model / fitter split);
-- revert the PR as well to restore the r489 page. r489 is not touched by the release or by this undo. No data is changed.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r850 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r850 undo: staging only'; END IF;
 PERFORM set_config('pdc.r850_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r850_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r850_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r850_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r850 undo: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_fitting_statistics_850(integer,uuid)')) IS DISTINCT FROM '170ecb5674f39d78f3fd9135cb75aae5' THEN RAISE EXCEPTION 'r850 undo: function is not the r850 version; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r850' AND signature='public.get_pdc_fitting_statistics_850(integer,uuid)')<>1
    OR NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='fitting_statistics_850' AND added_in='r850') THEN RAISE EXCEPTION 'r850 undo: r850 is not applied'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='fitting_statistics_850' AND added_in='r850';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r850' AND signature='public.get_pdc_fitting_statistics_850(integer,uuid)';
DROP FUNCTION public.get_pdc_fitting_statistics_850(integer,uuid);
DO $g$ BEGIN
 IF to_regprocedure('public.get_pdc_fitting_statistics_850(integer,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r850 undo: function still there'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.get_pdc_fitting_statistics_489(integer)'::regprocedure) IS DISTINCT FROM '306a3d7a5ecd306492dcfafe00c70005' THEN RAISE EXCEPTION 'r850 undo: r489 report changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r850_tick') THEN RAISE EXCEPTION 'r850 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r850_frc') THEN RAISE EXCEPTION 'r850 undo: fault_regression_check changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r850' OR signature='public.get_pdc_fitting_statistics_850(integer,uuid)') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r850')
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r850_pins')::int-1 THEN RAISE EXCEPTION 'r850 undo: did not fully undo'; END IF;
END $g$;
