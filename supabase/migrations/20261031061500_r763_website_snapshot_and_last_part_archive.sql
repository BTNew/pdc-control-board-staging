-- r763 (F369, F371) / sorts 482, 483. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 2026 05:59 "go" (faster, automatic imports). Found on the way:
-- F369: the website Apply (r728) never recorded the whole-file snapshot (Kajel used to call record_snapshot_479 from the
--       email), so service_whole_archive_569 returned ok=false 'snapshot_not_recorded' on every part and every part was
--       rolled back. Every website Apply since 29 Oct applied nothing. Fix: public.revolution_upload_snapshot_763 lets the
--       uploader record the snapshot before the rows; the edge function calls it. A 'done' job with no applied part no
--       longer counts as a duplicate, so the same file can be sent again.
-- F371: when any car was due to leave the board, archive_569 archived it on part 1 and apply_part refused every part but
--       the last ('archive_count_not_0'). Fix: archive_569 only archives when apply_part says it is the last part
--       (pdc.import620_archive_allowed = 'on'); other parts return ok=true 'deferred_to_last_part'.
-- Backup: pdc_backup_r763_20261031.function_sources. Rollback: supabase/rollbacks/20261031061500_r763_website_snapshot_and_last_part_archive.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

CREATE SCHEMA IF NOT EXISTS pdc_backup_r763_20261031;
REVOKE ALL ON SCHEMA pdc_backup_r763_20261031 FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS pdc_backup_r763_20261031.function_sources (sig text PRIMARY KEY, prosrc text NOT NULL, md5 text NOT NULL, saved_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT s.sig, p.prosrc, md5(p.prosrc) FROM (VALUES ('pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'), ('pdc_import_620.apply_part(uuid,integer,boolean)'), ('public.revolution_upload_begin_728(text,text,text)')) s(sig)
JOIN pg_proc p ON p.oid = s.sig::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r763$
DECLARE v_old text; v_new text; v_def text; sig regprocedure;
  -- F371 a: archive_569 defers unless apply_part marked the last part
  a1 text := E'BEGIN\n SELECT count(*),\n';
  b1 text := E'BEGIN\n -- r763 (F371): only the last part of an import archives. apply_part sets pdc.import620_archive_allowed = on for it.\n'
          || E' IF coalesce(current_setting(''pdc.import620_archive_allowed'', true), '''') <> ''on'' THEN\n'
          || E'  RETURN jsonb_build_object(''ok'',true,''reason'',''deferred_to_last_part'',''archived'',0,''sales_write'',false); END IF;\n'
          || E' SELECT count(*),\n';
  -- F371 b: apply_part marks the last part
  a2 text := E'      UPDATE auth.users SET banned_until = NULL WHERE id = pdc_import_620.importer_id();\n      v_result := public.pdc_pilbara_service_apply_v1(';
  b2 text := E'      UPDATE auth.users SET banned_until = NULL WHERE id = pdc_import_620.importer_id();\n'
          || E'      PERFORM set_config(''pdc.import620_archive_allowed'', CASE WHEN p_last THEN ''on'' ELSE ''off'' END, true); -- r763 (F371)\n'
          || E'      v_result := public.pdc_pilbara_service_apply_v1(';
  -- F369 b: a done job that applied nothing is not a duplicate
  a3 text := E'  IF p_mode = ''apply'' AND EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE workbook_sha256 = p_sha AND mode = ''apply'' AND status = ''done'') THEN\n';
  b3 text := E'  IF p_mode = ''apply'' AND EXISTS (SELECT 1 FROM pdc_import_620.jobs j WHERE j.workbook_sha256 = p_sha AND j.mode = ''apply'' AND j.status = ''done''\n'
          || E'      AND EXISTS (SELECT 1 FROM jsonb_array_elements(j.parts) p WHERE p->''apply''->>''ok'' = ''true'')) THEN -- r763 (F369): applied nothing = not a duplicate\n';
  a4 text := E'    IF v_prior.status IN (''queued'', ''running'') OR (p_mode = ''apply'' AND v_prior.status = ''done'') THEN RETURN jsonb_build_object(''ok'', false, ''error'', ''duplicate_file''); END IF;\n';
  b4 text := E'    IF v_prior.status IN (''queued'', ''running'') THEN RETURN jsonb_build_object(''ok'', false, ''error'', ''duplicate_file''); END IF; -- r763 (F369)\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r763: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order IN (482, 483) OR fault_id IN ('F369', 'F371') OR added_in = 'r763') THEN RAISE EXCEPTION 'r763: sort 482/483 or F369/F371 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r763: an import job is running'; END IF;

  sig := 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '86b429f0e59cebccd82359d890c8b0f6' THEN RAISE EXCEPTION 'r763: archive_569 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r763: archive anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r763: archive readback differs'; END IF;

  sig := 'pdc_import_620.apply_part(uuid,integer,boolean)'::regprocedure;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '8fdc72089413b558fd90c6b85ccd5a37' THEN RAISE EXCEPTION 'r763: apply_part is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1 THEN RAISE EXCEPTION 'r763: apply_part anchor not found once'; END IF;
  v_new := replace(v_old, a2, b2);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r763: apply_part readback differs'; END IF;

  sig := 'public.revolution_upload_begin_728(text,text,text)'::regprocedure;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '2b75aa8ecef7eae73b0ca48941eb6475' THEN RAISE EXCEPTION 'r763: begin_728 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a3, ''))) / length(a3) <> 1 OR (length(v_old) - length(replace(v_old, a4, ''))) / length(a4) <> 1 THEN RAISE EXCEPTION 'r763: begin_728 anchors not found once'; END IF;
  v_new := replace(replace(v_old, a3, b3), a4, b4);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r763: begin_728 readback differs'; END IF;
END $r763$;

-- F369 a: the uploader records the whole-file snapshot (same recorder Kajel used), before the rows are sent.
CREATE OR REPLACE FUNCTION public.revolution_upload_snapshot_763(p_upload uuid, p_header jsonb, p_lines jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
SET statement_timeout TO '120s'
AS $function$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); u pdc_import_620.web_uploads_728; v_lines integer; v_at timestamptz; v_exp integer;
BEGIN
  -- r763 (F369): the website Apply records the 'as a Whole' snapshot the archive step needs. Writes only pdc_service_snapshot_private.
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'staging_only'); END IF;
  SELECT * INTO u FROM pdc_import_620.web_uploads_728 WHERE upload_id = p_upload AND auth_user_id = auth.uid();
  IF NOT FOUND OR u.job_id IS NULL OR u.mode <> 'apply' THEN RETURN jsonb_build_object('ok', false, 'error', 'upload_not_found'); END IF;
  IF jsonb_typeof(p_header) <> 'object' OR p_header->>'snapshot_sha256' IS DISTINCT FROM u.workbook_sha256 THEN RETURN jsonb_build_object('ok', false, 'error', 'snapshot_sha_mismatch'); END IF;
  IF jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) NOT BETWEEN 1 AND 30000 THEN RETURN jsonb_build_object('ok', false, 'error', 'bad_lines'); END IF;
  -- r763c (F380): the same file sent again. The snapshot is the file's own evidence; a complete one is reused as recorded
  -- (board-derived identity columns may have moved since, and the recorder refuses a different value for a recorded line).
  SELECT s.source_snapshot_at, s.expected_line_count INTO v_at, v_exp FROM pdc_service_snapshot_private.snapshots_479 s WHERE s.snapshot_sha256 = u.workbook_sha256;
  IF FOUND THEN
    SELECT count(*) INTO v_lines FROM pdc_service_snapshot_private.snapshot_lines_479 l WHERE l.snapshot_sha256 = u.workbook_sha256;
    IF v_lines = v_exp THEN
      RETURN jsonb_build_object('ok', true, 'upload_id', p_upload, 'snapshot_sha256', u.workbook_sha256, 'lines_recorded', v_lines, 'expected', v_exp, 'reused', true);
    END IF;
    -- partial: keep the first header so the recorder accepts the rest of the lines
    p_header := p_header || jsonb_build_object('source_snapshot_at', to_char(v_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  END IF;
  PERFORM pdc_service_snapshot_private.record_snapshot_479(p_header - 'gmail_message_id', p_lines);
  SELECT count(*) INTO v_lines FROM pdc_service_snapshot_private.snapshot_lines_479 l WHERE l.snapshot_sha256 = u.workbook_sha256;
  RETURN jsonb_build_object('ok', true, 'upload_id', p_upload, 'snapshot_sha256', u.workbook_sha256, 'lines_recorded', v_lines, 'expected', (p_header->>'line_count')::integer);
END $function$;
REVOKE ALL ON FUNCTION public.revolution_upload_snapshot_763(uuid, jsonb, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revolution_upload_snapshot_763(uuid, jsonb, jsonb) TO authenticated, service_role;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('website_snapshot_recorded_763', 'F369',
 'Upload (r763): the website Apply can record the as-a-Whole snapshot (revolution_upload_snapshot_763 exists, authenticated may call it, it calls record_snapshot_479) and a done job that applied nothing is not a duplicate in begin_728.',
 $chk$
SELECT to_regprocedure('public.revolution_upload_snapshot_763(uuid,jsonb,jsonb)') IS NOT NULL
   AND has_function_privilege('authenticated', 'public.revolution_upload_snapshot_763(uuid,jsonb,jsonb)', 'EXECUTE')
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.revolution_upload_snapshot_763(uuid,jsonb,jsonb)')), 'record_snapshot_479') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.revolution_upload_begin_728(text,text,text)')), $$p->'apply'->>'ok' = 'true'$$) > 0
 AS ok, 'website apply records the snapshot; a job that applied nothing can be sent again' AS detail
$chk$, true, 482, 'r763'),
('archive_only_on_last_part_763', 'F371',
 'Upload (r763): service_whole_archive_569 defers unless pdc.import620_archive_allowed is on, and apply_part turns it on for the last part only.',
 $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)')), 'deferred_to_last_part') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.apply_part(uuid,integer,boolean)')), $$set_config('pdc.import620_archive_allowed', CASE WHEN p_last THEN 'on' ELSE 'off' END, true)$$) > 0
 AS ok, 'cars leave the board on the last part only; earlier parts apply their lines' AS detail
$chk$, true, 483, 'r763');

-- Check 279 (service_whole_snapshot_479) expected the r479 key literal; r760 made the board key the master. Accept either.
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,
  $old$position($q$'board_key_not_blank_r479'$q$ in src.k)>0 AND position($q$r.raw_row->>'email_subject'='PMG PD Service as a Whole w/Sublet'$q$ in src.k)>0 AS key_fill_blank_only$old$,
  $new$(position($q$'board_key_not_blank_r479'$q$ in src.k)>0 OR position($q$'board_key_is_master_r760'$q$ in src.k)>0) AND position($q$r.raw_row->>'email_subject'='PMG PD Service as a Whole w/Sublet'$q$ in src.k)>0 AS key_fill_blank_only$new$)
WHERE check_name = 'service_whole_snapshot_479';
