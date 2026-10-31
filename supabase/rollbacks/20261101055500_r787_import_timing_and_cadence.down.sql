-- Rollback r787 (F395): run_jobs back to the r782 body; worker back to every minute.
DO $d$
DECLARE v_src text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.run_jobs()@r787pre';
  IF md5(v_src) <> '5ffe3b511dd0884354eb068571defec5' THEN RAISE EXCEPTION 'backup missing'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  PERFORM cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'pdc-import-620-worker'), schedule := '* * * * *');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'import_timing_cadence_787';
END $d$;
