-- r620 (F235) / sort 379. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026: Kajel's Service as a Whole import takes about 200 calls and 40 to 60 minutes. Make it two calls.
--
-- Call 1 (Kajel, management connection): SELECT pdc_import_620.submit_service_whole(rows, workbook_sha256, envelope, 'preview'|'apply');
--   rows      = the prepared, enriched rows from prepare-service.py / build-parts.py (all of them, before partitioning)
--   envelope  = {mailbox, sender, gmail_message_id, filename, approval_evidence, provenance}
-- Worker: pg_cron runs CALL pdc_import_620.run_jobs() every minute (resumable, see run_jobs). It does exactly what Kajel's part-NN/preview.sql and
--   apply.sql do, one committed transaction per partition: same guards, md5 pins, advisory locks, LOCK TABLE, importer
--   unban/re-ban inside the transaction (a failure always rolls the unban back), same before/after snapshots and RAISEs.
--   Holds work as holdstock.py: a conflict at preview or a staff-locked change at apply holds the whole stock, the part is
--   re-previewed without it. Holds carry forward to the next run like staff-lock-holds.json / line-holds.json.
--   Sanity gate: more than 15 new board vehicles holds the run before anything is sent; the last partition (which archives)
--   is rolled back and the run held if it would archive more than 15.
-- Call 2 (Kajel): SELECT pdc_import_620.job_receipt(job_id);  (status queued / running / done / held / failed)
--
-- Existing import functions are called unchanged; Kajel's pinned md5s stay. Pins stay 241. Department 135 untouched.
-- Kajel still records the snapshot (record_snapshot_479) before an apply job, as today.
-- Undo: supabase/rollbacks/20261028190000_r620_one_step_import.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard620$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r620: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r620: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r620: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 379 OR fault_id = 'F235' OR added_in = 'r620' OR check_name = 'one_step_import_620') THEN
    RAISE EXCEPTION 'r620: sort 379 or F232 is taken';
  END IF;
  IF to_regnamespace('pdc_import_620') IS NOT NULL THEN RAISE EXCEPTION 'r620: schema exists'; END IF;
END $guard620$;

CREATE SCHEMA pdc_import_620;
REVOKE ALL ON SCHEMA pdc_import_620 FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE pdc_import_620.jobs (
  job_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report text NOT NULL CHECK (report = 'service_whole'),
  mode text NOT NULL CHECK (mode IN ('preview', 'apply')),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'done', 'held', 'failed')),
  workbook_sha256 text NOT NULL CHECK (workbook_sha256 ~ '^[0-9a-f]{64}$'),
  envelope jsonb NOT NULL,
  partitions jsonb NOT NULL CHECK (jsonb_typeof(partitions) = 'array'),
  parts jsonb NOT NULL DEFAULT '[]',       -- per partition: rows, source_hash, preview_batch_id, apply result
  holds jsonb NOT NULL DEFAULT '[]',       -- rows not sent, with reasons
  note text,
  error text,
  step_attempts integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  started_at timestamptz,
  finished_at timestamptz
);

