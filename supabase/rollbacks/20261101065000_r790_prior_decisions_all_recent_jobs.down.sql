-- Rollback r790 (F398): prior decisions back to the last job only.
DO $d$
DECLARE v_src text; v_def text; sig regprocedure := 'public.revolution_prior_decisions_728()'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'public.revolution_prior_decisions_728()@r790pre';
  IF md5(v_src) <> 'ab705c652d453fe9f48490d5304790e4' THEN RAISE EXCEPTION 'backup missing'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'prior_decisions_recent_jobs_790';
END $d$;
