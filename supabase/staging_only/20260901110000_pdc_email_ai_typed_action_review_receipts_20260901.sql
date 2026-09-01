-- STAGING ONLY 20260901110000: preserve typed review dispositions at the
-- authenticated v2 boundary. Appends to 1000; no operational action is invoked
-- for review, unsupported or conflict evidence, including unresolved evidence.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901110000-typed-action-review-receipts',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901100000' AND name='pdc_email_ai_typed_action_strict_wrapper_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901110000')
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901110000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- Non-planned evidence is durably receipted without entering the compatibility
-- projection. This function is reachable only from the strict wrapper and keeps
-- unresolved review evidence nullable rather than inventing a vehicle binding.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $non_dispatch$
DECLARE
  actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  ident public.pdc_email_ai_successor_runtime_identities%rowtype;
  source_id uuid:=(p_plan->>'source_receipt_id')::uuid;
  source_hash text:=lower(p_plan->>'source_digest'); evidence_hash text:=lower(p_plan->>'evidence_digest');
  plan_hash text:=public.pdc_email_ai_successor_hash(p_plan);
  tx uuid:=gen_random_uuid(); item jsonb; item_vehicle_id uuid; before_state jsonb;
  action_key text; action_receipt uuid; actions jsonb:='[]'::jsonb; dispositions text[]:='{}'::text[];
  decision text; disposition text; reason text; unresolved boolean; verification jsonb; response jsonb;
  existing public.pdc_email_ai_successor_transaction_receipts%rowtype; aggregate text;
