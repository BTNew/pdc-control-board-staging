-- r641 (F256) / sort 381. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Kajel's first r620 preview (28 Oct 12:30 file, 6885 rows, about 28 MB) timed out in submit: rows were appended one by
-- one with || (quadratic) and the whole file had to fit one request. Fix:
--   * rows go into a table (pdc_import_620.job_rows), loaded in chunks: submit_begin -> add_rows (any number of calls,
--     keep each under about 1-2 MB) -> submit_finish. submit_service_whole stays for small files and uses the same path.
--   * holds, the new-vehicle gate and partitioning are set-based (one UPDATE / one SELECT; the greedy 180-row packing
--     only walks the ~400 stock counts, never the row bodies).
--   * each step reads only its own partition's rows.
-- Same guards, pins, locks, unban/re-ban and snapshots as r620. Pins stay 241.
-- Undo: supabase/rollbacks/20261028220000_r641_one_step_import_chunks.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard641$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r641: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r641: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r641: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 381 OR fault_id = 'F256' OR added_in = 'r641' OR check_name = 'one_step_import_chunks_641') THEN
    RAISE EXCEPTION 'r641: sort 381 or F256 is taken';
  END IF;
  IF to_regnamespace('pdc_import_620') IS NULL OR to_regclass('pdc_import_620.job_rows') IS NOT NULL THEN RAISE EXCEPTION 'r641: r620 missing or r641 already there'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r641: a job is running'; END IF;
END $guard641$;

-- The test job from the r620 install (failed at its first step, never touched the board).
DELETE FROM pdc_import_620.jobs WHERE job_id = 'cc9b562d-4516-4127-9dc4-ca3e937463c3' AND status = 'failed';

