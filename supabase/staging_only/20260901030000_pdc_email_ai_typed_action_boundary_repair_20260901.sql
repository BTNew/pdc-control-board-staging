-- STAGING ONLY 20260901030000: strict v2 action-boundary repair.
-- Appends to 0200; never rewrites its receipts, rules or function history.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901030000-typed-action-boundary-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901020000' AND name='pdc_email_ai_typed_action_surface_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901030000')
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)') IS NULL
     OR to_regclass('public.pdc_email_ai_successor_action_receipts') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901030000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- PostgreSQL-owned exact per-action schema. It is called only after actor
-- binding and before source lookup, canonical dispatch or receipt INSERT.
CREATE FUNCTION public.pdc_email_ai_successor_validate_instruction_20260901(p_item jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $validate$
SELECT jsonb_typeof(p_item)='object'
 AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item) k)=ARRAY['action_type','evidence_refs','expected_vehicle_version','identity','instruction_id','payload','vehicle_id']::text[]
 AND p_item->>'action_type' IN('activate_vehicle','operation_add','operation_update','parts_eta_set','parts_complete','booking_set','booking_move','booking_cancel','required_work_set','work_complete','note_append','location_set','rft_transfer','rft_collect')
 AND p_item->>'vehicle_id'~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
 AND btrim(p_item->>'instruction_id')<>'' AND p_item->>'expected_vehicle_version'~'^[1-9][0-9]*$'
 AND jsonb_typeof(p_item->'identity')='object'
 AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'identity') k)=ARRAY['backend_record_id','stock_number','vin']::text[]
 AND (p_item->'identity'->>'stock_number' IS NOT NULL OR p_item->'identity'->>'vin' IS NOT NULL)
 AND jsonb_typeof(p_item->'payload')='object'
 AND jsonb_typeof(p_item->'evidence_refs')='array' AND jsonb_array_length(p_item->'evidence_refs') BETWEEN 1 AND 20
 AND CASE p_item->>'action_type'
   WHEN 'activate_vehicle' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['backend_record_id','job_card_number','stock_number','vin']::text[] AND p_item->'payload'->>'backend_record_id'~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AND btrim(p_item->'payload'->>'stock_number')<>''
   WHEN 'operation_add' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['description','estimated_hours','operation_no','source_row_no','source_uid','taxonomy_disposition','taxonomy_version','work_key']::text[] AND p_item->'payload'->>'operation_no'~'^OP[1-9][0-9]{0,2}$' AND p_item->'payload'->>'source_row_no'~'^[1-9][0-9]*$' AND jsonb_typeof(p_item->'payload'->'estimated_hours')='number' AND (p_item->'payload'->>'estimated_hours')::numeric BETWEEN 0 AND 999.99 AND p_item->'payload'->>'taxonomy_version'~'^pdc-operation-taxonomy-(proposed|approved)/v[0-9]+$' AND p_item->'payload'->>'taxonomy_disposition' IN('classified','review','unsupported','conflict')
   WHEN 'operation_update' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['description','estimated_hours','operation_no','source_row_no','source_uid','taxonomy_disposition','taxonomy_version','work_key']::text[] AND p_item->'payload'->>'operation_no'~'^OP[1-9][0-9]{0,2}$' AND p_item->'payload'->>'source_row_no'~'^[1-9][0-9]*$' AND jsonb_typeof(p_item->'payload'->'estimated_hours')='number' AND (p_item->'payload'->>'estimated_hours')::numeric BETWEEN 0 AND 999.99 AND p_item->'payload'->>'taxonomy_version'~'^pdc-operation-taxonomy-(proposed|approved)/v[0-9]+$' AND p_item->'payload'->>'taxonomy_disposition' IN('classified','review','unsupported','conflict')
   WHEN 'parts_eta_set' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['eta']::text[] AND (p_item->'payload'->>'eta' IS NULL OR p_item->'payload'->>'eta'~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$')
   WHEN 'parts_complete' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['confirmed']::text[] AND p_item->'payload'->>'confirmed'='true'
   WHEN 'booking_set' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['bay_number','duration_minutes','scheduled_start_at','stage_code','technician_id']::text[] AND p_item->'payload'->>'bay_number'~'^[1-9][0-9]*$' AND (p_item->'payload'->>'duration_minutes')::integer>=60 AND btrim(p_item->'payload'->>'stage_code')<>'' AND p_item->'payload'->>'scheduled_start_at'~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
   WHEN 'booking_move' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['booking_id','bay_number','duration_minutes','expected_booking_version','override_reason','scheduled_start_at','stage_code']::text[] AND p_item->'payload'->>'booking_id'~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AND p_item->'payload'->>'expected_booking_version'~'^[1-9][0-9]*$' AND (p_item->'payload'->>'duration_minutes')::integer>=60 AND p_item->'payload'->>'bay_number'~'^[1-9][0-9]*$' AND p_item->'payload'->>'scheduled_start_at'~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
   WHEN 'booking_cancel' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['booking_id','expected_booking_version','reason']::text[] AND p_item->'payload'->>'booking_id'~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AND p_item->'payload'->>'expected_booking_version'~'^[1-9][0-9]*$' AND btrim(p_item->'payload'->>'reason')<>''
   WHEN 'required_work_set' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['required','work_key']::text[] AND p_item->'payload'->>'work_key' IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET') AND jsonb_typeof(p_item->'payload'->'required')='boolean'
   WHEN 'work_complete' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['booking_id','completed_at','expected_booking_version','work_key']::text[] AND p_item->'payload'->>'booking_id'~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AND p_item->'payload'->>'expected_booking_version'~'^[1-9][0-9]*$' AND btrim(p_item->'payload'->>'work_key')<>'' AND p_item->'payload'->>'completed_at'~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
   WHEN 'note_append' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['event_at','text']::text[] AND btrim(p_item->'payload'->>'text')<>'' AND p_item->'payload'->>'event_at'~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
   WHEN 'location_set' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['location','reason']::text[] AND upper(p_item->'payload'->>'location') IN('YH','PMB','QC','RFT','OTHER','IT') AND btrim(p_item->'payload'->>'reason')<>''
   WHEN 'rft_transfer' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['confirmed']::text[] AND p_item->'payload'->>'confirmed'='true'
   WHEN 'rft_collect' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['confirmed']::text[] AND p_item->'payload'->>'confirmed'='true'
   ELSE false END
$validate$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_validate_instruction_20260901(jsonb) FROM public,anon,authenticated,service_role;

-- Narrow typed operation update: source operation rows remain immutable and the
-- effective Board projection is updated through a namespaced source overlay.
CREATE FUNCTION public.pdc_email_ai_successor_operation_update_20260901(p_vehicle_id uuid,p_expected_vehicle_version integer,p_source_hash text,p_source_uid text,p_operation_no text,p_work_key text,p_description text,p_estimated_hours numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $operation_update$
DECLARE v_vehicle public.vehicles%rowtype; v_source public.pdc_authenticated_email_operation_lines%rowtype; v_before jsonb; v_after jsonb; v_overlay public.vehicle_workshop_line_adjustments%rowtype; v_now timestamptz:=clock_timestamp();
BEGIN
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.version<>p_expected_vehicle_version OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active' THEN RETURN jsonb_build_object('ok',false,'code','operation_update_vehicle_conflict'); END IF;
  SELECT * INTO v_source FROM public.pdc_authenticated_email_operation_lines WHERE vehicle_id=p_vehicle_id AND source_hash=lower(btrim(p_source_hash)) AND source_uid=p_source_uid AND operation_no=upper(btrim(p_operation_no)) FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_update_source_not_found'); END IF;
  SELECT * INTO v_overlay FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=p_vehicle_id AND line_key='source:'||v_source.operation_line_id::text FOR UPDATE;
  v_before:=case when v_overlay.adjustment_id is null then to_jsonb(v_source) else to_jsonb(v_overlay) end;
  IF v_overlay.adjustment_id IS NULL THEN
    INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,created_by,updated_by,operation_code,display_order,manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number)
    VALUES(p_vehicle_id,'source:'||v_source.operation_line_id::text,'source',public.workshop_stage_code_for_work_key(upper(btrim(p_work_key))),btrim(p_description),p_estimated_hours,true,1,auth.uid(),auth.uid(),v_source.operation_no,v_source.source_row_no,false,'pdc_email_ai_v2',v_source.operation_line_id,v_source.job_card_number)
    RETURNING * INTO v_overlay;
  ELSE
    UPDATE public.vehicle_workshop_line_adjustments SET stage_code=public.workshop_stage_code_for_work_key(upper(btrim(p_work_key))),description=btrim(p_description),estimated_hours=p_estimated_hours,active=true,version=version+1,updated_by=auth.uid(),updated_at=v_now,correction_origin='pdc_email_ai_v2' WHERE adjustment_id=v_overlay.adjustment_id RETURNING * INTO v_overlay;
  END IF;
  UPDATE public.vehicles SET version=version+1,updated_by=auth.uid(),updated_at=v_now WHERE id=p_vehicle_id RETURNING * INTO v_vehicle;
  v_after:=to_jsonb(v_overlay);
  PERFORM public.audit_pdc_event('update'::public.audit_action,'vehicle_workshop_line_adjustments',v_overlay.adjustment_id,p_vehicle_id,v_before,v_after,jsonb_build_object('source','pdc_email_ai_typed_action_surface_20260901','operation_update',true,'source_hash',p_source_hash,'source_uid',p_source_uid,'operation_no',p_operation_no));
  RETURN jsonb_build_object('ok',true,'code','operation_updated','vehicle',to_jsonb(v_vehicle),'operation',v_after,'source_operation_line_id',v_source.operation_line_id);
END $operation_update$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_operation_update_20260901(uuid,integer,text,text,text,text,text,numeric) FROM public,anon,authenticated,service_role;

-- Actor-first strict wrapper. Legacy 0200 remains callable only as an internal
-- implementation for plans that pass this exact boundary.
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $strict$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); identity_ok boolean; item jsonb;
BEGIN
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard() OR auth.role()<>'authenticated' OR actor IS NULL OR email='' THEN RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  SELECT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities WHERE auth_user_id=actor AND normalized_email=email AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL) AND NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=actor AND active AND account_status='approved' AND role::text='administrator') INTO identity_ok;
  IF NOT identity_ok THEN RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  IF jsonb_typeof(p_plan)<>'object' OR (p_plan->'versions'->>'action_contract')<>'pdc-email-ai-actions-v2' OR jsonb_typeof(p_plan->'instructions')<>'array' OR NOT (SELECT bool_and(public.pdc_email_ai_successor_validate_instruction_20260901(value)) FROM jsonb_array_elements(p_plan->'instructions')) THEN
    RETURN jsonb_build_object('ok',false,'code','typed_instruction_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'action_type'='operation_update') THEN
    IF (SELECT count(*) FROM jsonb_array_elements(p_plan->'instructions'))<>1 THEN RETURN jsonb_build_object('ok',false,'code','operation_update_mixed_plan_requires_replan','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
    RETURN public.apply_pdc_email_ai_operation_update_transaction_20260901(p_plan);
  END IF;
  RETURN public.apply_pdc_email_ai_typed_action_surface_20260901(p_plan);
END $strict$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) TO authenticated;

-- Operation-update transaction receipt wrapper. It is intentionally single-action
-- so source/version/readback parity is atomic and cannot hide a mixed result.
CREATE FUNCTION public.apply_pdc_email_ai_operation_update_transaction_20260901(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $transaction$
DECLARE actor uuid:=auth.uid(); source_id uuid:=(p_plan->'source'->>'receipt_id')::uuid; source_hash text:=lower(p_plan->'source'->>'source_digest'); evidence_hash text:=lower(p_plan->'source'->>'evidence_digest'); item jsonb:=p_plan->'instructions'->0; vehicle_id uuid:=(item->>'vehicle_id')::uuid; action_key text; tx uuid:=gen_random_uuid(); result jsonb; before_state jsonb; after_state jsonb; readback jsonb; rb_vehicle jsonb; parity boolean; action_receipt uuid; plan_hash text:=public.pdc_email_ai_successor_hash(p_plan);
BEGIN
  action_key:=public.pdc_email_ai_successor_hash(jsonb_build_object('source_digest',source_hash,'receipt_id',source_id,'vehicle_id',vehicle_id,'instruction_id',item->>'instruction_id','action_type',item->>'action_type','payload',item->'payload'));
  IF NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=source_id AND lower(coalesce(i.source_hash,''))=source_hash AND i.duplicate_of IS NULL AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->'source'->>'message_id') AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->'source'->>'thread_id') AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=evidence_hash) THEN RETURN jsonb_build_object('ok',false,'code','source_receipt_digest_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  SELECT to_jsonb(v) INTO before_state FROM public.vehicles v WHERE v.id=vehicle_id;
  result:=public.pdc_email_ai_successor_operation_update_20260901(vehicle_id,(item->>'expected_vehicle_version')::integer,source_hash,item->'payload'->>'source_uid',item->'payload'->>'operation_no',item->'payload'->>'work_key',item->'payload'->>'description',(item->'payload'->>'estimated_hours')::numeric);
  IF NOT coalesce((result->>'ok')::boolean,false) THEN
    INSERT INTO public.pdc_email_ai_successor_action_receipts(transaction_id,source_receipt_id,action_key,instruction_id,vehicle_id,action_type,requested,disposition,reason,canonical_rpc,before_state,after_state,verification,taxonomy_version,taxonomy_disposition) VALUES(tx,source_id,action_key,item->>'instruction_id',vehicle_id,'operation_update',item->'payload','BLOCKED_EXACT_REASON',coalesce(result->>'code','operation_update_rejected'),'public.pdc_email_ai_successor_operation_update_20260901',before_state,null,jsonb_build_object('checked',false,'parity',false),p_plan->'versions'->>'taxonomy',''||(item->'payload'->>'taxonomy_disposition')) RETURNING action_receipt_id INTO action_receipt;
  ELSE
    after_state:=result->'operation'; readback:=public.get_pdc_email_vehicle_location_snapshot(); SELECT v INTO rb_vehicle FROM jsonb_array_elements(coalesce(readback#>'{data,vehicles}','[]'::jsonb)) v WHERE v->>'id'=vehicle_id::text LIMIT 1; parity:=rb_vehicle IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(rb_vehicle->'operation_lines','[]'::jsonb)) l WHERE l->>'operation_no'=item->'payload'->>'operation_no' AND l->>'description'=item->'payload'->>'description');
    INSERT INTO public.pdc_email_ai_successor_action_receipts(transaction_id,source_receipt_id,action_key,instruction_id,vehicle_id,action_type,requested,disposition,reason,canonical_rpc,before_state,after_state,verification,taxonomy_version,taxonomy_disposition) VALUES(tx,source_id,action_key,item->>'instruction_id',vehicle_id,'operation_update',item->'payload',case when parity then 'APPLIED_AND_VERIFIED' else 'FAILED_QUEUED_RETRY' end,case when parity then 'operation_update_verified' else 'authoritative_readback_field_parity_failed' end,'public.pdc_email_ai_successor_operation_update_20260901',before_state,after_state,jsonb_build_object('checked',true,'parity',parity,'field_scope','operation_update'),p_plan->'versions'->>'taxonomy',item->'payload'->>'taxonomy_disposition') RETURNING action_receipt_id INTO action_receipt;
  END IF;
  PERFORM public.audit_pdc_event('update'::public.audit_action,'pdc_email_ai_successor_action_receipts',action_receipt,vehicle_id,before_state,after_state,jsonb_build_object('source','pdc_email_ai_typed_action_surface_20260901','action_key',action_key,'taxonomy_version',p_plan->'versions'->>'taxonomy'));
  INSERT INTO public.pdc_email_ai_successor_transaction_receipts(transaction_id,identity_id,source_receipt_id,source_digest,evidence_digest,plan_hash,typed_plan,aggregate_disposition,readback_parity,response) SELECT tx,r.identity_id,source_id,source_hash,evidence_hash,plan_hash,p_plan,case when parity then 'SUCCESS' else 'PARTIAL_FAILURE' end,coalesce(parity,false),jsonb_build_object('transaction_id',tx,'source_receipt_id',source_id,'plan_hash',plan_hash,'disposition',case when parity then 'SUCCESS' else 'PARTIAL_FAILURE' end,'actions',jsonb_build_array(jsonb_build_object('instruction_id',item->>'instruction_id','action_key',action_key,'action_type','operation_update','disposition',case when parity then 'APPLIED_AND_VERIFIED' else 'FAILED_QUEUED_RETRY' end,'after_state',after_state,'verification',jsonb_build_object('checked',true,'parity',parity))),'readback',readback,'readback_parity',coalesce(parity,false),'taxonomy_version',p_plan->'versions'->>'taxonomy','action_contract_version','pdc-email-ai-actions-v2','supabase_action_version','20260901030000','production_writes',false,'outbound_email',false) FROM public.pdc_email_ai_successor_runtime_identities r WHERE r.auth_user_id=actor AND r.active LIMIT 1;
  RETURN jsonb_build_object('ok',coalesce(parity,false),'code',case when parity then 'pdc_email_ai_typed_action_surface_verified' else 'pdc_email_ai_typed_action_surface_partial_failure' end,'disposition',case when parity then 'SUCCESS' else 'PARTIAL_FAILURE' end,'readback',readback,'readback_parity',coalesce(parity,false),'transaction_id',tx,'production_writes',false,'outbound_email',false);
END $transaction$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb) FROM public,anon,authenticated,service_role;

-- Route the versioned alias through the strict actor/payload boundary and close
-- the old direct authenticated entrypoint without deleting it as rollback code.
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(p_plan jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $$
  SELECT public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan)
$$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb) FROM authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901030000','pdc_email_ai_typed_action_boundary_repair_20260901',ARRAY[
 'Actor-first strict wrapper requires the v2 action contract and PostgreSQL-owned exact per-action key/type/range validation before source lookup, canonical dispatch or receipt writes',
 'Operation update is a narrow immutable-source overlay successor with expected vehicle version, exact source UID/hash/operation identity, audit and field-level Board readback',
 'Operation update is atomic single-action; mixed update plans require replan rather than hiding partial outcomes',
 'Canonical operation add, Parts, booking, work, note, location, activation and RFT dispatch are reachable only through fixed server-owned signatures after strict validation',
 'Typed alias routes through the strict wrapper; the previous 0200 function remains retained rollback implementation but loses direct authenticated execution',
 'Unresolved taxonomy review dispositions remain typed REVIEW and mixed signage/GVM/decal text cannot become Hoist or Sublet; Production/mailbox/outbound paths remain false'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
