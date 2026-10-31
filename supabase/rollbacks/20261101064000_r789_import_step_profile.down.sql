-- Rollback r789 (F397): run_jobs back to the r788 body.
DO $d$
DECLARE v_src text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.run_jobs()@r789pre';
  IF md5(v_src) <> '3c9916cfc89c13f67529429f8b0e42f6' THEN RAISE EXCEPTION 'backup missing'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'import_step_profile_789';
END $d$;
