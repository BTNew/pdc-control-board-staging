-- r728 (F338). Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 2026 16:53-16:58 AWST: turn on Apply on the website Revolution uploads page; Kajel is switched off
-- ("website only"); Service as a Whole first. Craig gave his OK to change the import functions for website upload.
--
-- Until now the service import only accepted a workbook that came by email from noreply@revolutionsoftware.com.au.
-- A website upload has no email, so its proof of origin is a server-side receipt instead: an active administrator,
-- signed in, uploaded this exact file (sha256) at this time. The receipt table is private (no client grant); only the
-- r728 RPCs below write it, and only for the signed-in administrator. Everything else is unchanged: the same job queue
-- (pdc_import_620, run by the existing cron), preview before apply per part, the 15-new-vehicle stop, holds, the same
-- row rules (one line per Dept + R/O + Line, hours never summed, Sub Status 99 not created), duplicate files refused.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $guard728$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r728: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r728: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r728: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 476 OR fault_id = 'F338' OR added_in = 'r728') THEN RAISE EXCEPTION 'r728: sort 476 or F338 is taken'; END IF;
  IF to_regclass('pdc_import_620.web_uploads_728') IS NOT NULL THEN RAISE EXCEPTION 'r728: already applied'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r728: an import job is running'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)) <> '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r728: row validator changed since this was written'; END IF;
END $guard728$;

-- Pre-record the green checks that read anything this release touches; they must stay green.
CREATE TEMP TABLE r728_green ON COMMIT DROP AS SELECT check_name FROM pdc_ops.regression_checks WHERE false;
DO $pre728$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks
           WHERE enabled AND (check_sql ILIKE '%revolution_service_rows_20261006%' OR check_sql ILIKE '%9be0883b1a555f48f3c1ba9fa111c891%'
             OR check_sql ILIKE '%management_authorized%' OR check_sql ILIKE '%management_email_manifests%' OR check_sql ILIKE '%pdc_import_620%'
             OR check_sql ILIKE '%revolution_upload%') LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; END;
    IF ok IS TRUE THEN INSERT INTO r728_green VALUES (r.check_name); END IF;
  END LOOP;
END $pre728$;

-- 1. The receipt: who uploaded which file. Private.
CREATE TABLE pdc_import_620.web_uploads_728 (
  upload_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL,
  uploader_email text NOT NULL CHECK (uploader_email ~ '^[^@\s]+@[^@\s]+$'),
  workbook_sha256 text NOT NULL CHECK (workbook_sha256 ~ '^[0-9a-f]{64}$'),
  filename text NOT NULL CHECK (length(filename) BETWEEN 1 AND 200),
  mode text NOT NULL CHECK (mode IN ('preview', 'apply')),
  job_id uuid,
  active_txid bigint,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (workbook_sha256, mode)
);
ALTER TABLE pdc_import_620.web_uploads_728 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_import_620.web_uploads_728 FROM PUBLIC, anon, authenticated;

-- True only inside an r728 RPC (owner postgres), in the same transaction that stamped the receipt.
CREATE FUNCTION pdc_import_620.web_upload_active_728()
RETURNS boolean LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $fn$
  SELECT current_user = 'postgres' AND EXISTS (
    SELECT 1 FROM pdc_import_620.web_uploads_728 u
    WHERE u.active_txid = txid_current() AND u.upload_id::text = current_setting('pdc.web_upload_728', true))
$fn$;

CREATE FUNCTION pdc_import_620.web_upload_manifest_ok_728(p_provenance jsonb, p_workbook_sha256 text)
RETURNS boolean LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $fn$
  SELECT coalesce(p_provenance->>'source_kind' = 'website_admin_upload_728'
    AND coalesce(p_provenance->>'upload_id', '') ~ '^[0-9a-f-]{36}$'
    AND EXISTS (SELECT 1 FROM pdc_import_620.web_uploads_728 u
                WHERE u.upload_id = (p_provenance->>'upload_id')::uuid AND u.workbook_sha256 = p_workbook_sha256
                  AND lower(u.uploader_email) = lower(coalesce(p_provenance->>'uploader_email', ''))), false)
