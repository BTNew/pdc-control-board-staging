-- r590 (F204) / sort 361. Preview. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target. Do not leave this applied
-- until Craig says go-live.
--
-- Ledger tip on staging is r592 / F206 / sort 360 (hoist place-after, PR #572).
-- r588 / F202 is live (side-panel tick grid, frontend only, no ledger row).
-- r589 / F203 stays with the open PRs #570 and #571.
-- r584 / F198 / sort 356 stays with PR #498.
-- This is the next free triple: r590 / F204 / sort 361.
--
-- Stock 13047122 is in QC with every checkable line ticked and a stored photo.
-- The Sublet station icon is green (4 of 4), including Craig's side-panel ticks
-- from the #564 override. vehicle_work_items.sublet is still required and not
-- completed, so pdc_qc_gate_issues returns outstanding_required_work:SUBLET.
-- The sign-off trigger raises that as SQLSTATE 22023. The screen keeps the
-- code and does not name Sublet.
--
-- A station the icon calls complete — QC tick, panel tick, latest fitter Done,
-- or a controller/admin station override — is no longer outstanding work.
-- The sign-off button is given the outstanding sentences.
-- Pin count stays 241. The r405 gate pin moves in place. No pin is inserted.
-- Department 135 stays fd05b9eef69498002ac06dd68e01cdff.
-- Kajel rows stay 9be0883b1a555f48f3c1ba9fa111c891.
-- Kajel apply stays b62fb7c29ffd2a1629f214f696e5cb14.
-- Undo: supabase/rollbacks/20261028080000_r590_qc_signoff_override.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r590: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r590: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r590: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_gate_issues(uuid)')) IS DISTINCT FROM '2d9f3d968a51790d3395c0367af70578' THEN RAISE EXCEPTION 'r590: QC gate is not the r405 body'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.pdc_qc_gate_issues(uuid)' AND release='r405') IS DISTINCT FROM '2d9f3d968a51790d3395c0367af70578' THEN RAISE EXCEPTION 'r590: QC gate pin is not r405'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)')) IS DISTINCT FROM 'e4c7271b2efe49ed45117f600b6fe954' THEN RAISE EXCEPTION 'r590: sign-off function changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_require_all_operations_complete_379()')) IS DISTINCT FROM 'e6018eac99505f2548df1ae0c8647c58' THEN RAISE EXCEPTION 'r590: QC line trigger changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r590: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN RAISE EXCEPTION 'r590: fitter command changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r590: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r590: Kajel apply changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r590: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r590: QC lines changed'; END IF;
 IF to_regprocedure('public.pdc_qc_line_counts_complete_590(uuid,jsonb)') IS NOT NULL
    OR to_regprocedure('public.qc_signoff_outstanding_590(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r590: already applied'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='board_qc_nesting_587' AND fault_id='F201' AND sort_order=359 AND added_in='r587') THEN RAISE EXCEPTION 'r590: r587 / F201 sort 359 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=356 OR fault_id='F198' OR added_in='r584') THEN RAISE EXCEPTION 'r590: sort 356 / F198 is taken; leave that preview its number'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE fault_id IN ('F202','F203') OR added_in IN ('r588','r589')) THEN RAISE EXCEPTION 'r590: r588 / F202 or r589 / F203 is already on the ledger'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='hoist_place_after_592' AND fault_id='F206' AND sort_order=360 AND added_in='r592') THEN RAISE EXCEPTION 'r590: r592 / F206 sort 360 is not the hoist place-after check'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=361 OR fault_id='F204' OR check_name='qc_signoff_override_590' OR added_in='r590') THEN RAISE EXCEPTION 'r590: sort 361 / F204 is taken'; END IF;
END $g$;

