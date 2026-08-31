-- STAGING ONLY: append-only successor command/read hardening after 3300.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-email-ai-successor-command-read-hardening-20260831340000',0));
DO $guard$
BEGIN
 IF current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831330000' AND name='pdc_email_ai_successor_inbox_read_projection')<>1
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260831340000')
 THEN RAISE EXCEPTION 'PDC_EMAIL_AI_SUCCESSOR_3400_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_transaction_successor(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $apply$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_identity public.pdc_email_ai_successor_runtime_identities%rowtype;
  v_source_id uuid;
  v_source_hash text:=lower(btrim(coalesce(p_plan->'source'->>'source_digest','')));
  v_evidence_hash text:=lower(btrim(coalesce(p_plan->'source'->>'evidence_digest','')));
  v_plan_hash text;
  v_existing public.pdc_email_ai_successor_transaction_receipts%rowtype;
  v_transaction_id uuid:=gen_random_uuid();
  v_item jsonb;
  v_action_key text;
  v_instruction text;
  v_vehicle_id uuid;
  v_expected_version integer;
  v_action_type text;
  v_payload jsonb;
  v_vehicle public.vehicles%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_result jsonb;
  v_disposition text;
  v_reason text;
  v_rpc text;
  v_verification jsonb;
  v_expected jsonb;
  v_actual jsonb;
  v_initial_vehicle_versions jsonb:='{}'::jsonb;
  v_actions jsonb:='[]'::jsonb;
  v_action_dispositions text[]:='{}'::text[];
  v_applied integer:=0;
  v_blocked integer:=0;
  v_readback jsonb;
  v_readback_ok boolean:=false;
  v_aggregate text;
  v_seen text[]:='{}'::text[];
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR auth.role()<>'authenticated' OR v_actor IS NULL OR v_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  SELECT * INTO v_identity
  FROM public.pdc_email_ai_successor_runtime_identities
  WHERE auth_user_id=v_actor AND normalized_email=v_email AND environment='staging'
    AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL
  FOR SHARE;
  IF NOT FOUND OR EXISTS(
    SELECT 1 FROM public.pdc_user_roles r
    WHERE r.auth_user_id=v_actor AND r.active AND r.account_status='approved'
      AND r.role::text='administrator'
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  IF jsonb_typeof(p_plan)<>'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_plan) k)
        IS DISTINCT FROM ARRAY['instructions','schema_version','source','versions']::text[]
     OR p_plan->>'schema_version'<>'pdc-email-ai-plan-v1'
     OR jsonb_typeof(p_plan->'source')<>'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_plan->'source') k)
        IS DISTINCT FROM ARRAY['attachment_digests','evidence_digest','message_id','receipt_id','source_digest','thread_id']::text[]
     OR jsonb_typeof(p_plan->'versions')<>'object'
     OR jsonb_typeof(p_plan->'instructions')<>'array'
     OR jsonb_array_length(p_plan->'instructions')>200
     OR v_source_hash !~ '^[a-f0-9]{64}$'
     OR v_evidence_hash !~ '^[a-f0-9]{64}$'
     OR (p_plan->'source'->>'receipt_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR nullif(btrim(p_plan->'source'->>'message_id'),'') IS NULL
     OR nullif(btrim(p_plan->'source'->>'thread_id'),'') IS NULL
     OR jsonb_typeof(p_plan->'source'->'attachment_digests')<>'array'
     OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_plan->'source'->'attachment_digests') x WHERE x !~ '^[a-f0-9]{64}$')
     OR (p_plan->'versions'->>'action_contract')<>'pdc-email-ai-actions-v1'
     OR (p_plan->'versions'->>'taxonomy')<>v_identity.taxonomy_version
     OR (p_plan->'versions'->>'rules')<>v_identity.rule_version
     OR (p_plan->'versions'->>'model')<>v_identity.model_version
     OR (p_plan->'versions'->>'prompt')<>v_identity.prompt_version
  THEN
    RETURN jsonb_build_object('ok',false,'code','typed_plan_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  v_source_id:=(p_plan->'source'->>'receipt_id')::uuid;
  v_plan_hash:=public.pdc_email_ai_successor_hash(p_plan);
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-email-ai-source:'||v_source_hash,0));
  SELECT * INTO v_existing FROM public.pdc_email_ai_successor_transaction_receipts
  WHERE source_receipt_id=v_source_id;
  IF FOUND THEN
    IF v_existing.source_digest<>v_source_hash OR v_existing.plan_hash<>v_plan_hash THEN
      RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    RETURN v_existing.response||jsonb_build_object('replay',true);
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.ai_email_intake i
    WHERE i.id=v_source_id AND lower(coalesce(i.source_hash,''))=v_source_hash
      AND i.duplicate_of IS NULL
      AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->'source'->>'message_id')
      AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->'source'->>'thread_id')
      AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=v_evidence_hash
      AND coalesce((SELECT jsonb_agg(lower(a.source_hash) ORDER BY lower(a.source_hash))
                    FROM public.ai_email_attachments a
                    WHERE a.intake_id=i.id AND a.source_hash IS NOT NULL),'[]'::jsonb)
          =coalesce((SELECT jsonb_agg(lower(x) ORDER BY lower(x))
                     FROM jsonb_array_elements_text(p_plan->'source'->'attachment_digests') x),'[]'::jsonb)
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','source_receipt_digest_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;

  -- Validate every instruction and its identity before the first canonical call.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    v_action_type:=v_item->>'action_type';
    IF jsonb_typeof(v_item)<>'object'
       OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item) k)
          IS DISTINCT FROM ARRAY['action_type','evidence_refs','expected_vehicle_version','identity','instruction_id','payload','vehicle_id']::text[]
       OR v_item->>'action_type' NOT IN(
          'activate_from_navision','location_set','workgroup_requirement_set','operation_upsert',
          'parts_eta_set','parts_ordered','parts_complete','notes_append','job_card_upsert',
          'sublet_booking_upsert','rft_transfer','rft_collect')
       OR (v_item->>'vehicle_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       OR (v_item->>'instruction_id') IS NULL
       OR (v_item->>'expected_vehicle_version') !~ '^[1-9][0-9]*$'
       OR jsonb_typeof(v_item->'payload')<>'object'
       OR jsonb_typeof(v_item->'identity')<>'object'
       OR jsonb_typeof(v_item->'evidence_refs')<>'array'
       OR jsonb_array_length(v_item->'evidence_refs')=0
       OR p_plan::text ~* '"(sql|table|tables|column|schema|rpc|function|query|mutation|dml|service_role|administrator|admin|rls_bypass|security_definer)"[[:space:]]*:'
       OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'identity') k)
          IS DISTINCT FROM ARRAY['backend_record_id','stock_number','vin']::text[]
       OR (v_item->'identity'->>'stock_number' IS NULL AND v_item->'identity'->>'vin' IS NULL)
       OR (v_action_type='parts_eta_set' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'payload') k) IS DISTINCT FROM ARRAY['eta']::text[])
       OR (v_action_type IN('parts_ordered','parts_complete','rft_transfer','rft_collect') AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'payload') k) IS DISTINCT FROM ARRAY['confirmed']::text[])
       OR (v_action_type IN('parts_ordered','parts_complete','rft_transfer','rft_collect') AND v_item->'payload'->>'confirmed' IS DISTINCT FROM 'true')
       OR (v_action_type='location_set' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'payload') k) IS DISTINCT FROM ARRAY['location','reason']::text[])
       OR (v_action_type='workgroup_requirement_set' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'payload') k) IS DISTINCT FROM ARRAY['required','work_key']::text[])
       OR (v_action_type IN('operation_upsert') AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'payload') k) IS DISTINCT FROM ARRAY['description','estimated_hours','operation_no','source_row_no','work_key']::text[])
       OR (v_action_type='job_card_upsert' AND ((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'payload') k) IS DISTINCT FROM ARRAY['job_card_number','lines']::text[] OR jsonb_typeof(v_item->'payload'->'lines')<>'array'))
       OR (v_action_type='notes_append' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'payload') k) IS DISTINCT FROM ARRAY['text']::text[])
       OR (v_action_type='sublet_booking_upsert' AND (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_item->'payload') k) IS DISTINCT FROM ARRAY['booking_id','expected_booking_version','expected_return_date','mode','out_date','provider_id','provider_name']::text[])
       OR (v_action_type='parts_eta_set' AND v_item->'payload'->>'eta' IS NOT NULL AND v_item->'payload'->>'eta' !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$')
    THEN
      RETURN jsonb_build_object('ok',false,'code','typed_instruction_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    v_action_key:=public.pdc_email_ai_successor_hash(jsonb_build_object(
      'source_digest',v_source_hash,'receipt_id',v_source_id,
      'vehicle_id',v_item->>'vehicle_id','instruction_id',v_item->>'instruction_id',
      'action_type',v_item->>'action_type','payload',v_item->'payload'));
    IF v_action_key=ANY(v_seen) THEN
      RETURN jsonb_build_object('ok',false,'code','duplicate_action_key','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    v_seen:=array_append(v_seen,v_action_key);
  END LOOP;

  -- Lock and validate each distinct vehicle once before any action can advance
  -- its version. Later actions in this same transaction use the locked current
  -- row and are not incorrectly rejected because an earlier sibling advanced it.
  FOR v_vehicle_id IN SELECT DISTINCT (value->>'vehicle_id')::uuid
    FROM jsonb_array_elements(p_plan->'instructions') q(value) LOOP
    SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_vehicle_id FOR UPDATE;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok',false,'code','vehicle_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    v_initial_vehicle_versions:=jsonb_set(v_initial_vehicle_versions,ARRAY[v_vehicle_id::text],to_jsonb(v_vehicle.version),true);
  END LOOP;

  -- The typed identity must resolve to the same locked canonical vehicle.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    v_vehicle_id:=(v_item->>'vehicle_id')::uuid;
    SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_vehicle_id FOR SHARE;
    IF NOT FOUND
       OR (v_item->'identity'->>'stock_number' IS NOT NULL AND public.normalize_vehicle_stock_number(v_item->'identity'->>'stock_number') IS DISTINCT FROM v_vehicle.stock_number_normalized)
       OR (v_item->'identity'->>'vin' IS NOT NULL AND public.normalize_vehicle_vin(v_item->'identity'->>'vin') IS DISTINCT FROM public.normalize_vehicle_vin(v_vehicle.vin))
    THEN
      RETURN jsonb_build_object('ok',false,'code','identity_vehicle_mismatch','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    v_instruction:=v_item->>'instruction_id';
    v_vehicle_id:=(v_item->>'vehicle_id')::uuid;
    v_expected_version:=(v_item->>'expected_vehicle_version')::integer;
    v_action_type:=v_item->>'action_type';
    v_payload:=v_item->'payload';
    v_action_key:=public.pdc_email_ai_successor_hash(jsonb_build_object(
      'source_digest',v_source_hash,'receipt_id',v_source_id,
      'vehicle_id',v_vehicle_id,'instruction_id',v_instruction,
      'action_type',v_action_type,'payload',v_payload));
    SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_vehicle_id FOR UPDATE;
    v_before:=CASE WHEN FOUND THEN to_jsonb(v_vehicle) ELSE NULL END;
    v_after:=NULL; v_result:='{}'::jsonb; v_rpc:=NULL; v_expected:=jsonb_build_object('action_type',v_action_type,'payload',v_payload); v_actual:=jsonb_build_object('applied',false); v_verification:=jsonb_build_object('checked',false,'parity',false);
    v_disposition:='BLOCKED_EXACT_REASON'; v_reason:='No canonical action was selected';
    IF NOT FOUND THEN
      v_reason:='vehicle_not_found';
    ELSIF (v_initial_vehicle_versions->>v_vehicle_id::text)::integer<>v_expected_version THEN
      v_reason:='stale_authoritative_vehicle_version_requires_replan';
    ELSIF v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active'
       OR upper(btrim(coalesce(v_vehicle.current_location,''))) IN('RFT','COMPLETED')
       OR v_vehicle.rft_collected_at IS NOT NULL THEN
      v_reason:='vehicle_is_lifecycle_protected';
    ELSIF v_action_type='parts_eta_set' THEN
      v_rpc:='public.update_pdc_parts_eta(uuid,integer,date)';
      PERFORM set_config('pdc_monitor_canonical_action','pdc-email-ai-693',true);
      v_result:=public.update_pdc_parts_eta(v_vehicle.id,v_vehicle.version,(v_payload->>'eta')::date);
      PERFORM set_config('pdc_monitor_canonical_action','',true);
      v_after:=v_result->'vehicle';
      IF coalesce((v_result->>'ok')::boolean,false) THEN
        v_disposition:='APPLIED_AND_VERIFIED'; v_reason:='Canonical Parts ETA RPC returned the updated vehicle';
        v_expected:=jsonb_build_object('parts.eta',v_payload->>'eta'); v_actual:=jsonb_build_object('parts.eta',v_result#>>'{parts_update,worst_eta}');
        v_verification:=jsonb_build_object('checked',true,'parity',v_actual->>'parts.eta' IS NOT DISTINCT FROM v_expected->>'parts.eta');
        IF v_verification->>'parity'='true' THEN v_applied:=v_applied+1; ELSE v_disposition:='FAILED_QUEUED_RETRY'; v_reason:='Canonical Parts ETA response did not prove the requested value'; END IF;
      ELSE v_reason:=coalesce(v_result->>'error','canonical_parts_eta_rejected'); END IF;
    ELSIF v_action_type='parts_complete' AND to_regprocedure('public.mark_pdc_parts_complete(uuid,integer)') IS NOT NULL THEN
      v_rpc:='public.mark_pdc_parts_complete(uuid,integer)';
      PERFORM set_config('pdc_monitor_canonical_action','pdc-email-ai-693',true);
      EXECUTE 'SELECT public.mark_pdc_parts_complete($1,$2)' INTO v_result USING v_vehicle.id,v_vehicle.version;
      PERFORM set_config('pdc_monitor_canonical_action','',true);
      v_after:=v_result->'vehicle';
      IF coalesce((v_result->>'ok')::boolean,false) THEN v_disposition:='APPLIED_AND_VERIFIED';v_reason:='Canonical Parts Complete RPC returned the updated vehicle';v_expected:=jsonb_build_object('parts.complete',true);v_actual:=jsonb_build_object('parts.complete',true);v_verification:=jsonb_build_object('checked',true,'parity',true);v_applied:=v_applied+1; ELSE v_reason:=coalesce(v_result->>'error','canonical_parts_complete_rejected');END IF;
    ELSIF v_action_type='sublet_booking_upsert'
      AND v_payload->>'mode'='update'
      AND to_regprocedure('public.update_pdc_sublet_booking(uuid,bigint,date,date,text)') IS NOT NULL THEN
      v_rpc:='public.update_pdc_sublet_booking(uuid,bigint,date,date,text)';
      EXECUTE 'SELECT public.update_pdc_sublet_booking($1,$2,$3,$4,$5)' INTO v_result
        USING (v_payload->>'booking_id')::uuid,(v_payload->>'expected_booking_version')::bigint,
              (v_payload->>'out_date')::date,(v_payload->>'expected_return_date')::date,NULL;
      v_after:=v_result->'booking';
      IF coalesce((v_result->>'ok')::boolean,false) THEN v_disposition:='APPLIED_AND_VERIFIED';v_reason:='Existing canonical Sublet booking updated';v_expected:=jsonb_build_object('sublet.booking_date',v_payload->>'out_date');v_actual:=jsonb_build_object('sublet.booking_date',v_result#>>'{booking,out_date}');v_verification:=jsonb_build_object('checked',true,'parity',v_actual->>'sublet.booking_date' IS NOT DISTINCT FROM v_expected->>'sublet.booking_date');IF v_verification->>'parity'<>'true' THEN v_disposition:='FAILED_QUEUED_RETRY'; ELSE v_applied:=v_applied+1; END IF; ELSE v_reason:=coalesce(v_result->>'error','canonical_sublet_update_rejected');END IF;
    ELSIF v_action_type='location_set' THEN
      v_reason:='canonical_location_rpc_requires_operator_or_reviewed_monitor_capability';
    ELSIF v_action_type IN('operation_upsert','job_card_upsert') THEN
      v_reason:='canonical_jobcard_attachment_path_requires_bound_pdf_receipt_and_source_row_evidence';
    ELSIF v_action_type IN('workgroup_requirement_set','notes_append') THEN
      v_reason:='canonical_work_requirement_or_notes_rpc_is_not_available_to_successor_identity';
    ELSIF v_action_type IN('rft_transfer','rft_collect') THEN
      v_reason:='canonical_lifecycle_rpc_requires_operator_authority_and_fresh_gate_readback';
    ELSIF v_action_type='activate_from_navision' THEN
      v_reason:='canonical_activation_requires_navision_receipt_link_and_activation-bound source evidence';
    ELSE
      v_reason:='canonical_action_not_supported';
    END IF;
    IF v_disposition='BLOCKED_EXACT_REASON' THEN v_blocked:=v_blocked+1; END IF;
    v_action_dispositions:=array_append(v_action_dispositions,v_disposition);
    INSERT INTO public.pdc_email_ai_successor_action_receipts(
      transaction_id,source_receipt_id,action_key,instruction_id,vehicle_id,action_type,requested,
      disposition,reason,canonical_rpc,before_state,after_state,verification)
    VALUES(v_transaction_id,v_source_id,v_action_key,v_instruction,v_vehicle_id,v_action_type,v_item->'payload',
      v_disposition,v_reason,v_rpc,v_before,v_after,v_verification);
    v_actions:=v_actions||jsonb_build_array(jsonb_build_object(
      'instruction_id',v_instruction,'action_key',v_action_key,'action_type',v_action_type,
      'disposition',v_disposition,'reason',v_reason,'canonical_rpc',v_rpc,'expected',v_expected,'actual',v_actual,
      'before_state',v_before,'after_state',v_after,'verification',v_verification));
  END LOOP;

  v_readback:=public.get_pdc_email_vehicle_location_snapshot();
  v_readback_ok:=coalesce((v_readback->>'ok')::boolean,false);
  IF jsonb_array_length(p_plan->'instructions')=0 THEN v_aggregate:='NO_ACTIONS';
  ELSIF v_blocked=0 AND NOT EXISTS(SELECT 1 FROM unnest(v_action_dispositions) x WHERE x NOT IN('APPLIED_AND_VERIFIED','ALREADY_CORRECT')) THEN v_aggregate:='SUCCESS';
  ELSE v_aggregate:='PARTIAL_FAILURE'; END IF;
  INSERT INTO public.pdc_email_ai_successor_transaction_receipts(
    transaction_id,identity_id,source_receipt_id,source_digest,evidence_digest,plan_hash,typed_plan,
    aggregate_disposition,readback_parity,response)
  VALUES(v_transaction_id,v_identity.identity_id,v_source_id,v_source_hash,v_evidence_hash,v_plan_hash,
    p_plan,v_aggregate,v_readback_ok,jsonb_build_object(
      'transaction_id',v_transaction_id,'source_receipt_id',v_source_id,'source_digest',v_source_hash,
      'evidence_digest',v_evidence_hash,'plan_hash',v_plan_hash,'disposition',v_aggregate,
      'actions',v_actions,'readback',v_readback,'readback_parity',v_readback_ok,
      'transport_release_version',v_identity.transport_release_version,
      'model_version',v_identity.model_version,'prompt_version',v_identity.prompt_version,
      'taxonomy_version',v_identity.taxonomy_version,'rule_version',v_identity.rule_version,
      'action_contract_version',v_identity.action_contract_version,'supabase_action_version',v_identity.action_contract_version,
      'retry_policy',jsonb_build_object('max_attempts',3,'backoff_seconds',ARRAY[1,2,4]),
      'production_writes',false,'mailbox_contacted',false));
  RETURN jsonb_build_object(
    'ok',v_aggregate='SUCCESS' AND v_readback_ok,
    'code',case when v_aggregate='SUCCESS' AND v_readback_ok then 'pdc_email_ai_transaction_verified' else 'pdc_email_ai_transaction_partial_failure' end,
    'disposition',v_aggregate,'actions',v_actions,'readback',v_readback,
    'readback_parity',v_readback_ok,'transaction_id',v_transaction_id,'plan_hash',v_plan_hash,
    'production_writes',false,'mailbox_contacted',false);
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_existing FROM public.pdc_email_ai_successor_transaction_receipts WHERE source_receipt_id=v_source_id;
  IF FOUND THEN RETURN v_existing.response||jsonb_build_object('replay',true); END IF;
  RAISE;
END $apply$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_transaction_successor(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_transaction_successor(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_safe_plan(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public
AS $safe$
DECLARE v_result jsonb:=coalesce(p_plan,'{}'::jsonb);v_items jsonb:='[]'::jsonb;v_item jsonb;v_refs jsonb;v_ref text;
BEGIN
 IF jsonb_typeof(v_result)<>'object' THEN RETURN '{}'::jsonb; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(coalesce(v_result->'instructions','[]'::jsonb)) LOOP
  v_refs:='[]'::jsonb;
  FOR v_ref IN SELECT value FROM jsonb_array_elements_text(coalesce(v_item->'evidence_refs','[]'::jsonb)) LOOP
   v_refs:=v_refs||jsonb_build_array(case when v_ref ~ '^(correspondence|attachment)-digest:[a-f0-9]{64}$' then v_ref else 'legacy-evidence-reference' end);
  END LOOP;
  v_items:=v_items||jsonb_build_array((v_item-'evidence_refs')||jsonb_build_object('evidence_refs',v_refs));
 END LOOP;
 RETURN jsonb_set(v_result,'{instructions}',v_items,true);
END $safe$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_safe_plan(jsonb) FROM public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(
  p_cursor jsonb DEFAULT NULL,
  p_page_size integer DEFAULT 100
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $inbox$
DECLARE
  v_role text:=public.current_pdc_user_role()::text;
  v_limit integer:=greatest(1,least(coalesce(p_page_size,100),250));
  v_revision bigint;
  v_items jsonb;
  v_snapshot jsonb;
  v_next_cursor jsonb;
  v_cursor_sort_time timestamptz;
  v_cursor_created_at timestamptz;
  v_cursor_id uuid;
  v_has_more boolean:=false;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR auth.role()<>'authenticated'
     OR auth.uid() IS NULL
     OR v_role NOT IN('viewer','operator','importer','administrator')
  THEN
    RETURN jsonb_build_object('ok',false,'code','successor_inbox_unauthorized','items','[]'::jsonb);
  END IF;
  IF p_cursor IS NOT NULL THEN
    IF jsonb_typeof(p_cursor)<>'object'
       OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_cursor) k) IS DISTINCT FROM ARRAY['created_at','id','sort_time']::text[]
       OR (p_cursor->>'sort_time') !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
       OR (p_cursor->>'created_at') !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
       OR (p_cursor->>'id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    THEN RETURN jsonb_build_object('ok',false,'code','invalid_successor_inbox_cursor','items','[]'::jsonb); END IF;
    v_cursor_sort_time:=(p_cursor->>'sort_time')::timestamptz;
    v_cursor_created_at:=(p_cursor->>'created_at')::timestamptz;
    v_cursor_id:=(p_cursor->>'id')::uuid;
  END IF;
  SELECT revision INTO v_revision FROM public.pdc_email_ai_successor_ui_revision WHERE singleton;
  v_snapshot:=public.get_pdc_email_vehicle_location_snapshot();
  WITH snapshot_vehicles AS (
    SELECT
      (v->>'id')::uuid AS vehicle_id,
      v->>'stock_number' AS stock_number,
      v->>'vehicle_description' AS vehicle_description,
      v->>'current_location' AS current_location,
      v->>'version' AS vehicle_version
    FROM jsonb_array_elements(coalesce(v_snapshot#>'{data,vehicles}','[]'::jsonb)) v
    WHERE (v->>'id') IS NOT NULL
  ),
  selected AS (
    SELECT i.*, row_number() OVER (ORDER BY coalesce(i.received_at,i.created_at) DESC, i.created_at DESC, i.id DESC) AS row_no,
      coalesce(i.received_at,i.created_at) AS sort_time
    FROM public.ai_email_intake i
    WHERE p_cursor IS NULL OR coalesce(i.received_at,i.created_at)<v_cursor_sort_time OR (coalesce(i.received_at,i.created_at)=v_cursor_sort_time AND (i.created_at<v_cursor_created_at OR (i.created_at=v_cursor_created_at AND i.id<v_cursor_id)))
    ORDER BY coalesce(i.received_at,i.created_at) DESC, i.created_at DESC, i.id DESC
    LIMIT v_limit+1
  ),
  bounded AS (SELECT * FROM selected WHERE row_no<=v_limit),
  parent_rows AS (
    SELECT b.*,
      t.transaction_id,t.source_digest AS transaction_source_digest,t.evidence_digest AS transaction_evidence_digest,
      t.plan_hash,t.typed_plan,t.aggregate_disposition,t.readback_parity,t.response,
      coalesce(att.attachments,'[]'::jsonb) AS attachment_summary,
      jsonb_build_object('job_card_number',left(coalesce(b.extracted_data->>'job_card_number',''),80),'operation_count',case when jsonb_typeof(b.extracted_data->'operation_lines')='array' then jsonb_array_length(b.extracted_data->'operation_lines') else 0 end,'extraction_status',case when b.extracted_data='{}'::jsonb then 'not_extracted' else 'available' end) AS job_card_summary,
      coalesce(vr.vehicle_results,'[]'::jsonb) AS vehicle_results
    FROM bounded b
    LEFT JOIN public.pdc_email_ai_successor_transaction_receipts t ON t.source_receipt_id=b.id
    LEFT JOIN LATERAL (
      SELECT jsonb_build_object(
        'count',count(*)::integer,
        'names',coalesce(jsonb_agg(a.file_name ORDER BY a.created_at,a.id),'[]'::jsonb),
        'digests',coalesce(jsonb_agg(a.source_hash ORDER BY a.created_at,a.id) FILTER (WHERE a.source_hash IS NOT NULL),'[]'::jsonb)
      ) AS attachments
      FROM public.ai_email_attachments a WHERE a.intake_id=b.id
    ) att ON true
    LEFT JOIN LATERAL (
      SELECT jsonb_agg(jsonb_build_object(
        'vehicle_id',groups.vehicle_id,
        'stock',coalesce(sv.stock_number,'Unresolved stock'),
        'vehicle',coalesce(sv.vehicle_description,'Vehicle identity unavailable'),
        'location',coalesce(sv.current_location,'—'),
        'identity_status',case when sv.vehicle_id IS NULL then 'UNRESOLVED' else 'MATCHED' end,
        'actions',groups.actions,
        'readback',coalesce((t.response->'readback'),null)
      ) ORDER BY coalesce(sv.stock_number,''),groups.vehicle_id) AS vehicle_results
      FROM (
        SELECT a.vehicle_id,
          jsonb_agg(jsonb_build_object(
            'action_type',a.action_type,
            'instruction_id',a.instruction_id,
            'canonical_rpc',a.canonical_rpc,
            'disposition',a.disposition,
            'reason',a.reason,
            'before',a.before_state,
            'requested',a.requested,
            'result',a.after_state,
            'expected',coalesce(response_action.action->'expected','null'::jsonb),
            'actual',coalesce(response_action.action->'actual','null'::jsonb),
            'verification',a.verification,
            'evidence_refs',coalesce(plan_instruction.instruction->'evidence_refs','[]'::jsonb),
            'action_receipt_id',a.action_receipt_id,
            'action_key',a.action_key
          ) ORDER BY a.created_at,a.action_receipt_id) AS actions
        FROM public.pdc_email_ai_successor_action_receipts a
        LEFT JOIN LATERAL (
          SELECT x AS action FROM jsonb_array_elements(coalesce(t.response->'actions','[]'::jsonb)) x
          WHERE x->>'action_key'=a.action_key LIMIT 1
        ) response_action ON true
        LEFT JOIN LATERAL (
          SELECT x AS instruction FROM jsonb_array_elements(coalesce(t.typed_plan->'instructions','[]'::jsonb)) x
          WHERE x->>'instruction_id'=a.instruction_id LIMIT 1
        ) plan_instruction ON true
        WHERE a.transaction_id=t.transaction_id
        GROUP BY a.vehicle_id
      ) groups
      LEFT JOIN snapshot_vehicles sv ON sv.vehicle_id=groups.vehicle_id
    ) vr ON true
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'intake_id',p.id,
    'source_receipt_id',p.id,
    'intake_uid',coalesce(nullif(p.provider_uid,''),nullif(p.graph_message_id,''),p.id::text),
    'provider_uid',p.provider_uid,
    'message_id',coalesce(p.internet_message_id,p.graph_message_id),
    'thread_id',p.graph_thread_id,
    'received_at',coalesce(p.received_at,p.created_at),
    'sender',coalesce(p.sender_email,'Unknown sender'),
    'subject',coalesce(p.subject,'Email received'),
    'attachment_summary',p.attachment_summary,
    'job_card_summary',p.job_card_summary,
    'disposition',coalesce(p.aggregate_disposition::text,case when p.permanent_failure then 'QUARANTINED' else 'RECEIVED_WAITING' end),
    'verification_status',case when p.aggregate_disposition='SUCCESS' and p.readback_parity then 'PASS' when p.aggregate_disposition IS NOT NULL then 'PARTIAL' else 'NOT_RUN' end,
    'summary',jsonb_build_object(
      'before',case when jsonb_array_length(p.vehicle_results)>0 then jsonb_array_length(p.vehicle_results)::text||' vehicle result(s)' else 'No successor result yet' end,
      'requested',case when p.transaction_id IS NULL then 'Awaiting typed plan' else coalesce(jsonb_array_length(p.response->'actions')::text,'0')||' typed action(s)' end,
      'result',coalesce(p.aggregate_disposition::text,'Awaiting successor processing')
    ),
    'transaction',case when p.transaction_id IS NULL then null else jsonb_build_object(
      'transaction_id',p.transaction_id,
      'source_receipt_id',p.id,
      'source_digest',p.transaction_source_digest,
      'evidence_digest',p.transaction_evidence_digest,
      'plan_hash',p.plan_hash,
      'disposition',p.aggregate_disposition,
      'typed_plan',public.pdc_email_ai_successor_safe_plan(p.typed_plan),
      'versions',jsonb_build_object(
        'model',p.response->>'model_version',
        'prompt',p.response->>'prompt_version',
        'instruction_set',p.response->>'action_contract_version',
        'taxonomy',p.response->>'taxonomy_version',
        'rules',p.response->>'rule_version',
        'action_contract',p.response->>'action_contract_version',
        'supabase_action',p.response->>'supabase_action_version',
        'transport',p.response->>'transport_release_version'
      ),
      'readback',p.response->'readback',
      'readback_parity',p.readback_parity,
      'response',jsonb_build_object('actions',p.response->'actions','readback_parity',p.response->'readback_parity')
    ) end,
    'vehicle_results',p.vehicle_results,
    'retry_state',jsonb_build_object(
      'attempts',coalesce(p.queue_attempts,0),
      'retry_class',p.retry_class,
      'next_attempt_at',p.next_attempt_at,
      'last_error_code',p.last_error_code,
      'quarantine',coalesce(p.permanent_failure,false)
    ),
    'quarantine',case when p.permanent_failure then jsonb_build_object('quarantined',true,'reason',p.last_error_code,'retry_class',p.retry_class) else null end
  ) ORDER BY p.sort_time DESC,p.created_at DESC,p.id DESC),'[]'::jsonb),
  (SELECT jsonb_build_object('sort_time',q.sort_time,'created_at',q.created_at,'id',q.id) FROM parent_rows q WHERE q.row_no=v_limit LIMIT 1),
  (SELECT count(*) FROM selected)>v_limit
  INTO v_items,v_next_cursor,v_has_more
  FROM parent_rows p;
  RETURN jsonb_build_object('ok',true,'code','successor_inbox_snapshot','revision',coalesce(v_revision,1),
    'has_more',v_has_more,'next_cursor',v_next_cursor,'items',v_items);
END $inbox$;
REVOKE ALL ON FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260831340000','pdc_email_ai_successor_command_read_hardening',ARRAY[
 'Typed identity Stock/VIN is compared with the locked canonical vehicle before any canonical call',
 'Confirmation-bearing actions require payload confirmed=true at the database boundary',
 'Safe plan projection replaces legacy body-bearing evidence refs with stable digest/redacted references',
 'Composite cursor v2 orders by sort time, created time and UUID without timestamp tie omission',
 'All source rows without a successor receipt remain RECEIVED_WAITING; metadata and Job Card extraction summary are visible',
 'Production sentinel rejected; direct DML, service-role execution, mailbox and outbound email remain unavailable'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
