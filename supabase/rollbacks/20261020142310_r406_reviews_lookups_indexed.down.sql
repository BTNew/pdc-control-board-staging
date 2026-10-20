-- Undo r406 (F16): remove the reviews_lookups_indexed check. Staging cdsmnqxtyyoeoznmbidd only.
-- Nothing else was changed by r406 (the indexes predate it and stay).
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r406 undo: staging only'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='reviews_lookups_indexed' AND added_in='r406') IS DISTINCT FROM '725010dda682fc1ed9faa1b377fb1491' THEN RAISE EXCEPTION 'r406 undo: check missing or changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r406 undo: frc md5'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='reviews_lookups_indexed' AND added_in='r406';

DO $p$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r406') THEN RAISE EXCEPTION 'r406 undo: check left'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r406 undo: frc md5'; END IF;
END $p$;