CREATE FUNCTION public.pdc_qc_line_counts_complete_590(p_vehicle_id uuid, p_line jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog
AS $line590$
  SELECT coalesce((p_line->>'completed')::boolean, false)
  OR EXISTS (
    SELECT 1
    FROM public.pdc_panel_line_completion_565 c
    WHERE c.vehicle_id = p_vehicle_id
      AND c.line_identity = p_line->>'line_identity'
      AND c.completed
  )
  OR EXISTS (
    SELECT 1
    FROM (
      SELECT p.completed
      FROM pdc_fitter_private.operation_progress p
      JOIN public.workshop_bookings wb ON wb.id = p.booking_id
      WHERE wb.vehicle_id = p_vehicle_id
        AND wb.deleted_at IS NULL
        AND p.line_identity = p_line->>'line_identity'
      ORDER BY p.updated_at DESC, p.booking_id
      LIMIT 1
    ) latest
    WHERE latest.completed
  )
  OR EXISTS (
    SELECT 1
    FROM public.pdc_station_completion_override_578 o
    WHERE o.vehicle_id = p_vehicle_id
      AND o.completed
      AND o.work_key = CASE pg_catalog.upper(pg_catalog.btrim(coalesce(p_line->>'stage_code', '')))
        WHEN 'BUS_4X4' THEN 'bus4x4'
        WHEN 'BUS_MECHANICAL' THEN 'bus4x4'
        WHEN 'BUS_ACCESSORIES' THEN 'bus4x4'
        WHEN 'BUS_ELECTRICAL' THEN 'bus4x4'
        WHEN 'BUS_QA' THEN 'bus4x4'
        WHEN 'TINT' THEN 'tint'
        WHEN 'HOIST' THEN 'hoist'
        WHEN 'FITTING' THEN 'fitting'
        WHEN 'FABRICATION' THEN 'fabrication'
        WHEN 'ELECTRICAL' THEN 'electrical'
        WHEN 'TYRE' THEN 'tyre'
        WHEN 'SUBLET' THEN 'sublet'
        WHEN 'PARTS' THEN 'parts'
        ELSE NULL
      END
  );
$line590$;

REVOKE ALL ON FUNCTION public.pdc_qc_line_counts_complete_590(uuid, jsonb) FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.pdc_qc_line_counts_complete_590(uuid, jsonb) IS
  'r590 (F204): a QC line counts as done for sign-off when the QC flag, a panel tick, the latest fitter Done, or a controller station override says so.';

CREATE OR REPLACE FUNCTION public.pdc_qc_gate_issues(p_vehicle_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $gate590$
  WITH vehicle AS (
    SELECT id,upper(btrim(coalesce(current_location,''))) location,
           CASE WHEN regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g')='PITINSPECTION' THEN ''
                ELSE regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g') END stage
    FROM public.vehicles WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL
  ), icon_done AS (
    -- r590 (F204): the #564 station icon. Green includes a panel tick, a fitter Done, and a controller or admin override.
    SELECT s->>'work_key' AS work_key
    FROM jsonb_array_elements(pdc_work_categories_private.station_icon_completion_578(ARRAY[p_vehicle_id])) s
    WHERE coalesce((s->>'complete')::boolean, false)
  ), outstanding AS (
    SELECT string_agg(distinct upper(btrim(wi.work_key)),', ' ORDER BY upper(btrim(wi.work_key))) labels
    FROM public.vehicle_work_items wi
    WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed
      AND regexp_replace(upper(btrim(coalesce(wi.work_key,''))),'[^A-Z0-9]+','','g') NOT IN ('QC','PARTS','PITINSPECTION')
      AND NOT EXISTS (
        SELECT 1 FROM icon_done d
        WHERE d.work_key = lower(btrim(wi.work_key))
      )
  ), canonical_missing AS (
    SELECT count(*) n FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
    LEFT JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
    WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
      AND NOT public.pdc_qc_line_counts_complete_590(p_vehicle_id, l)
      AND coalesce(l->>'stage_code','') NOT IN('JOB_CARD_NOTES','PIT_INSPECTION','QC','PARTS')
      -- r405 (F14): a Pit and weigh line, whatever it was filed under, is never unresolved work.
      AND NOT public.pdc_line_is_pit_401(p_vehicle_id,l)
      AND (s.work_key IS NULL OR NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi
        WHERE wi.vehicle_id=p_vehicle_id AND wi.work_key=s.work_key AND (wi.required OR wi.completed)))
  ), active_planner AS (
    SELECT string_agg(distinct s.code,', ' ORDER BY s.code) labels
    FROM public.workshop_bookings b
    JOIN public.workshop_stages s ON s.id=b.stage_id
    WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL
      AND b.status IN ('queued','planned','started','stoppage') AND s.planner_enabled AND s.code<>'PIT_INSPECTION'
  )
  SELECT array_remove(array[
    CASE WHEN (SELECT n FROM canonical_missing)>0 THEN 'unresolved_jobcard_work' END,
    CASE WHEN NOT EXISTS(SELECT 1 FROM vehicle) THEN 'active_vehicle_required' END,
    CASE WHEN (SELECT location FROM vehicle) NOT IN ('PMB','QC') THEN 'vehicle_must_be_at_pmb_or_qc_gate' END,
    CASE WHEN coalesce((SELECT stage FROM vehicle),'')<>'' THEN 'vehicle_still_in_workshop_stage:'||(SELECT stage FROM vehicle) END,
    CASE WHEN (SELECT labels FROM outstanding) IS NOT NULL THEN 'outstanding_required_work:'||(SELECT labels FROM outstanding) END,
    CASE WHEN (SELECT labels FROM active_planner) IS NOT NULL THEN 'active_workshop_booking:'||(SELECT labels FROM active_planner) END
  ],null::text)
$gate590$;

COMMENT ON FUNCTION public.pdc_qc_gate_issues(uuid) IS
  'r590 (F204): a green station icon is not outstanding required work. The r405 pin moves in place.';

CREATE FUNCTION public.qc_signoff_outstanding_590(p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $out590$
DECLARE
  v_role text;
  v_issues text[];
  v_issue text;
  v_label text;
  v_part text;
  v_items text[] := ARRAY[]::text[];
  v_line_items text[] := ARRAY[]::text[];
  v_lines jsonb;
BEGIN
  v_role := pg_catalog.lower(pg_catalog.btrim(coalesce(public.current_pdc_user_role()::text, '')));
  IF v_role NOT IN ('viewer', 'operator', 'importer', 'administrator', 'fitter', 'salesperson') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'role_required', 'ready', false, 'outstanding', '[]'::jsonb, 'message', 'Sign in before checking QC sign-off.');
  END IF;
  v_issues := public.pdc_qc_gate_issues(p_vehicle_id);
  FOREACH v_issue IN ARRAY coalesce(v_issues, ARRAY[]::text[]) LOOP
    IF v_issue LIKE 'outstanding_required_work:%' THEN
      v_label := pg_catalog.substr(v_issue, pg_catalog.length('outstanding_required_work:') + 1);
      FOREACH v_part IN ARRAY pg_catalog.string_to_array(v_label, ',') LOOP
        v_part := pg_catalog.btrim(v_part);
        IF v_part <> '' THEN
          v_items := v_items || (pg_catalog.initcap(pg_catalog.lower(v_part)) || ' is still required. The station icon is not green.');
        END IF;
      END LOOP;
    ELSIF v_issue LIKE 'active_workshop_booking:%' THEN
      v_items := v_items || (pg_catalog.initcap(pg_catalog.lower(pg_catalog.replace(pg_catalog.substr(v_issue, pg_catalog.length('active_workshop_booking:') + 1), '_', ' '))) || ' still has an open booking.');
    ELSIF v_issue LIKE 'vehicle_still_in_workshop_stage:%' THEN
      v_items := v_items || ('The vehicle is still in ' || pg_catalog.initcap(pg_catalog.lower(pg_catalog.replace(pg_catalog.substr(v_issue, pg_catalog.length('vehicle_still_in_workshop_stage:') + 1), '_', ' '))) || '.');
    ELSIF v_issue = 'unresolved_jobcard_work' THEN
      v_items := v_items || 'A job-card line is not on a station and is not ticked.';
    ELSIF v_issue = 'vehicle_must_be_at_pmb_or_qc_gate' THEN
      v_items := v_items || 'The vehicle is not at PMB or the QC gate.';
    ELSIF v_issue = 'active_vehicle_required' THEN
      v_items := v_items || 'This vehicle is not an active workshop vehicle.';
    ELSE
      v_items := v_items || v_issue;
    END IF;
  END LOOP;
  v_lines := public.pdc_qc_checkable_operation_lines_10700(p_vehicle_id);
  IF coalesce(pg_catalog.jsonb_array_length(v_lines), 0) = 0 THEN
    v_items := v_items || 'There is no active QC line to sign off.';
  ELSE
    SELECT coalesce(pg_catalog.array_agg(spoken.sentence ORDER BY named.sort_key), ARRAY[]::text[])
    INTO v_line_items
    FROM pg_catalog.jsonb_array_elements(v_lines) line
    CROSS JOIN LATERAL (
      SELECT
        CASE pg_catalog.upper(coalesce(line->>'stage_code', ''))
          WHEN 'UNALLOCATED_MAPPING_REVIEW' THEN 'Unallocated'
          WHEN 'BUS_4X4' THEN 'Bus 4x4'
          ELSE pg_catalog.initcap(pg_catalog.lower(pg_catalog.replace(coalesce(line->>'stage_code', 'Line'), '_', ' ')))
        END AS label,
        coalesce(nullif(line->>'description', ''), 'a line') AS title,
        coalesce(line->>'stage_code', '') || coalesce(line->>'description', '') AS sort_key
    ) named
    CROSS JOIN LATERAL (
      SELECT CASE
        WHEN line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (line->>'estimated_hours') IS NULL
          THEN named.label || ': ' || named.title || ' has no hours, so it cannot be signed off.'
        ELSE named.label || ': ' || named.title || ' is not ticked.'
      END AS sentence
    ) spoken
    WHERE coalesce((line->>'active')::boolean, false)
      AND (
        NOT public.pdc_qc_line_counts_complete_590(p_vehicle_id, line)
        OR (line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (line->>'estimated_hours') IS NULL)
      );
    v_items := v_items || coalesce(v_line_items, ARRAY[]::text[]);
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'ready', coalesce(pg_catalog.array_length(v_items, 1), 0) = 0,
    'outstanding', to_jsonb(coalesce(v_items, ARRAY[]::text[])),
    'message', CASE WHEN coalesce(pg_catalog.array_length(v_items, 1), 0) = 0 THEN '' ELSE pg_catalog.array_to_string(v_items, ' ') END
  );
