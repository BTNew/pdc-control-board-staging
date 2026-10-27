-- r570 (F184) / sort 341. Go-live. Staging cdsmnqxtyyoeoznmbidd only.
-- Production is not a target.
--
-- Ledger. Live on main: r562 / F176 / sort 335 is the key gate, r563 / F177 /
-- sort 336 is the arrival age, r565 / F179 / sort 337 is the panel tick,
-- r567 / F181 / sort 338 is the typed Parts ETA, r568 / F182 / sort 339 is the
-- bus component split, and r569 / F183 / sort 340 is the bay pause (#554).
-- r566 / F180 was applied and rolled back. This release is the next free row:
-- r570 / F184 / sort 341. Object names stay _569 so the helper and patched
-- prosrc md5s hold. It does not treat r562 / F176 / sort 335 as free, and it
-- does not treat r569 / F183 / sort 340 as free.
--
-- Craig, 27 Oct 2026 10:27 and 10:52 AWST. The latest as-a-Whole sheet is the
-- only list of active department 138 and 139 vehicles. A card on the sheet and
-- on the board is updated. A card on the sheet, not on the board, and not Sub
-- Status 99 is created in the New vehicle section (Yard Hold, hidden), including
-- a division match. A 138/139 board vehicle that is not on the sheet is archived.
-- There is no QC step and no open-job-card guard. A CreateAdvisor filename that
-- is otherwise a complete file is allowed.
--
-- Craig, 27 Oct 2026 10:57 AWST. Archive applies to the PMB board only
-- (departments 138 and 139). It never archives, hides, or alters Broome Toyota
-- Sales (37047) or Karratha Sales (14450). Those boards have their own rules.
-- A vehicle that is also on a Sales board is still archived on the PMB side.
-- The archive update reads public.vehicles and pdc_pilbara_service_operations
-- only. It does not update a Sales table or a Navision row. sales_write is false.
--
-- Archive means off the board and off every list: visible_on_board false,
-- board_purged_at set, PMB bay cleared. deleted_at is not set. lifecycle_state
-- is not changed. Nothing is hard-deleted. A queued or planned booking has its
-- bay cleared and its assignment released, and the prior bay is stored so
-- service_whole_unarchive_569 puts it back. Status is not changed to deleted.
-- A started or stoppage booking is not modified. It is reported. An owner hold
-- is not released. Department 135 is not edited.
--
-- Undo of one vehicle: SELECT pdc_codex_intake_private.service_whole_unarchive_569(vehicle_id);
-- Undo of this release: supabase/rollbacks/20261027220000_r569_service_whole_archive.down.sql
-- Pins stay 241. Only the rows validator and public apply move in place.
-- capture_service_status, finish_tune_checkout, and apply_service_pmb_complete
-- stay at 7870d544117de6a5465b8212f0d228b7, 3e5c6b28e7c025a6ebbae61879ff3a82,
-- and 9808feb2a0a93a79b0d67aebdca0a4aa. Karratha apply stays
-- a033c7d7719ae588e8a9aa1b26bf2fbf. Karratha intake stays
-- 3fca9ba755a6d30f9b6ac642da084b9b, f4480286dba918f82061bd6daffb4d43, and
-- fbc4f46f10b8581feca8742da2c5ab98.
-- Anchors below are LF. A CRLF region of apply is matched by replace(..., chr(10), chr(13)||chr(10)).
-- The key-loop anchor in apply is LF in the live body and is not converted.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r570: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r570: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r570: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_562' AND fault_id='F176' AND sort_order=335 AND added_in='r562') THEN RAISE EXCEPTION 'r570: r562 / F176 sort 335 is not the key gate'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563') THEN RAISE EXCEPTION 'r570: r563 / F177 sort 336 is not the arrival age'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' AND fault_id='F179' AND sort_order=337 AND added_in='r565') THEN RAISE EXCEPTION 'r570: r565 / F179 sort 337 is not the panel tick'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_stoppage_manual_567' AND fault_id='F181' AND sort_order=338 AND added_in='r567') THEN RAISE EXCEPTION 'r570: r567 / F181 sort 338 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bus_component_split_568' AND fault_id='F182' AND sort_order=339 AND added_in='r568') THEN RAISE EXCEPTION 'r570: r568 / F182 sort 339 is not the bus split'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_job_pause_569' AND fault_id='F183' AND sort_order=340 AND added_in='r569') THEN RAISE EXCEPTION 'r570: r569 / F183 sort 340 is not the bay pause'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=341 OR fault_id='F184' OR check_name='service_whole_archive_570' OR added_in='r570') THEN RAISE EXCEPTION 'r570: sort 341 or F184 is taken'; END IF;
 IF pg_catalog.to_regprocedure('pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)') IS NOT NULL
    OR pg_catalog.to_regprocedure('pdc_codex_intake_private.service_whole_unarchive_569(uuid)') IS NOT NULL
    OR pg_catalog.to_regprocedure('pdc_codex_intake_private.service_whole_board_decision_569(text,boolean,text,integer,text,boolean,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'r569: already applied'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='capture_service_status'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='preview_id uuid, apply_id uuid') IS DISTINCT FROM '7870d544117de6a5465b8212f0d228b7' THEN
  RAISE EXCEPTION 'r569: capture md5 is not r479'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='finish_tune_checkout'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='vid uuid') IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
  RAISE EXCEPTION 'r569: finish_tune_checkout md5 is not baseline'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='apply_service_pmb_complete'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='apply_id uuid') IS DISTINCT FROM '9808feb2a0a93a79b0d67aebdca0a4aa' THEN
  RAISE EXCEPTION 'r569: status 80 md5 is not r511'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='capture_service_status') IS DISTINCT FROM '3fca9ba755a6d30f9b6ac642da084b9b'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='finish_tune_checkout') IS DISTINCT FROM 'f4480286dba918f82061bd6daffb4d43'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_intake' AND p.proname='apply_service_pmb_complete') IS DISTINCT FROM 'fbc4f46f10b8581feca8742da2c5ab98' THEN
  RAISE EXCEPTION 'r569: department 135 intake md5 changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='revolution_service_rows_20261006') IS DISTINCT FROM '5807a896cef15f81030f84a1b68a597b' THEN
  RAISE EXCEPTION 'r569: rows md5 is not r505'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='pdc_pilbara_service_apply_v1') IS DISTINCT FROM 'fc3717a5215de94c93ebb2c7facfe744' THEN
  RAISE EXCEPTION 'r569: apply md5 is not r442'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_pdc' AND p.proname='pdc_pilbara_service_apply_v1') IS DISTINCT FROM 'a033c7d7719ae588e8a9aa1b26bf2fbf' THEN
  RAISE EXCEPTION 'r569: department 135 apply md5 changed'; END IF;
END $g$;

