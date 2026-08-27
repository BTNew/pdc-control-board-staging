-- STAGING ONLY 701: append-only repair of the final QC transition.
-- The live trigger pdc_enforce_qc_then_rft requires QC sign-off and the RFT
-- move to remain two audited row transitions in one transaction. Applied 700
-- is preserved; this successor only replaces its effective function body.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-701-final-qc-transition-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $pre$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827101000'
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827101000' AND name='700_final_authoritative_pdc_lifecycle')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827101000')
     OR to_regprocedure('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)') IS NULL
     OR to_regclass('public.pdc_final_pdc_lifecycle_receipts_700') IS NULL
     OR to_regprocedure('public.pdc_enforce_qc_then_rft()') IS NULL
  THEN RAISE EXCEPTION 'PDC_701_EXACT_700_PRESTATE_REQUIRED' USING errcode='55000'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.finalize_pdc_qc_to_rft_700(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_photo_receipt_id uuid,p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $qc$
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
  IF NOT FOUND OR photo.bucket_id<>'pdc-qc-evidence-staging' OR photo.content_type NOT LIKE 'image/%' OR photo.byte_length NOT BETWEEN 1 AND 1048576 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_receipt_required'); END IF;
  lines_all:=public.pdc_qc_operation_lines_379(p_vehicle_id);
  lines:=coalesce((SELECT jsonb_agg(line ORDER BY line->>'stage_code',line->>'operation_no',line->>'line_identity') FROM jsonb_array_elements(lines_all) line WHERE coalesce((line->>'active')::boolean,false)),'[]'::jsonb);
  IF jsonb_array_length(lines)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) line WHERE NOT coalesce((line->>'completed')::boolean,false) OR (line->>'estimated_hours') IS NULL) THEN RETURN jsonb_build_object('ok',false,'code','qc_operation_lines_incomplete'); END IF;
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
END $qc$;
REVOKE ALL ON FUNCTION public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid) TO authenticated;

DO $post$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure) INTO d;
  IF position('finalize_pdc_qc_to_rft_701_qc_signoff' in d)=0 OR position('finalize_pdc_qc_to_rft_701_rft_transfer' in d)=0 OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','EXECUTE') OR has_function_privilege('anon','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'PDC_701_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827102000','701_final_qc_two_transition_repair',ARRAY[
  'Preserve applied 700 and repair its effective QC RPC to satisfy the live QC-then-RFT trigger contract',
  'Keep QC sign-off and RFT movement as two audited updates in one atomic transaction with no 399 email and no timer',
  'Retain 700 receipt/idempotency/evidence shape and authenticated-only least-privilege grant; Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
