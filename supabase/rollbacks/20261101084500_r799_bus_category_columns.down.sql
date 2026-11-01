-- Rollback r799 (F409): list_station_icon_completion_578 back to the r578 rows only; drop the category function and check.
DO $d$
DECLARE v_src text; v_def text; v_cur text; sig regprocedure := 'public.list_station_icon_completion_578(uuid[])'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'public.list_station_icon_completion_578(uuid[])@r799pre';
  IF md5(v_src) <> 'df6ea3b81690d85efd750e32a6f7098d' THEN RAISE EXCEPTION 'backup missing'; END IF;
  SELECT md5(prosrc) INTO v_cur FROM pg_proc WHERE oid = sig;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_cur, md5(v_src)) WHERE position(v_cur IN check_sql) > 0;
  DROP FUNCTION IF EXISTS pdc_work_categories_private.bus_category_completion_799(uuid[]);
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'bus_category_columns_799';
END $d$;
