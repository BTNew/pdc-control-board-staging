-- Rollback r760 (F366): the as-a-Whole file fills a blank board key again (r479 behaviour); pin back; drop check 480.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $r760d$
DECLARE v_old text; v_new text; v_def text;
  sig regprocedure := 'public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure;
  b1 text := E' -- r760 (F366): the key on the board is the key. The ''as a Whole'' report never writes one, blank board key included.\n'
          || E' if exists(select 1 from public.pdc_pilbara_service_import_rows r\n'
          || E'   where r.batch_id=p_preview_batch_id and r.stock_number=v.stock_number and r.raw_row->>''email_subject''=''PMG PD Service as a Whole w/Sublet'') then\n'
          || E'  return jsonb_build_object(''changed'',false,''key_number'',v.key_number,''kept'',''board_key_is_master_r760'',''file_key_number'',keys[1]);\n'
          || E' end if;\n';
  a1 text := E' if nullif(btrim(coalesce(v.key_number,'''')),'''') is not null and exists(select 1 from public.pdc_pilbara_service_import_rows r\n'
          || E'   where r.batch_id=p_preview_batch_id and r.stock_number=v.stock_number and r.raw_row->>''email_subject''=''PMG PD Service as a Whole w/Sublet'') then\n'
          || E'  return jsonb_build_object(''changed'',false,''key_number'',v.key_number,''kept'',''board_key_not_blank_r479'',''file_key_number'',keys[1]);\n'
          || E' end if;\n';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  v_new := replace(v_old, b1, a1);
  IF md5(v_new) <> '7db7b5482de592222cfc5828ff9e6a45' THEN RAISE EXCEPTION 'r760 down: body would not return to the r479 md5'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = '7db7b5482de592222cfc5828ff9e6a45', release = 'r479' WHERE prosrc_md5 = md5(v_old);
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'board_key_is_master_760';
END $r760d$;
