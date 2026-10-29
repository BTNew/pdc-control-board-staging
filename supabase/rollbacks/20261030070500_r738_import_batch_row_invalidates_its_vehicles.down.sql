-- r738 rollback: a service import batch row wipes the whole QC lines cache again. Staging cdsmnqxtyyoeoznmbidd only.
DO $down738$
DECLARE v_old text; v_new text; v_def text; v_md5 text; v_start integer; v_end integer;
  c_new text := $n$  IF TG_OP = 'TRUNCATE' OR TG_TABLE_NAME IN ('ai_routing_20261019', 'import_rules_139_20261018', 'import_rules_20261017', 'navision_backend_records', 'workshop_stage_aliases', 'workshop_stages') THEN$n$;
  c_old text := $o$  IF TG_OP = 'TRUNCATE' OR TG_TABLE_NAME IN ('ai_routing_20261019', 'import_rules_139_20261018', 'import_rules_20261017', 'navision_backend_records', 'pdc_pilbara_service_import_batches', 'workshop_stage_aliases', 'workshop_stages') THEN$o$;
  c_branch_start text := $b$  IF TG_TABLE_NAME = 'pdc_pilbara_service_import_batches' THEN$b$;
  c_branch_end text := $e$  IF TG_TABLE_NAME = 'vehicles' THEN$e$;
BEGIN
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure;
  IF (length(v_old) - length(replace(v_old, c_new, ''))) / length(c_new) <> 1 THEN RAISE EXCEPTION 'r738 down: anchor not found once'; END IF;
  v_start := position(c_branch_start IN v_old); v_end := position(c_branch_end IN v_old);
  IF v_start = 0 OR v_end = 0 OR v_end < v_start THEN RAISE EXCEPTION 'r738 down: branch not found'; END IF;
  v_new := replace(left(v_old, v_start - 1) || substring(v_old FROM v_end), c_new, c_old);
  v_def := regexp_replace(pg_get_functiondef('pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'import_batch_row_invalidates_its_vehicles_738';
END $down738$;
