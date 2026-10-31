-- Rollback r794 (F403): run_other_781 back to Perth stamps (refuses same-morning deal-item files again).
DO $d$
DECLARE v_src text; v_def text; v_cur text; sig regprocedure := 'pdc_import_620.run_other_781()'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.run_other_781()@r794pre';
  IF md5(v_src) <> '811edc9940e82f580a027a82835ede35' THEN RAISE EXCEPTION 'backup missing'; END IF;
  SELECT md5(prosrc) INTO v_cur FROM pg_proc WHERE oid = sig;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_cur, md5(v_src)) WHERE position(v_cur IN check_sql) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'deal_items_sydney_stamp_794';
END $d$;
