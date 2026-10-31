-- r781 (F386) / sort 568. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 2026 11:41 AWST: "i cant upload the PMG PD Parts files or the KTA/BT Sales ones"; 11:42: "turn on the applys for the other
-- uploads so i can do them". Kajel is off, so CW parts and the BT / KTA deal items had no way in. Their importers only run on a management
-- connection (session postgres, no JWT), so the website cannot call them directly.
-- This release:
--   * pdc_import_620.other_uploads_781: queue of website uploads for cw_parts / bt_deal_items / kta_deal_items (rows as parsed by the
--     edge function, same rows Kajel sent; r591 matched them 0 field diffs).
--   * public.revolution_upload_other_781(...)        administrator only: queue one file (one queued/running at a time, no repeat of a done sha).
--   * public.revolution_upload_other_status_781(id)   administrator only: status and importer result.
--   * pdc_import_620.run_other_781()                  cron (postgres, management connection): runs one queued file through the existing importer
--       cw_parts      -> public.pdc_import_job_parts_csv_20260912, source_kind user_attached_workbook (authority explicit_user_request)
--       bt_deal_items -> pdc_sales_private.import_sales_accessories_20261020 manifest, preview, apply
--       kta_deal_items-> pdc_sales_private.import_karratha_sales_accessories_20261025 manifest, preview, apply
--   * KTA normalize: mailbox/sender rule also passes for the queued website upload being run (pdc_import_620.web_upload_781_ok).
-- Backup: pdc_backup_r763_20261031.function_sources (*@r781pre). Rollback: supabase/rollbacks/20261031120000_r781_website_apply_parts_and_deal_items.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $g$ BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r781: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 568 OR fault_id = 'F386' OR added_in = 'r781') THEN RAISE EXCEPTION 'r781: sort 568 or F386 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r781: an import job is running'; END IF;
END $g$;

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)@r781pre', p.prosrc, md5(p.prosrc) FROM pg_proc p
WHERE p.oid = 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)'::regprocedure
ON CONFLICT (sig) DO NOTHING;

CREATE TABLE pdc_import_620.other_uploads_781 (
  upload_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('cw_parts', 'bt_deal_items', 'kta_deal_items')),
  workbook_sha256 text NOT NULL CHECK (workbook_sha256 ~ '^[0-9a-f]{64}$'),
  filename text NOT NULL,
  uploader_email text NOT NULL,
  auth_user_id uuid NOT NULL,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  rows jsonb NOT NULL CHECK (jsonb_typeof(rows) = 'array'),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'done', 'failed')),
  result jsonb,
  error text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  started_at timestamptz,
  finished_at timestamptz
);
CREATE INDEX other_uploads_781_status ON pdc_import_620.other_uploads_781 (status, created_at);
ALTER TABLE pdc_import_620.other_uploads_781 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_import_620.other_uploads_781 FROM PUBLIC, anon, authenticated, service_role;

-- True only while run_other_781 is running this exact upload; used by the KTA mailbox/sender rule.
CREATE FUNCTION pdc_import_620.web_upload_781_ok(p_envelope jsonb)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'pg_catalog', 'public' AS $f$
  SELECT coalesce(p_envelope->>'mailbox', '') = 'website_admin_upload'
     AND coalesce(nullif(current_setting('pdc.web_upload_781', true), ''), '') ~ '^[0-9a-f-]{36}$'
     AND EXISTS (SELECT 1 FROM pdc_import_620.other_uploads_781 u
                 WHERE u.upload_id = current_setting('pdc.web_upload_781', true)::uuid AND u.status = 'running'
                   AND u.workbook_sha256 = lower(coalesce(p_envelope->>'file_sha256', ''))
                   AND lower(u.uploader_email) = lower(coalesce(p_envelope->>'sender', '')))
$f$;
REVOKE ALL ON FUNCTION pdc_import_620.web_upload_781_ok(jsonb) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.revolution_upload_other_781(p_kind text, p_sha text, p_filename text, p_meta jsonb, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' SET statement_timeout TO '60s' AS $f$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); v_uid uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email', ''))); v_id uuid;
BEGIN
  IF v_role <> 'administrator' OR v_uid IS NULL OR v_email = '' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'staging_only'); END IF;
  IF coalesce(p_kind, '') NOT IN ('cw_parts', 'bt_deal_items', 'kta_deal_items') OR coalesce(p_sha, '') !~ '^[0-9a-f]{64}$'
     OR length(btrim(coalesce(p_filename, ''))) NOT BETWEEN 1 AND 200 OR jsonb_typeof(p_meta) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_request');
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.other_uploads_781 WHERE status IN ('queued', 'running')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'job_already_running', 'message', 'Another parts or deal items upload is still running. Try again in a minute.');
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.other_uploads_781 WHERE workbook_sha256 = p_sha AND status = 'done') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'duplicate_file', 'message', 'This file has already been imported.');
  END IF;
  INSERT INTO pdc_import_620.other_uploads_781 (kind, workbook_sha256, filename, uploader_email, auth_user_id, meta, rows)
  VALUES (p_kind, p_sha, btrim(p_filename), v_email, v_uid, p_meta, p_rows) RETURNING upload_id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'upload_id', v_id, 'status', 'queued');