END
$out590$;

REVOKE ALL ON FUNCTION public.qc_signoff_outstanding_590(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.qc_signoff_outstanding_590(uuid) TO authenticated;
COMMENT ON FUNCTION public.qc_signoff_outstanding_590(uuid) IS
  'r590 (F204): plain-English list of what still blocks QC / RFT sign-off. A green station icon is not outstanding.';

CREATE OR REPLACE FUNCTION public.finalize_pdc_qc_to_rft_700(p_vehicle_id uuid, p_expected_vehicle_version integer, p_photo_receipt_id uuid, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public, extensions
 SET statement_timeout TO '120s'
AS $fin590$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; signed public.vehicles%rowtype; after_vehicle public.vehicles%rowtype; photo public.pdc_qc_finalization_photo_evidence_399%rowtype; old public.pdc_final_pdc_lifecycle_receipts_700%rowtype;
  lines_all jsonb; lines jsonb; request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; receipt uuid; result jsonb; notifications_before bigint; notifications_after bigint;
  v_block jsonb;
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_photo_receipt_id IS NULL OR p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok',false,'code','qc_finalization_invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  request_payload:=jsonb_build_object('contract','pdc-final-authoritative-qc-to-rft-700','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'photo_receipt_id',p_photo_receipt_id,'idempotency_key',p_idempotency_key);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-701-qc-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-701-qc-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=p_vehicle_id AND action='qc_signed_off';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id,'vehicle_version',v.version)); END IF;
  IF v.lifecycle_state<>'active' OR upper(btrim(coalesce(v.current_location,'')))<>'QC' THEN RETURN jsonb_build_object('ok',false,'code','qc_vehicle_not_in_qc'); END IF;
  SELECT * INTO photo FROM public.pdc_qc_finalization_photo_evidence_399 WHERE photo_receipt_id=p_photo_receipt_id AND vehicle_id=p_vehicle_id FOR SHARE;
  IF NOT FOUND OR photo.qc_inspection_key IS DISTINCT FROM (public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>'inspection_key')::uuid OR photo.bucket_id<>'pdc-qc-evidence-staging' OR photo.content_type NOT LIKE 'image/%' OR photo.byte_length NOT BETWEEN 1 AND 1048576 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_receipt_required'); END IF;
  -- r590 (F204): name what is still outstanding. A green icon, including an override, is not outstanding. This migration does not call this function.
  v_block := public.qc_signoff_outstanding_590(p_vehicle_id);
  IF coalesce((v_block->>'ok')::boolean, false) IS NOT TRUE OR coalesce((v_block->>'ready')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'code', 'qc_signoff_outstanding', 'message', coalesce(nullif(v_block->>'message', ''), 'QC sign-off is still blocked.'), 'outstanding', coalesce(v_block->'outstanding', '[]'::jsonb));
  END IF;
  lines_all:=public.pdc_qc_checkable_operation_lines_10700(p_vehicle_id);
  lines:=coalesce((SELECT jsonb_agg(line ORDER BY line->>'stage_code',line->>'operation_no',line->>'line_identity') FROM jsonb_array_elements(lines_all) line WHERE coalesce((line->>'active')::boolean,false)),'[]'::jsonb);
  IF jsonb_array_length(lines)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) line WHERE NOT public.pdc_qc_line_counts_complete_590(p_vehicle_id, line) OR (line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (line->>'estimated_hours') IS NULL)) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'qc_signoff_outstanding', 'message', 'A QC line is still not ticked or has no hours.', 'outstanding', jsonb_build_array('A QC line is still not ticked or has no hours.'));
  END IF;
  LOCK TABLE public.vehicle_notifications IN SHARE MODE;
  notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'qc_state','QC','email_outbox_399_created',false,'timer_started',false);
  -- The live trigger deliberately requires these as separate audited transitions.
  UPDATE public.vehicles SET qc_completed_at=coalesce(qc_completed_at,clock_timestamp()),qc_completed_by=uid,version=version+1,updated_at=clock_timestamp(),updated_by=uid WHERE id=p_vehicle_id RETURNING * INTO signed;
  PERFORM public.audit_pdc_event('update','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v),to_jsonb(signed),jsonb_build_object('action','finalize_pdc_qc_to_rft_701_qc_signoff','photo_receipt_id',photo.photo_receipt_id,'email_outbox_created',false,'timer_started',false));
  UPDATE public.vehicles SET lifecycle_state='rft',current_location='RFT',date_to_rft=coalesce(date_to_rft,(clock_timestamp() at time zone 'Australia/Perth')::date),rft_transferred_at=coalesce(rft_transferred_at,clock_timestamp()),version=version+1,updated_at=clock_timestamp(),updated_by=uid WHERE id=p_vehicle_id RETURNING * INTO after_vehicle;
  PERFORM public.audit_pdc_event('rft','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(signed),to_jsonb(after_vehicle),jsonb_build_object('action','finalize_pdc_qc_to_rft_701_rft_transfer','photo_receipt_id',photo.photo_receipt_id,'email_outbox_created',false,'timer_started',false));
  after_state:=jsonb_build_object('vehicle',to_jsonb(after_vehicle),'qc_state','RFT','email_outbox_399_created',false,'timer_started',false);
  receipt:=extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,uid::text||':qc:'||p_idempotency_key::text);
  result:=jsonb_build_object('ok',true,'code','qc_signed_off_moved_to_rft','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',p_vehicle_id,'vehicle_version_before',v.version,'vehicle_version_after',after_vehicle.version,'photo_receipt_id',photo.photo_receipt_id,'completed_items',lines,'email_outbox_created',false,'timer_started',false));
  INSERT INTO public.pdc_final_pdc_lifecycle_receipts_700(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,p_vehicle_id,'qc_signed_off',uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('photo_receipt_id',photo.photo_receipt_id,'photo_storage_path',photo.storage_path,'completed_items',lines,'legacy_399_outbox_dispatchable',false,'transition_shape','two_audited_updates'),result);
  notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
  IF notifications_after<>notifications_before OR after_vehicle.current_location<>'RFT' OR after_vehicle.lifecycle_state<>'rft' OR after_vehicle.version<>v.version+2 OR after_vehicle.rft_transport_booked_at IS NOT NULL OR after_vehicle.dealer_transit_started_at IS NOT NULL THEN RAISE EXCEPTION 'PDC_701_QC_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','qc_finalization_conflict');
