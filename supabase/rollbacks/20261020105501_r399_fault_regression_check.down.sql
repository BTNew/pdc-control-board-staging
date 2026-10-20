-- r399 Part B undo: drops the health check (no other object depends on it).
DO $g$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='cdsmnqxtyyoeoznmbidd')
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r399 ops undo: staging only'; END IF;
END $g$;
DROP FUNCTION pdc_ops.fault_regression_check();
DROP TABLE pdc_ops.regression_checks;
DROP TABLE pdc_ops.expected_function_md5;
DROP SCHEMA pdc_ops;