CREATE TABLE pdc_import_620.holds (
  hold_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  stock_number text NOT NULL,
  repair_order_number text,                -- NULL = every R/O of the stock
  original_line_number integer,            -- NULL = every line
  reason text NOT NULL,
  source_job uuid,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- Standing holds from Kajel's README.
INSERT INTO pdc_import_620.holds (stock_number, original_line_number, reason) VALUES
  ('13044312', 7, 'standing_hold:L7'),
  ('13042994', NULL, 'standing_hold:perth_delivery'),
  ('13092999', NULL, 'standing_hold:perth_delivery'),
  ('13073002', NULL, 'standing_hold:perth_delivery');
REVOKE ALL ON ALL TABLES IN SCHEMA pdc_import_620 FROM PUBLIC, anon, authenticated, service_role;

-- Kajel's importer service user and its normal ban.
CREATE FUNCTION pdc_import_620.importer_id() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '0640d2f1-9f97-4e20-8a4f-cb6069b005df'::uuid $$;
CREATE FUNCTION pdc_import_620.importer_ban() RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$ SELECT '2126-08-21T11:05:10.641388+00:00'::timestamptz $$;

CREATE FUNCTION pdc_import_620.require_management() RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
BEGIN
  IF pdc_codex_intake_private.management_connection() IS NOT TRUE OR public.pdc_monitor_staging_guard() IS NOT TRUE THEN
    RAISE EXCEPTION 'staging_management_required';
  END IF;
END $fn$;

CREATE FUNCTION pdc_import_620.held(p_row jsonb) RETURNS text LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $fn$
  SELECT h.reason FROM pdc_import_620.holds h
  WHERE h.active AND h.stock_number = p_row->>'stock_number'
    AND (h.repair_order_number IS NULL OR h.repair_order_number = p_row->>'repair_order_number')
    AND (h.original_line_number IS NULL OR h.original_line_number = (p_row->>'original_line_number')::integer)
  ORDER BY h.hold_id LIMIT 1
$fn$;

-- Same partition rule as build-parts.py: by stock, in order of first appearance, at most 180 rows; a stock never spans two parts.
CREATE FUNCTION pdc_import_620.partition_rows(p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, public AS $fn$
DECLARE v_stock record; v_parts jsonb := '[]'; v_cur jsonb := '[]';
BEGIN
  FOR v_stock IN
    SELECT s.stock, jsonb_agg(s.r ORDER BY s.ord) rs, count(*) n
    FROM (SELECT r, ord, r->>'stock_number' stock, min(ord) OVER (PARTITION BY r->>'stock_number') first_ord
          FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(r, ord)) s
    GROUP BY s.stock, s.first_ord ORDER BY s.first_ord
  LOOP
    IF jsonb_array_length(v_cur) > 0 AND jsonb_array_length(v_cur) + v_stock.n > 180 THEN
      v_parts := v_parts || jsonb_build_array(v_cur); v_cur := '[]';
    END IF;
    v_cur := v_cur || v_stock.rs;
  END LOOP;
  IF jsonb_array_length(v_cur) > 0 THEN v_parts := v_parts || jsonb_build_array(v_cur); END IF;
  RETURN v_parts;
END $fn$;

-- Call 1.
CREATE FUNCTION pdc_import_620.submit_service_whole(p_rows jsonb, p_workbook_sha256 text, p_envelope jsonb, p_mode text DEFAULT 'preview')
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_job uuid; v_send jsonb := '[]'; v_holds jsonb := '[]'; v_r jsonb; v_reason text; v_new integer; v_status text := 'queued'; v_note text;
BEGIN
  PERFORM pdc_import_620.require_management();
  IF p_mode NOT IN ('preview', 'apply') OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) = 0
     OR p_workbook_sha256 !~ '^[0-9a-f]{64}$' OR jsonb_typeof(p_envelope->'provenance') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'bad_request';
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'job_already_running'; END IF;
  FOR v_r IN SELECT r FROM jsonb_array_elements(p_rows) r LOOP
    IF coalesce(v_r->>'department', '') NOT IN ('138', '139') OR v_r->>'workbook_sha256' IS DISTINCT FROM p_workbook_sha256 THEN
      RAISE EXCEPTION 'row_outside_contract';
    END IF;
    v_reason := pdc_import_620.held(v_r);
    IF v_reason IS NULL THEN v_send := v_send || jsonb_build_array(v_r);
    ELSE v_holds := v_holds || jsonb_build_array(jsonb_build_object('stock', v_r->>'stock_number', 'ro', v_r->>'repair_order_number',
      'line', v_r->>'original_line_number', 'reason', v_reason, 'at', 'submit'));
    END IF;
  END LOOP;
  SELECT count(DISTINCT r->>'stock_number') INTO v_new FROM jsonb_array_elements(v_send) r
  WHERE r->'raw_row'->'identity_r479'->>'basis' = 'new_board_vehicle';
  IF p_mode = 'apply' AND v_new > 15 THEN v_status := 'held'; v_note := format('sanity gate: %s new board vehicles (more than 15)', v_new); END IF;
  INSERT INTO pdc_import_620.jobs (report, mode, status, workbook_sha256, envelope, partitions, holds, note, finished_at)
  VALUES ('service_whole', p_mode, v_status, p_workbook_sha256, p_envelope, pdc_import_620.partition_rows(v_send), v_holds, v_note,
          CASE WHEN v_status = 'held' THEN clock_timestamp() END)
  RETURNING job_id INTO v_job;
  RETURN jsonb_build_object('ok', true, 'job_id', v_job, 'status', v_status, 'note', v_note, 'rows_sent', jsonb_array_length(v_send),
    'rows_held', jsonb_array_length(v_holds), 'new_board_vehicles', v_new,
    'partitions', (SELECT jsonb_array_length(partitions) FROM pdc_import_620.jobs WHERE job_id = v_job));
END $fn$;

-- One preview of one row set, exactly as partition-preview.sql (caller holds the locks). Returns the preview receipt.
CREATE FUNCTION pdc_import_620.preview_rows(p_job pdc_import_620.jobs, p_part integer, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_hash text := encode(extensions.digest(convert_to(p_rows::text, 'UTF8'), 'sha256'), 'hex'); v_ban timestamptz; v_result jsonb;
BEGIN
  INSERT INTO pdc_codex_intake_private.management_email_manifests
    (source_hash, workbook_sha256, server_rows_sha256, source_rows, mailbox, sender, gmail_message_id, filename, actor_id, approval_evidence, provenance)
  VALUES (v_hash, p_job.workbook_sha256, v_hash, jsonb_array_length(p_rows), p_job.envelope->>'mailbox', p_job.envelope->>'sender',
    p_job.envelope->>'gmail_message_id', p_job.envelope->>'filename', pdc_import_620.importer_id(), p_job.envelope->>'approval_evidence',
    (p_job.envelope->'provenance') || jsonb_build_object('partition', p_part, 'whole_stock_partition', true, 'one_step_job', p_job.job_id))
  ON CONFLICT (source_hash) DO NOTHING;
  SELECT banned_until INTO STRICT v_ban FROM auth.users WHERE id = pdc_import_620.importer_id() FOR UPDATE;
  IF v_ban IS DISTINCT FROM pdc_import_620.importer_ban() THEN RAISE EXCEPTION 'unexpected_importer_state'; END IF;
  UPDATE auth.users SET banned_until = NULL WHERE id = pdc_import_620.importer_id();
  v_result := public.pdc_pilbara_service_preview_v1(p_rows, v_hash, 'codex-owner-email-preview-' || v_hash);
  UPDATE auth.users SET banned_until = v_ban WHERE id = pdc_import_620.importer_id();
  IF (SELECT banned_until FROM auth.users WHERE id = pdc_import_620.importer_id()) IS DISTINCT FROM v_ban THEN RAISE EXCEPTION 'importer_restore_failed'; END IF;
  RETURN v_result || jsonb_build_object('source_hash_617', v_hash);
END $fn$;

-- Drop whole stocks from a partition and record the holds (holdstock.py).
CREATE FUNCTION pdc_import_620.hold_stocks(p_job uuid, p_part integer, p_stocks text[], p_reason text)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_rows jsonb; v_keep jsonb;
BEGIN
  SELECT partitions->p_part INTO v_rows FROM pdc_import_620.jobs WHERE job_id = p_job FOR UPDATE;
  SELECT coalesce(jsonb_agg(r ORDER BY o), '[]') INTO v_keep FROM jsonb_array_elements(v_rows) WITH ORDINALITY t(r, o) WHERE NOT (r->>'stock_number' = ANY (p_stocks));
  UPDATE pdc_import_620.jobs j SET partitions = jsonb_set(j.partitions, ARRAY[p_part::text], v_keep),
    holds = j.holds || (SELECT coalesce(jsonb_agg(jsonb_build_object('stock', s, 'part', p_part + 1, 'reason', p_reason,
      'lines', (SELECT count(*) FROM jsonb_array_elements(v_rows) r WHERE r->>'stock_number' = s))), '[]') FROM unnest(p_stocks) s)
  WHERE j.job_id = p_job;
  INSERT INTO pdc_import_620.holds (stock_number, reason, source_job) SELECT DISTINCT s, p_reason, p_job FROM unnest(p_stocks) s
  WHERE NOT EXISTS (SELECT 1 FROM pdc_import_620.holds h WHERE h.active AND h.stock_number = s AND h.repair_order_number IS NULL AND h.original_line_number IS NULL);
  RETURN v_keep;
END $fn$;

-- Preview step for one partition (one transaction). Conflicts hold the stock and re-preview.
CREATE FUNCTION pdc_import_620.preview_part(p_job uuid, p_part integer)
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
    v_rows := v_job.partitions->p_part;
    IF jsonb_array_length(v_rows) = 0 THEN RETURN jsonb_build_object('part', p_part + 1, 'rows', 0, 'skipped', 'all_rows_held'); END IF;
    v_result := pdc_import_620.preview_rows(v_job, p_part + 1, v_rows);
    IF v_result->>'ok' = 'true' AND v_result->>'apply_allowed' = 'true' AND coalesce((v_result->'operations'->>'conflict')::integer, 0) = 0 THEN
      RETURN jsonb_build_object('part', p_part + 1, 'rows', jsonb_array_length(v_rows), 'source_hash', v_result->>'source_hash_617',
        'preview_batch_id', v_result->>'preview_batch_id', 'operations', v_result->'operations', 'tries', v_try);
    END IF;
    SELECT array_agg(DISTINCT r.stock_number) INTO v_stocks FROM public.pdc_pilbara_service_import_rows r
    WHERE r.batch_id = (v_result->>'preview_batch_id')::uuid AND r.decision = 'conflict';
    IF v_stocks IS NULL OR v_try >= 12 THEN RAISE EXCEPTION 'preview_not_allowed part % %', p_part + 1, left(v_result::text, 1500); END IF;
    PERFORM pdc_import_620.hold_stocks(p_job, p_part, v_stocks, 'conflict:' || coalesce((SELECT string_agg(DISTINCT r.reason, ',') FROM public.pdc_pilbara_service_import_rows r
      WHERE r.batch_id = (v_result->>'preview_batch_id')::uuid AND r.decision = 'conflict'), 'conflict'));
  END LOOP;
END $fn$;

-- Apply step for one partition (one transaction), exactly as build-apply.py's apply.sql. A staff-locked change holds the
-- stock (subtransaction rolled back), re-previews and re-applies.
CREATE FUNCTION pdc_import_620.apply_part(p_job uuid, p_part integer, p_last boolean)
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
    IF jsonb_array_length(v_job.partitions->p_part) = 0 THEN
      v_prev := jsonb_build_object('part', p_part + 1, 'rows', 0, 'skipped', 'all_rows_held');
    ELSE
      v_result := pdc_import_620.preview_rows(v_job, p_part + 1, v_job.partitions->p_part);
      IF v_result->>'ok' IS DISTINCT FROM 'true' OR v_result->>'apply_allowed' IS DISTINCT FROM 'true' OR coalesce((v_result->'operations'->>'conflict')::integer, 0) <> 0 THEN
        RAISE EXCEPTION 'repreview_not_allowed part % %', p_part + 1, left(v_result::text, 1500);
      END IF;
      v_prev := jsonb_build_object('part', p_part + 1, 'rows', jsonb_array_length(v_job.partitions->p_part), 'source_hash', v_result->>'source_hash_617',
        'preview_batch_id', v_result->>'preview_batch_id', 'operations', v_result->'operations', 'repreviewed_after_staff_hold', true);
    END IF;
    UPDATE pdc_import_620.jobs SET parts = jsonb_set(parts, ARRAY[p_part::text], v_prev) WHERE job_id = p_job;
  END LOOP;
END $fn$;

-- The worker. No SET clause (a procedure with SET cannot COMMIT). One step = one partition preview or apply, committed on
-- its own. Resumable: each cron tick carries on from the job's recorded progress, and stops after about 40 s when the
-- session has a statement timeout, so a tick is never cut off by it. A step tried 3 times without finishing fails the job.
CREATE PROCEDURE pdc_import_620.run_jobs()
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
    v_n := pg_catalog.jsonb_array_length(v_job.partitions);
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

-- Call 2.
CREATE FUNCTION pdc_import_620.job_receipt(p_job uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public AS $fn$
DECLARE j pdc_import_620.jobs;
BEGIN
  PERFORM pdc_import_620.require_management();
  SELECT * INTO j FROM pdc_import_620.jobs WHERE job_id = p_job;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'job_not_found'); END IF;
  RETURN jsonb_build_object('ok', true, 'job_id', j.job_id, 'mode', j.mode, 'status', j.status, 'note', j.note, 'error', j.error,
    'created_at', j.created_at, 'started_at', j.started_at, 'finished_at', j.finished_at,
    'partitions', jsonb_array_length(j.partitions), 'previewed', (SELECT count(*) FROM jsonb_array_elements(j.parts) p WHERE p ? 'preview_batch_id' OR p ? 'skipped'),
    'applied', (SELECT count(*) FROM jsonb_array_elements(j.parts) p WHERE p->'apply'->>'ok' = 'true'),
    'inserted', (SELECT coalesce(sum((p->'apply'->>'insert')::numeric), 0) FROM jsonb_array_elements(j.parts) p WHERE jsonb_typeof(p->'apply'->'insert') = 'number'),
    'updated', (SELECT coalesce(sum((p->'apply'->>'update')::numeric), 0) FROM jsonb_array_elements(j.parts) p WHERE jsonb_typeof(p->'apply'->'update') = 'number'),
    'archived_now', (SELECT coalesce(sum((p->'apply'->>'archived_now')::numeric), 0) FROM jsonb_array_elements(j.parts) p WHERE p->'apply' ? 'archived_now'),
    'holds', j.holds, 'parts', j.parts);
END $fn$;

-- Kajel can carry her existing holds over once (stock, optional R/O and line).
CREATE FUNCTION pdc_import_620.add_hold(p_stock text, p_reason text, p_ro text DEFAULT NULL, p_line integer DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_id bigint;
BEGIN
  PERFORM pdc_import_620.require_management();
  INSERT INTO pdc_import_620.holds (stock_number, repair_order_number, original_line_number, reason) VALUES (btrim(p_stock), p_ro, p_line, p_reason) RETURNING hold_id INTO v_id;
  RETURN v_id;
END $fn$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_import_620 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON PROCEDURE pdc_import_620.run_jobs() FROM PUBLIC, anon, authenticated, service_role;

SELECT cron.schedule('pdc-import-620-worker', '* * * * *', 'CALL pdc_import_620.run_jobs()');

DO $check620$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('one_step_import_620', 'F235',
    'One-step import stays private to the management connection, calls the pinned import functions, and its worker is scheduled.',
    $chk620$
SELECT
  NOT has_schema_privilege('authenticated', 'pdc_import_620', 'USAGE')
  AND NOT has_schema_privilege('anon', 'pdc_import_620', 'USAGE')
  AND NOT has_schema_privilege('service_role', 'pdc_import_620', 'USAGE')
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.preview_rows(pdc_import_620.jobs,integer,jsonb)')), 'public.pdc_pilbara_service_preview_v1(') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.apply_part(uuid,integer,boolean)')), 'public.pdc_pilbara_service_apply_v1(') > 0
  AND EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pdc-import-620-worker' AND active)
  AND (SELECT banned_until FROM auth.users WHERE id = '0640d2f1-9f97-4e20-8a4f-cb6069b005df') = '2126-08-21T11:05:10.641388+00:00'::timestamptz
 AS ok,
 'one-step import is private, wired to the pinned functions, worker scheduled, importer banned' AS detail
$chk620$,
    true, 379, 'r620');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'one_step_import_620') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r620: check red: %', detail; END IF;
END $check620$;