-- Kajel's current stock holds from the 28 Oct 12:30 run (preview/apply holds), carried over like staff-lock-holds.json.
INSERT INTO pdc_import_620.holds (stock_number, reason)
SELECT v.stock, v.reason FROM (VALUES
  ('U159812', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13056870', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13056871', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13056872', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13017933', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13048526', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('U152943', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('1HHZ681', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13048522', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13070895', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13070899', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('1GQP121', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13019220', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13047346', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13070900', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('12329493', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('12710970', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13077191', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13071999', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13091191', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13109750', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13109746', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13109749', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13109751', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13109748', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13136259', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13109752', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13109747', 'carried_from_kajel_20261028:preview_or_apply_hold'),
  ('13094083', 'carried_from_kajel_20261028:preview_or_apply_hold')) v(stock, reason)
WHERE NOT EXISTS (SELECT 1 FROM pdc_import_620.holds h WHERE h.active AND h.stock_number = v.stock AND h.repair_order_number IS NULL AND h.original_line_number IS NULL);

ALTER TABLE pdc_import_620.jobs DROP CONSTRAINT IF EXISTS jobs_status_check;
ALTER TABLE pdc_import_620.jobs ADD CONSTRAINT jobs_status_check CHECK (status IN ('loading', 'queued', 'running', 'done', 'held', 'failed'));
ALTER TABLE pdc_import_620.jobs ADD COLUMN n_parts integer NOT NULL DEFAULT 0;
ALTER TABLE pdc_import_620.jobs ADD COLUMN rows_loaded integer NOT NULL DEFAULT 0;

CREATE TABLE pdc_import_620.job_rows (
  job_id uuid NOT NULL REFERENCES pdc_import_620.jobs(job_id) ON DELETE CASCADE,
  ord integer NOT NULL,
  stock_number text NOT NULL,
  part integer,                 -- 0-based partition, set by submit_finish
  held_reason text,             -- not sent (hold)
  row jsonb NOT NULL,
  PRIMARY KEY (job_id, ord)
);
CREATE INDEX job_rows_part_620 ON pdc_import_620.job_rows (job_id, part, ord);
REVOKE ALL ON pdc_import_620.job_rows FROM PUBLIC, anon, authenticated, service_role;

-- Rows of one partition that are still to be sent, in file order.
CREATE FUNCTION pdc_import_620.part_rows(p_job uuid, p_part integer) RETURNS jsonb LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $fn$
  SELECT coalesce(jsonb_agg(r.row ORDER BY r.ord), '[]'::jsonb) FROM pdc_import_620.job_rows r
  WHERE r.job_id = p_job AND r.part = p_part AND r.held_reason IS NULL
$fn$;

CREATE FUNCTION pdc_import_620.submit_begin(p_workbook_sha256 text, p_envelope jsonb, p_mode text DEFAULT 'preview')
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_job uuid;
BEGIN
  PERFORM pdc_import_620.require_management();
  IF p_mode NOT IN ('preview', 'apply') OR p_workbook_sha256 !~ '^[0-9a-f]{64}$' OR jsonb_typeof(p_envelope->'provenance') IS DISTINCT FROM 'object'
     OR coalesce(p_envelope->>'filename', '') = '' OR coalesce(p_envelope->>'gmail_message_id', '') = '' THEN
    RAISE EXCEPTION 'bad_request (needs workbook sha256, mode, and envelope with filename, gmail_message_id and provenance)';
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'job_already_running'; END IF;
  DELETE FROM pdc_import_620.jobs WHERE status = 'loading' AND created_at < clock_timestamp() - interval '6 hours';
  INSERT INTO pdc_import_620.jobs (report, mode, status, workbook_sha256, envelope, partitions)
  VALUES ('service_whole', p_mode, 'loading', p_workbook_sha256, p_envelope, '[]') RETURNING job_id INTO v_job;
  RETURN jsonb_build_object('ok', true, 'job_id', v_job, 'status', 'loading');
END $fn$;

CREATE FUNCTION pdc_import_620.add_rows(p_job uuid, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_job pdc_import_620.jobs; v_base integer; v_n integer;
BEGIN
  PERFORM pdc_import_620.require_management();
  SELECT * INTO v_job FROM pdc_import_620.jobs WHERE job_id = p_job FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'loading' THEN RAISE EXCEPTION 'job_not_loading'; END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) = 0 THEN RAISE EXCEPTION 'bad_rows'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) r
             WHERE coalesce(r->>'department', '') NOT IN ('138', '139') OR r->>'workbook_sha256' IS DISTINCT FROM v_job.workbook_sha256
                OR coalesce(r->>'stock_number', '') = '') THEN
    RAISE EXCEPTION 'row_outside_contract';
  END IF;
  v_base := v_job.rows_loaded;
  INSERT INTO pdc_import_620.job_rows (job_id, ord, stock_number, row)
  SELECT p_job, v_base + t.o::integer, t.r->>'stock_number', t.r FROM jsonb_array_elements(p_rows) WITH ORDINALITY t(r, o);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE pdc_import_620.jobs SET rows_loaded = rows_loaded + v_n WHERE job_id = p_job;
  RETURN jsonb_build_object('ok', true, 'job_id', p_job, 'added', v_n, 'rows_loaded', v_base + v_n);
END $fn$;

