-- r740 (F345): moving a booking's time no longer wipes the vehicle's QC lines cache.
-- A same-bay swap or push-back timed out at 30s: every placement updated the booking row, the cache trigger bumped
-- the vehicle's epoch and dropped its cache row, and the assignment validation that follows recomputed the lines
-- (~40ms each, dozens of times per booking) for every job in the bay. The lines only read a booking's vehicle, stage,
-- status, deleted flag, work category, scope and created time, so an update that changes none of those returns early.
-- The check is nested inside the table test: plpgsql evaluates OLD.stage_id even when the table test is false, so a flat
-- AND chain raised "record old has no field stage_id" on every other table's update (caught live 08:04, Craig approved).
-- The rest of the trigger body is byte-identical; the pin and a regression check follow.
-- Staging cdsmnqxtyyoeoznmbidd only. Production never touched.
-- Rollback: supabase/rollbacks/20261030000500_r740_booking_time_move_keeps_qc_cache.down.sql
DO $r740$
DECLARE v_oid oid; v_src text; v_new text; v_def text; v_anchor text; v_branch text; v_n integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r740: staging only'; END IF;
  v_oid := to_regprocedure('pdc_work_categories_private.invalidate_qc_operation_lines_cache()');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'r740: cache trigger function missing'; END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF strpos(v_src, 'r740 (F345)') > 0 THEN
    -- Already live (applied by hand on 30 Oct): only make sure the pin matches the body.
    UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_src), updated_at = clock_timestamp()
    WHERE signature = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()' AND release = 'baseline' AND prosrc_md5 IS DISTINCT FROM md5(v_src);
    RAISE NOTICE 'r740: already applied'; RETURN;
  END IF;
  v_anchor := E'  IF TG_TABLE_NAME = \'pdc_pilbara_service_import_batches\' THEN\n';
  IF (SELECT count(*) FROM regexp_matches(v_src, '  IF TG_TABLE_NAME = ''pdc_pilbara_service_import_batches'' THEN\n', 'g')) <> 1 THEN
    RAISE EXCEPTION 'r740: anchor not found exactly once';
  END IF;
  v_branch := E'  IF TG_TABLE_NAME = \'workshop_bookings\' AND TG_OP = \'UPDATE\' THEN\n'
    || E'    -- 30 Oct fix (Craig approved 08:04): nested so OLD.stage_id etc. are only read on workshop_bookings (plpgsql does not short-circuit field lookups).\n'
    || E'    IF OLD.vehicle_id IS NOT DISTINCT FROM NEW.vehicle_id AND OLD.stage_id IS NOT DISTINCT FROM NEW.stage_id\n'
    || E'     AND OLD.status IS NOT DISTINCT FROM NEW.status AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at\n'
    || E'     AND OLD.work_category IS NOT DISTINCT FROM NEW.work_category AND OLD.work_category_scope IS NOT DISTINCT FROM NEW.work_category_scope\n'
    || E'     AND OLD.created_at IS NOT DISTINCT FROM NEW.created_at THEN\n'
    || E'      -- r740 (F345): a time, bay, duration or technician change does not alter the QC lines; keep the cache.\n'
    || E'      RETURN NULL;\n'
    || E'    END IF;\n'
    || E'  END IF;\n';
  v_new := replace(v_src, v_anchor, v_branch || v_anchor);
  IF v_new = v_src THEN RAISE EXCEPTION 'r740: body unchanged'; END IF;
  v_def := pg_get_functiondef(v_oid);
  v_def := replace(v_def, v_src, v_new);
  IF v_def = pg_get_functiondef(v_oid) THEN RAISE EXCEPTION 'r740: definition unchanged'; END IF;
  EXECUTE v_def;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF v_src <> v_new THEN RAISE EXCEPTION 'r740: readback differs'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new), note = coalesce(note,'') || '; r740 (F345): booking time moves keep the QC lines cache', updated_at = clock_timestamp()
  WHERE signature = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()' AND release = 'baseline';
  GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'r740: pin not moved'; END IF;
  RAISE NOTICE 'r740: trigger %', md5(v_new);
END $r740$;

INSERT INTO pdc_ops.regression_checks(check_name, sort_order, fault_id, added_in, enabled, description, check_sql)
VALUES ('booking_time_move_keeps_qc_cache_740', 458, 'F345', 'r740', true,
  'A workshop booking update that only changes time, bay, duration or technician keeps the vehicle''s QC lines cache (the lines read vehicle, stage, status, deleted flag, work category, scope and created time only), so a bay swap or push-back applies in seconds; the trigger body matches its pin.',
  $chk$
SELECT strpos(src, 'r740 (F345)') > 0
   AND strpos(src, 'OLD.work_category_scope IS NOT DISTINCT FROM NEW.work_category_scope') > 0
   AND strpos(src, 'OLD.created_at IS NOT DISTINCT FROM NEW.created_at THEN') > 0
   AND pg_catalog.md5(src) = (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e WHERE e.signature = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()' AND e.release = 'baseline') AS ok,
 'booking time moves keep the QC lines cache (r740)' AS detail
FROM (SELECT prosrc src FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('pdc_work_categories_private.invalidate_qc_operation_lines_cache()')) s
$chk$)
ON CONFLICT (check_name) DO NOTHING;

DO $post740$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('booking_time_move_keeps_qc_cache_740','import_batch_row_invalidates_its_vehicles_738','qc_lines_memo_732','protected_function_md5s','regression_checks_self_test') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r740: % red after apply: %', r.check_name, left(r.detail, 160); END IF;
  END LOOP;
END $post740$;