$fn$;

CREATE FUNCTION pdc_import_620.web_upload_row_ok_728(x jsonb)
RETURNS boolean LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $fn$
  SELECT coalesce(x->'raw_row'->>'delivery' = 'website_admin_upload_728'
    AND x->'raw_row'->>'email_subject' = 'PMG PD Service as a Whole w/Sublet'
    AND NOT (x->'raw_row' ?| ARRAY['from_address', 'mailbox', 'gmail_message_id', 'internet_message_id', 'outlook_message_id', 'verified_by'])
    AND coalesce(x->'raw_row'->'upload'->>'upload_id', '') ~ '^[0-9a-f-]{36}$'
    AND EXISTS (SELECT 1 FROM pdc_import_620.web_uploads_728 u
                WHERE u.upload_id = (x->'raw_row'->'upload'->>'upload_id')::uuid
                  AND u.workbook_sha256 = x->>'workbook_sha256'
                  AND lower(u.uploader_email) = lower(coalesce(x->'raw_row'->'upload'->>'uploader_email', ''))), false)
$fn$;
REVOKE ALL ON FUNCTION pdc_import_620.web_upload_active_728(), pdc_import_620.web_upload_manifest_ok_728(jsonb, text),
  pdc_import_620.web_upload_row_ok_728(jsonb) FROM PUBLIC, anon, authenticated;

-- 2. In-place edits of the existing import functions (each anchor must be found exactly once).
DO $edit728$
DECLARE v_old text; v_new text; v_def text; v_sig text; v_old_md5 text; v_new_md5 text; v_n integer; v_c text;
  a1 text := $a$ OR x->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR x->'raw_row'->>'mailbox' NOT IN ('pmbcontroller@gmail.com','pdc@pmgwa.com.au')$a$;
  b1 text := $b$ OR (pdc_import_620.web_upload_row_ok_728(x) IS NOT TRUE AND (x->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware.com.au'
 OR x->'raw_row'->>'mailbox' NOT IN ('pmbcontroller@gmail.com','pdc@pmgwa.com.au'))) -- r728 (F338): or a receipted website upload$b$;
  a2 text := $a$IF pdc_codex_intake_private.management_connection() IS NOT TRUE OR$a$;
  b2 text := $b$IF (pdc_codex_intake_private.management_connection() IS NOT TRUE AND pdc_import_620.web_upload_active_728() IS NOT TRUE /* r728 (F338) */) OR$b$;
  a3 text := $a$OR coalesce(p_envelope->>'gmail_message_id', '') = '' THEN$a$;
  b3 text := $b$OR (coalesce(p_envelope->>'gmail_message_id', '') = '' AND pdc_import_620.web_upload_active_728() IS NOT TRUE) THEN -- r728 (F338): a website upload has no email$b$;
  a4 text := $a$IF m.sender='noreply@revolutionsoftware.com.au' AND (NOT revolution_service_manifest_20261006(m.provenance,m.gmail_message_id,m.filename) OR NOT revolution_service_rows_20261006(p_rows)) THEN RETURN false; END IF;$a$;
  b4 text := $b$IF m.sender='noreply@revolutionsoftware.com.au' AND (NOT revolution_service_manifest_20261006(m.provenance,m.gmail_message_id,m.filename) OR NOT revolution_service_rows_20261006(p_rows)) THEN RETURN false; END IF;
   -- r728 (F338): a website upload is proven by its receipt instead of an email
   IF m.sender IS NULL AND m.provenance->>'source_kind'='website_admin_upload_728' AND (NOT pdc_import_620.web_upload_manifest_ok_728(m.provenance,m.workbook_sha256) OR NOT revolution_service_rows_20261006(p_rows)) THEN RETURN false; END IF;$b$;
  a5 text := $a$IF m.sender='noreply@revolutionsoftware.com.au' AND NOT revolution_service_manifest_20261006(m.provenance,m.gmail_message_id,m.filename) THEN RETURN false; END IF;$a$;
  b5 text := $b$IF m.sender='noreply@revolutionsoftware.com.au' AND NOT revolution_service_manifest_20261006(m.provenance,m.gmail_message_id,m.filename) THEN RETURN false; END IF;
 IF m.sender IS NULL AND m.provenance->>'source_kind'='website_admin_upload_728' AND NOT pdc_import_620.web_upload_manifest_ok_728(m.provenance,m.workbook_sha256) THEN RETURN false; END IF; -- r728 (F338)$b$;
  a6 text := $a$ IF p_action='apply' THEN$a$;
  b6 text := $b$ IF p_action='apply' THEN
   IF m.sender IS NULL AND m.provenance->>'source_kind'='website_admin_upload_728' THEN -- r728 (F338): same row rules as an emailed file
    SELECT jsonb_agg(r.normalized_payload||jsonb_build_object('raw_row',r.raw_row) ORDER BY r.source_order) INTO scope_rows FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=b.batch_id;
    IF jsonb_array_length(coalesce(scope_rows,'[]'))<>m.source_rows OR NOT revolution_service_rows_20261006(scope_rows) THEN RETURN false; END IF;
   END IF;$b$;
