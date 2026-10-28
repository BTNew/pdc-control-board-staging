-- r590 (F204) undo. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Puts the QC gate, the sign-off function and the QC line trigger back,
-- moves the r405 gate pin back, and removes the F204 check.
-- Department 135, Kajel, the clock and the pin count stay put.
-- This does not change a vehicle.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r590 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r590 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r590 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r590 undo: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r590 undo: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r590 undo: Kajel apply changed'; END IF;
 IF to_regprocedure('public.qc_signoff_outstanding_590(uuid)') IS NULL THEN RAISE EXCEPTION 'r590 undo: sign-off wording is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='qc_signoff_override_590' AND fault_id='F204' AND sort_order=361 AND added_in='r590') THEN RAISE EXCEPTION 'r590 undo: F204 check is missing'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.pdc_qc_gate_issues(p_vehicle_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH vehicle AS (
    SELECT id,upper(btrim(coalesce(current_location,''))) location,
           CASE WHEN regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g')='PITINSPECTION' THEN ''
                ELSE regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g') END stage
    FROM public.vehicles WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL
  ), outstanding AS (
    SELECT string_agg(distinct upper(btrim(wi.work_key)),', ' ORDER BY upper(btrim(wi.work_key))) labels
    FROM public.vehicle_work_items wi
    WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed
      AND regexp_replace(upper(btrim(coalesce(wi.work_key,''))),'[^A-Z0-9]+','','g') NOT IN ('QC','PARTS','PITINSPECTION')
  ), canonical_missing AS (
    SELECT count(*) n FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
    LEFT JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
    WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true' AND coalesce(l->>'completed','false')<>'true'
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
$function$;

CREATE OR REPLACE FUNCTION public.finalize_pdc_qc_to_rft_700(p_vehicle_id uuid, p_expected_vehicle_version integer, p_photo_receipt_id uuid, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; signed public.vehicles%rowtype; after_vehicle public.vehicles%rowtype; photo public.pdc_qc_finalization_photo_evidence_399%rowtype; old public.pdc_final_pdc_lifecycle_receipts_700%rowtype;
  lines_all jsonb; lines jsonb; request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; receipt uuid; result jsonb; notifications_before bigint; notifications_after bigint;
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
  lines_all:=public.pdc_qc_checkable_operation_lines_10700(p_vehicle_id);
  lines:=coalesce((SELECT jsonb_agg(line ORDER BY line->>'stage_code',line->>'operation_no',line->>'line_identity') FROM jsonb_array_elements(lines_all) line WHERE coalesce((line->>'active')::boolean,false)),'[]'::jsonb);
  IF jsonb_array_length(lines)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) line WHERE NOT coalesce((line->>'completed')::boolean,false) OR (line->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (line->>'estimated_hours') IS NULL)) THEN RETURN jsonb_build_object('ok',false,'code','qc_operation_lines_incomplete'); END IF;
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
END $function$;

CREATE OR REPLACE FUNCTION public.pdc_qc_require_all_operations_complete_379()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
 IF NEW.qc_completed_at IS NOT NULL AND OLD.qc_completed_at IS NULL AND (
  (EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=NEW.id AND w.required AND lower(w.work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre'))
   AND jsonb_array_length(public.pdc_qc_checkable_operation_lines_10700(NEW.id))=0)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(NEW.id)) l WHERE coalesce((l->>'active')::boolean,false) AND ((l->>'stage_code' IS DISTINCT FROM 'SUBLET' AND (l->>'estimated_hours') IS NULL) OR NOT coalesce((l->>'completed')::boolean,false)))
 ) THEN RAISE EXCEPTION 'PDC_QC_OPERATION_LINES_INCOMPLETE_OR_UNKNOWN' USING errcode='23514';END IF;
 RETURN NEW;
END $function$;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5 = '2d9f3d968a51790d3395c0367af70578',
    note = 'PMB->QC gate ignores Pit lines, any filing (r405)',
    updated_at = '2026-10-20 13:54:27.067868+00'
WHERE signature = 'public.pdc_qc_gate_issues(uuid)'
  AND release = 'r405';

DELETE FROM pdc_ops.regression_checks
WHERE check_name = 'qc_signoff_override_590'
  AND fault_id = 'F204'
  AND sort_order = 361
  AND added_in = 'r590';

DROP FUNCTION public.qc_signoff_outstanding_590(uuid);
DROP FUNCTION public.pdc_qc_line_counts_complete_590(uuid, jsonb);

DO $post$
DECLARE
  v_gate text;
  v_fin text;
  v_trig text;
BEGIN
  SELECT md5(p.prosrc) INTO v_gate FROM pg_proc p WHERE p.oid = to_regprocedure('public.pdc_qc_gate_issues(uuid)');
  SELECT md5(p.prosrc) INTO v_fin FROM pg_proc p WHERE p.oid = to_regprocedure('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)');
  SELECT md5(p.prosrc) INTO v_trig FROM pg_proc p WHERE p.oid = to_regprocedure('public.pdc_qc_require_all_operations_complete_379()');
  IF v_gate IS DISTINCT FROM '2d9f3d968a51790d3395c0367af70578' THEN RAISE EXCEPTION 'r590 undo: gate md5 %', v_gate; END IF;
  IF v_fin IS DISTINCT FROM 'e4c7271b2efe49ed45117f600b6fe954' THEN RAISE EXCEPTION 'r590 undo: sign-off md5 %', v_fin; END IF;
  IF v_trig IS DISTINCT FROM 'e6018eac99505f2548df1ae0c8647c58' THEN RAISE EXCEPTION 'r590 undo: line trigger md5 %', v_trig; END IF;
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.pdc_qc_gate_issues(uuid)' AND release='r405') IS DISTINCT FROM '2d9f3d968a51790d3395c0367af70578' THEN RAISE EXCEPTION 'r590 undo: pin md5 did not return'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r590 undo: pin count moved'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='qc_signoff_override_590') THEN RAISE EXCEPTION 'r590 undo: check remains'; END IF;
  IF to_regprocedure('public.qc_signoff_outstanding_590(uuid)') IS NOT NULL OR to_regprocedure('public.pdc_qc_line_counts_complete_590(uuid,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r590 undo: helper remains'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r590 undo: department 135 moved'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r590 undo: Kajel rows moved'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r590 undo: Kajel apply moved'; END IF;
END
$post$;
