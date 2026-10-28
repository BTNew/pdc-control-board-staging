-- r688 rollback. Restores the 10 QC function bodies saved before r688 and drops the check.
-- Vehicles put in QC by override will again fail to tick, photo, reject or sign off.
DO $d$ DECLARE r record; BEGIN
  IF (SELECT count(*) FROM pdc_ops.r688_function_backup) <> 10 THEN RAISE EXCEPTION 'r688 down: backup incomplete'; END IF;
  FOR r IN SELECT def FROM pdc_ops.r688_function_backup LOOP EXECUTE r.def; END LOOP;
END $d$;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'qc_follows_override_688';
