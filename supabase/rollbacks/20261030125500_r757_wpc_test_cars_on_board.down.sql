-- Rollback r757 (F363): remove the WPC test car line from the board filter, move the md5 literal and pin back, drop check 469.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $r757d$
DECLARE v_old text; v_new text; v_def text; v_md5 text;
  c_line text := E'      OR coalesce((v.source_payload->>''wpc_test_20261030'')::boolean,false)\n';
BEGIN
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure;
  IF strpos(v_old, c_line) = 0 THEN RAISE EXCEPTION 'r757 down: line not present'; END IF;
  v_new := replace(v_old, c_line, '');
  IF md5(v_new) <> 'd3b6f69bdf3420336403816fc7c60255' THEN RAISE EXCEPTION 'r757 down: body would not return to the pre-r757 md5'; END IF;
  v_def := regexp_replace(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'wpc_test_cars_on_board_757';
  UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = now() WHERE singleton;
END $r757d$;
