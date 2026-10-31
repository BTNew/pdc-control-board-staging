-- Rollback r796 (F406): board_every_stock_674 back to the r791 body.
DO $d$
DECLARE v_src text; v_def text; v_cur text; sig regprocedure := 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.board_every_stock_674(uuid,boolean)@r796pre';
  IF md5(v_src) <> '9c0dd65faf1aa7d5ab659c296e80e3ec' THEN RAISE EXCEPTION 'backup missing'; END IF;
  SELECT md5(prosrc) INTO v_cur FROM pg_proc WHERE oid = sig;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_cur, md5(v_src)) WHERE position(v_cur IN check_sql) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'delivered_then_dropped_796';
END $d$;