END
$fin590$;

CREATE OR REPLACE FUNCTION public.pdc_qc_require_all_operations_complete_379()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $trig590$
BEGIN
 IF NEW.qc_completed_at IS NOT NULL AND OLD.qc_completed_at IS NULL AND (
  (EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=NEW.id AND w.required AND lower(w.work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre'))
   AND jsonb_array_length(public.pdc_qc_checkable_operation_lines_10700(NEW.id))=0)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(NEW.id)) l WHERE coalesce((l->>'active')::boolean,false) AND ((l->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (l->>'estimated_hours') IS NULL) OR NOT public.pdc_qc_line_counts_complete_590(NEW.id, l)))
 ) THEN RAISE EXCEPTION 'PDC_QC_OPERATION_LINES_INCOMPLETE_OR_UNKNOWN' USING errcode='23514';END IF;
 RETURN NEW;
END
$trig590$;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5 = (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.pdc_qc_gate_issues(uuid)'::regprocedure),
    note = 'r590: a green station icon, including a controller or admin override, is not outstanding work',
    updated_at = pg_catalog.clock_timestamp()
WHERE signature = 'public.pdc_qc_gate_issues(uuid)'
  AND release = 'r405';

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES (
  'qc_signoff_override_590',
  'F204',
  'A green station icon, including a controller or admin override, is not outstanding QC work, and sign-off names what is still open.',
  $chk590$
SELECT
  frozen.same
  AND pins.n = 241
  AND added.n = 0
  AND gate.icon
  AND gate.helper
  AND signer.names
  AND words.plain
  AND pin_row.matches
  AND auth_exec.ok
  AND anon_blocked.ok
  AND helper_blocked.ok
  AND icon_gap.n = 0
  AND panel_gap.n = 0
  AND override_gap.n = 0
  AND stock_13047122.clear
  AS ok,
  ('pins ' || pins.n::pg_catalog.text
    || ' | icon gaps ' || icon_gap.n::pg_catalog.text
    || ' | panel gaps ' || panel_gap.n::pg_catalog.text
    || ' | override gaps ' || override_gap.n::pg_catalog.text
    || ' | stock 13047122 ' || CASE WHEN stock_13047122.clear THEN 'clear' ELSE 'blocked' END
    || ' | qc sign-off override') AS detail
FROM (
  SELECT
    (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
    AND (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) = '9be0883b1a555f48f3c1ba9fa111c891'
    AND (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) = 'b62fb7c29ffd2a1629f214f696e5cb14'
    AND (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) = '3b2398e33a2ea35fc137deeedeca4af5'
    AND (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = '626ca8b23a2e5f02e2ca8f96a4533d6f'
    AND (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) = 'b7f90bff12643229ff80f8ca552663a2'
    AS same
) frozen
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r590') added
CROSS JOIN (
  SELECT pg_catalog.strpos(p.prosrc, 'station_icon_completion_578') > 0 AS icon,
         pg_catalog.strpos(p.prosrc, 'pdc_qc_line_counts_complete_590') > 0 AS helper
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_qc_gate_issues(uuid)')
) gate
CROSS JOIN (
  SELECT pg_catalog.strpos(p.prosrc, 'qc_signoff_outstanding') > 0 AS names
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)')
) signer
CROSS JOIN (
  SELECT pg_catalog.strpos(p.prosrc, 'is still required. The station icon is not green.') > 0
     AND pg_catalog.strpos(p.prosrc, 'still has an open booking.') > 0
     AND pg_catalog.strpos(p.prosrc, 'The vehicle is still in ') > 0
     AND pg_catalog.strpos(p.prosrc, 'The vehicle is not at PMB or the QC gate.') > 0
     AND pg_catalog.strpos(p.prosrc, 'This vehicle is not an active workshop vehicle.') > 0
     AND pg_catalog.strpos(p.prosrc, 'A job-card line is not on a station and is not ticked.') > 0
     AND pg_catalog.strpos(p.prosrc, ' is not ticked.') > 0
     AND pg_catalog.strpos(p.prosrc, 'has no hours, so it cannot be signed off.') > 0
     AS plain
  FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.qc_signoff_outstanding_590(uuid)')
) words
CROSS JOIN (
  SELECT m.prosrc_md5 IS NOT DISTINCT FROM (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_qc_gate_issues(uuid)')) AS matches
  FROM pdc_ops.expected_function_md5 m
  WHERE m.signature = 'public.pdc_qc_gate_issues(uuid)' AND m.release = 'r405'
) pin_row
CROSS JOIN (
  SELECT pg_catalog.has_function_privilege('authenticated', pg_catalog.to_regprocedure('public.qc_signoff_outstanding_590(uuid)'), 'EXECUTE') AS ok
) auth_exec
CROSS JOIN (
  SELECT NOT pg_catalog.has_function_privilege('anon', pg_catalog.to_regprocedure('public.qc_signoff_outstanding_590(uuid)'), 'EXECUTE') AS ok
) anon_blocked
CROSS JOIN (
  SELECT NOT pg_catalog.has_function_privilege('authenticated', pg_catalog.to_regprocedure('public.pdc_qc_line_counts_complete_590(uuid,jsonb)'), 'EXECUTE') AS ok
) helper_blocked
CROSS JOIN (
  SELECT count(*) AS n
  FROM (
    SELECT sampled.vehicle_id
    FROM (
      SELECT c.vehicle_id FROM public.pdc_panel_line_completion_565 c WHERE c.completed
      UNION
      SELECT o.vehicle_id FROM public.pdc_station_completion_override_578 o WHERE o.completed
    ) sampled
    LIMIT 40
  ) sample
  JOIN public.vehicle_work_items wi
    ON wi.vehicle_id = sample.vehicle_id AND wi.required AND NOT wi.completed
  JOIN LATERAL (
    SELECT s->>'work_key' AS work_key
    FROM pg_catalog.jsonb_array_elements(pdc_work_categories_private.station_icon_completion_578(ARRAY[sample.vehicle_id])) s
    WHERE coalesce((s->>'complete')::boolean, false)
  ) icon ON icon.work_key = pg_catalog.lower(pg_catalog.btrim(wi.work_key))
  JOIN LATERAL pg_catalog.unnest(public.pdc_qc_gate_issues(sample.vehicle_id)) issue ON true
  WHERE issue LIKE 'outstanding_required_work:%'
    AND pg_catalog.strpos(issue, pg_catalog.upper(pg_catalog.btrim(wi.work_key))) > 0
) icon_gap
CROSS JOIN (
  SELECT count(*) AS n
  FROM (
    SELECT c.vehicle_id, c.line_identity
    FROM public.pdc_panel_line_completion_565 c
    WHERE c.completed
    LIMIT 30
  ) c
  WHERE NOT public.pdc_qc_line_counts_complete_590(
    c.vehicle_id,
    pg_catalog.jsonb_build_object('completed', false, 'line_identity', c.line_identity, 'stage_code', 'FITTING')
  )
) panel_gap
CROSS JOIN (
  SELECT count(*) AS n
  FROM (
    SELECT o.vehicle_id, o.work_key
    FROM public.pdc_station_completion_override_578 o
    WHERE o.completed
      AND o.work_key IN ('bus4x4', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet', 'parts')
    LIMIT 20
  ) o
  WHERE NOT public.pdc_qc_line_counts_complete_590(
    o.vehicle_id,
    pg_catalog.jsonb_build_object(
      'completed', false,
      'line_identity', 'r590-not-a-real-line',
      'stage_code', CASE o.work_key
        WHEN 'bus4x4' THEN 'BUS_4X4'
        WHEN 'tint' THEN 'TINT'
        WHEN 'hoist' THEN 'HOIST'
        WHEN 'fitting' THEN 'FITTING'
        WHEN 'fabrication' THEN 'FABRICATION'
        WHEN 'electrical' THEN 'ELECTRICAL'
        WHEN 'tyre' THEN 'TYRE'
        WHEN 'sublet' THEN 'SUBLET'
        WHEN 'parts' THEN 'PARTS'
        ELSE 'NO_SUCH_STAGE'
      END
    )
  )
) override_gap
CROSS JOIN (
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.vehicles v
    WHERE v.id = 'bc6e92b8-b476-4645-956c-5305f10c7231'
      AND v.deleted_at IS NULL
      AND pg_catalog.upper(pg_catalog.btrim(v.current_location)) = 'QC'
      AND v.qc_completed_at IS NULL
      AND EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(public.pdc_qc_gate_issues(v.id)) issue
        WHERE issue LIKE '%SUBLET%'
      )
  ) AS clear
) stock_13047122
$chk590$,
  true,
  361,
  'r590'
);

DO $post590$
DECLARE
  v_sql text;
  v_probe record;
BEGIN
  SELECT c.check_sql INTO v_sql FROM pdc_ops.regression_checks c WHERE c.check_name = 'qc_signoff_override_590';
  PERFORM pg_catalog.set_config('search_path', 'pg_catalog', true);
  EXECUTE v_sql INTO v_probe;
  IF NOT coalesce(v_probe.ok, false) THEN
    RAISE EXCEPTION 'r590: regression failed: %', coalesce(v_probe.detail, 'missing');
  END IF;
  PERFORM pg_catalog.set_config('search_path', 'public, extensions', true);
  IF EXISTS (
    SELECT 1 FROM public.vehicles
    WHERE id = 'bc6e92b8-b476-4645-956c-5305f10c7231'
      AND deleted_at IS NULL
      AND pg_catalog.upper(pg_catalog.btrim(current_location)) = 'QC'
      AND qc_completed_at IS NULL
  ) AND EXISTS (
    SELECT 1
    FROM pg_catalog.unnest(public.pdc_qc_gate_issues('bc6e92b8-b476-4645-956c-5305f10c7231')) issue
    WHERE issue LIKE '%SUBLET%'
  ) THEN
    RAISE EXCEPTION 'r590: stock 13047122 is still blocked on Sublet';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
    RAISE EXCEPTION 'r590: pin count moved';
  END IF;
  IF (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
     IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
    RAISE EXCEPTION 'r590: department 135 moved';
  END IF;
END
$post590$;
