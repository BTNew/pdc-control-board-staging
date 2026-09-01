-- STAGING ONLY 20260901050000: bind the v2 planner envelope to the strict RPC.
-- Appends to 0400; no receipt, rule or operational history is rewritten.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901050000-v2-contract-binding',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901040000' AND name='pdc_email_ai_typed_action_validator_binding_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901050000')
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901050000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- Exact v2 instruction validator. It is deliberately separate from the legacy
-- seven-key validator retained for rollback compatibility.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_validate_v2_instruction_20260901(p_item jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $validate$
SELECT jsonb_typeof(p_item)='object'
 AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item) k)=ARRAY['action_type','audit_event_ref','decision_disposition','evidence_refs','expected_state','identity','instruction_id','payload','provenance','reason','required_evidence','vehicle_id']::text[]
 AND p_item->>'action_type' IN('activate_vehicle','operation_add','operation_update','parts_eta_set','parts_complete','booking_set','booking_move','booking_cancel','required_work_set','work_complete','note_append','location_set','rft_transfer','rft_collect')
 AND p_item->>'decision_disposition' IN('planned','review','unsupported','conflict')
 AND p_item->>'vehicle_id'~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
 AND btrim(p_item->>'instruction_id')<>''
 AND jsonb_typeof(p_item->'identity')='object'
 AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'identity') k)=ARRAY['backend_record_id','stock_number','vehicle_id','vin']::text[]
 AND p_item->'identity'->>'vehicle_id'=p_item->>'vehicle_id'
 AND (p_item->'identity'->>'stock_number' IS NOT NULL OR p_item->'identity'->>'vin' IS NOT NULL)
 AND jsonb_typeof(p_item->'expected_state')='object'
 AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'expected_state') k)=ARRAY['backend_revision','vehicle_version']::text[]
 AND p_item->'expected_state'->>'vehicle_version'~'^[1-9][0-9]*$'
 AND p_item->'expected_state'->>'backend_revision'~'^[0-9]+$'
 AND jsonb_typeof(p_item->'payload')='object'
 AND jsonb_typeof(p_item->'evidence_refs')='array' AND jsonb_array_length(p_item->'evidence_refs') BETWEEN 1 AND 20
 AND jsonb_typeof(p_item->'provenance')='object'
 AND CASE p_item->>'action_type'
   WHEN 'activate_vehicle' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['backend_record_id','job_card_number','stock_number','vin']::text[] AND p_item->'payload'->>'backend_record_id'~'^[0-9a-f-]{36}$' AND btrim(p_item->'payload'->>'stock_number')<>''
   WHEN 'operation_add' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['description','estimated_hours','operation_no','source_row_no','source_uid','taxonomy_disposition','taxonomy_version','work_key']::text[] AND p_item->'payload'->>'operation_no'~'^OP[1-9][0-9]{0,2}$' AND p_item->'payload'->>'source_row_no'~'^[1-9][0-9]*$' AND jsonb_typeof(p_item->'payload'->'estimated_hours')='number' AND (p_item->'payload'->>'estimated_hours')::numeric BETWEEN 0 AND 999.99 AND p_item->'payload'->>'taxonomy_version'='pdc-operation-taxonomy-proposed/v1' AND p_item->'payload'->>'taxonomy_disposition' IN('classified','review','unsupported','conflict') AND btrim(p_item->'payload'->>'source_uid')<>''
   WHEN 'operation_update' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['description','estimated_hours','operation_no','source_row_no','source_uid','taxonomy_disposition','taxonomy_version','work_key']::text[] AND p_item->'payload'->>'operation_no'~'^OP[1-9][0-9]{0,2}$' AND p_item->'payload'->>'source_row_no'~'^[1-9][0-9]*$' AND jsonb_typeof(p_item->'payload'->'estimated_hours')='number' AND (p_item->'payload'->>'estimated_hours')::numeric BETWEEN 0 AND 999.99 AND p_item->'payload'->>'taxonomy_version'='pdc-operation-taxonomy-proposed/v1' AND p_item->'payload'->>'taxonomy_disposition'='classified' AND btrim(p_item->'payload'->>'source_uid')<>''
   WHEN 'parts_eta_set' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['eta']::text[] AND (p_item->'payload'->>'eta' IS NULL OR p_item->'payload'->>'eta'~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$')
   WHEN 'parts_complete' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['confirmed']::text[] AND jsonb_typeof(p_item->'payload'->'confirmed')='boolean' AND p_item->'payload'->>'confirmed'='true'
   WHEN 'booking_set' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['bay_number','duration_minutes','scheduled_start_at','stage_code','technician_id']::text[] AND p_item->'payload'->>'bay_number'~'^[1-9][0-9]*$' AND p_item->'payload'->>'duration_minutes'~'^[1-9][0-9]*$' AND (p_item->'payload'->>'duration_minutes')::integer>=60 AND btrim(p_item->'payload'->>'stage_code')<>''
   WHEN 'booking_move' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['booking_id','bay_number','duration_minutes','expected_booking_version','override_reason','scheduled_start_at','stage_code']::text[] AND p_item->'payload'->>'booking_id'~'^[0-9a-f-]{36}$' AND p_item->'payload'->>'expected_booking_version'~'^[1-9][0-9]*$' AND p_item->'payload'->>'bay_number'~'^[1-9][0-9]*$' AND p_item->'payload'->>'duration_minutes'~'^[1-9][0-9]*$' AND (p_item->'payload'->>'duration_minutes')::integer>=60 AND btrim(p_item->'payload'->>'stage_code')<>''
   WHEN 'booking_cancel' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['booking_id','expected_booking_version','reason']::text[] AND p_item->'payload'->>'booking_id'~'^[0-9a-f-]{36}$' AND p_item->'payload'->>'expected_booking_version'~'^[1-9][0-9]*$' AND btrim(p_item->'payload'->>'reason')<>''
   WHEN 'required_work_set' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['required','work_key']::text[] AND upper(p_item->'payload'->>'work_key') IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET') AND jsonb_typeof(p_item->'payload'->'required')='boolean'
   WHEN 'work_complete' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['booking_id','completed_at','expected_booking_version','work_key']::text[] AND p_item->'payload'->>'booking_id'~'^[0-9a-f-]{36}$' AND p_item->'payload'->>'expected_booking_version'~'^[1-9][0-9]*$' AND upper(p_item->'payload'->>'work_key') IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET')
   WHEN 'note_append' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['event_at','text']::text[] AND btrim(p_item->'payload'->>'text')<>'' AND p_item->'payload'->>'event_at'~'^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
   WHEN 'location_set' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['location','reason']::text[] AND upper(p_item->'payload'->>'location') IN('YH','PMB','QC','RFT','OTHER','IT') AND btrim(p_item->'payload'->>'reason')<>''
   WHEN 'rft_transfer' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['confirmed']::text[] AND p_item->'payload'->>'confirmed'='true'
   WHEN 'rft_collect' THEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_item->'payload') k)=ARRAY['confirmed']::text[] AND p_item->'payload'->>'confirmed'='true'
   ELSE false END