CREATE FUNCTION pdc_import_620.submit_finish(p_job uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_job pdc_import_620.jobs; v_new integer; v_status text := 'queued'; v_note text; v_part integer := 0; v_cur integer := 0; v_s record; v_parts integer;
BEGIN
  PERFORM pdc_import_620.require_management();
  SELECT * INTO v_job FROM pdc_import_620.jobs WHERE job_id = p_job FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'loading' THEN RAISE EXCEPTION 'job_not_loading'; END IF;
  IF v_job.rows_loaded = 0 THEN RAISE EXCEPTION 'no_rows'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'job_already_running'; END IF;
  -- Holds, set-based.
  UPDATE pdc_import_620.job_rows r SET held_reason = h.reason
  FROM LATERAL (SELECT h.reason FROM pdc_import_620.holds h
                WHERE h.active AND h.stock_number = r.stock_number
                  AND (h.repair_order_number IS NULL OR h.repair_order_number = r.row->>'repair_order_number')
                  AND (h.original_line_number IS NULL OR h.original_line_number = (r.row->>'original_line_number')::integer)
                ORDER BY h.hold_id LIMIT 1) h
  WHERE r.job_id = p_job;
  SELECT count(DISTINCT stock_number) INTO v_new FROM pdc_import_620.job_rows
  WHERE job_id = p_job AND held_reason IS NULL AND row->'raw_row'->'identity_r479'->>'basis' = 'new_board_vehicle';
  IF v_job.mode = 'apply' AND v_new > 15 THEN v_status := 'held'; v_note := format('sanity gate: %s new board vehicles (more than 15)', v_new); END IF;
  -- Partitions as build-parts.py: by stock in first-appearance order, at most 180 rows, a stock never split.
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

-- Small files: one call, same path.
CREATE OR REPLACE FUNCTION pdc_import_620.submit_service_whole(p_rows jsonb, p_workbook_sha256 text, p_envelope jsonb, p_mode text DEFAULT 'preview')
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_job uuid;
BEGIN
  v_job := (pdc_import_620.submit_begin(p_workbook_sha256, p_envelope, p_mode)->>'job_id')::uuid;
  PERFORM pdc_import_620.add_rows(v_job, p_rows);
  RETURN pdc_import_620.submit_finish(v_job);
END $fn$;

CREATE OR REPLACE FUNCTION pdc_import_620.hold_stocks(p_job uuid, p_part integer, p_stocks text[], p_reason text)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
BEGIN
  UPDATE pdc_import_620.jobs j SET holds = j.holds || (SELECT coalesce(jsonb_agg(jsonb_build_object('stock', s, 'part', p_part + 1, 'reason', p_reason,
      'lines', (SELECT count(*) FROM pdc_import_620.job_rows r WHERE r.job_id = p_job AND r.part = p_part AND r.stock_number = s AND r.held_reason IS NULL))), '[]')
    FROM unnest(p_stocks) s)
  WHERE j.job_id = p_job;
  UPDATE pdc_import_620.job_rows SET held_reason = p_reason
  WHERE job_id = p_job AND part = p_part AND stock_number = ANY (p_stocks) AND held_reason IS NULL;
  INSERT INTO pdc_import_620.holds (stock_number, reason, source_job) SELECT DISTINCT s, p_reason, p_job FROM unnest(p_stocks) s
  WHERE NOT EXISTS (SELECT 1 FROM pdc_import_620.holds h WHERE h.active AND h.stock_number = s AND h.repair_order_number IS NULL AND h.original_line_number IS NULL);
  RETURN pdc_import_620.part_rows(p_job, p_part);
END $fn$;

CREATE OR REPLACE FUNCTION pdc_import_620.preview_part(p_job uuid, p_part integer)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_job pdc_import_620.jobs; v_rows jsonb; v_result jsonb; v_stocks text[]; v_try integer := 0;
BEGIN
  PERFORM set_config('lock_timeout', '20s', true); PERFORM set_config('statement_timeout', '120s', true);
  PERFORM pdc_import_620.require_management();
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)) <> 'ea9a62537a146f05a01e866c636d367b' THEN RAISE EXCEPTION 'preview_contract_changed'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)) <> '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'row_validator_contract_changed'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911', 0));
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation', 0));
  LOCK TABLE public.vehicles, public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
  LOOP
    v_try := v_try + 1;
    SELECT * INTO STRICT v_job FROM pdc_import_620.jobs WHERE job_id = p_job;
    v_rows := pdc_import_620.part_rows(p_job, p_part);
    IF jsonb_array_length(v_rows) = 0 THEN RETURN jsonb_build_object('part', p_part + 1, 'rows', 0, 'skipped', 'all_rows_held'); END IF;
    v_result := pdc_import_620.preview_rows(v_job, p_part + 1, v_rows);
    IF v_result->>'ok' = 'true' AND v_result->>'apply_allowed' = 'true' AND coalesce((v_result->'operations'->>'conflict')::integer, 0) = 0 THEN
      RETURN jsonb_build_object('part', p_part + 1, 'rows', jsonb_array_length(v_rows), 'source_hash', v_result->>'source_hash_620',
        'preview_batch_id', v_result->>'preview_batch_id', 'operations', v_result->'operations', 'tries', v_try);
    END IF;
    SELECT array_agg(DISTINCT r.stock_number) INTO v_stocks FROM public.pdc_pilbara_service_import_rows r
    WHERE r.batch_id = (v_result->>'preview_batch_id')::uuid AND r.decision = 'conflict';
    IF v_stocks IS NULL OR v_try >= 12 THEN RAISE EXCEPTION 'preview_not_allowed part % %', p_part + 1, left(v_result::text, 1500); END IF;
    PERFORM pdc_import_620.hold_stocks(p_job, p_part, v_stocks, 'conflict:' || coalesce((SELECT string_agg(DISTINCT r.reason, ',') FROM public.pdc_pilbara_service_import_rows r
      WHERE r.batch_id = (v_result->>'preview_batch_id')::uuid AND r.decision = 'conflict'), 'conflict'));
  END LOOP;