BEGIN
  -- 2a. Row validator (pinned): keep every rule, add the receipted website delivery as the alternative to the email.
  v_sig := 'pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)';
  SELECT prosrc, md5(prosrc) INTO v_old, v_old_md5 FROM pg_proc WHERE oid = v_sig::regprocedure;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r728: row validator anchor not found once'; END IF;
  v_def := regexp_replace(pg_get_functiondef(v_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(v_old, a1, b1) || substring(v_def from '\$[a-zA-Z_]*\$$');
  SELECT md5(prosrc) INTO v_new_md5 FROM pg_proc WHERE oid = v_sig::regprocedure;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_new_md5 WHERE prosrc_md5 = v_old_md5;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r728: row validator pin rows %', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_old_md5, v_new_md5) WHERE strpos(check_sql, v_old_md5) > 0;
  -- The job runner and the upload gate refuse a changed validator by its md5: move those literals with the pin.
  FOREACH v_sig IN ARRAY ARRAY['pdc_import_620.preview_part(uuid,integer)', 'public.pdc_revolution_upload_gate_591(integer,integer,boolean,text)'] LOOP
    SELECT prosrc INTO v_old FROM pg_proc WHERE oid = v_sig::regprocedure;
    IF strpos(v_old, v_old_md5) = 0 THEN RAISE EXCEPTION 'r728: % has no validator md5', v_sig; END IF;
    v_def := regexp_replace(pg_get_functiondef(v_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || replace(v_old, v_old_md5, v_new_md5) || substring(v_def from '\$[a-zA-Z_]*\$$');
  END LOOP;

  -- 2b. require_management, submit_begin, management_authorized.
  FOR v_sig, v_c IN SELECT * FROM (VALUES ('pdc_import_620.require_management()', 'a2'), ('pdc_import_620.submit_begin(text,jsonb,text)', 'a3'),
                                         ('pdc_codex_intake_private.management_authorized(text,jsonb,text,text,uuid)', 'a456')) t LOOP
    SELECT prosrc INTO v_old FROM pg_proc WHERE oid = v_sig::regprocedure;
    v_new := v_old;
    IF v_c = 'a2' THEN
      IF (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1 THEN RAISE EXCEPTION 'r728: require_management anchor'; END IF;
      v_new := replace(v_new, a2, b2);
    ELSIF v_c = 'a3' THEN
      IF (length(v_old) - length(replace(v_old, a3, ''))) / length(a3) <> 1 THEN RAISE EXCEPTION 'r728: submit_begin anchor'; END IF;
      v_new := replace(v_new, a3, b3);
    ELSE
      IF (length(v_old) - length(replace(v_old, a4, ''))) / length(a4) <> 1 THEN RAISE EXCEPTION 'r728: management_authorized preview anchor'; END IF;
      IF (length(v_old) - length(replace(v_old, a5, ''))) / length(a5) <> 1 THEN RAISE EXCEPTION 'r728: management_authorized batch anchor'; END IF;
      IF (length(v_old) - length(replace(v_old, a6, ''))) / length(a6) <> 1 THEN RAISE EXCEPTION 'r728: management_authorized apply anchor'; END IF;
      v_new := replace(replace(replace(v_new, a4, b4), a5, b5), a6, b6);
    END IF;
    v_def := regexp_replace(pg_get_functiondef(v_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  END LOOP;
END $edit728$;

-- 2c. The manifest table: a website manifest has no mailbox, sender or message id; its receipt must exist.
DO $con728$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint
  WHERE conrelid = 'pdc_codex_intake_private.management_email_manifests'::regclass AND conname = 'management_manifest_actual_source';
  IF v_def IS NULL OR v_def !~ '^CHECK \(' THEN RAISE EXCEPTION 'r728: manifest constraint not found'; END IF;
  EXECUTE 'ALTER TABLE pdc_codex_intake_private.management_email_manifests DROP CONSTRAINT management_manifest_actual_source';
  EXECUTE 'ALTER TABLE pdc_codex_intake_private.management_email_manifests ADD CONSTRAINT management_manifest_actual_source CHECK (('
    || substring(v_def from '^CHECK \((.*)\)$')
    || ') OR COALESCE(mailbox IS NULL AND sender IS NULL AND gmail_message_id IS NULL'
    || ' AND (provenance->>''source_kind'') = ''website_admin_upload_728'' AND length(btrim(approval_evidence)) > 20'
    || ' AND pdc_import_620.web_upload_manifest_ok_728(provenance, workbook_sha256), false))';
END $con728$;

-- 3. The website RPCs. Each one: active administrator, staging, own receipt; stamps the receipt with this
-- transaction so the existing import functions accept the call; the cron job then runs preview and apply as before.
CREATE FUNCTION public.revolution_upload_begin_728(p_sha text, p_filename text, p_mode text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public SET statement_timeout = '60s' AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); v_uid uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email', ''))); v_id uuid; v_job jsonb; v_prior record;
BEGIN
  IF v_role <> 'administrator' OR v_uid IS NULL OR v_email = '' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'staging_only'); END IF;
  IF coalesce(p_sha, '') !~ '^[0-9a-f]{64}$' OR coalesce(p_mode, '') NOT IN ('preview', 'apply') OR length(btrim(coalesce(p_filename, ''))) NOT BETWEEN 1 AND 200 THEN RETURN jsonb_build_object('ok', false, 'error', 'bad_request'); END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running') OR (status = 'loading' AND created_at > clock_timestamp() - interval '30 minutes')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'job_already_running', 'message', 'Another import is still running. Try again when it finishes.');
  END IF;
  IF p_mode = 'apply' AND EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE workbook_sha256 = p_sha AND mode = 'apply' AND status = 'done') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'duplicate_file', 'message', 'This file has already been imported.');
  END IF;
  -- A retry of the same file is allowed when the earlier attempt did not finish.
  SELECT u.upload_id, j.status INTO v_prior FROM pdc_import_620.web_uploads_728 u LEFT JOIN pdc_import_620.jobs j ON j.job_id = u.job_id
  WHERE u.workbook_sha256 = p_sha AND u.mode = p_mode;
  IF FOUND THEN
    IF v_prior.status IN ('queued', 'running') OR (p_mode = 'apply' AND v_prior.status = 'done') THEN RETURN jsonb_build_object('ok', false, 'error', 'duplicate_file'); END IF;
    DELETE FROM pdc_import_620.web_uploads_728 WHERE upload_id = v_prior.upload_id;
  END IF;
  INSERT INTO pdc_import_620.web_uploads_728 (auth_user_id, uploader_email, workbook_sha256, filename, mode, active_txid)
  VALUES (v_uid, v_email, p_sha, btrim(p_filename), p_mode, txid_current()) RETURNING upload_id INTO v_id;
  PERFORM set_config('pdc.web_upload_728', v_id::text, true);
  v_job := pdc_import_620.submit_begin(p_sha, jsonb_build_object(
    'filename', btrim(p_filename),
    'provenance', jsonb_build_object('source_kind', 'website_admin_upload_728', 'upload_id', v_id, 'uploader_email', v_email,
      'report_title', 'PMG PD Service as a Whole w/Sublet', 'snapshot_scope', 'full_open_ro_snapshot_r479', 'authority', 'website_admin_upload',
      'received_at', clock_timestamp()),
    'approval_evidence', format('Website upload by %s (active administrator) at %s AWST. Craig 29 Oct 2026 16:58 AWST approved website uploads in place of Kajel (r728); every part is previewed before it is applied.',
      v_email, to_char(clock_timestamp() AT TIME ZONE 'Australia/Perth', 'DD Mon YYYY HH24:MI'))), p_mode);
  UPDATE pdc_import_620.web_uploads_728 SET job_id = (v_job->>'job_id')::uuid, active_txid = NULL WHERE upload_id = v_id;
  RETURN jsonb_build_object('ok', true, 'upload_id', v_id, 'job_id', v_job->>'job_id', 'mode', p_mode);
END $fn$;

CREATE FUNCTION public.revolution_upload_rows_728(p_upload uuid, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public SET statement_timeout = '60s' AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); u pdc_import_620.web_uploads_728; v_res jsonb;
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  SELECT * INTO u FROM pdc_import_620.web_uploads_728 WHERE upload_id = p_upload AND auth_user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR u.job_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'upload_not_found'); END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000 THEN RETURN jsonb_build_object('ok', false, 'error', 'bad_rows'); END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE x->'raw_row'->'upload'->>'upload_id' IS DISTINCT FROM p_upload::text
             OR x->>'workbook_sha256' IS DISTINCT FROM u.workbook_sha256 OR x->'raw_row'->>'delivery' IS DISTINCT FROM 'website_admin_upload_728') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'row_not_from_this_upload');
  END IF;
  UPDATE pdc_import_620.web_uploads_728 SET active_txid = txid_current() WHERE upload_id = p_upload;
  PERFORM set_config('pdc.web_upload_728', p_upload::text, true);
  v_res := pdc_import_620.add_rows(u.job_id, p_rows);
  UPDATE pdc_import_620.web_uploads_728 SET active_txid = NULL WHERE upload_id = p_upload;
  RETURN v_res;
END $fn$;

CREATE FUNCTION public.revolution_upload_finish_728(p_upload uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public SET statement_timeout = '300s' AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); u pdc_import_620.web_uploads_728; v_res jsonb;
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  SELECT * INTO u FROM pdc_import_620.web_uploads_728 WHERE upload_id = p_upload AND auth_user_id = auth.uid() FOR UPDATE;
  IF NOT FOUND OR u.job_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'upload_not_found'); END IF;
  UPDATE pdc_import_620.web_uploads_728 SET active_txid = txid_current() WHERE upload_id = p_upload;
  PERFORM set_config('pdc.web_upload_728', p_upload::text, true);
  v_res := pdc_import_620.submit_finish(u.job_id);
  UPDATE pdc_import_620.web_uploads_728 SET active_txid = NULL WHERE upload_id = p_upload;
  RETURN v_res;