BEGIN
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard()
     OR auth.role()<>'authenticated' OR actor IS NULL OR email='' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  SELECT * INTO ident FROM public.pdc_email_ai_successor_runtime_identities
   WHERE auth_user_id=actor AND normalized_email=email AND environment='staging'
     AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL FOR SHARE;
  IF NOT FOUND OR EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=actor AND active AND account_status='approved' AND role::text='administrator') THEN
    RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-email-ai-typed-source:'||source_hash,0));
  SELECT * INTO existing FROM public.pdc_email_ai_successor_transaction_receipts WHERE source_receipt_id=source_id;
  IF FOUND THEN
    IF existing.source_digest<>source_hash OR existing.plan_hash<>plan_hash THEN
      RETURN jsonb_build_object('ok',false,'code','source_reuse_conflict','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    RETURN existing.response||jsonb_build_object('replay',true);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=source_id
      AND lower(coalesce(i.source_hash,''))=source_hash AND i.duplicate_of IS NULL
      AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->>'source_message_id')
      AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->>'source_thread_id')
      AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=evidence_hash) THEN
    RETURN jsonb_build_object('ok',false,'code','source_receipt_digest_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    decision:=item->>'decision_disposition';
    unresolved:=item->'identity'->>'stock_number' IS NULL
      AND item->'identity'->>'vin' IS NULL AND item->'identity'->>'backend_record_id' IS NULL;
    item_vehicle_id:=NULL; before_state:=NULL;
    IF NOT unresolved THEN
      item_vehicle_id:=(item->>'vehicle_id')::uuid;
      SELECT to_jsonb(v) INTO before_state FROM public.vehicles v WHERE v.id=item_vehicle_id;
    END IF;
    action_key:=public.pdc_email_ai_successor_hash(jsonb_build_object(
      'source_digest',source_hash,'receipt_id',source_id,'vehicle_id',item->>'vehicle_id',
      'instruction_id',item->>'instruction_id','action_type',item->>'action_type','payload',item->'payload'));
    disposition:=CASE WHEN decision='review' THEN 'GENUINELY_AMBIGUOUS' ELSE 'BLOCKED_EXACT_REASON' END;
    reason:=coalesce(nullif(item->>'reason',''),CASE WHEN decision='review' THEN 'typed review evidence requires human resolution' ELSE 'typed evidence is not dispatchable' END);
    IF decision='planned' THEN
      disposition:='FAILED_QUEUED_RETRY'; reason:='mixed_plan_contains_non_planned_instruction';
    END IF;
    verification:=jsonb_build_object(
      'checked',true,'parity',false,'dispatch',false,'action_rpc_invoked',false,
      'decision_disposition',decision,'unresolved_review_evidence',unresolved,
      'scope','strict_v2_non_dispatch');
    INSERT INTO public.pdc_email_ai_successor_action_receipts(
      transaction_id,source_receipt_id,action_key,instruction_id,vehicle_id,action_type,requested,
      disposition,reason,canonical_rpc,before_state,after_state,verification,taxonomy_version,taxonomy_disposition)
    VALUES(tx,source_id,action_key,item->>'instruction_id',item_vehicle_id,item->>'action_type',item->'payload',
      disposition,reason,NULL,before_state,NULL,verification,p_plan->'versions'->>'taxonomy_version',item->'payload'->>'taxonomy_disposition')
    RETURNING action_receipt_id INTO action_receipt;
    PERFORM public.audit_pdc_event('update'::public.audit_action,'pdc_email_ai_successor_action_receipts',action_receipt,item_vehicle_id,before_state,NULL,
      jsonb_build_object('source','pdc_email_ai_typed_action_surface_20260901','successor_version','20260901110000',
        'action_key',action_key,'action_type',item->>'action_type','decision_disposition',decision,
        'disposition',disposition,'canonical_rpc',NULL,'action_rpc_invoked',false));
    actions:=actions||jsonb_build_array(jsonb_build_object(
      'instruction_id',item->>'instruction_id','action_key',action_key,'action_type',item->>'action_type',
      'decision_disposition',decision,'disposition',disposition,'reason',reason,'canonical_rpc',NULL,
      'requested',item->'payload','before_state',before_state,'after_state',NULL,'verification',verification,
      'action_receipt_id',action_receipt,'taxonomy_version',p_plan->'versions'->>'taxonomy_version',
      'taxonomy_disposition',item->'payload'->>'taxonomy_disposition'));
    dispositions:=array_append(dispositions,disposition);
  END LOOP;
  aggregate:=CASE WHEN cardinality(dispositions)=0 THEN 'NO_ACTIONS' ELSE 'PARTIAL_FAILURE' END;
  response:=jsonb_build_object(
    'ok',false,'code','pdc_email_ai_typed_action_non_dispatch_receipt','disposition',aggregate,
    'actions',actions,'readback',jsonb_build_object('checked',false,'parity',false,'scope','non_dispatch'),
    'readback_parity',false,'transaction_id',tx,'action_rpc_invoked',false,
    'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
  INSERT INTO public.pdc_email_ai_successor_transaction_receipts(
    transaction_id,identity_id,source_receipt_id,source_digest,evidence_digest,plan_hash,typed_plan,
    aggregate_disposition,readback_parity,response)
  VALUES(tx,ident.identity_id,source_id,source_hash,evidence_hash,plan_hash,p_plan,aggregate,false,response);
  RETURN response;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO existing FROM public.pdc_email_ai_successor_transaction_receipts WHERE source_receipt_id=source_id;
  IF FOUND THEN RETURN existing.response||jsonb_build_object('replay',true); END IF;
  RAISE;
END $non_dispatch$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb) FROM public,anon,authenticated,service_role;

-- Rebind the strict wrapper. Validation still runs first; any review,
-- unsupported or conflict disposition is receipted before normalized_items is
-- constructed, so no non-planned row can reach the canonical compatibility path.
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $strict$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); identity_ok boolean; x jsonb; normalized jsonb; normalized_items jsonb;
BEGIN
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard() OR auth.role()<>'authenticated' OR actor IS NULL OR email='' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  SELECT EXISTS(
    SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities
    WHERE auth_user_id=actor AND normalized_email=email AND environment='staging'
      AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL
  ) AND NOT EXISTS(
    SELECT 1 FROM public.pdc_user_roles
    WHERE auth_user_id=actor AND active AND account_status='approved' AND role::text='administrator'
  ) INTO identity_ok;
  IF NOT identity_ok THEN
    RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  IF NOT public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan) THEN
    RETURN jsonb_build_object('ok',false,'code','typed_v2_plan_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  -- Preserve every decision_disposition in the durable non-dispatch receipt;
  -- this branch is before source lookup and before normalized_items projection.
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'decision_disposition'<>'planned') THEN
    RETURN public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(p_plan);
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'action_type'='operation_update') THEN
    IF (SELECT count(*) FROM jsonb_array_elements(p_plan->'instructions'))<>1 THEN
      RETURN jsonb_build_object('ok',false,'code','operation_update_mixed_plan_requires_replan','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    RETURN public.apply_pdc_email_ai_operation_update_transaction_20260901(p_plan);
  END IF;
  -- Only planned rows reach this retained compatibility projection.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'instruction_id',x->>'instruction_id',
    'vehicle_id',x->>'vehicle_id',
    'identity',jsonb_build_object(
      'stock_number',x->'identity'->'stock_number',
      'vin',x->'identity'->'vin',
      'backend_record_id',x->'identity'->'backend_record_id'
    ),
    'expected_vehicle_version',(x->'expected_state'->>'vehicle_version')::integer,
    'action_type',x->>'action_type',
    'payload',x->'payload',
    'evidence_refs',coalesce((SELECT jsonb_agg(r->>'ref') FROM jsonb_array_elements(x->'evidence_refs') r),'[]'::jsonb)
  ) ORDER BY x->>'instruction_id'),'[]'::jsonb)
  INTO normalized_items
  FROM jsonb_array_elements(p_plan->'instructions') q(x);
  normalized:=jsonb_build_object(
    'schema_version','pdc-email-ai-plan-v1',
    'source',jsonb_build_object(
      'receipt_id',p_plan->>'source_receipt_id',
      'source_digest',p_plan->>'source_digest',
      'evidence_digest',p_plan->>'evidence_digest',
      'thread_id',p_plan->>'source_thread_id',
      'message_id',p_plan->>'source_message_id',
      'attachment_digests',p_plan->'attachment_digests'
    ),
    'versions',jsonb_build_object('action_contract','pdc-email-ai-actions-v2','taxonomy',p_plan->'versions'->>'taxonomy_version'),
    'instructions',normalized_items
  );
  RETURN public.apply_pdc_email_ai_typed_action_surface_20260901(normalized);
END $strict$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,service_role;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901110000','pdc_email_ai_typed_action_review_receipts_20260901',ARRAY[
 'Strict v2 validation preserves decision_disposition before any compatibility projection',
 'Review, unsupported and conflict evidence is stored as immutable typed non-dispatch action receipts with canonical_rpc NULL and action_rpc_invoked false',
 'Unresolved review evidence keeps nullable vehicle_id and is receipted as GENUINELY_AMBIGUOUS without a vehicle lookup or canonical RPC',
 'Only all-planned instructions reach the retained compatibility executor; mixed plans fail closed as typed evidence',
 'Authenticated-only strict ACL, staging guard, append-only receipts, Production and mailbox boundaries remain unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