CREATE FUNCTION pdc_codex_intake_private.service_whole_board_decision_569(
 p_basis text, p_all_lines_99 boolean, p_identity_stock text, p_nav_count integer, p_dealer text, p_owner_hold boolean, p_tombstone boolean)
 RETURNS jsonb
 LANGUAGE sql IMMUTABLE
 SET search_path TO pg_catalog
AS $fn$
SELECT CASE
 WHEN p_basis IS DISTINCT FROM 'new_board_vehicle' THEN
  jsonb_build_object('action','existing_row','create',false,'broome_sales',false,'location',NULL,'visible',NULL,'board',false,'new_to_pmb',false)
 WHEN coalesce(p_all_lines_99,false) THEN
  jsonb_build_object('action','skip_status_99','create',false,'broome_sales',false,'location',NULL,'visible',false,'board',false,'new_to_pmb',false)
 WHEN coalesce(p_owner_hold,false) THEN
  jsonb_build_object('action','skip_owner_hold','create',false,'broome_sales',false,'location',NULL,'visible',false,'board',false,'new_to_pmb',false)
 WHEN coalesce(p_tombstone,false) THEN
  jsonb_build_object('action','skip_pending_restore','create',false,'broome_sales',false,'location',NULL,'visible',false,'board',false,'new_to_pmb',false)
 WHEN btrim(coalesce(p_identity_stock,''))='' THEN
  jsonb_build_object('action','skip_no_stock','create',false,'broome_sales',false,'location',NULL,'visible',false,'board',false,'new_to_pmb',false)
 WHEN coalesce(p_nav_count,0)>1 THEN
  jsonb_build_object('action','skip_ambiguous_navision','create',false,'broome_sales',false,'location',NULL,'visible',false,'board',false,'new_to_pmb',false)
 WHEN coalesce(p_nav_count,0)=1 THEN
  jsonb_build_object('action','create_division','create',true,'broome_sales',false,'location','Yard Hold','visible',false,'board',false,'new_to_pmb',false,'dealer_code',p_dealer,'link','navision')
 ELSE
  jsonb_build_object('action','create_new_vehicle','create',true,'broome_sales',false,'location','Yard Hold','visible',false,'board',false,'new_to_pmb',false,'dealer_code',NULL,'link','tune')
END
$fn$;

CREATE FUNCTION pdc_codex_intake_private.service_whole_file_guard_569(
 p_line_count integer, p_ro_count integer, p_complete boolean, p_previous_lines integer, p_filename text, p_scope text)
 RETURNS jsonb
 LANGUAGE sql IMMUTABLE
 SET search_path TO pg_catalog
AS $fn$
SELECT CASE
 WHEN p_complete IS NOT TRUE THEN jsonb_build_object('ok',false,'reason','partial_file')
 WHEN coalesce(p_line_count,0)<1 OR coalesce(p_ro_count,0)<1 THEN jsonb_build_object('ok',false,'reason','empty_file')
 WHEN p_scope IS DISTINCT FROM 'full_open_ro_snapshot_r479' THEN jsonb_build_object('ok',false,'reason','not_full_snapshot')
 WHEN coalesce(p_line_count,0)<1000 OR coalesce(p_ro_count,0)<100 THEN jsonb_build_object('ok',false,'reason','below_minimum_size')
 WHEN p_previous_lines IS NULL THEN jsonb_build_object('ok',false,'reason','no_previous_complete_snapshot')
 WHEN p_line_count * 2 < p_previous_lines THEN jsonb_build_object('ok',false,'reason','partial_vs_previous')
 ELSE jsonb_build_object('ok',true,'reason','complete_file')
END
$fn$;

CREATE FUNCTION pdc_codex_intake_private.service_whole_archive_decision_569(
 p_on_pmb_board boolean, p_on_sheet boolean, p_dept135 boolean, p_file_ok boolean, p_on_sales_board boolean)
 RETURNS jsonb
 LANGUAGE sql IMMUTABLE
 SET search_path TO pg_catalog
AS $fn$
-- p_on_sales_board does not block the PMB archive and does not write a Sales row.
-- Broome Toyota Sales is dealer 37047. Karratha Sales is dealer 14450.
SELECT CASE
 WHEN p_file_ok IS NOT TRUE THEN jsonb_build_object('archive',false,'reason','file_not_ok','delete',false,'tombstone',false,'sales_write',false,'hide_sales',false,'booking_released',false,'live_booking_reported',false)
 WHEN p_on_pmb_board IS NOT TRUE THEN jsonb_build_object('archive',false,'reason','not_pmb_board','delete',false,'tombstone',false,'sales_write',false,'hide_sales',false,'booking_released',false,'live_booking_reported',false)
 WHEN p_on_sheet IS TRUE THEN jsonb_build_object('archive',false,'reason','on_sheet','delete',false,'tombstone',false,'sales_write',false,'hide_sales',false,'booking_released',false,'live_booking_reported',false)
 WHEN p_dept135 IS TRUE THEN jsonb_build_object('archive',false,'reason','dept_135','delete',false,'tombstone',false,'sales_write',false,'hide_sales',false,'booking_released',false,'live_booking_reported',false)
 ELSE jsonb_build_object('archive',true,'reason','absent_from_sheet','delete',false,'tombstone',false,'sales_write',false,'hide_sales',false,'booking_released',true,'live_booking_reported',true,'on_sales_board',coalesce(p_on_sales_board,false))
END
$fn$;

CREATE FUNCTION pdc_codex_intake_private.service_whole_direct_board_569(p_batch uuid, p_stock text)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE
 SET search_path TO pg_catalog, public
AS $fn$
DECLARE
 v_n integer; v_all99 boolean; v_nav integer; v_dealer text; v_backend uuid; v_hold boolean; v_tomb boolean; v_decision jsonb;
