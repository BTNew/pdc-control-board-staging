-- r660 (F270) / sort 382. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026 19:06: Status 80 on the Service report must put the vehicle in QC with every item ticked, even if
-- someone forgot to clear a stoppage, it is marked at sublet, or line changes are still pending review.
-- Change to pdc_codex_intake_private.apply_service_pmb_complete (Kajel's apply calls it; apply_v1 itself is unchanged):
--   * drop the three holds: active_stoppage, sublet_return, pending_operation_changes (the stoppage is cleared on the move)
--   * tick every open checkable item as a panel tick (same table as the side panel), so QC sign-off is not blocked
--   Kept: job status validation review, newer linked job, QC rework; vehicles already QC/RFT/completed/99 are skipped.
-- The body is edited in place (each edit must match exactly once). Its pin and the four checks that pin it move to the
-- new md5. Pin count stays 241. Kajel's guarded md5s (preview, rows, apply_v1, PO feed) are unchanged.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $r660$
DECLARE
  awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_drop text := E'\n  ELSIF v.pmb_stoppage_started_at IS NOT NULL\n   THEN problem:=''active_stoppage_requires_review'';\n  ELSIF upper(btrim(coalesce(v.current_location,'''')))=''SUBLET''\n   THEN problem:=''sublet_return_requires_review'';\n  ELSIF EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=v.id AND status=''pending'')\n   THEN problem:=''pending_operation_changes_require_review'';';
  c_move text := E'  UPDATE public.vehicles SET current_location=''QC'',pmb_stage=NULL,';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r660: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r660: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r660: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 382 OR fault_id = 'F270' OR added_in = 'r660' OR check_name = 'status80_to_qc_660') THEN RAISE EXCEPTION 'r660: sort 382 or F270 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r660: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure;
  IF md5(v_old) <> '9808feb2a0a93a79b0d67aebdca0a4aa' THEN RAISE EXCEPTION 'r660: status 80 function is not the r511 text'; END IF;
  v_old := replace(v_old, E'\r\n', E'\n');
  IF (length(v_old) - length(replace(v_old, c_drop, ''))) / length(c_drop) <> 1 THEN RAISE EXCEPTION 'r660: hold block not found once'; END IF;
  IF (length(v_old) - length(replace(v_old, c_move, ''))) / length(c_move) <> 1 THEN RAISE EXCEPTION 'r660: QC move not found once'; END IF;
  v_new := replace(v_old, c_drop, E'\n  -- r660 (F270): an open stoppage, a sublet location or pending line changes no longer hold Status 80 out of QC.');
  v_new := replace(v_new, c_move,
E'  -- r660 (F270): tick every open checkable item (panel ticks, as the side panel does) so QC sign-off is not blocked.\n'
|| E'  INSERT INTO public.pdc_panel_line_completion_history_565(vehicle_id,line_identity,completed,actor_id,actor_email,actor_role,acted_at)\n'
|| E'  SELECT v.id,l->>''line_identity'',true,b.created_by,''tune-status-80'',NULL,recorded\n'
|| E'  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l\n'
|| E'  WHERE coalesce(l->>''active'',''true'')=''true'' AND coalesce(l->>''rejected'',''false'')<>''true'' AND coalesce(l->>''completed'',''false'')<>''true''\n'
|| E'    AND l->>''line_identity'' ~* ''^(source|manual):[0-9a-f-]{36}$''\n'
|| E'    AND upper(btrim(coalesce(l->>''stage_code'',''''))) NOT IN(''JOB_CARD_NOTES'',''PIT_INSPECTION'')\n'
|| E'    AND NOT EXISTS(SELECT 1 FROM public.pdc_panel_line_completion_565 c WHERE c.vehicle_id=v.id AND c.line_identity=l->>''line_identity'' AND c.completed);\n'
|| E'  INSERT INTO public.pdc_panel_line_completion_565(vehicle_id,line_identity,completed,actor_id,actor_email,actor_role,acted_at,version)\n'
|| E'  SELECT v.id,l->>''line_identity'',true,b.created_by,''tune-status-80'',NULL,recorded,1\n'
|| E'  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l\n'
|| E'  WHERE coalesce(l->>''active'',''true'')=''true'' AND coalesce(l->>''rejected'',''false'')<>''true'' AND coalesce(l->>''completed'',''false'')<>''true''\n'
|| E'    AND l->>''line_identity'' ~* ''^(source|manual):[0-9a-f-]{36}$''\n'
|| E'    AND upper(btrim(coalesce(l->>''stage_code'',''''))) NOT IN(''JOB_CARD_NOTES'',''PIT_INSPECTION'')\n'
|| E'  ON CONFLICT(vehicle_id,line_identity) DO UPDATE SET completed=true,actor_id=EXCLUDED.actor_id,actor_email=EXCLUDED.actor_email,\n'
|| E'    actor_role=NULL,acted_at=EXCLUDED.acted_at,version=pdc_panel_line_completion_565.version+1\n'
|| E'  WHERE NOT pdc_panel_line_completion_565.completed AND pdc_panel_line_completion_565.vehicle_id=EXCLUDED.vehicle_id\n'
|| E'    AND pdc_panel_line_completion_565.line_identity=EXCLUDED.line_identity;\n'
|| E'  UPDATE public.vehicles SET current_location=''QC'',pmb_stage=NULL,\n'
|| E'   pmb_stoppage_reason=NULL,pmb_stoppage_started_at=NULL,pmb_stoppage_started_by=NULL,\n'
|| E'   pmb_stoppage_cleared_at=CASE WHEN pmb_stoppage_started_at IS NOT NULL THEN recorded ELSE pmb_stoppage_cleared_at END,\n'
|| E'   pmb_stoppage_cleared_by=CASE WHEN pmb_stoppage_started_at IS NOT NULL THEN b.created_by ELSE pmb_stoppage_cleared_by END,');
  -- Rebuild the function with the same header (arguments, return, language, security, settings).
  v_def := pg_get_functiondef('pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure);
  v_def := regexp_replace(v_def, '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid = 'pdc_codex_intake_private.apply_service_pmb_complete(uuid)'::regprocedure;
  IF v_md5 = '9808feb2a0a93a79b0d67aebdca0a4aa' THEN RAISE EXCEPTION 'r660: function did not change'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_md5, release = 'r660'
  WHERE signature = 'pdc_codex_intake_private.apply_service_pmb_complete(uuid)' AND prosrc_md5 = '9808feb2a0a93a79b0d67aebdca0a4aa';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r660: pin row not moved'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, '9808feb2a0a93a79b0d67aebdca0a4aa', v_md5)
  WHERE check_sql LIKE '%9808feb2a0a93a79b0d67aebdca0a4aa%';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 4 THEN RAISE EXCEPTION 'r660: expected 4 checks to move to the new md5, moved %', v_n; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r660: pin count changed'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('status80_to_qc_660', 'F270',
    'Status 80 moves to QC with every checkable item ticked; open stoppage, sublet and pending changes no longer hold it.',
    $chk660$
SELECT strpos(a, 'active_stoppage_requires_review') = 0 AND strpos(a, 'sublet_return_requires_review') = 0
  AND strpos(a, 'pending_operation_changes_require_review') = 0
  AND strpos(a, 'qc_rework_requires_review') > 0 AND strpos(a, 'newer_linked_job_requires_review') > 0
  AND strpos(a, 'INSERT INTO public.pdc_panel_line_completion_565') > 0 AND strpos(a, 'pdc_qc_operation_completions_379') = 0
  AND strpos(a, 'pmb_stoppage_started_at=NULL') > 0
 AS ok, 'Status 80 goes to QC with items ticked' AS detail
FROM (SELECT prosrc AS a FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.apply_service_pmb_complete(uuid)')) x
$chk660$, true, 382, 'r660');
END $r660$;

-- Checks that pinned the old md5 must still pass against the new text.
DO $post660$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks
           WHERE check_name IN ('status80_upserts_qc_station_work_items', 'status80_completes_parts_sublet_and_all_bays', 'status80_to_qc_660') LOOP
    EXECUTE r.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r660: check % red: %', r.check_name, detail; END IF;
  END LOOP;
END $post660$;
