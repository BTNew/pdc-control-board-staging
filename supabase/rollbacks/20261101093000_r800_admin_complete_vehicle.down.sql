-- Rollback r800 (F415): drop the admin complete RPC and its check; board_every_stock_674 back to the r796 body. Completed cars stay completed.
DO $d$
DECLARE v_src text; v_def text; v_cur text; sig regprocedure := 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
BEGIN
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.board_every_stock_674(uuid,boolean)@r800pre';
  IF md5(v_src) <> '4b8ead90d34c6818f077f8e729b04d9d' THEN RAISE EXCEPTION 'backup missing'; END IF;
  SELECT md5(prosrc) INTO v_cur FROM pg_proc WHERE oid = sig;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_cur, md5(v_src)) WHERE position(v_cur IN check_sql) > 0;
  DROP FUNCTION IF EXISTS public.admin_complete_vehicle_800(uuid, integer, text, text, uuid);
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'admin_complete_vehicle_800';
END $d$;