BEGIN
 IF p_batch IS NULL OR btrim(coalesce(p_stock,''))='' THEN
  RETURN jsonb_build_object('action','existing_create_path','create',true,'broome_sales',false,'location','Yard Hold','visible',false,'board',false,'new_to_pmb',false);
 END IF;
 SELECT count(*), coalesce(bool_and(btrim(coalesce(r.raw_row->>'Sub Status',''))='99'), false)
   INTO v_n, v_all99
 FROM public.pdc_pilbara_service_import_rows r
 WHERE r.batch_id=p_batch
   AND public.normalize_vehicle_stock_number(r.stock_number)=public.normalize_vehicle_stock_number(p_stock)
   AND r.raw_row->'identity_r479'->>'basis'='new_board_vehicle';
 IF coalesce(v_n,0)=0 THEN
  RETURN jsonb_build_object('action','existing_create_path','create',true,'broome_sales',false,'location','Yard Hold','visible',false,'board',false,'new_to_pmb',false);
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.pdc_pilbara_service_import_rows r
   WHERE r.batch_id=p_batch
     AND public.normalize_vehicle_stock_number(r.stock_number)=public.normalize_vehicle_stock_number(p_stock)
     AND r.raw_row->'identity_r479'->>'basis'='new_board_vehicle'
     AND btrim(coalesce(r.raw_row->>'Dept','')) IN ('138','139'))
    AND EXISTS (
   SELECT 1 FROM public.pdc_pilbara_service_import_rows r
   WHERE r.batch_id=p_batch
     AND public.normalize_vehicle_stock_number(r.stock_number)=public.normalize_vehicle_stock_number(p_stock)
     AND r.raw_row->'identity_r479'->>'basis'='new_board_vehicle'
     AND btrim(coalesce(r.raw_row->>'Dept',''))<>''
     AND btrim(r.raw_row->>'Dept') NOT IN ('138','139')) THEN
  RETURN jsonb_build_object('action','skip_department','create',false,'broome_sales',false,'location',NULL,'visible',false,'board',false,'new_to_pmb',false);
 END IF;
 SELECT count(*),
        CASE WHEN count(*)=1 THEN min(n.dealer_code) ELSE NULL END,
        CASE WHEN count(*)=1 THEN (array_agg(n.id))[1] ELSE NULL END
   INTO v_nav, v_dealer, v_backend
 FROM public.navision_backend_records n
 WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status::text='current'
   AND public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock'))
       = public.normalize_vehicle_stock_number(p_stock);
 v_hold := pdc_codex_intake_private.owner_board_hold_active_20261019(NULL, p_stock, NULL);
 v_tomb := EXISTS (SELECT 1 FROM public.pdc_vehicle_tombstones t WHERE t.normalized_stock=public.normalize_vehicle_stock_number(p_stock));
 v_decision := pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', v_all99, p_stock, v_nav, v_dealer, v_hold, v_tomb);
 IF v_nav=1 AND v_backend IS NOT NULL THEN
  v_decision := v_decision || jsonb_build_object('backend_record_id', v_backend);
 END IF;
 RETURN v_decision;
END
$fn$;

CREATE TABLE pdc_codex_intake_private.service_whole_archive_receipt_569 (
 vehicle_id uuid NOT NULL,
 stock text,
 snapshot_sha256 text,
 archived_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 archived_by uuid,
 prior jsonb NOT NULL,
 released_bookings jsonb NOT NULL DEFAULT '[]'::jsonb,
 reported_live_bookings jsonb NOT NULL DEFAULT '[]'::jsonb,
 unarchived_at timestamptz,
 unarchived_by uuid
);
CREATE UNIQUE INDEX service_whole_archive_receipt_569_open
 ON pdc_codex_intake_private.service_whole_archive_receipt_569 (vehicle_id)
 WHERE unarchived_at IS NULL;
ALTER TABLE pdc_codex_intake_private.service_whole_archive_receipt_569 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_codex_intake_private.service_whole_archive_receipt_569 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_codex_intake_private.service_whole_archive_569(p_preview uuid, p_apply uuid)
 RETURNS jsonb
 LANGUAGE plpgsql VOLATILE
 SET search_path TO pg_catalog, public
AS $fn$
DECLARE
 v_n integer; v_whole integer; v_sha text; v_sha_n integer; v_missing integer; v_name text;
 v_snap pdc_service_snapshot_private.snapshots_479%ROWTYPE;
 v_lines integer; v_ros integer; v_prev integer; v_guard jsonb; v_actor uuid; v_row record;
 v_archived integer := 0; v_visible integer := 0; v_hidden integer := 0; v_hold integer := 0;
 v_live_vehicles integer := 0; v_live_bookings integer := 0; v_released integer := 0;
 v_sales integer := 0; v_broome integer := 0; v_karratha integer := 0; v_both integer := 0;
 v_pmb integer := 0; v_it integer := 0; v_other integer := 0; v_yard integer := 0; v_qc integer := 0;
 v_released_rows jsonb; v_live_rows jsonb; v_on_sales boolean; v_loc text;
