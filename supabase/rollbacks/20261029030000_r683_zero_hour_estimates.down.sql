-- r683 rollback: stop the job and drop the function. Estimates already saved stay (they are normal hours rows,
-- marked zero_hour_estimate_683); set them to 0 by hand if wanted. Then drop the check.
SELECT cron.unschedule('pdc_zero_hour_estimate_683');
DROP FUNCTION IF EXISTS pdc_ops.zero_hour_estimate_683(integer);
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'zero_hour_estimates_683';
