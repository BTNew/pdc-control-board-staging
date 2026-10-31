-- Rollback r791 (F399): board_every_stock_674 back to its earlier body (the 7 cars stay completed; reopen by hand if needed).
DO $d$
DECLARE v_src text; v_def text; sig regprocedure := 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.board_every_stock_674(uuid,boolean)@r791pre';
  IF md5(v_src) <> '075419db9a4fb1a5777dff2b4225a031' THEN RAISE EXCEPTION 'backup missing'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'delivered_stays_completed_791';
END $d$;