BEGIN
 SELECT count(*),
        count(*) FILTER (WHERE r.raw_row->>'email_subject'='PMG PD Service as a Whole w/Sublet'),
        count(DISTINCT r.raw_row->>'snapshot_sha256') FILTER (WHERE r.raw_row->>'snapshot_sha256' ~ '^[0-9a-f]{64}$'),
        count(*) FILTER (WHERE coalesce(r.raw_row->>'snapshot_sha256','') !~ '^[0-9a-f]{64}$'),
        min(r.raw_row->>'source_filename')
   INTO v_n, v_whole, v_sha_n, v_missing, v_name
 FROM public.pdc_pilbara_service_import_rows r
 WHERE r.batch_id=p_preview;
 IF coalesce(v_n,0)=0 OR v_n IS DISTINCT FROM v_whole THEN
  RETURN jsonb_build_object('ok',false,'reason','not_as_a_whole','archived',0,'sales_write',false); END IF;
 IF coalesce(v_sha_n,0)<>1 OR coalesce(v_missing,0)<>0 THEN
  RETURN jsonb_build_object('ok',false,'reason','snapshot_sha_not_one','archived',0,'sales_write',false); END IF;
 SELECT r.raw_row->>'snapshot_sha256' INTO v_sha FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=p_preview LIMIT 1;
 SELECT * INTO v_snap FROM pdc_service_snapshot_private.snapshots_479 s WHERE s.snapshot_sha256=v_sha;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','snapshot_not_recorded','archived',0,'sales_write',false); END IF;
 SELECT count(*), count(DISTINCT l.repair_order_number) INTO v_lines, v_ros
 FROM pdc_service_snapshot_private.snapshot_lines_479 l WHERE l.snapshot_sha256=v_sha;
 SELECT s.expected_line_count INTO v_prev
 FROM pdc_service_snapshot_private.snapshots_479 s
 WHERE s.snapshot_sha256<>v_sha AND s.snapshot_scope='full_open_ro_snapshot_r479'
   AND (SELECT count(*) FROM pdc_service_snapshot_private.snapshot_lines_479 l WHERE l.snapshot_sha256=s.snapshot_sha256)=s.expected_line_count
   AND (SELECT count(DISTINCT l.repair_order_number) FROM pdc_service_snapshot_private.snapshot_lines_479 l WHERE l.snapshot_sha256=s.snapshot_sha256)=s.expected_ro_count
 ORDER BY s.source_snapshot_at DESC, s.recorded_at DESC
 LIMIT 1;
 v_guard := pdc_codex_intake_private.service_whole_file_guard_569(
  v_lines, v_ros, v_lines=v_snap.expected_line_count AND v_ros=v_snap.expected_ro_count AND v_lines>=1,
  v_prev, v_name, v_snap.snapshot_scope);
 IF NOT coalesce((v_guard->>'ok')::boolean, false) THEN
  RETURN jsonb_build_object('ok',false,'reason',v_guard->>'reason','archived',0,'sales_write',false); END IF;
 SELECT b.created_by INTO v_actor FROM public.pdc_pilbara_service_import_batches b WHERE b.batch_id=p_apply;
 CREATE TEMP TABLE IF NOT EXISTS r569_archive_pick (
  vehicle_id uuid PRIMARY KEY, stock_number text, from_location text, from_stage text, from_bay_stage text, from_bay text,
  visible_on_board boolean
 ) ON COMMIT DROP;
 DELETE FROM pg_temp.r569_archive_pick WHERE vehicle_id IS NOT NULL;
 INSERT INTO pg_temp.r569_archive_pick(vehicle_id, stock_number, from_location, from_stage, from_bay_stage, from_bay, visible_on_board)
 SELECT v.id, v.stock_number, v.current_location, v.pmb_stage, v.pmb_bay_stage, v.pmb_bay_number, v.visible_on_board
 FROM public.vehicles v
 WHERE v.deleted_at IS NULL AND v.board_purged_at IS NULL AND v.lifecycle_state::text='active'
   AND public.normalize_vehicle_stock_number(v.stock_number) IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.pdc_pilbara_service_operations o
               WHERE o.vehicle_id=v.id AND o.department IN ('138','139'))
   AND NOT EXISTS (SELECT 1 FROM public.pdc_pilbara_service_operations o
                   WHERE o.vehicle_id=v.id AND o.department='135')
   AND NOT EXISTS (
    SELECT 1 FROM pdc_service_snapshot_private.snapshot_lines_479 l
    WHERE l.snapshot_sha256=v_sha
      AND public.normalize_vehicle_stock_number(v.stock_number) IN (
       public.normalize_vehicle_stock_number(l.stock_number),
       public.normalize_vehicle_stock_number(l.file_stock),
       public.normalize_vehicle_stock_number(l.file_rego)))
   AND NOT EXISTS (
    SELECT 1 FROM public.pdc_pilbara_service_operations o
    WHERE o.vehicle_id=v.id
      AND EXISTS (SELECT 1 FROM pdc_service_snapshot_private.snapshot_lines_479 l
                  WHERE l.snapshot_sha256=v_sha AND btrim(l.repair_order_number)=btrim(o.repair_order_number)));
 SELECT count(*) FILTER (WHERE p.visible_on_board),
        count(*) FILTER (WHERE NOT coalesce(p.visible_on_board,false)),
        count(*) FILTER (WHERE upper(btrim(coalesce(p.from_location,'')))='PMB'),
        count(*) FILTER (WHERE upper(btrim(coalesce(p.from_location,''))) IN ('IT','IN TRANSIT','INTRANSIT')),
        count(*) FILTER (WHERE upper(btrim(coalesce(p.from_location,''))) IN ('OTHER','ALL VEHICLES')),
        count(*) FILTER (WHERE upper(btrim(coalesce(p.from_location,''))) IN ('YARD','YH','YARD HOLD','YARDHOLD')),
        count(*) FILTER (WHERE upper(btrim(coalesce(p.from_location,'')))='QC')
   INTO v_visible, v_hidden, v_pmb, v_it, v_other, v_yard, v_qc
 FROM pg_temp.r569_archive_pick p
 WHERE p.vehicle_id IS NOT NULL;
 SELECT count(*) INTO v_hold FROM pg_temp.r569_archive_pick p
 WHERE pdc_codex_intake_private.owner_board_hold_active_20261019(p.vehicle_id, p.stock_number, NULL);
 SELECT count(DISTINCT p.vehicle_id), count(*)
   INTO v_live_vehicles, v_live_bookings
 FROM pg_temp.r569_archive_pick p
 JOIN public.workshop_bookings b ON b.vehicle_id=p.vehicle_id AND b.deleted_at IS NULL AND b.status IN ('started','stoppage')
 WHERE p.vehicle_id IS NOT NULL;
 SELECT count(*) FILTER (WHERE s.broome OR s.karratha),
        count(*) FILTER (WHERE s.broome AND NOT s.karratha),
        count(*) FILTER (WHERE s.karratha AND NOT s.broome),
        count(*) FILTER (WHERE s.broome AND s.karratha)
   INTO v_sales, v_broome, v_karratha, v_both
 FROM (
  SELECT
   EXISTS (SELECT 1 FROM public.navision_backend_records n
           WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status::text='current'
             AND n.dealer_code IN ('37047','037047')
             AND public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock'))
                 = public.normalize_vehicle_stock_number(p.stock_number)) AS broome,
   EXISTS (SELECT 1 FROM public.navision_backend_records n
           WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status::text='current'
             AND n.dealer_code IN ('14450','014450')
             AND public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock'))
                 = public.normalize_vehicle_stock_number(p.stock_number)) AS karratha
  FROM pg_temp.r569_archive_pick p
  WHERE p.vehicle_id IS NOT NULL
 ) s;
 FOR v_row IN SELECT * FROM pg_temp.r569_archive_pick ORDER BY stock_number LOOP
  IF v_actor IS NULL THEN
   SELECT v.updated_by INTO v_actor FROM public.vehicles v WHERE v.id=v_row.vehicle_id;
  END IF;
  v_loc := upper(btrim(coalesce(v_row.from_location,'')));
  v_on_sales := EXISTS (
   SELECT 1 FROM public.navision_backend_records n
   WHERE n.source_system='microsoft_navision' AND n.is_current AND n.record_status::text='current'
     AND n.dealer_code IN ('37047','037047','14450','014450')
     AND public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock'))
         = public.normalize_vehicle_stock_number(v_row.stock_number));
  IF NOT coalesce((pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, v_on_sales)->>'archive')::boolean, false) THEN
   CONTINUE; END IF;
  IF coalesce((pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, v_on_sales)->>'sales_write')::boolean, true) THEN
   RAISE EXCEPTION 'r569: archive must not write a Sales record'; END IF;
  UPDATE public.vehicles SET visible_on_board=false, board_purged_at=clock_timestamp(),
    board_purge_reason='r569: 138/139 PMB-board vehicle absent from the latest complete as-a-Whole sheet',
    board_purged_by=v_actor, pmb_stage=NULL, pmb_bay_stage=NULL, pmb_bay_number=NULL,
    version=version+1, updated_by=v_actor, updated_at=clock_timestamp()
  WHERE id=v_row.vehicle_id AND deleted_at IS NULL AND board_purged_at IS NULL AND lifecycle_state::text='active'
    AND NOT EXISTS (SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=public.vehicles.id AND o.department='135');
  IF NOT FOUND THEN CONTINUE; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id', b.id, 'bay_id', b.bay_id, 'status', b.status,
           'assignment_ids', (SELECT coalesce(jsonb_agg(a.id), '[]'::jsonb) FROM public.workshop_booking_assignments a
                              WHERE a.booking_id=b.id AND a.released_at IS NULL))), '[]'::jsonb)
    INTO v_released_rows
  FROM public.workshop_bookings b
  WHERE b.vehicle_id=v_row.vehicle_id AND b.deleted_at IS NULL AND b.status IN ('queued','planned') AND b.bay_id IS NOT NULL;
  SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id', b.id, 'bay_id', b.bay_id, 'status', b.status)), '[]'::jsonb)
    INTO v_live_rows
  FROM public.workshop_bookings b
  WHERE b.vehicle_id=v_row.vehicle_id AND b.deleted_at IS NULL AND b.status IN ('started','stoppage');
  UPDATE public.workshop_booking_assignments a SET released_at=clock_timestamp()
  WHERE a.released_at IS NULL AND a.booking_id IN (
    SELECT b.id FROM public.workshop_bookings b
    WHERE b.vehicle_id=v_row.vehicle_id AND b.deleted_at IS NULL AND b.status IN ('queued','planned') AND b.bay_id IS NOT NULL);
  UPDATE public.workshop_bookings b SET bay_id=NULL
  WHERE b.vehicle_id=v_row.vehicle_id AND b.deleted_at IS NULL AND b.status IN ('queued','planned') AND b.bay_id IS NOT NULL;
  v_released := v_released + coalesce(jsonb_array_length(v_released_rows), 0);
  INSERT INTO pdc_codex_intake_private.service_whole_archive_receipt_569(
    vehicle_id, stock, snapshot_sha256, archived_by, prior, released_bookings, reported_live_bookings)
  VALUES (v_row.vehicle_id, v_row.stock_number, v_sha, v_actor,
    jsonb_build_object('visible_on_board', v_row.visible_on_board, 'current_location', v_row.from_location,
     'pmb_stage', v_row.from_stage, 'pmb_bay_stage', v_row.from_bay_stage, 'pmb_bay_number', v_row.from_bay,
     'on_sales_board', v_on_sales, 'sales_write', false),
    coalesce(v_released_rows, '[]'::jsonb), coalesce(v_live_rows, '[]'::jsonb));
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by,moved_at)
  VALUES (v_row.vehicle_id, v_row.from_location, v_row.from_location, v_row.from_stage, NULL, v_row.from_bay_stage, NULL,
    v_row.from_bay, NULL,
    'r569: 138/139 vehicle absent from the latest complete as-a-Whole sheet archived off the PMB board',
    v_actor, clock_timestamp());
  PERFORM public.audit_pdc_event('update','vehicles',v_row.vehicle_id,v_row.vehicle_id,
    jsonb_build_object('visible_on_board',v_row.visible_on_board,'stock_number',v_row.stock_number,'current_location',v_row.from_location),
    jsonb_build_object('visible_on_board',false,'board_purged',true,'sales_write',false,'delete',false),
    jsonb_build_object('authority','Craig 27 Oct 2026: a 138/139 vehicle absent from the sheet is archived off the PMB board. Broome Toyota Sales (37047) and Karratha Sales (14450) are not written. A queued booking bay is cleared and can be restored. A started or stoppage booking is only reported',
     'apply_batch_id',p_apply,'preview_batch_id',p_preview,'snapshot_sha256',v_sha,
     'on_sales_board',v_on_sales,'sales_write',false,'bookings_deleted',false,'deleted_at_set',false,
     'location',v_loc));
  v_archived := v_archived + 1;
 END LOOP;
 RETURN jsonb_build_object('ok',true,'reason','complete_file','archived',v_archived,'visible',v_visible,'hidden',v_hidden,
  'included_hold',v_hold,'location_pmb',v_pmb,'location_it',v_it,'location_other',v_other,'location_yard',v_yard,'location_qc',v_qc,
  'started_stoppage_vehicles',v_live_vehicles,'started_stoppage_bookings',v_live_bookings,
  'queued_planned_released',v_released,'also_on_sales',v_sales,'broome_sales',v_broome,'karratha_sales',v_karratha,'both_sales',v_both,
  'sales_write',false,'sales_rows_written',0,'deleted',false,'snapshot_sha256',v_sha,'source_filename',v_name);
