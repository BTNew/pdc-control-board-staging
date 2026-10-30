-- r759 (F365) / sort 479. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 18:28 and 20:01: "go with the new rules and make sure we have a backup". Backup: schema
-- pdc_backup_r759_20261030 (vehicles, bookings, assignments, Navision records, activations, archive receipts, function sources).
-- The Service as a Whole apply used to archive every 138/139 board car missing from the sheet (hidden, still active,
-- no times). New rules, applied per car inside service_whole_archive_569:
--  Rule 1 (not on Navision): the car is completed (lifecycle completed, location Completed, off the board, dates kept),
--    reason "left the Revolution service list". board_purged_at is still stamped so the 15-car apply gate counts it.
--  Rule 2 (still on Navision, dealer 37047 or 14450): the car stays on the board where it is, tagged
--    source_payload.revolution_missing_since = first date it was missing; nothing else changes. It completes later on
--    Navision "Delivered - At Dealer" or when its record leaves Navision (r758). The tag clears when the car is back in a sheet.
--  Unchanged: dept 135 and owner-hold rules, queued/planned bay release on completion, no Sales write, decision function.
-- Rollback: supabase/rollbacks/20261030201500_r759_upload_left_revolution_rules.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $r759$
DECLARE v_old text; v_new text; v_def text; v_anchor text;
  sig regprocedure := 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure;
  a1 text := E' v_released_rows jsonb; v_live_rows jsonb; v_on_sales boolean; v_loc text;\n';
  b1 text := E' v_released_rows jsonb; v_live_rows jsonb; v_on_sales boolean; v_loc text;\n v_kept integer := 0; v_cleared integer := 0;\n';
  a2 text := E' SELECT count(*) FILTER (WHERE p.visible_on_board),\n';
  b2 text := E' -- r759: a car back in the sheet loses its "missing from Revolution" tag.\n'
          || E' UPDATE public.vehicles v SET source_payload=(coalesce(v.source_payload,''{}''::jsonb) - ''revolution_missing_since'') - ''revolution_missing_rule'',\n'
          || E'   version=version+1, updated_at=clock_timestamp()\n'
          || E' WHERE v.deleted_at IS NULL AND v.lifecycle_state::text=''active'' AND (v.source_payload->>''revolution_missing_since'') IS NOT NULL\n'
          || E'   AND EXISTS (SELECT 1 FROM pdc_service_snapshot_private.snapshot_lines_479 l WHERE l.snapshot_sha256=v_sha\n'
          || E'     AND public.normalize_vehicle_stock_number(v.stock_number) IN (public.normalize_vehicle_stock_number(l.stock_number),\n'
          || E'       public.normalize_vehicle_stock_number(l.file_stock), public.normalize_vehicle_stock_number(l.file_rego)));\n'
          || E' GET DIAGNOSTICS v_cleared = ROW_COUNT;\n'
          || E' SELECT count(*) FILTER (WHERE p.visible_on_board),\n';
  a3 text := E'  UPDATE public.vehicles SET visible_on_board=false, board_purged_at=clock_timestamp(),\n'
          || E'    board_purge_reason=''r569: 138/139 PMB-board vehicle absent from the latest complete as-a-Whole sheet'',\n'
          || E'    board_purged_by=v_actor, pmb_stage=NULL, pmb_bay_stage=NULL, pmb_bay_number=NULL,\n'
          || E'    version=version+1, updated_by=v_actor, updated_at=clock_timestamp()\n'
          || E'  WHERE id=v_row.vehicle_id AND deleted_at IS NULL AND board_purged_at IS NULL AND lifecycle_state::text=''active''\n';
  b3 text := E'  -- r759 (F365): still on Navision -> stays on the board, tagged. Off Navision -> completed (left the Revolution service list).\n'
          || E'  IF v_on_sales THEN\n'
          || E'   UPDATE public.vehicles SET source_payload=coalesce(source_payload,''{}''::jsonb)||jsonb_build_object(\n'
          || E'      ''revolution_missing_since'', to_char(clock_timestamp() AT TIME ZONE ''Australia/Perth'',''YYYY-MM-DD''), ''revolution_missing_rule'', ''r759''),\n'
          || E'     version=version+1, updated_by=v_actor, updated_at=clock_timestamp()\n'
          || E'   WHERE id=v_row.vehicle_id AND deleted_at IS NULL AND board_purged_at IS NULL AND lifecycle_state::text=''active''\n'
          || E'     AND (source_payload->>''revolution_missing_since'') IS NULL;\n'
          || E'   IF FOUND THEN v_kept := v_kept + 1; END IF;\n'
          || E'   CONTINUE;\n'
          || E'  END IF;\n'
          || E'  UPDATE public.vehicles SET visible_on_board=false, board_purged_at=clock_timestamp(),\n'
          || E'    board_purge_reason=''r759: left the Revolution service list and is not on Navision; completed'',\n'
          || E'    board_purged_by=v_actor, pmb_stage=NULL, pmb_bay_stage=NULL, pmb_bay_number=NULL,\n'
          || E'    lifecycle_state=''completed'', current_location=''Completed'', workshop_status=''completed'',\n'
          || E'    workshop_status_updated_at=clock_timestamp(), workshop_status_updated_by=v_actor, active_workshop_booking_id=NULL,\n'
          || E'    location_override=NULL, location_override_reason=NULL, location_override_at=NULL, location_override_by=NULL,\n'
          || E'    source_payload=coalesce(source_payload,''{}''::jsonb)||jsonb_build_object(''left_revolution_rule'',''r759'',''left_revolution_at'',clock_timestamp()),\n'
          || E'    version=version+1, updated_by=v_actor, updated_at=clock_timestamp()\n'
          || E'  WHERE id=v_row.vehicle_id AND deleted_at IS NULL AND board_purged_at IS NULL AND lifecycle_state::text=''active''\n';
  a4 text := E'    ''r569: 138/139 vehicle absent from the latest complete as-a-Whole sheet archived off the PMB board'',\n';
  b4 text := E'    ''r759: 138/139 vehicle left the Revolution service list and is not on Navision; completed off the PMB board'',\n';
  a5 text := E' RETURN jsonb_build_object(''ok'',true,''reason'',''complete_file'',''archived'',v_archived,';
  b5 text := E' RETURN jsonb_build_object(''ok'',true,''reason'',''complete_file'',''archived'',v_archived,''completed_left_revolution'',v_archived,''kept_on_navision'',v_kept,''missing_tag_cleared'',v_cleared,';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r759: staging only'; END IF;
  IF to_regclass('pdc_backup_r759_20261030.vehicles') IS NULL THEN RAISE EXCEPTION 'r759: backup schema missing'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 479 OR fault_id = 'F365' OR added_in = 'r759') THEN RAISE EXCEPTION 'r759: sort 479 or F365 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r759: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '6bd4a75d2b96a187b3e0d5ff99f4d217' THEN RAISE EXCEPTION 'r759: service_whole_archive_569 is not the expected body'; END IF;
  FOREACH v_anchor IN ARRAY ARRAY[a1, a2, a3, a4, a5] LOOP
    IF (length(v_old) - length(replace(v_old, v_anchor, ''))) / length(v_anchor) <> 1 THEN RAISE EXCEPTION 'r759: anchor not found once: %', left(v_anchor, 70); END IF;
  END LOOP;
  v_new := replace(replace(replace(replace(replace(v_old, a1, b1), a2, b2), a3, b3), a4, b4), a5, b5);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r759: readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('upload_left_revolution_rules_759', 'F365',
    'Upload (r759): a board car missing from the Service as a Whole sheet is completed when off Navision and kept, tagged, when still on Navision. Both branches present; no car archived (hidden but active) by the upload after r759.',
    $chk$
SELECT (SELECT strpos(prosrc, 'revolution_missing_since') > 0 AND strpos(prosrc, 'left_revolution_rule') > 0 AND strpos(prosrc, 'IF v_on_sales THEN') > 0
          FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'))
   AND NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state = 'active' AND NOT v.visible_on_board
                   AND v.board_purged_at > '2026-10-30 20:30+08'::timestamptz AND v.board_purge_reason LIKE 'r569:%')
 AS ok, 'missing-from-sheet cars complete (off Navision) or stay tagged (on Navision); no new r569 archives' AS detail
$chk$, true, 479, 'r759');
END $r759$;
