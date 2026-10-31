-- r771 (F372) / sort 486. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 2026 05:58 "is there a faster way for reports to be updated automatically? maybe view whats already on and only
-- applys changes?" and 05:59 "go". A Service as a Whole import previewed and applied all 40 parts (about 25 minutes, with the
-- vehicles table locked for every part) although most lines were identical to the last import.
-- From this release a part whose every stock has exactly the same lines (content, not file metadata) as the most recent part
-- that applied OK for that stock is recorded as skipped ('unchanged_since_last_apply'): no preview, no apply, no lock, no
-- 3-second gap. The last part is never skipped, so the leaving-the-board step (r763) always runs. Rows held in this job,
-- stocks never applied before, and any changed line keep the full preview + apply path.
-- Backup: pdc_backup_r763_20261031.function_sources (run_jobs added). Rollback: supabase/rollbacks/20261031081500_r771_delta_apply.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.run_jobs()', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.run_jobs()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

-- Content hash of one import row: the line as Revolution sent it plus the board context it was prepared with, without the
-- per-upload metadata (sha, filename, upload id, timestamps, row numbers, report parameters).
CREATE OR REPLACE FUNCTION pdc_import_620.row_content_hash_771(p_row jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
  SELECT md5(((p_row - 'workbook_sha256')
    || jsonb_build_object('raw_row', (p_row->'raw_row') - 'upload' - 'source_filename' - 'snapshot_sha256' - 'parent_attachment_sha256'
         - 'source_snapshot_at' - 'source_row_number' - 'source_row_numbers' - 'source_report_parameters'))::text)
$function$;

-- NULL when the part must be previewed and applied; otherwise the skip record for the part.
CREATE OR REPLACE FUNCTION pdc_import_620.part_skip_771(p_job uuid, p_part integer, p_before timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_job pdc_import_620.jobs; v_before timestamptz; v_stocks integer; v_same integer; v_rows integer; v_since uuid;
BEGIN
  SELECT * INTO v_job FROM pdc_import_620.jobs WHERE job_id = p_job;
  IF NOT FOUND OR v_job.report <> 'service_whole' THEN RETURN NULL; END IF;
  v_before := coalesce(p_before, v_job.created_at);
  IF EXISTS (SELECT 1 FROM pdc_import_620.job_rows r WHERE r.job_id = p_job AND r.part = p_part AND r.held_reason IS NOT NULL) THEN RETURN NULL; END IF;
  SELECT count(*) INTO v_rows FROM pdc_import_620.job_rows r WHERE r.job_id = p_job AND r.part = p_part;
  IF v_rows = 0 THEN RETURN NULL; END IF;
  WITH cur AS (
    SELECT r.stock_number, array_agg(pdc_import_620.row_content_hash_771(r.row) ORDER BY pdc_import_620.row_content_hash_771(r.row)) hashes
    FROM pdc_import_620.job_rows r WHERE r.job_id = p_job AND r.part = p_part GROUP BY r.stock_number
  ), prior AS (
    -- for each stock: the most recent earlier apply job whose part holding that stock applied OK
    SELECT DISTINCT ON (c.stock_number) c.stock_number, j.job_id, r.part
    FROM cur c
    JOIN pdc_import_620.job_rows r ON r.stock_number = c.stock_number AND r.held_reason IS NULL
    JOIN pdc_import_620.jobs j ON j.job_id = r.job_id AND j.job_id <> p_job AND j.mode = 'apply' AND j.status = 'done'
      AND j.report = 'service_whole' AND j.created_at < v_before
      AND (j.parts->r.part->'apply'->>'ok') = 'true' AND coalesce(j.parts->r.part->'apply'->>'skipped', '') = ''
    ORDER BY c.stock_number, j.created_at DESC
  ), prev AS (
    SELECT p.stock_number, p.job_id, array_agg(pdc_import_620.row_content_hash_771(r.row) ORDER BY pdc_import_620.row_content_hash_771(r.row)) hashes
    FROM prior p JOIN pdc_import_620.job_rows r ON r.job_id = p.job_id AND r.part = p.part AND r.stock_number = p.stock_number AND r.held_reason IS NULL
    GROUP BY p.stock_number, p.job_id
  )
  SELECT count(*), count(*) FILTER (WHERE pv.hashes = c.hashes), max(pv.job_id::text)::uuid
    INTO v_stocks, v_same, v_since
  FROM cur c LEFT JOIN prev pv ON pv.stock_number = c.stock_number;
  IF v_stocks = 0 OR v_same <> v_stocks THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('part', p_part + 1, 'rows', v_rows, 'stocks', v_stocks, 'skipped', 'unchanged_since_last_apply', 'since_job', v_since,
    'operations', jsonb_build_object('insert', 0, 'update', 0, 'conflict', 0, 'unchanged', v_rows, 'quarantine', 0, 'duplicate_ignored', 0));
END $function$;
REVOKE ALL ON FUNCTION pdc_import_620.row_content_hash_771(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_import_620.part_skip_771(uuid, integer, timestamptz) FROM PUBLIC, anon, authenticated;

DO $r771$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
  a1 text := E'        v_step := pdc_import_620.preview_part(v_job.job_id, v_i);\n';
  b1 text := E'        -- r771 (F372): a part whose stocks are line-for-line what the last OK apply had is skipped; the last part never is.\n'
          || E'        v_step := CASE WHEN v_i < v_n - 1 THEN pdc_import_620.part_skip_771(v_job.job_id, v_i) END;\n'
          || E'        IF v_step IS NULL THEN v_step := pdc_import_620.preview_part(v_job.job_id, v_i); END IF;\n';
  a2 text := E'      IF v_apply THEN\n        v_step := pdc_import_620.apply_part(v_job.job_id, v_i, v_i = v_n - 1);\n';
  b2 text := E'      IF v_apply AND v_job.parts->v_i->>''skipped'' = ''unchanged_since_last_apply'' THEN\n'
          || E'        -- r771 (F372): nothing to write for this part; no lock, no apply call.\n'
          || E'        v_step := pg_catalog.jsonb_build_object(''ok'', true, ''skipped'', ''unchanged_since_last_apply'', ''part'', v_i + 1, ''insert'', 0, ''update'', 0, ''archived_now'', 0);\n'
          || E'        UPDATE pdc_import_620.jobs SET parts = pg_catalog.jsonb_set(parts, ARRAY[v_i::text], parts->v_i || pg_catalog.jsonb_build_object(''apply'', v_step)), step_attempts = 0\n'
          || E'        WHERE job_id = v_job.job_id;\n'
          || E'      ELSIF v_apply THEN\n        v_step := pdc_import_620.apply_part(v_job.job_id, v_i, v_i = v_n - 1);\n';
  a3 text := E'    IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN (''queued'', ''running'')) THEN PERFORM pg_catalog.pg_sleep(3); END IF;\n';
  b3 text := E'    IF v_step->>''skipped'' IS DISTINCT FROM ''unchanged_since_last_apply''\n'
          || E'       AND EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN (''queued'', ''running'')) THEN PERFORM pg_catalog.pg_sleep(3); END IF; -- r771: no gap after a skipped part\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r771: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 486 OR fault_id = 'F372' OR added_in = 'r771') THEN RAISE EXCEPTION 'r771: sort 486 or F372 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r771: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '22538aba31b44f2bb667f98a1cb9a15c' THEN RAISE EXCEPTION 'r771: run_jobs is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1
     OR (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1
     OR (length(v_old) - length(replace(v_old, a3, ''))) / length(a3) <> 1 THEN RAISE EXCEPTION 'r771: run_jobs anchors not found once'; END IF;
  v_new := replace(replace(replace(v_old, a1, b1), a2, b2), a3, b3);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r771: run_jobs readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('delta_apply_771', 'F372',
    'Upload (r771): the worker skips a part whose stocks are line-for-line what the last OK apply had (part_skip_771), never the last part, and takes no 3 s gap after a skipped part; the content hash ignores only per-upload metadata.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'CASE WHEN v_i < v_n - 1 THEN pdc_import_620.part_skip_771(v_job.job_id, v_i) END') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), $$v_job.parts->v_i->>'skipped' = 'unchanged_since_last_apply'$$) > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.part_skip_771(uuid,integer,timestamptz)')), 'held_reason IS NOT NULL) THEN RETURN NULL') > 0
   AND pdc_import_620.row_content_hash_771('{"a":1,"workbook_sha256":"x","raw_row":{"Dept":"138","upload":{"upload_id":"u1"},"source_row_number":5}}'::jsonb)
     = pdc_import_620.row_content_hash_771('{"a":1,"workbook_sha256":"y","raw_row":{"Dept":"138","upload":{"upload_id":"u2"},"source_row_number":9}}'::jsonb)
   AND pdc_import_620.row_content_hash_771('{"a":1,"raw_row":{"Dept":"138","Sub Status":"10"}}'::jsonb)
    <> pdc_import_620.row_content_hash_771('{"a":1,"raw_row":{"Dept":"138","Sub Status":"99"}}'::jsonb)
   AND NOT has_function_privilege('authenticated', 'pdc_import_620.part_skip_771(uuid,integer,timestamptz)', 'EXECUTE')
 AS ok, 'unchanged parts skipped; last part always previewed and applied' AS detail
$chk$, true, 486, 'r771');
END $r771$;