END
$fn$;

CREATE FUNCTION pdc_codex_intake_private.service_whole_unarchive_569(p_vehicle uuid)
 RETURNS jsonb
 LANGUAGE plpgsql VOLATILE
 SET search_path TO pg_catalog, public
AS $fn$
DECLARE
 v_prior jsonb; v_released jsonb; v_stock text; v_item jsonb; v_location text; v_actor uuid;
BEGIN
 IF p_vehicle IS NULL THEN RAISE EXCEPTION 'r569: vehicle is required'; END IF;
 SELECT r.prior, r.released_bookings, r.stock, r.archived_by INTO v_prior, v_released, v_stock, v_actor
 FROM pdc_codex_intake_private.service_whole_archive_receipt_569 r
 WHERE r.vehicle_id=p_vehicle AND r.unarchived_at IS NULL
 ORDER BY r.archived_at DESC
 LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'r569: no open archive receipt for this vehicle'; END IF;
 v_location := v_prior->>'current_location';
 UPDATE public.vehicles SET
   visible_on_board=coalesce((v_prior->>'visible_on_board')::boolean, visible_on_board),
   board_purged_at=NULL, board_purge_reason=NULL, board_purged_by=NULL,
   pmb_stage=NULLIF(v_prior->>'pmb_stage',''),
   pmb_bay_stage=NULLIF(v_prior->>'pmb_bay_stage',''),
   pmb_bay_number=NULLIF(v_prior->>'pmb_bay_number',''),
   version=version+1, updated_at=clock_timestamp()
 WHERE id=p_vehicle AND deleted_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'r569: vehicle is not live'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_released, '[]'::jsonb)) LOOP
  UPDATE public.workshop_bookings SET bay_id=NULLIF(v_item->>'bay_id','')::uuid
  WHERE id=NULLIF(v_item->>'booking_id','')::uuid AND vehicle_id=p_vehicle AND deleted_at IS NULL
    AND status IN ('queued','planned');
  UPDATE public.workshop_booking_assignments SET released_at=NULL
  WHERE booking_id=NULLIF(v_item->>'booking_id','')::uuid
    AND id IN (SELECT (jsonb_array_elements_text(coalesce(v_item->'assignment_ids','[]'::jsonb)))::uuid);
 END LOOP;
 UPDATE pdc_codex_intake_private.service_whole_archive_receipt_569
 SET unarchived_at=clock_timestamp(), unarchived_by=v_actor
 WHERE vehicle_id=p_vehicle AND unarchived_at IS NULL;
 v_actor := coalesce(v_actor, (SELECT v.updated_by FROM public.vehicles v WHERE v.id=p_vehicle));
 INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,reason,moved_by,moved_at)
 VALUES (p_vehicle, v_location, v_location, 'r569: un-archive restored the PMB board flag and the cleared booking bays', v_actor, clock_timestamp());
 PERFORM public.audit_pdc_event('update','vehicles',p_vehicle,p_vehicle,
  jsonb_build_object('board_purged',true,'stock_number',v_stock),
  jsonb_build_object('board_purged',false,'visible_on_board',v_prior->'visible_on_board','sales_write',false),
  jsonb_build_object('authority','r569 un-archive. Broome Toyota Sales (37047) and Karratha Sales (14450) were not changed by the archive and are not changed here','sales_write',false,'delete',false));
 RETURN jsonb_build_object('ok',true,'vehicle_id',p_vehicle,'sales_write',false,'delete',false,'stock',v_stock);