$validate$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $strict$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); identity_ok boolean; item jsonb; normalized jsonb; normalized_items jsonb;
BEGIN
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard() OR auth.role()<>'authenticated' OR actor IS NULL OR email='' THEN RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  SELECT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities WHERE auth_user_id=actor AND normalized_email=email AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL) AND NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=actor AND active AND account_status='approved' AND role::text='administrator') INTO identity_ok;
  IF NOT identity_ok THEN RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  IF jsonb_typeof(p_plan)<>'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_plan) k) IS DISTINCT FROM ARRAY['aggregate_disposition','attachment_digests','created_at','environment','evidence_digest','instructions','plan_id','planner_failure_reason','planner_status','schema_version','source_message_id','source_receipt_id','source_thread_id','source_digest','versions']::text[]
     OR p_plan->>'schema_version'<>'pdc-email-ai-plan-v1' OR p_plan->>'environment'<>'staging'
     OR p_plan->>'plan_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR p_plan->>'source_receipt_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR p_plan->>'source_digest' !~ '^[a-f0-9]{64}$' OR p_plan->>'evidence_digest' !~ '^[a-f0-9]{64}$'
     OR nullif(btrim(p_plan->>'source_message_id'),'') IS NULL OR nullif(btrim(p_plan->>'source_thread_id'),'') IS NULL
     OR jsonb_typeof(p_plan->'versions')<>'object' OR p_plan->'versions'->>'supabase_action_contract_version'<>'pdc-email-ai-action-request-v1' OR p_plan->'versions'->>'taxonomy_version'<>'pdc-operation-taxonomy-proposed/v1'
     OR p_plan->'versions'->>'source_digest'<>p_plan->>'source_digest' OR p_plan->'versions'->>'evidence_digest'<>p_plan->>'evidence_digest'
     OR jsonb_typeof(p_plan->'instructions')<>'array' THEN
    RETURN jsonb_build_object('ok',false,'code','typed_v2_plan_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  IF NOT COALESCE((SELECT bool_and(public.pdc_email_ai_successor_validate_v2_instruction_20260901(value)) FROM jsonb_array_elements(p_plan->'instructions')),true) THEN
    RETURN jsonb_build_object('ok',false,'code','typed_v2_instruction_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'action_type'='operation_update') THEN
    IF (SELECT count(*) FROM jsonb_array_elements(p_plan->'instructions'))<>1 THEN RETURN jsonb_build_object('ok',false,'code','operation_update_mixed_plan_requires_replan','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
    RETURN public.apply_pdc_email_ai_operation_update_transaction_20260901(p_plan);
  END IF;
  -- Adapt only after the strict v2 preflight; the retained 0200 executor sees
  -- the legacy seven-key shape and remains unreachable as a public RPC.
  SELECT coalesce(jsonb_agg(jsonb_build_object('instruction_id',x->>'instruction_id','vehicle_id',x->>'vehicle_id','identity',jsonb_build_object('stock_number',x->'identity'->'stock_number','vin',x->'identity'->'vin','backend_record_id',x->'identity'->'backend_record_id'),'expected_vehicle_version',(x->'expected_state'->>'vehicle_version')::integer,'action_type',x->>'action_type','payload',x->'payload','evidence_refs',coalesce((SELECT jsonb_agg(r->>'ref') FROM jsonb_array_elements(x->'evidence_refs') r),'[]'::jsonb)) ORDER BY x->>'instruction_id'),'[]'::jsonb) INTO normalized_items FROM jsonb_array_elements(p_plan->'instructions') q(x);
  normalized:=jsonb_build_object('schema_version','pdc-email-ai-plan-v1','source',jsonb_build_object('receipt_id',p_plan->>'source_receipt_id','source_digest',p_plan->>'source_digest','evidence_digest',p_plan->>'evidence_digest','thread_id',p_plan->>'source_thread_id','message_id',p_plan->>'source_message_id','attachment_digests',p_plan->'attachment_digests'),'versions',jsonb_build_object('action_contract','pdc-email-ai-actions-v2','taxonomy',p_plan->'versions'->>'taxonomy_version'),'instructions',normalized_items);
  RETURN public.apply_pdc_email_ai_typed_action_surface_20260901(normalized);
END $strict$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_operation_update_transaction_20260901(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $transaction$
DECLARE actor uuid:=auth.uid(); source_id uuid:=(p_plan->>'source_receipt_id')::uuid; source_hash text:=lower(p_plan->>'source_digest'); evidence_hash text:=lower(p_plan->>'evidence_digest'); item jsonb:=p_plan->'instructions'->0; vehicle_id uuid:=(item->>'vehicle_id')::uuid; action_key text; tx uuid:=gen_random_uuid(); result jsonb; before_state jsonb; after_state jsonb; readback jsonb; rb_vehicle jsonb; parity boolean; action_receipt uuid; plan_hash text:=public.pdc_email_ai_successor_hash(p_plan);
BEGIN
  action_key:=public.pdc_email_ai_successor_hash(jsonb_build_object('source_digest',source_hash,'receipt_id',source_id,'vehicle_id',vehicle_id,'instruction_id',item->>'instruction_id','action_type',item->>'action_type','payload',item->'payload'));
  IF NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=source_id AND lower(coalesce(i.source_hash,''))=source_hash AND i.duplicate_of IS NULL AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->>'source_message_id') AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->>'source_thread_id') AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=evidence_hash) THEN RETURN jsonb_build_object('ok',false,'code','source_receipt_digest_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  SELECT to_jsonb(v) INTO before_state FROM public.vehicles v WHERE v.id=vehicle_id;
  result:=public.pdc_email_ai_successor_operation_update_20260901(vehicle_id,(item->'expected_state'->>'vehicle_version')::integer,source_hash,item->'payload'->>'source_uid',item->'payload'->>'operation_no',item->'payload'->>'work_key',item->'payload'->>'description',(item->'payload'->>'estimated_hours')::numeric);
  IF NOT coalesce((result->>'ok')::boolean,false) THEN
    INSERT INTO public.pdc_email_ai_successor_action_receipts(transaction_id,source_receipt_id,action_key,instruction_id,vehicle_id,action_type,requested,disposition,reason,canonical_rpc,before_state,after_state,verification,taxonomy_version,taxonomy_disposition) VALUES(tx,source_id,action_key,item->>'instruction_id',vehicle_id,'operation_update',item->'payload','BLOCKED_EXACT_REASON',coalesce(result->>'code','operation_update_rejected'),'public.pdc_email_ai_successor_operation_update_20260901',before_state,null,jsonb_build_object('checked',false,'parity',false),p_plan->'versions'->>'taxonomy_version',item->'payload'->>'taxonomy_disposition') RETURNING action_receipt_id INTO action_receipt;
  ELSE
    after_state:=result->'operation'; readback:=public.get_pdc_email_vehicle_location_snapshot(); SELECT v INTO rb_vehicle FROM jsonb_array_elements(coalesce(readback#>'{data,vehicles}','[]'::jsonb)) v WHERE v->>'id'=vehicle_id::text LIMIT 1; parity:=rb_vehicle IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(rb_vehicle->'operation_lines','[]'::jsonb)) l WHERE l->>'operation_no'=item->'payload'->>'operation_no' AND l->>'description'=item->'payload'->>'description' AND upper(l->>'work_key')=upper(item->'payload'->>'work_key') AND (l->>'estimated_hours')::numeric=(item->'payload'->>'estimated_hours')::numeric);
    INSERT INTO public.pdc_email_ai_successor_action_receipts(transaction_id,source_receipt_id,action_key,instruction_id,vehicle_id,action_type,requested,disposition,reason,canonical_rpc,before_state,after_state,verification,taxonomy_version,taxonomy_disposition) VALUES(tx,source_id,action_key,item->>'instruction_id',vehicle_id,'operation_update',item->'payload',case when parity then 'APPLIED_AND_VERIFIED' else 'FAILED_QUEUED_RETRY' end,case when parity then 'operation_update_verified' else 'authoritative_readback_field_parity_failed' end,'public.pdc_email_ai_successor_operation_update_20260901',before_state,after_state,jsonb_build_object('checked',true,'parity',parity,'field_scope','operation_update'),p_plan->'versions'->>'taxonomy_version',item->'payload'->>'taxonomy_disposition') RETURNING action_receipt_id INTO action_receipt;
  END IF;
  PERFORM public.audit_pdc_event('update'::public.audit_action,'pdc_email_ai_successor_action_receipts',action_receipt,vehicle_id,before_state,after_state,jsonb_build_object('source','pdc_email_ai_typed_action_surface_20260901','action_key',action_key,'taxonomy_version',p_plan->'versions'->>'taxonomy_version'));
  INSERT INTO public.pdc_email_ai_successor_transaction_receipts(transaction_id,identity_id,source_receipt_id,source_digest,evidence_digest,plan_hash,typed_plan,aggregate_disposition,readback_parity,response) SELECT tx,r.identity_id,source_id,source_hash,evidence_hash,plan_hash,p_plan,case when parity then 'SUCCESS' else 'PARTIAL_FAILURE' end,coalesce(parity,false),jsonb_build_object('transaction_id',tx,'source_receipt_id',source_id,'plan_hash',plan_hash,'disposition',case when parity then 'SUCCESS' else 'PARTIAL_FAILURE' end,'actions',jsonb_build_array(jsonb_build_object('instruction_id',item->>'instruction_id','action_key',action_key,'action_type','operation_update','disposition',case when parity then 'APPLIED_AND_VERIFIED' else 'FAILED_QUEUED_RETRY' end,'after_state',after_state,'verification',jsonb_build_object('checked',true,'parity',parity))),'readback',readback,'readback_parity',coalesce(parity,false),'taxonomy_version',p_plan->'versions'->>'taxonomy_version','action_contract_version','pdc-email-ai-actions-v2','supabase_action_version','20260901050000','production_writes',false,'outbound_email',false) FROM public.pdc_email_ai_successor_runtime_identities r WHERE r.auth_user_id=actor AND r.active LIMIT 1;
  RETURN jsonb_build_object('ok',coalesce(parity,false),'code',case when parity then 'pdc_email_ai_typed_action_surface_verified' else 'pdc_email_ai_typed_action_surface_partial_failure' end,'disposition',case when parity then 'SUCCESS' else 'PARTIAL_FAILURE' end,'readback',readback,'readback_parity',coalesce(parity,false),'transaction_id',tx,'production_writes',false,'outbound_email',false);
END $transaction$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb) FROM public,anon,authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901050000','pdc_email_ai_typed_action_v2_contract_binding_20260901',ARRAY[
 'v2 planner envelope is validated with exact top-level, instruction, identity, expected-state and per-action payload keys before any source lookup or canonical RPC',
 'v2 source thread/message/digest identity is preserved while the retained executor receives only a server-built legacy compatibility projection',
 'operation_update uses a single typed optimistic-concurrency transaction with source identity, audit receipt and operation field-level readback parity',
 'strict authenticated-only entrypoint remains the only enabled typed RPC; public, anon and service_role remain denied; Production/mailbox/outbound paths remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
