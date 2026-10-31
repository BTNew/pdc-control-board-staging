-- Rollback r793 (F402). Restores the r789 body, which fails under the cron role. Only for audit; do not apply.
DO $d$
DECLARE v_src text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.run_jobs()@r793pre';
  IF md5(v_src) <> '24968dc50480acc40ea85719013fe101' THEN RAISE EXCEPTION 'backup missing'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'import_no_superuser_settings_793';
END $d$;
