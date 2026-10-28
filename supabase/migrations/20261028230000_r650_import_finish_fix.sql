-- r650 (F265). Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Kajel's first chunked run: submit_finish failed (42P10) because UPDATE ... FROM LATERAL referenced the UPDATE target.
-- Fix: holds set with a correlated subquery. Nothing else changes. Pins stay 241.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';
DO $guard650$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r650: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r650: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r650: pin count'; END IF;
END $guard650$;

CREATE OR REPLACE FUNCTION pdc_import_620.submit_finish(p_job uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_job pdc_import_620.jobs; v_new integer; v_status text := 'queued'; v_note text; v_part integer := 0; v_cur integer := 0; v_s record; v_parts integer;
BEGIN
  PERFORM pdc_import_620.require_management();
  SELECT * INTO v_job FROM pdc_import_620.jobs WHERE job_id = p_job FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'loading' THEN RAISE EXCEPTION 'job_not_loading'; END IF;
  IF v_job.rows_loaded = 0 THEN RAISE EXCEPTION 'no_rows'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'job_already_running'; END IF;
  -- r650 (F265): correlated subquery (a LATERAL in UPDATE ... FROM cannot see the target row).
  UPDATE pdc_import_620.job_rows r SET held_reason = (
    SELECT h.reason FROM pdc_import_620.holds h
    WHERE h.active AND h.stock_number = r.stock_number
      AND (h.repair_order_number IS NULL OR h.repair_order_number = r.row->>'repair_order_number')
      AND (h.original_line_number IS NULL OR h.original_line_number = (r.row->>'original_line_number')::integer)
    ORDER BY h.hold_id LIMIT 1)
  WHERE r.job_id = p_job;
  SELECT count(DISTINCT stock_number) INTO v_new FROM pdc_import_620.job_rows
  WHERE job_id = p_job AND held_reason IS NULL AND row->'raw_row'->'identity_r479'->>'basis' = 'new_board_vehicle';
  IF v_job.mode = 'apply' AND v_new > 15 THEN v_status := 'held'; v_note := format('sanity gate: %s new board vehicles (more than 15)', v_new); END IF;
  CREATE TEMP TABLE IF NOT EXISTS pdc620_stock_part (stock text PRIMARY KEY, part integer) ON COMMIT DROP;
  TRUNCATE pdc620_stock_part;
  FOR v_s IN SELECT stock_number, count(*) n, min(ord) first_ord FROM pdc_import_620.job_rows
             WHERE job_id = p_job AND held_reason IS NULL GROUP BY stock_number ORDER BY min(ord) LOOP
    IF v_cur > 0 AND v_cur + v_s.n > 180 THEN v_part := v_part + 1; v_cur := 0; END IF;
    INSERT INTO pdc620_stock_part VALUES (v_s.stock_number, v_part);
    v_cur := v_cur + v_s.n;
  END LOOP;
  UPDATE pdc_import_620.job_rows r SET part = sp.part FROM pdc620_stock_part sp WHERE r.job_id = p_job AND r.stock_number = sp.stock;
  SELECT count(DISTINCT part) INTO v_parts FROM pdc_import_620.job_rows WHERE job_id = p_job AND part IS NOT NULL;
  UPDATE pdc_import_620.jobs SET status = v_status, note = v_note, n_parts = v_parts,
    holds = (SELECT coalesce(jsonb_agg(jsonb_build_object('stock', stock_number, 'ro', row->>'repair_order_number', 'line', row->>'original_line_number',
             'reason', held_reason, 'at', 'submit') ORDER BY ord), '[]') FROM pdc_import_620.job_rows WHERE job_id = p_job AND held_reason IS NOT NULL),
    finished_at = CASE WHEN v_status = 'held' THEN clock_timestamp() END
  WHERE job_id = p_job;
  RETURN jsonb_build_object('ok', true, 'job_id', p_job, 'status', v_status, 'note', v_note, 'rows_loaded', v_job.rows_loaded,
    'rows_sent', (SELECT count(*) FROM pdc_import_620.job_rows WHERE job_id = p_job AND held_reason IS NULL),
    'rows_held', (SELECT count(*) FROM pdc_import_620.job_rows WHERE job_id = p_job AND held_reason IS NOT NULL),
    'stocks', (SELECT count(DISTINCT stock_number) FROM pdc_import_620.job_rows WHERE job_id = p_job),
    'new_board_vehicles', v_new, 'partitions', v_parts);
END $fn$;
REVOKE ALL ON FUNCTION pdc_import_620.submit_finish(uuid) FROM PUBLIC, anon, authenticated, service_role;
