-- r740 rollback: the early return for time-only booking updates is removed (trigger md5 back to 4b39cc4c107f50e3f45289a11166d2bc),
-- the baseline pin follows, the check is removed. Staging cdsmnqxtyyoeoznmbidd only.
DO $down740$
DECLARE v_oid oid; v_src text; v_new text; v_def text; v_branch text; v_n integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r740 down: staging only'; END IF;
  v_oid := to_regprocedure('pdc_work_categories_private.invalidate_qc_operation_lines_cache()');
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF strpos(v_src, 'r740 (F345)') = 0 THEN RAISE NOTICE 'r740 down: not applied'; RETURN; END IF;
  v_branch := E'  IF TG_TABLE_NAME = \'workshop_bookings\' AND TG_OP = \'UPDATE\'\n'
    || E'     AND OLD.vehicle_id IS NOT DISTINCT FROM NEW.vehicle_id AND OLD.stage_id IS NOT DISTINCT FROM NEW.stage_id\n'
    || E'     AND OLD.status IS NOT DISTINCT FROM NEW.status AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at\n'
    || E'     AND OLD.work_category IS NOT DISTINCT FROM NEW.work_category AND OLD.work_category_scope IS NOT DISTINCT FROM NEW.work_category_scope\n'
    || E'     AND OLD.created_at IS NOT DISTINCT FROM NEW.created_at THEN\n'
    || E'    -- r740 (F345): a time, bay, duration or technician change does not alter the QC lines; keep the cache.\n'
    || E'    RETURN NULL;\n'
    || E'  END IF;\n';
  v_new := replace(v_src, v_branch, '');
  IF v_new = v_src THEN RAISE EXCEPTION 'r740 down: branch not found'; END IF;
  IF md5(v_new) <> '4b39cc4c107f50e3f45289a11166d2bc' THEN RAISE EXCEPTION 'r740 down: body would not match the baseline md5'; END IF;
  v_def := replace(pg_get_functiondef(v_oid), v_src, v_new);
  EXECUTE v_def;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = '4b39cc4c107f50e3f45289a11166d2bc', note = coalesce(note,'') || '; r740 rolled back', updated_at = clock_timestamp()
  WHERE signature = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()' AND release = 'baseline';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r740 down: pin not moved'; END IF;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'booking_time_move_keeps_qc_cache_740';
END $down740$;