END $fn$;

-- Progress for the page (any administrator can see any website upload).
CREATE FUNCTION public.revolution_upload_status_728(p_upload uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); r record;
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  SELECT u.upload_id, u.uploader_email, u.filename, u.mode, u.received_at, j.status, j.note, j.error, j.rows_loaded, j.n_parts,
         jsonb_array_length(coalesce(j.parts, '[]')) AS parts_previewed,
         (SELECT count(*) FROM jsonb_array_elements(coalesce(j.parts, '[]')) p WHERE p ? 'apply') AS parts_applied,
         jsonb_array_length(coalesce(j.holds, '[]')) AS holds, j.started_at, j.finished_at
  INTO r FROM pdc_import_620.web_uploads_728 u LEFT JOIN pdc_import_620.jobs j ON j.job_id = u.job_id WHERE u.upload_id = p_upload;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'upload_not_found'); END IF;
  RETURN jsonb_build_object('ok', true) || to_jsonb(r);
END $fn$;

-- Kajel's last decisions per Dept + description (station, rule, hours provenance, ARB review), so a line Kajel already
-- reviewed is routed and timed exactly as before. Read by the upload function with the service key only.
CREATE FUNCTION public.revolution_prior_decisions_728()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public SET statement_timeout = '60s' AS $fn$
  WITH j AS (SELECT job_id FROM pdc_import_620.jobs WHERE status = 'done' AND mode = 'apply' ORDER BY created_at DESC LIMIT 1),
  r AS (SELECT DISTINCT ON (k) (x.row->>'department') || '|' || upper(regexp_replace(btrim(coalesce(x.row->>'operation_description', '')), '\s+', ' ', 'g')) AS k, x.row
        FROM pdc_import_620.job_rows x JOIN j USING (job_id) ORDER BY k, x.ord)
  SELECT coalesce(jsonb_object_agg(k, jsonb_strip_nulls(jsonb_build_object(
    'proposed_station', row->'proposed_station', 'routing_rule', row->'routing_rule', 'routing_provenance', row->'routing_provenance',
    'routing_rule_version', row->'routing_rule_version', 'hours_provenance', row->'hours_provenance',
    'effective_estimated_hours', row->'effective_estimated_hours', 'source_estimated_hours', row->'source_estimated_hours',
    'needs_hours_review', row->'needs_hours_review', 'arb_review', row->'arb_review'))), '{}'::jsonb) FROM r
