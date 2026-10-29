-- r735 (F342): the r732 memo upsert (INSERT ... ON CONFLICT DO UPDATE) gains the repo's pg-safeupdate convention,
-- WHERE true, like bump_qc_operation_lines_cache_epoch. Behaviour is identical; the fill function's pin follows.
-- Idempotent: a fresh environment gets this body from the amended r732 file and this file changes nothing.
-- Staging cdsmnqxtyyoeoznmbidd only. Production never touched.
-- Rollback: supabase/rollbacks/20261029232000_r735_memo_fill_where_true.down.sql
DO $r735$
DECLARE v_md5 text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r735: staging only'; END IF;
  IF to_regprocedure('pdc_work_categories_private.qc_lines_memo_fill_732(uuid)') IS NULL THEN RAISE EXCEPTION 'r735: run r732 first'; END IF;
  CREATE OR REPLACE FUNCTION pdc_work_categories_private.qc_lines_memo_fill_732(p_vehicle_id uuid) RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog' AS $b$
 BEGIN
  -- r732 (F342): transaction-scoped memo of a vehicle's QC lines, stamped with the cache epoch generations.
  IF p_vehicle_id IS NULL THEN RETURN; END IF;
  CREATE TEMP TABLE IF NOT EXISTS pdc_qc_lines_memo_732(vehicle_id uuid PRIMARY KEY, vgen bigint NOT NULL, ggen bigint NOT NULL, lines jsonb NOT NULL) ON COMMIT DROP;
  INSERT INTO pg_temp.pdc_qc_lines_memo_732(vehicle_id, vgen, ggen, lines)
  SELECT p_vehicle_id,
    coalesce((SELECT gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch WHERE vehicle_id = p_vehicle_id), 0),
    coalesce((SELECT gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch WHERE vehicle_id = '00000000-0000-0000-0000-000000000000'::uuid), 0),
    public.pdc_qc_operation_lines_379_uncached(p_vehicle_id)
  ON CONFLICT (vehicle_id) DO UPDATE SET vgen = excluded.vgen, ggen = excluded.ggen, lines = excluded.lines WHERE true; -- pg-safeupdate convention (r735)
 END $b$;
  REVOKE ALL ON FUNCTION pdc_work_categories_private.qc_lines_memo_fill_732(uuid) FROM PUBLIC, anon, authenticated;
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid = to_regprocedure('pdc_work_categories_private.qc_lines_memo_fill_732(uuid)');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_md5, updated_at = clock_timestamp()
  WHERE signature = 'pdc_work_categories_private.qc_lines_memo_fill_732(uuid)' AND release = 'r732' AND prosrc_md5 IS DISTINCT FROM v_md5;
END $r735$;

DO $post735$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('qc_lines_memo_732','protected_function_md5s','regression_checks_self_test') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r735: % red after apply: %', r.check_name, left(r.detail, 160); END IF;
  END LOOP;
END $post735$;