END $fn$;

CREATE OR REPLACE FUNCTION pdc_import_620.apply_part(p_job uuid, p_part integer, p_last boolean)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE
  v_job pdc_import_620.jobs; v_info jsonb; v_bid uuid; v_hash text; v_ban timestamptz; v_result jsonb; v_try integer := 0;
  protected_before text; protected_after text; kta_before jsonb; kta_after jsonb; r record; v text;
  parts_before jsonb; parts_after jsonb; staff_before jsonb; staff_after jsonb; v_stocks text[]; v_archived integer; v_prev jsonb;
BEGIN
  PERFORM set_config('lock_timeout', '240s', true); PERFORM set_config('statement_timeout', '300s', true);
  PERFORM pdc_import_620.require_management();
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)) <> 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'apply_contract_changed'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'::regprocedure)) <> '66379d312c3fddfd2eaab5b37c0ba497'
     OR md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)) <> '6083fb5bcf03d341d9101831c2217cb8' THEN RAISE EXCEPTION 'sublet_po_feed_contract_changed'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911', 0));
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation', 0));
  LOCK TABLE public.vehicles, public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
  LOOP
    v_try := v_try + 1;
    SELECT * INTO STRICT v_job FROM pdc_import_620.jobs WHERE job_id = p_job;
    v_info := v_job.parts->p_part;
    IF v_info ? 'skipped' THEN RETURN v_info; END IF;
    v_bid := (v_info->>'preview_batch_id')::uuid; v_hash := v_info->>'source_hash';
    v_stocks := NULL;
    BEGIN
      SELECT banned_until INTO STRICT v_ban FROM auth.users WHERE id = pdc_import_620.importer_id() FOR UPDATE;
      IF v_ban IS DISTINCT FROM pdc_import_620.importer_ban() THEN RAISE EXCEPTION 'unexpected_importer_state'; END IF;
      SELECT md5(jsonb_build_object('confirmations', (SELECT jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::text) FROM public.pdc_parts_completion_email_confirmations c),
        'manual_parts', (SELECT jsonb_agg(to_jsonb(u) ORDER BY to_jsonb(u)::text) FROM public.vehicle_parts_updates u))::text) INTO protected_before;
      SELECT jsonb_object_agg(id::text, jsonb_build_object('parts_attached', parts_attached, 'backorder', backorder, 'po_flag', po_flag,
        'parts_snapshot_at', parts_snapshot_at, 'parts_receipt_id', parts_receipt_id)) INTO parts_before FROM pdc_parts_private.jobs;
      SELECT coalesce(jsonb_object_agg(adjustment_id::text, to_jsonb(a)), '{}') INTO staff_before FROM public.vehicle_workshop_line_adjustments a WHERE active AND manual_assignment_locked;
      kta_before := '{}';
      FOR r IN SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ('karratha135_pdc', 'karratha135_parts', 'karratha135_intake') ORDER BY schemaname, tablename LOOP
        EXECUTE format($k$SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text)::text,'[]')) FROM %I.%I x$k$, r.schemaname, r.tablename) INTO v;
        kta_before := kta_before || jsonb_build_object(r.schemaname || '.' || r.tablename, v);
      END LOOP;
      UPDATE auth.users SET banned_until = NULL WHERE id = pdc_import_620.importer_id();
      v_result := public.pdc_pilbara_service_apply_v1(v_bid, v_hash, 'codex-owner-email-apply-' || v_hash);
      IF v_result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'apply_failed %', left(v_result::text, 1500); END IF;
      UPDATE auth.users SET banned_until = v_ban WHERE id = pdc_import_620.importer_id();
      IF (SELECT banned_until FROM auth.users WHERE id = pdc_import_620.importer_id()) IS DISTINCT FROM v_ban THEN RAISE EXCEPTION 'importer_restore_failed'; END IF;
      SELECT md5(jsonb_build_object('confirmations', (SELECT jsonb_agg(to_jsonb(c) ORDER BY to_jsonb(c)::text) FROM public.pdc_parts_completion_email_confirmations c),
        'manual_parts', (SELECT jsonb_agg(to_jsonb(u) ORDER BY to_jsonb(u)::text) FROM public.vehicle_parts_updates u))::text) INTO protected_after;
      SELECT jsonb_object_agg(id::text, jsonb_build_object('parts_attached', parts_attached, 'backorder', backorder, 'po_flag', po_flag,
        'parts_snapshot_at', parts_snapshot_at, 'parts_receipt_id', parts_receipt_id)) INTO parts_after FROM pdc_parts_private.jobs;
      SELECT coalesce(jsonb_object_agg(adjustment_id::text, to_jsonb(a)), '{}') INTO staff_after FROM public.vehicle_workshop_line_adjustments a WHERE active AND manual_assignment_locked;
      -- existing_staff_estimate_or_choice_changed / new_adjustment_not_audited_to_exact_current_source: hold those stocks.
      SELECT array_agg(DISTINCT vv.stock_number) INTO v_stocks FROM jsonb_each(staff_before) o JOIN public.vehicles vv ON vv.id = (o.value->>'vehicle_id')::uuid
      WHERE (staff_after->o.key) - ARRAY['version','updated_at','updated_by'] IS DISTINCT FROM o.value - ARRAY['version','updated_at','updated_by'];
      IF v_stocks IS NULL THEN
        SELECT array_agg(DISTINCT vv.stock_number) INTO v_stocks FROM public.vehicle_workshop_line_adjustments a JOIN public.vehicles vv ON vv.id = a.vehicle_id
        WHERE a.active AND a.manual_assignment_locked AND NOT staff_before ? a.adjustment_id::text
          AND NOT EXISTS (SELECT 1 FROM public.pdc_tune_operation_change_reviews rv JOIN public.pdc_pilbara_service_import_rows sr ON sr.evidence_id = rv.evidence_id
            WHERE rv.batch_id = (v_result->>'apply_batch_id')::uuid AND sr.batch_id = v_bid AND rv.status = 'approved' AND rv.automation_result->>'ok' = 'true'
              AND rv.vehicle_id = a.vehicle_id AND rv.automation_result->'data'->'operation'->>'line_identity' = a.line_key
              AND (rv.automation_result->'data'->'operation'->>'estimated_hours')::numeric = a.estimated_hours
              AND rv.proposed_source->>'workbook_sha256' = v_job.workbook_sha256);
      END IF;
      IF v_stocks IS NOT NULL THEN RAISE EXCEPTION 'pdc620_staff_hold'; END IF;
      SELECT count(*) INTO v_archived FROM public.vehicles vv WHERE vv.board_purged_at >= now();
      IF NOT p_last AND v_archived <> 0 THEN RAISE EXCEPTION 'archive_count_not_0 %', v_archived; END IF;
      IF p_last AND v_archived > 15 THEN v_stocks := ARRAY[]::text[]; RAISE EXCEPTION 'pdc620_archive_gate'; END IF;
      IF EXISTS (SELECT 1 FROM public.navision_backend_records n WHERE n.dealer_code IN ('37047','037047','14450','014450') AND n.updated_at >= now()) THEN RAISE EXCEPTION 'sales_written'; END IF;
      IF protected_before IS DISTINCT FROM protected_after THEN RAISE EXCEPTION 'staff_or_person_parts_state_changed'; END IF;
      IF EXISTS (SELECT 1 FROM jsonb_each(parts_before) e WHERE parts_after->e.key IS DISTINCT FROM e.value) THEN RAISE EXCEPTION 'existing_parts_flags_changed_by_service'; END IF;
      kta_after := '{}';
      FOR r IN SELECT schemaname, tablename FROM pg_tables WHERE schemaname IN ('karratha135_pdc', 'karratha135_parts', 'karratha135_intake') ORDER BY schemaname, tablename LOOP
        EXECUTE format($k$SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text)::text,'[]')) FROM %I.%I x$k$, r.schemaname, r.tablename) INTO v;
        kta_after := kta_after || jsonb_build_object(r.schemaname || '.' || r.tablename, v);
      END LOOP;
      IF kta_before IS DISTINCT FROM kta_after THEN RAISE EXCEPTION 'parked135_state_changed'; END IF;
      IF v_result->'sublet_pos' IS NULL THEN RAISE EXCEPTION 'r442_apply_without_sublet_pos'; END IF;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM = 'pdc620_archive_gate' THEN
        RETURN jsonb_build_object('part', p_part + 1, 'held', true, 'reason', format('sanity gate: would archive %s vehicles (more than 15); this partition was rolled back', v_archived));
      ELSIF SQLERRM <> 'pdc620_staff_hold' THEN
        RAISE;
      END IF;
    END;
    IF v_stocks IS NULL THEN
      RETURN jsonb_build_object('part', p_part + 1, 'ok', true, 'tries', v_try, 'archived_now', v_archived, 'insert', v_result->'insert', 'update', v_result->'update',
        'archived', v_result->'archived', 'sublet_pos_ok', coalesce((v_result->'sublet_pos'->>'ok')::boolean, false), 'apply_batch_id', v_result->>'apply_batch_id');
    END IF;
    IF v_try >= 6 THEN RAISE EXCEPTION 'staff_hold_loop part %', p_part + 1; END IF;
    PERFORM pdc_import_620.hold_stocks(p_job, p_part, v_stocks, 'staff_locked_hours');
    SELECT * INTO STRICT v_job FROM pdc_import_620.jobs WHERE job_id = p_job;
    IF jsonb_array_length(pdc_import_620.part_rows(p_job, p_part)) = 0 THEN
      v_prev := jsonb_build_object('part', p_part + 1, 'rows', 0, 'skipped', 'all_rows_held');
    ELSE
      v_result := pdc_import_620.preview_rows(v_job, p_part + 1, pdc_import_620.part_rows(p_job, p_part));
      IF v_result->>'ok' IS DISTINCT FROM 'true' OR v_result->>'apply_allowed' IS DISTINCT FROM 'true' OR coalesce((v_result->'operations'->>'conflict')::integer, 0) <> 0 THEN
        RAISE EXCEPTION 'repreview_not_allowed part % %', p_part + 1, left(v_result::text, 1500);
      END IF;
      v_prev := jsonb_build_object('part', p_part + 1, 'rows', jsonb_array_length(pdc_import_620.part_rows(p_job, p_part)), 'source_hash', v_result->>'source_hash_620',
        'preview_batch_id', v_result->>'preview_batch_id', 'operations', v_result->'operations', 'repreviewed_after_staff_hold', true);
    END IF;
    UPDATE pdc_import_620.jobs SET parts = jsonb_set(parts, ARRAY[p_part::text], v_prev) WHERE job_id = p_job;
  END LOOP;