END $f$;

CREATE FUNCTION public.revolution_upload_other_status_781(p_upload uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); u pdc_import_620.other_uploads_781;
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  SELECT * INTO u FROM pdc_import_620.other_uploads_781 WHERE upload_id = p_upload;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  RETURN jsonb_build_object('ok', true, 'upload_id', u.upload_id, 'kind', u.kind, 'status', u.status, 'result', u.result, 'error', u.error,
    'rows', jsonb_array_length(u.rows), 'created_at', u.created_at, 'finished_at', u.finished_at);
END $f$;

REVOKE ALL ON FUNCTION public.revolution_upload_other_781(text, text, text, jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revolution_upload_other_status_781(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revolution_upload_other_781(text, text, text, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revolution_upload_other_status_781(uuid) TO authenticated;

-- No SET clause: a procedure with SET options cannot COMMIT. Every name below is schema-qualified.
CREATE PROCEDURE pdc_import_620.run_other_781()
LANGUAGE plpgsql AS $f$
DECLARE u pdc_import_620.other_uploads_781; env jsonb; res jsonb; prev jsonb; m text[]; snap timestamptz; v_err text;
  headers constant jsonb := '["Quote #","Stock #","PO Line","Price Level Desc","Notes","PO #","Transaction Sub-Type","Transaction Type"]';
BEGIN
  IF pdc_codex_intake_private.management_connection() IS NOT TRUE THEN RETURN; END IF;
  IF NOT pg_try_advisory_lock(hashtextextended('pdc_import_620.run_other_781', 0)) THEN RETURN; END IF;
  -- A run that died mid-way (container restart) is failed, never retried silently.
  UPDATE pdc_import_620.other_uploads_781 SET status = 'failed', error = 'worker stopped mid-run', finished_at = clock_timestamp()
  WHERE status = 'running' AND started_at < clock_timestamp() - interval '10 minutes';
  SELECT * INTO u FROM pdc_import_620.other_uploads_781 WHERE status = 'queued' ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN PERFORM pg_advisory_unlock(hashtextextended('pdc_import_620.run_other_781', 0)); COMMIT; RETURN; END IF;
  UPDATE pdc_import_620.other_uploads_781 SET status = 'running', started_at = clock_timestamp() WHERE upload_id = u.upload_id;
  COMMIT;
  BEGIN
    PERFORM set_config('pdc.web_upload_781', u.upload_id::text, true);
    m := regexp_match(coalesce(u.meta->>'extract_text', ''), '^Extracted on [A-Za-z]+, ([A-Za-z]+ \d{1,2}, \d{4}) @ (\d{1,2}:\d{2} [AP]M)');
    snap := CASE WHEN m IS NULL THEN u.created_at
                 ELSE to_timestamp(m[1] || ' ' || m[2], 'FMMonth FMDD, YYYY FMHH12:MI AM')::timestamp AT TIME ZONE 'Australia/Perth' END;
    IF snap > u.created_at + interval '4 minutes' THEN snap := u.created_at; END IF;
    IF u.kind = 'cw_parts' THEN
      env := jsonb_build_object('source_kind', 'user_attached_workbook', 'source_system', 'tune_pmg', 'company', '01', 'division', '1',
        'attachment_sha256', u.workbook_sha256, 'attachment_id', u.upload_id::text, 'source_file', u.filename,
        'authority', 'explicit_user_request', 'snapshot_at', snap,
        'user_instruction', format('Website upload by %s (active administrator) at %s AWST, run by r781. Craig 31 Oct 2026 11:42 AWST: "turn on the applys for the other uploads so i can do them".',
          u.uploader_email, to_char(u.created_at AT TIME ZONE 'Australia/Perth', 'DD Mon YYYY HH24:MI')));
      res := public.pdc_import_job_parts_csv_20260912(env, u.rows);
    ELSE
      env := jsonb_build_object('source_kind', CASE u.kind WHEN 'bt_deal_items' THEN 'broome_sales_deal_items_workbook' ELSE 'karratha_sales_deal_items_workbook' END,
        'sheet', coalesce(u.meta->>'sheet', ''), 'header_row', 4, 'headers', headers, 'file_name', u.filename, 'file_sha256', u.workbook_sha256,
        'container', coalesce(u.meta->>'container', ''), 'extract_text', coalesce(u.meta->>'extract_text', ''), 'extract_tz', 'Australia/Perth',
        'received_at', u.created_at, 'source_rows', jsonb_array_length(u.rows), 'mailbox', 'website_admin_upload', 'sender', u.uploader_email,
        'internet_message_id', 'website-upload-781:' || u.upload_id::text);
      IF u.kind = 'kta_deal_items' THEN env := env || jsonb_build_object('dealer_code', '14450'); END IF;
      IF u.kind = 'bt_deal_items' THEN
        res := pdc_sales_private.import_sales_accessories_20261020('manifest', env, u.rows, NULL);
        IF res->>'ok' = 'true' THEN prev := pdc_sales_private.import_sales_accessories_20261020('preview', env, NULL, NULL); res := prev; END IF;
        IF res->>'ok' = 'true' AND coalesce(res->>'replay', 'false') <> 'true' THEN
          res := pdc_sales_private.import_sales_accessories_20261020('apply', env, NULL, prev->>'preview_hash') || jsonb_build_object('preview', prev->'summary');
        END IF;
      ELSE
        res := pdc_sales_private.import_karratha_sales_accessories_20261025('manifest', env, u.rows, NULL);
        IF res->>'ok' = 'true' THEN prev := pdc_sales_private.import_karratha_sales_accessories_20261025('preview', env, NULL, NULL); res := prev; END IF;
        IF res->>'ok' = 'true' AND coalesce(res->>'replay', 'false') <> 'true' THEN
          res := pdc_sales_private.import_karratha_sales_accessories_20261025('apply', env, NULL, prev->>'preview_hash') || jsonb_build_object('preview', prev->'summary');
        END IF;
      END IF;
    END IF;
    IF res->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'importer refused: %', coalesce(res->>'code', left(res::text, 300)); END IF;
    UPDATE pdc_import_620.other_uploads_781 SET status = 'done', result = res, finished_at = clock_timestamp() WHERE upload_id = u.upload_id;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  IF v_err IS NOT NULL THEN
    UPDATE pdc_import_620.other_uploads_781 SET status = 'failed', error = left(v_err, 1000), finished_at = clock_timestamp() WHERE upload_id = u.upload_id;
  END IF;
  PERFORM pg_advisory_unlock(hashtextextended('pdc_import_620.run_other_781', 0));
  COMMIT;
END $f$;
REVOKE ALL ON PROCEDURE pdc_import_620.run_other_781() FROM PUBLIC, anon, authenticated, service_role;

-- KTA normalize: the email rule (pdc@ mailbox, Revolution sender) also passes for the website upload being run right now.
DO $r781$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)'::regprocedure;
  a1 text := $a$IF lower(btrim(coalesce(p_envelope->>'mailbox','')))$a$;
  a2 text := $a$IF lower(btrim(coalesce(p_envelope->>'sender','')))$a$;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> 'ef85e5393c5039ac4e8421f6b058c405' THEN RAISE EXCEPTION 'r781: KTA normalize is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 OR (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1 THEN
    RAISE EXCEPTION 'r781: KTA anchors not found once'; END IF;
  v_new := replace(replace(v_old, a1, $b$IF NOT pdc_import_620.web_upload_781_ok(p_envelope) /* r781 (F386) website upload */ AND lower(btrim(coalesce(p_envelope->>'mailbox','')))$b$),
                   a2, $b$IF NOT pdc_import_620.web_upload_781_ok(p_envelope) AND lower(btrim(coalesce(p_envelope->>'sender','')))$b$);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r781: readback differs'; END IF;
END $r781$;

SELECT cron.schedule('pdc-import-other-781', '* * * * *', 'CALL pdc_import_620.run_other_781()');

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('website_apply_other_reports_781', 'F386',
  'Upload (r781): CW parts and BT / KTA deal items can be applied from the website: queue RPC administrator only, queue table closed to API roles, worker on cron, KTA website rule only for the running upload.',
  $chk$
SELECT to_regprocedure('public.revolution_upload_other_781(text,text,text,jsonb,jsonb)') IS NOT NULL
   AND NOT has_function_privilege('anon', 'public.revolution_upload_other_781(text,text,text,jsonb,jsonb)', 'EXECUTE')
   AND NOT has_table_privilege('authenticated', 'pdc_import_620.other_uploads_781', 'SELECT')
   AND EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pdc-import-other-781' AND active)
   AND position('web_upload_781_ok(p_envelope)' IN (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)'))) > 0
   AND NOT pdc_import_620.web_upload_781_ok('{"mailbox":"website_admin_upload","file_sha256":"x","sender":"x"}'::jsonb)
 AS ok, 'website apply for parts and deal items' AS detail
$chk$, true, 568, 'r781');