END
$fn$;

REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_whole_board_decision_569(text,boolean,text,integer,text,boolean,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_whole_file_guard_569(integer,integer,boolean,integer,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_whole_archive_decision_569(boolean,boolean,boolean,boolean,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_whole_direct_board_569(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_whole_archive_569(uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.service_whole_unarchive_569(uuid) FROM PUBLIC, anon, authenticated;

DO $patch$
DECLARE def text; n int;
BEGIN
 SELECT pg_catalog.pg_get_functiondef(p.oid) INTO def
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='pdc_codex_intake_private' AND p.proname='revolution_service_rows_20261006'
   AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_rows jsonb';
 IF def IS NULL THEN RAISE EXCEPTION 'r569: rows function missing'; END IF;
 IF (length(def) - length(replace(def, $up_rows_src$   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job')
   AND btrim(coalesce(x->>'stock_number',''))<>''$up_rows_src$, ''))) IS DISTINCT FROM length($up_rows_src$   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job')
   AND btrim(coalesce(x->>'stock_number',''))<>''$up_rows_src$) THEN
  RAISE EXCEPTION 'r569: rows anchor missing or not unique'; END IF;
 def := replace(def, $up_rows_src$   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job')
   AND btrim(coalesce(x->>'stock_number',''))<>''$up_rows_src$, $up_rows_dst$   AND x->'raw_row'->'identity_r479'->>'basis' IN ('stock_column','rego_column_exact_board_stock','job_card_exact','job_card_service_job','new_board_vehicle')
   AND btrim(coalesce(x->>'stock_number',''))<>''
   AND (x->'raw_row'->'identity_r479'->>'basis' IS DISTINCT FROM 'new_board_vehicle'
    OR (btrim(coalesce(x->'raw_row'->>'Sub Status','')) IS DISTINCT FROM '99'
     AND coalesce(x->'raw_row'->>'snapshot_sha256','') ~ '^[0-9a-f]{64}$'))$up_rows_dst$);
 EXECUTE def;
 SELECT pg_catalog.pg_get_functiondef(p.oid) INTO def
 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='pdc_pilbara_service_apply_v1'
   AND pg_catalog.pg_get_function_identity_arguments(p.oid)='p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text';
 IF def IS NULL THEN RAISE EXCEPTION 'r569: apply function missing'; END IF;
 IF (length(def) - length(replace(def, replace($up_temp_src$  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP$up_temp_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($up_temp_src$  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP$up_temp_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569: apply anchor temp missing or not unique'; END IF;
 def := replace(def, replace($up_temp_src$  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP$up_temp_src$, chr(10), chr(13)||chr(10)), replace($up_temp_dst$  IF v_tune THEN
    CREATE TEMP TABLE IF NOT EXISTS r569_direct_skip(stock_number text PRIMARY KEY) ON COMMIT DROP;
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP$up_temp_dst$, chr(10), chr(13)||chr(10)));
 IF (length(def) - length(replace(def, replace($up_create_src$      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL THEN
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;
        -- Link only the unique current exact-Stock record accepted by this revision.
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')
        WHERE id=v_vehicle_id;
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);
      END IF;$up_create_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($up_create_src$      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL THEN
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;
        -- Link only the unique current exact-Stock record accepted by this revision.
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')
        WHERE id=v_vehicle_id;
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);
      END IF;$up_create_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569: apply anchor create missing or not unique'; END IF;
 def := replace(def, replace($up_create_src$      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL THEN
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;
        -- Link only the unique current exact-Stock record accepted by this revision.
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')
        WHERE id=v_vehicle_id;
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);
      END IF;$up_create_src$, chr(10), chr(13)||chr(10)), replace($up_create_dst$      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      PERFORM set_config('pdc.r569_direct','{}',true);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        PERFORM set_config('pdc.r569_direct',pdc_codex_intake_private.service_whole_direct_board_569(v_preview.batch_id,v_stock)::text,true);
        IF current_setting('pdc.r569_direct',true)::jsonb->>'dealer_code'='14450'
           AND coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'broome_sales')::boolean,false) THEN
          RAISE EXCEPTION 'r569: dealer 14450 must not enter Broome Sales';
        END IF;
        IF coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'new_to_pmb')::boolean,false) THEN
          RAISE EXCEPTION 'r569: a new as-a-Whole vehicle stays in the New vehicle section';
        END IF;
        IF coalesce((current_setting('pdc.r569_direct',true)::jsonb->>'create')::boolean,false) THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
        ELSE
          INSERT INTO pg_temp.r569_direct_skip(stock_number) VALUES (v_stock) ON CONFLICT DO NOTHING;
        END IF;
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;
        -- Link only the unique current exact-Stock record accepted by this revision.
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')
        WHERE id=v_vehicle_id;
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);
      END IF;$up_create_dst$, chr(10), chr(13)||chr(10)));
 IF (length(def) - length(replace(def, replace($up_fields_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$up_fields_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($up_fields_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$up_fields_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569: apply anchor fields missing or not unique'; END IF;
 def := replace(def, replace($up_fields_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$up_fields_src$, chr(10), chr(13)||chr(10)), replace($up_fields_dst$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN CONTINUE; END IF;
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$up_fields_dst$, chr(10), chr(13)||chr(10)));
 IF (length(def) - length(replace(def, $up_key_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$up_key_src$, ''))) IS DISTINCT FROM length($up_key_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$up_key_src$) THEN
  RAISE EXCEPTION 'r569: apply anchor key missing or not unique'; END IF;
 def := replace(def, $up_key_src$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$up_key_src$, $up_key_dst$      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_stock) THEN CONTINUE; END IF;
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;$up_key_dst$);
 IF (length(def) - length(replace(def, replace($up_row_src$    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;$up_row_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($up_row_src$    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;$up_row_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569: apply anchor row missing or not unique'; END IF;
 def := replace(def, replace($up_row_src$    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;$up_row_src$, chr(10), chr(13)||chr(10)), replace($up_row_dst$    IF v_tune THEN IF EXISTS (SELECT 1 FROM pg_temp.r569_direct_skip s WHERE s.stock_number=v_row.stock_number) THEN CONTINUE; END IF; SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;$up_row_dst$, chr(10), chr(13)||chr(10)));
 IF (length(def) - length(replace(def, replace($up_receipt_src$  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.$up_receipt_src$, chr(10), chr(13)||chr(10)), ''))) IS DISTINCT FROM length(replace($up_receipt_src$  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.$up_receipt_src$, chr(10), chr(13)||chr(10))) THEN
  RAISE EXCEPTION 'r569: apply anchor receipt missing or not unique'; END IF;
 def := replace(def, replace($up_receipt_src$  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.$up_receipt_src$, chr(10), chr(13)||chr(10)), replace($up_receipt_dst$  v_response:=v_response||jsonb_build_object('sublet_pos',pdc_codex_intake_private.service_sublet_po_feed_442(v_preview.batch_id,false));
  v_response:=v_response||coalesce(pdc_codex_intake_private.service_whole_archive_569(v_preview.batch_id,v_apply_batch),'{}'::jsonb);
   -- Persist the final response in the append-only apply receipt below; do not mutate the batch header.$up_receipt_dst$, chr(10), chr(13)||chr(10)));
 EXECUTE def;
END $patch$;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5='9be0883b1a555f48f3c1ba9fa111c891', release='r570',
    note='r570 (F184): as-a-Whole new_board_vehicle, Sub Status 99 refused',
    updated_at=clock_timestamp()
WHERE signature='pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'
  AND prosrc_md5='5807a896cef15f81030f84a1b68a597b';
UPDATE pdc_ops.expected_function_md5
SET prosrc_md5='b62fb7c29ffd2a1629f214f696e5cb14', release='r570',
    note='r570 (F184): new as-a-Whole vehicles stay in the New vehicle section; a vehicle absent from the sheet is archived off the PMB board',
    updated_at=clock_timestamp()
WHERE signature='public.pdc_pilbara_service_apply_v1(uuid,text,text)'
  AND prosrc_md5='fc3717a5215de94c93ebb2c7facfe744';
DO $pins$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r570' AND prosrc_md5 IN ('9be0883b1a555f48f3c1ba9fa111c891','b62fb7c29ffd2a1629f214f696e5cb14'))<>2 THEN
  RAISE EXCEPTION 'r570: pin update did not match the two in-place rows'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r569: pin count changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='capture_service_status'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='preview_id uuid, apply_id uuid') IS DISTINCT FROM '7870d544117de6a5465b8212f0d228b7'
    OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.capture_service_status(uuid,uuid)') IS DISTINCT FROM '7870d544117de6a5465b8212f0d228b7' THEN
  RAISE EXCEPTION 'r569: capture pin changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='finish_tune_checkout'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='vid uuid') IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82'
    OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.finish_tune_checkout(uuid)') IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
  RAISE EXCEPTION 'r569: finish_tune_checkout pin changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='apply_service_pmb_complete'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='apply_id uuid') IS DISTINCT FROM '9808feb2a0a93a79b0d67aebdca0a4aa'
    OR (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.apply_service_pmb_complete(uuid)') IS DISTINCT FROM '9808feb2a0a93a79b0d67aebdca0a4aa' THEN
  RAISE EXCEPTION 'r569: status 80 pin changed'; END IF;
END $pins$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('service_whole_archive_570', 'F184',
 'Departments 138 and 139. The latest sheet is the active list. A division vehicle and a non-division vehicle are both created hidden on Yard Hold in the New vehicle section. Sub Status 99 does not create. A 138/139 board vehicle absent from a complete file is archived off the PMB board. Broome Toyota Sales (37047) and Karratha Sales (14450) are not archived, hidden, or altered, including when the same vehicle is on a Sales board. sales_write stays false. Nothing is hard-deleted. A queued or planned booking bay is cleared and service_whole_unarchive_569 restores it. A started or stoppage booking is reported and not modified. A CreateAdvisor filename that is otherwise complete is allowed. Department 135 is not edited. Pin count stays 241.',
 $chk569$
SELECT
 (pg_catalog.set_config('search_path','pg_catalog',true) = 'pg_catalog'
  AND d.create_ok AND d.new_vehicle_ok AND d.skip99_ok AND d.broome_ok AND d.existing_ok
  AND d.guard_ok AND d.empty_ok AND d.partial_ok AND d.floor_ok AND d.advisor_ok AND d.half_ok
  AND d.archive_ok AND d.dual_ok AND d.no_archive AND d.sales_body_ok AND d.live_ok AND d.pins_ok AND d.karratha_ok AND d.unarchive_ok AND d.acl_ok) AS ok,
 ('create=' || d.create_ok::pg_catalog.text || ' newveh=' || d.new_vehicle_ok::pg_catalog.text
  || ' skip99=' || d.skip99_ok::pg_catalog.text || ' broome=' || d.broome_ok::pg_catalog.text
  || ' archive=' || d.archive_ok::pg_catalog.text || ' dual=' || d.dual_ok::pg_catalog.text
  || ' salesbody=' || d.sales_body_ok::pg_catalog.text || ' pins=' || d.pins_ok::pg_catalog.text) AS detail
FROM (
 SELECT
  (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0001', 1, '14450', false, false)->>'action')='create_division'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0001', 1, '14450', false, false)->>'location')='Yard Hold'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0001', 1, '14450', false, false)->>'visible')='false'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0001', 1, '14450', false, false)->>'board')='false'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0001', 1, '14450', false, false)->>'new_to_pmb')='false'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0001', 1, '14450', false, false)->>'broome_sales')='false'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0001', 1, '14450', false, false)->>'link')='navision'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0001', 1, '37047', false, false)->>'dealer_code')='37047'
   AS create_ok,
  (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0000', 0, NULL, false, false)->>'action')='create_new_vehicle'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0000', 0, NULL, false, false)->>'location')='Yard Hold'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0000', 0, NULL, false, false)->>'visible')='false'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0000', 0, NULL, false, false)->>'new_to_pmb')='false'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0000', 0, NULL, false, false)->>'link')='tune'
   AS new_vehicle_ok,
  (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', true, 'SYN0099', 0, NULL, false, false)->>'action')='skip_status_99'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0099', 0, NULL, true, false)->>'action')='skip_owner_hold'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0099', 0, NULL, false, true)->>'action')='skip_pending_restore'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN0099', 2, NULL, false, false)->>'action')='skip_ambiguous_navision'
   AS skip99_ok,
  (pdc_codex_intake_private.service_whole_board_decision_569('new_board_vehicle', false, 'SYN14450', 1, '14450', false, false)->>'broome_sales')='false'
   AS broome_ok,
  (pdc_codex_intake_private.service_whole_board_decision_569('stock_column', false, 'SYN0001', 1, '14450', false, false)->>'action')='existing_row'
   AND (pdc_codex_intake_private.service_whole_board_decision_569('stock_column', false, 'SYN0001', 1, '14450', false, false)->>'create')='false'
   AS existing_ok,
  (pdc_codex_intake_private.service_whole_file_guard_569(6774, 466, true, 6774, 'PMG PD Service as a Whole w/Sublet.xlsx', 'full_open_ro_snapshot_r479')->>'ok')='true'
   AS guard_ok,
  (pdc_codex_intake_private.service_whole_file_guard_569(0, 0, true, 6774, 'a.xlsx', 'full_open_ro_snapshot_r479')->>'reason')='empty_file'
   AS empty_ok,
  (pdc_codex_intake_private.service_whole_file_guard_569(6774, 466, false, 6774, 'a.xlsx', 'full_open_ro_snapshot_r479')->>'reason')='partial_file'
   AS partial_ok,
  (pdc_codex_intake_private.service_whole_file_guard_569(500, 50, true, 6774, 'a.xlsx', 'full_open_ro_snapshot_r479')->>'reason')='below_minimum_size'
   AS floor_ok,
  (pdc_codex_intake_private.service_whole_file_guard_569(6700, 460, true, 6731, 'CreateAdvisor-Service-as-a-Whole.xlsx', 'full_open_ro_snapshot_r479')->>'reason')='complete_file'
   AS advisor_ok,
  (pdc_codex_intake_private.service_whole_file_guard_569(2000, 200, true, 6731, 'a.xlsx', 'full_open_ro_snapshot_r479')->>'reason')='partial_vs_previous'
   AND (pdc_codex_intake_private.service_whole_file_guard_569(6774, 466, true, NULL, 'a.xlsx', 'full_open_ro_snapshot_r479')->>'reason')='no_previous_complete_snapshot'
   AS half_ok,
  (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, false)->>'archive')='true'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, false)->>'delete')='false'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, false)->>'sales_write')='false'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, false)->>'hide_sales')='false'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, false)->>'tombstone')='false'
   AS archive_ok,
  (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, true)->>'archive')='true'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, true)->>'sales_write')='false'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, true)->>'hide_sales')='false'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, true)->>'delete')='false'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, true, true)->>'on_sales_board')='true'
   AS dual_ok,
  (pdc_codex_intake_private.service_whole_archive_decision_569(false, false, false, true, false)->>'reason')='not_pmb_board'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, true, false, true, true)->>'reason')='on_sheet'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, true, true, false)->>'reason')='dept_135'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, false, false, false, true)->>'reason')='file_not_ok'
   AND (pdc_codex_intake_private.service_whole_archive_decision_569(true, true, false, true, true)->>'sales_write')='false'
   AS no_archive,
  (SELECT pg_catalog.strpos(p.prosrc, 'pdc_sales_private')=0
      AND pg_catalog.strpos(p.prosrc, 'UPDATE public.navision_backend_records')=0
      AND pg_catalog.strpos(p.prosrc, 'karratha135')=0
      AND pg_catalog.strpos(p.prosrc, 'DELETE FROM public.vehicles')=0
      AND pg_catalog.strpos(p.prosrc, 'DELETE FROM public.workshop_bookings')=0
      AND pg_catalog.strpos(p.prosrc, 'sales_write')>0
      AND pg_catalog.strpos(p.prosrc, '37047')>0
      AND pg_catalog.strpos(p.prosrc, '14450')>0
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='pdc_codex_intake_private' AND p.proname='service_whole_archive_569')
   AS sales_body_ok,
  (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='pdc_codex_intake_private' AND p.proname='capture_service_status')='7870d544117de6a5465b8212f0d228b7'
   AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='pdc_codex_intake_private' AND p.proname='finish_tune_checkout')='3e5c6b28e7c025a6ebbae61879ff3a82'
   AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='pdc_codex_intake_private' AND p.proname='apply_service_pmb_complete')='9808feb2a0a93a79b0d67aebdca0a4aa'
   AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='pdc_codex_intake_private' AND p.proname='revolution_service_rows_20261006')='9be0883b1a555f48f3c1ba9fa111c891'
   AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='pdc_pilbara_service_apply_v1')='b62fb7c29ffd2a1629f214f696e5cb14'
   AS live_ok,
  (SELECT pins.n FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins)=241
   AND (SELECT rel.n FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release='r570') rel)=2
   AND NOT EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature LIKE '%service_whole%569%')
   AS pins_ok,
  (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='karratha135_pdc' AND p.proname='pdc_pilbara_service_apply_v1')='a033c7d7719ae588e8a9aa1b26bf2fbf'
   AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='karratha135_intake' AND p.proname='capture_service_status')='3fca9ba755a6d30f9b6ac642da084b9b'
   AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='karratha135_intake' AND p.proname='finish_tune_checkout')='f4480286dba918f82061bd6daffb4d43'
   AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='karratha135_intake' AND p.proname='apply_service_pmb_complete')='fbc4f46f10b8581feca8742da2c5ab98'
   AS karratha_ok,
  pg_catalog.to_regprocedure('pdc_codex_intake_private.service_whole_unarchive_569(uuid)') IS NOT NULL
   AND pg_catalog.to_regclass('pdc_codex_intake_private.service_whole_archive_receipt_569') IS NOT NULL
   AS unarchive_ok,
  (SELECT coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)
      AND NOT pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false)
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='pdc_codex_intake_private' AND p.proname LIKE 'service_whole_%569')
   AS acl_ok
) d
$chk569$, true, 341, 'r570');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r569: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r570')<>2 THEN RAISE EXCEPTION 'r570: expected two in-place pins'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='revolution_service_rows_20261006') IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN
  RAISE EXCEPTION 'r569: rows md5 mismatch'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='pdc_pilbara_service_apply_v1') IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN
  RAISE EXCEPTION 'r569: apply md5 mismatch'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='capture_service_status'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='preview_id uuid, apply_id uuid') IS DISTINCT FROM '7870d544117de6a5465b8212f0d228b7' THEN
  RAISE EXCEPTION 'r569: capture md5 mismatch'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='finish_tune_checkout'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='vid uuid') IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
  RAISE EXCEPTION 'r569: finish_tune_checkout md5 mismatch'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='pdc_codex_intake_private' AND p.proname='apply_service_pmb_complete'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid)='apply_id uuid') IS DISTINCT FROM '9808feb2a0a93a79b0d67aebdca0a4aa' THEN
  RAISE EXCEPTION 'r569: status 80 md5 mismatch'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks
     WHERE check_name IN ('status80_completes_parts_sublet_and_all_bays', 'status80_upserts_qc_station_work_items')
       AND pg_catalog.strpos(check_sql, '9808feb2a0a93a79b0d67aebdca0a4aa')>0)<>2 THEN
  RAISE EXCEPTION 'r569: status 80 checks were rewritten'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='karratha135_pdc' AND p.proname='pdc_pilbara_service_apply_v1') IS DISTINCT FROM 'a033c7d7719ae588e8a9aa1b26bf2fbf' THEN
  RAISE EXCEPTION 'r569: department 135 apply md5 changed'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='service_whole_archive_570' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r569: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