$fn$;

REVOKE ALL ON FUNCTION public.revolution_upload_begin_728(text, text, text), public.revolution_upload_rows_728(uuid, jsonb),
  public.revolution_upload_finish_728(uuid), public.revolution_upload_status_728(uuid), public.revolution_prior_decisions_728() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revolution_upload_begin_728(text, text, text), public.revolution_upload_rows_728(uuid, jsonb),
  public.revolution_upload_finish_728(uuid), public.revolution_upload_status_728(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.revolution_prior_decisions_728() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.revolution_prior_decisions_728() TO service_role;

DO $check728$
DECLARE ok boolean; detail text; r record; bad text := '';
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('website_service_upload_728', 'F338',
    'A website Service as a Whole upload is accepted only with a receipt for the signed-in administrator; no email is faked; clients cannot reach the receipt or the job functions.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')), 'pdc_import_620.web_upload_row_ok_728(x) IS NOT TRUE AND') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.require_management()')), 'web_upload_active_728') > 0
   AND strpos((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'management_manifest_actual_source'
               AND conrelid = 'pdc_codex_intake_private.management_email_manifests'::regclass), 'web_upload_manifest_ok_728') > 0
   AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'pdc_import_620.web_uploads_728'::regclass)
   AND NOT has_schema_privilege('authenticated', 'pdc_import_620', 'usage')
   AND NOT has_function_privilege('anon', 'public.revolution_upload_begin_728(text,text,text)', 'execute')
   AND NOT has_function_privilege('authenticated', 'public.revolution_prior_decisions_728()', 'execute')
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.revolution_upload_begin_728(text,text,text)')), 'v_role <> ''administrator''') > 0
 AS ok, 'website upload proven by receipt' AS detail
$chk$, true, 476, 'r728');
  FOR r IN SELECT c.check_name, c.check_sql FROM pdc_ops.regression_checks c
           WHERE c.check_name = 'website_service_upload_728' OR c.check_name IN (SELECT g.check_name FROM r728_green g) LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; detail := SQLERRM; END;
    IF ok IS NOT TRUE THEN bad := bad || r.check_name || ' (' || left(coalesce(detail, ''), 80) || '); '; END IF;
  END LOOP;
  IF bad <> '' THEN RAISE EXCEPTION 'r728: red after change: %', bad; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r728: pin count changed'; END IF;
END $check728$;