END $fn$;

CREATE OR REPLACE PROCEDURE pdc_import_620.run_jobs()
LANGUAGE plpgsql AS $proc$
DECLARE
  v_job pdc_import_620.jobs; v_n integer; v_i integer; v_step jsonb; v_err text; v_held text; v_apply boolean;
  v_start timestamptz := pg_catalog.clock_timestamp();
  v_budget interval := CASE WHEN pg_catalog.current_setting('statement_timeout') IN ('0', '0ms') THEN interval '50 minutes' ELSE interval '40 seconds' END;
BEGIN
  IF NOT pg_catalog.pg_try_advisory_lock(pg_catalog.hashtextextended('pdc_import_620.run_jobs', 0)) THEN RETURN; END IF;
  LOOP
    SELECT * INTO v_job FROM pdc_import_620.jobs WHERE status IN ('queued', 'running') ORDER BY created_at LIMIT 1;
    EXIT WHEN v_job.job_id IS NULL OR pg_catalog.clock_timestamp() - v_start > v_budget;
    IF v_job.status = 'queued' THEN
      UPDATE pdc_import_620.jobs SET status = 'running', started_at = pg_catalog.clock_timestamp(), parts = '[]', step_attempts = 0 WHERE job_id = v_job.job_id;
      COMMIT; CONTINUE;
    END IF;
    v_n := v_job.n_parts;
    v_i := pg_catalog.jsonb_array_length(v_job.parts);
    v_apply := false;
    IF v_i >= v_n THEN
      IF v_job.mode = 'preview' THEN
        UPDATE pdc_import_620.jobs SET status = 'done', finished_at = pg_catalog.clock_timestamp() WHERE job_id = v_job.job_id; COMMIT; CONTINUE;
      END IF;
      SELECT pg_catalog.min(o - 1) INTO v_i FROM pg_catalog.jsonb_array_elements(v_job.parts) WITH ORDINALITY t(p, o) WHERE NOT (p ? 'apply');
      IF v_i IS NULL THEN
        UPDATE pdc_import_620.jobs SET status = 'done', finished_at = pg_catalog.clock_timestamp() WHERE job_id = v_job.job_id; COMMIT; CONTINUE;
      END IF;
      v_apply := true;
    END IF;
    IF v_job.step_attempts >= 3 THEN
      UPDATE pdc_import_620.jobs SET status = 'failed', error = pg_catalog.format('%s part %s did not finish after 3 tries', CASE WHEN v_apply THEN 'apply' ELSE 'preview' END, v_i + 1),
        finished_at = pg_catalog.clock_timestamp() WHERE job_id = v_job.job_id;
      COMMIT; CONTINUE;
    END IF;
    UPDATE pdc_import_620.jobs SET step_attempts = step_attempts + 1 WHERE job_id = v_job.job_id;
    COMMIT;
    v_err := NULL; v_held := NULL;
    BEGIN
      IF v_apply THEN
        v_step := pdc_import_620.apply_part(v_job.job_id, v_i, v_i = v_n - 1);
        UPDATE pdc_import_620.jobs SET parts = pg_catalog.jsonb_set(parts, ARRAY[v_i::text], parts->v_i || pg_catalog.jsonb_build_object('apply', v_step)), step_attempts = 0
        WHERE job_id = v_job.job_id;
        IF v_step->>'held' = 'true' THEN v_held := v_step->>'reason'; END IF;
      ELSE
        v_step := pdc_import_620.preview_part(v_job.job_id, v_i);
        UPDATE pdc_import_620.jobs SET parts = parts || pg_catalog.jsonb_build_array(v_step), step_attempts = 0 WHERE job_id = v_job.job_id;
      END IF;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
    END;
    IF v_err IS NOT NULL OR v_held IS NOT NULL THEN
      UPDATE pdc_import_620.jobs SET status = CASE WHEN v_err IS NULL THEN 'held' ELSE 'failed' END,
        error = CASE WHEN v_err IS NULL THEN NULL ELSE pg_catalog.format('%s part %s: %s', CASE WHEN v_apply THEN 'apply' ELSE 'preview' END, v_i + 1, v_err) END,
        note = coalesce(v_held, note), finished_at = pg_catalog.clock_timestamp() WHERE job_id = v_job.job_id;
    END IF;
    COMMIT;
  END LOOP;
  PERFORM pg_catalog.pg_advisory_unlock(pg_catalog.hashtextextended('pdc_import_620.run_jobs', 0));
