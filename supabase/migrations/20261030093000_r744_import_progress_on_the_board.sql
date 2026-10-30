-- r744 (F348) / imports plan step 4 / sort 461. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 07:10: "we need to really figure out a better way to do imports so it doesnt slow the whole board down";
-- 08:11 "5 - yes". While a Revolution import runs (about 30 minutes, 40 parts) staff saw a slow board with no reason
-- given. The board already refreshes on every revision bump, and every applied part bumps it, so the board snapshot
-- reader now carries 'import_progress' on all three of its answers (full, delta, not_modified). The website shows a
-- banner "Import running, part N of M" from it and hides it on the first answer after the import finishes. No new
-- calls, no polling: the field rides on reads the board already makes.
-- Rollback: supabase/rollbacks/20261030093000_r744_import_progress_on_the_board.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $pre744$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r744: staging only'; END IF;
  IF to_regprocedure('public.pdc_import_progress_744()') IS NOT NULL THEN RAISE EXCEPTION 'r744: already applied'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature LIKE '%board_snapshot_conditional%') THEN RAISE EXCEPTION 'r744: reader is pinned, not expected'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 461 OR fault_id = 'F348' OR added_in = 'r744') THEN RAISE EXCEPTION 'r744: sort 461 or F348 is taken'; END IF;
END $pre744$;

-- The newest queued or running import job, or running=false. Read only inside the board snapshot reader.
CREATE FUNCTION public.pdc_import_progress_744()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
  SELECT coalesce((
    SELECT jsonb_build_object('running', true, 'mode', j.mode, 'status', j.status, 'n_parts', coalesce(j.n_parts, 0),
      'part', least(coalesce(j.n_parts, 0), CASE WHEN j.mode = 'apply'
        THEN (SELECT count(*) FROM jsonb_array_elements(coalesce(j.parts, '[]'::jsonb)) p WHERE p ? 'apply')
        ELSE jsonb_array_length(coalesce(j.parts, '[]'::jsonb)) END),
      'started_at', j.started_at)
    FROM pdc_import_620.jobs j WHERE j.status IN ('queued', 'running') ORDER BY j.created_at DESC LIMIT 1),
    jsonb_build_object('running', false));
$fn$;
REVOKE ALL ON FUNCTION public.pdc_import_progress_744() FROM PUBLIC, anon, authenticated;

DO $r744$
DECLARE v_old text; v_new text; v_def text;
  a1 text := $a$RETURN jsonb_build_object('ok', true, 'code', 'not_modified', 'not_modified', true, 'snapshot_token', v_token);$a$;
  b1 text := $a$RETURN jsonb_build_object('ok', true, 'code', 'not_modified', 'not_modified', true, 'snapshot_token', v_token, 'import_progress', public.pdc_import_progress_744());$a$;
  a2 text := $a$RETURN v_base || jsonb_build_object('snapshot_token', v_token);$a$;
  b2 text := $a$RETURN v_base || jsonb_build_object('snapshot_token', v_token, 'import_progress', public.pdc_import_progress_744());$a$;
  a3 text := $a$'data', (v_base->'data') - 'vehicles', 'vehicle_ids', v_ids, 'changed', v_changed);$a$;
  b3 text := $a$'data', (v_base->'data') - 'vehicles', 'vehicle_ids', v_ids, 'changed', v_changed, 'import_progress', public.pdc_import_progress_744());$a$;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)'::regprocedure;
  IF md5(v_old) <> '5347811a3b138b67126da2fb023578bf' THEN RAISE EXCEPTION 'r744: reader is not the body this was written against'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1
     OR (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1
     OR (length(v_old) - length(replace(v_old, a3, ''))) / length(a3) <> 1 THEN RAISE EXCEPTION 'r744: anchors not found once'; END IF;
  v_new := replace(replace(replace(v_old, a1, b1), a2, b2), a3, b3);
  v_def := regexp_replace(pg_get_functiondef('public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)'::regprocedure) <> v_new THEN RAISE EXCEPTION 'r744: readback differs'; END IF;
END $r744$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, added_in, enabled, sort_order, description, check_sql) VALUES ('import_progress_on_the_board_744', 'F348', 'r744', true, 461,
 'Import progress (r744): the board snapshot reader carries import_progress on every answer; the progress function is staff-invisible and names the newest queued or running job.',
$chk744$
SELECT to_regprocedure('public.pdc_import_progress_744()') IS NOT NULL
  AND NOT has_function_privilege('authenticated', 'public.pdc_import_progress_744()', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.pdc_import_progress_744()', 'EXECUTE')
  AND (SELECT (length(prosrc) - length(replace(prosrc, 'pdc_import_progress_744()', ''))) / length('pdc_import_progress_744()') FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)'::regprocedure) = 3
  AND (public.pdc_import_progress_744() ? 'running')
 AS ok, 'import progress rides on the board reader' AS detail
$chk744$);

DO $post744$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('import_progress_on_the_board_744','board_delta_676','regression_checks_self_test','protected_function_md5s') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r744: % red after apply: %', r.check_name, left(r.detail, 200); END IF;
  END LOOP;
END $post744$;
