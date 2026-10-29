-- r732 rollback: baseline reader (md5 b7f90bff12643229ff80f8ca552663a2), r424 p_apply (d6eb557f2d80ed074658a9b525b8578a),
-- fill function dropped, pins and the three check literals back, check removed. Staging cdsmnqxtyyoeoznmbidd only.
DO $down732$
DECLARE v_oid oid; v_src text; v_new text; v_def text; v_live text;
  c_fill text := $a$ PERFORM pdc_work_categories_private.qc_lines_memo_fill_732(r.vehicle_id);$a$;
  c_pre text := E'\n -- r732 (F342): memo the lines of every vehicle this plan touches before the bay scans begin.\n PERFORM pdc_work_categories_private.qc_lines_memo_fill_732(z.vehicle_id) FROM (SELECT DISTINCT vehicle_id FROM pg_temp.r424_p WHERE changed) z;';
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r732 down: staging only'; END IF;
  SELECT md5(prosrc) INTO v_live FROM pg_proc WHERE oid = to_regprocedure('public.pdc_qc_operation_lines_379(uuid)');
  CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid) RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog' AS $function$
  SELECT coalesce(
    (SELECT c.lines
     FROM pdc_work_categories_private.qc_operation_lines_cache c
     WHERE c.vehicle_id = p_vehicle_id),
    public.pdc_qc_operation_lines_379_uncached(p_vehicle_id)
  );
$function$;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) <> 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r732 down: reader is not the baseline body'; END IF;
  v_oid := to_regprocedure('pdc_bay_seq_private.p_apply(jsonb,text)');
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  v_new := replace(replace(v_src, c_fill, ''), c_pre, '');
  IF md5(v_new) <> 'd6eb557f2d80ed074658a9b525b8578a' THEN RAISE EXCEPTION 'r732 down: p_apply is not the r424 body (%)', md5(v_new); END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  EXECUTE replace(v_def, v_src, v_new);
  DROP FUNCTION IF EXISTS pdc_work_categories_private.qc_lines_memo_fill_732(uuid);
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = 'b7f90bff12643229ff80f8ca552663a2', note = regexp_replace(coalesce(note,''), '; r732 \(F342\).*$', ''), updated_at = clock_timestamp()
  WHERE signature = 'public.pdc_qc_operation_lines_379(uuid)' AND release = 'baseline';
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = 'd6eb557f2d80ed074658a9b525b8578a', note = regexp_replace(coalesce(note,''), '; r732 \(F342\).*$', ''), updated_at = clock_timestamp()
  WHERE signature = 'pdc_bay_seq_private.p_apply(jsonb,text)' AND release = 'r424';
  DELETE FROM pdc_ops.expected_function_md5 WHERE signature = 'pdc_work_categories_private.qc_lines_memo_fill_732(uuid)';
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_live, 'b7f90bff12643229ff80f8ca552663a2')
  WHERE check_name IN ('station_icon_completion_578','board_qc_nesting_587','qc_signoff_override_590');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'qc_lines_memo_732';
END $down732$;