END $proc$;

CREATE OR REPLACE FUNCTION pdc_import_620.job_receipt(p_job uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public AS $fn$
DECLARE j pdc_import_620.jobs;
BEGIN
  PERFORM pdc_import_620.require_management();
  SELECT * INTO j FROM pdc_import_620.jobs WHERE job_id = p_job;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'job_not_found'); END IF;
  RETURN jsonb_build_object('ok', true, 'job_id', j.job_id, 'mode', j.mode, 'status', j.status, 'note', j.note, 'error', j.error,
    'created_at', j.created_at, 'started_at', j.started_at, 'finished_at', j.finished_at,
    'partitions', j.n_parts, 'rows_loaded', j.rows_loaded, 'previewed', (SELECT count(*) FROM jsonb_array_elements(j.parts) p WHERE p ? 'preview_batch_id' OR p ? 'skipped'),
    'applied', (SELECT count(*) FROM jsonb_array_elements(j.parts) p WHERE p->'apply'->>'ok' = 'true'),
    'inserted', (SELECT coalesce(sum((p->'apply'->>'insert')::numeric), 0) FROM jsonb_array_elements(j.parts) p WHERE jsonb_typeof(p->'apply'->'insert') = 'number'),
    'updated', (SELECT coalesce(sum((p->'apply'->>'update')::numeric), 0) FROM jsonb_array_elements(j.parts) p WHERE jsonb_typeof(p->'apply'->'update') = 'number'),
    'archived_now', (SELECT coalesce(sum((p->'apply'->>'archived_now')::numeric), 0) FROM jsonb_array_elements(j.parts) p WHERE p->'apply' ? 'archived_now'),
    'holds', j.holds, 'parts', j.parts);
END $fn$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_import_620 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON PROCEDURE pdc_import_620.run_jobs() FROM PUBLIC, anon, authenticated, service_role;

DO $check641$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('one_step_import_chunks_641', 'F256',
    'One-step import loads rows in chunks into a private table and builds holds and partitions set-based; still private and pinned.',
    $chk641$
SELECT
  to_regclass('pdc_import_620.job_rows') IS NOT NULL
  AND NOT has_schema_privilege('authenticated', 'pdc_import_620', 'USAGE')
  AND to_regprocedure('pdc_import_620.add_rows(uuid,jsonb)') IS NOT NULL
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.submit_service_whole(jsonb,text,jsonb,text)')), 'v_send ||') = 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.preview_part(uuid,integer)')), 'part_rows(p_job, p_part)') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.apply_part(uuid,integer,boolean)')), 'public.pdc_pilbara_service_apply_v1(') > 0
 AS ok,
 'one-step import loads in chunks and stays private' AS detail
$chk641$,
    true, 381, 'r641');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'one_step_import_chunks_641') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r641: check red: %', detail; END IF;
END $check641$;
