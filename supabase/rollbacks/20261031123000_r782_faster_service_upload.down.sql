-- Rollback r782 (F387): run_jobs back to 40 s per tick. (The edge function change rolls back with the function.)
DO $d$
DECLARE v_src text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.run_jobs()@r782pre';
  IF md5(v_src) <> '1036f5fbbceb08d2b13e87531df0253b' THEN RAISE EXCEPTION 'backup missing'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'faster_service_upload_782';
END $d$;
