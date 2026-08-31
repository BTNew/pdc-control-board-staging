-- STAGING ONLY: simplified PDC Email AI transaction successor.
-- This migration is append-only, receipt-first, and independent of the current
-- Email Monitor repair runtime. The runtime receives one typed plan only.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-email-ai-transaction-successor-20260831260000',0));

DO $guard$
BEGIN
  IF current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260831240000'
           AND name='858_runtime_authority_839_scope_compatibility_successor')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260831260000')
  THEN RAISE EXCEPTION 'PDC_EMAIL_AI_SUCCESSOR_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
  IF to_regclass('public.ai_email_intake') IS NULL
     OR to_regclass('public.vehicles') IS NULL
     OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') IS NULL
     OR to_regprocedure('public.update_pdc_parts_eta(uuid,integer,date)') IS NULL
     OR to_regprocedure('public.pdc_monitor_staging_guard()') IS NULL
  THEN RAISE EXCEPTION 'PDC_EMAIL_AI_SUCCESSOR_DEPENDENCY_MISSING' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_successor_runtime_identities (
  identity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,
  normalized_email text NOT NULL UNIQUE CHECK(normalized_email=lower(btrim(normalized_email))),
  environment text NOT NULL CHECK(environment='staging'),
  identity_purpose text NOT NULL CHECK(identity_purpose='pdc_email_ai_transaction_successor'),
  gateway_instance_id text NOT NULL CHECK(length(gateway_instance_id) BETWEEN 3 AND 160),
  transport_release_version text NOT NULL CHECK(length(transport_release_version) BETWEEN 1 AND 160),
  model_version text NOT NULL CHECK(length(model_version) BETWEEN 1 AND 160),
  prompt_version text NOT NULL CHECK(length(prompt_version) BETWEEN 1 AND 160),
  taxonomy_version text NOT NULL CHECK(length(taxonomy_version) BETWEEN 1 AND 160),
  rule_version text NOT NULL CHECK(length(rule_version) BETWEEN 1 AND 160),
  action_contract_version text NOT NULL CHECK(action_contract_version='pdc-email-ai-actions-v1'),
  active boolean NOT NULL DEFAULT true,
  approved_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at timestamptz,
  CHECK((active AND revoked_at IS NULL) OR (NOT active AND revoked_at IS NOT NULL))
);

CREATE TABLE public.pdc_email_ai_successor_transaction_receipts (
  transaction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  identity_id uuid NOT NULL REFERENCES public.pdc_email_ai_successor_runtime_identities(identity_id) ON DELETE RESTRICT,
  source_receipt_id uuid NOT NULL UNIQUE REFERENCES public.ai_email_intake(id) ON DELETE RESTRICT,
  source_digest text NOT NULL UNIQUE CHECK(source_digest ~ '^[a-f0-9]{64}$'),
  evidence_digest text NOT NULL CHECK(evidence_digest ~ '^[a-f0-9]{64}$'),
  plan_hash text NOT NULL UNIQUE CHECK(plan_hash ~ '^[a-f0-9]{64}$'),
  aggregate_disposition text NOT NULL CHECK(aggregate_disposition IN('SUCCESS','PARTIAL_FAILURE','NO_ACTIONS')),
  readback_parity boolean NOT NULL,
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.pdc_email_ai_successor_action_receipts (
  action_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id uuid NOT NULL REFERENCES public.pdc_email_ai_successor_transaction_receipts(transaction_id) ON DELETE RESTRICT,
  source_receipt_id uuid NOT NULL REFERENCES public.ai_email_intake(id) ON DELETE RESTRICT,
  action_key text NOT NULL CHECK(action_key ~ '^[a-f0-9]{64}$'),
  instruction_id text NOT NULL CHECK(length(instruction_id) BETWEEN 1 AND 160),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  action_type text NOT NULL CHECK(action_type IN(
    'activate_from_navision','location_set','workgroup_requirement_set','operation_upsert',
    'parts_eta_set','parts_ordered','parts_complete','notes_append','job_card_upsert',
    'sublet_booking_upsert','rft_transfer','rft_collect')),
  requested jsonb NOT NULL CHECK(jsonb_typeof(requested)='object'),
  disposition text NOT NULL CHECK(disposition IN(
    'APPLIED_AND_VERIFIED','ALREADY_CORRECT','SUPERSEDED','NOT_APPLICABLE',
    'BLOCKED_EXACT_REASON','GENUINELY_AMBIGUOUS','FAILED_QUEUED_RETRY')),
  reason text NOT NULL CHECK(length(reason) BETWEEN 1 AND 1000),
  canonical_rpc text,
  before_state jsonb,
  after_state jsonb,
  verification jsonb NOT NULL CHECK(jsonb_typeof(verification)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(source_receipt_id,action_key),
  UNIQUE(transaction_id,instruction_id)
);

ALTER TABLE public.pdc_email_ai_successor_runtime_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_runtime_identities FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_transaction_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_transaction_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_action_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_action_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_successor_runtime_identities FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_email_ai_successor_transaction_receipts FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_email_ai_successor_action_receipts FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_email_ai_successor_receipt_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RAISE EXCEPTION 'PDC_EMAIL_AI_SUCCESSOR_RECEIPT_IMMUTABLE' USING errcode='55000';
END $$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_receipt_immutable() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_successor_transaction_receipt_immutable
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_successor_transaction_receipts
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_successor_receipt_immutable();
CREATE TRIGGER pdc_email_ai_successor_action_receipt_immutable
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_successor_action_receipts
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_successor_receipt_immutable();

CREATE FUNCTION public.pdc_email_ai_successor_hash(p_value jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,extensions AS $$
  SELECT encode(extensions.digest(convert_to(coalesce(p_value,'null'::jsonb)::text,'UTF8'),'sha256'),'hex')
$$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_hash(jsonb) FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.apply_pdc_email_ai_transaction_successor(p_plan jsonb)
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
     OR jsonb_typeof(p_plan->'versions')<>'object'
     OR jsonb_typeof(p_plan->'instructions')<>'array'
     OR jsonb_array_length(p_plan->'instructions')>200
     OR v_source_hash !~ '^[a-f0-9]{64}$'
     OR v_evidence_hash !~ '^[a-f0-9]{64}$'
     OR (p_plan->'source'->>'receipt_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
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
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','source_receipt_digest_not_found','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;

  -- Validate every instruction and its identity before the first canonical call.
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
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
    v_after:=NULL; v_result:='{}'::jsonb; v_rpc:=NULL; v_verification:=jsonb_build_object('checked',false,'parity',false);
    v_disposition:='BLOCKED_EXACT_REASON'; v_reason:='No canonical action was selected';
    IF NOT FOUND THEN
      v_reason:='vehicle_not_found';
    ELSIF v_vehicle.version<>v_expected_version THEN
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
        v_verification:=jsonb_build_object('checked',true,'expected',v_payload->>'eta','actual',v_result#>>'{parts_update,worst_eta}');
        IF v_verification->>'expected' IS NOT DISTINCT FROM v_verification->>'actual' THEN v_applied:=v_applied+1; ELSE v_disposition:='FAILED_QUEUED_RETRY'; v_reason:='Canonical Parts ETA response did not prove the requested value'; END IF;
      ELSE v_reason:=coalesce(v_result->>'error','canonical_parts_eta_rejected'); END IF;
    ELSIF v_action_type='parts_complete' AND to_regprocedure('public.mark_pdc_parts_complete(uuid,integer)') IS NOT NULL THEN
      v_rpc:='public.mark_pdc_parts_complete(uuid,integer)';
      PERFORM set_config('pdc_monitor_canonical_action','pdc-email-ai-693',true);
      EXECUTE 'SELECT public.mark_pdc_parts_complete($1,$2)' INTO v_result USING v_vehicle.id,v_vehicle.version;
      PERFORM set_config('pdc_monitor_canonical_action','',true);
      v_after:=v_result->'vehicle';
      IF coalesce((v_result->>'ok')::boolean,false) THEN v_disposition:='APPLIED_AND_VERIFIED';v_reason:='Canonical Parts Complete RPC returned the updated vehicle';v_applied:=v_applied+1; ELSE v_reason:=coalesce(v_result->>'error','canonical_parts_complete_rejected');END IF;
    ELSIF v_action_type='sublet_booking_upsert'
      AND v_payload->>'mode'='update'
      AND to_regprocedure('public.update_pdc_sublet_booking(uuid,bigint,date,date,text)') IS NOT NULL THEN
      v_rpc:='public.update_pdc_sublet_booking(uuid,bigint,date,date,text)';
      EXECUTE 'SELECT public.update_pdc_sublet_booking($1,$2,$3,$4,$5)' INTO v_result
        USING (v_payload->>'booking_id')::uuid,(v_payload->>'expected_booking_version')::bigint,
              (v_payload->>'out_date')::date,(v_payload->>'expected_return_date')::date,NULL;
      v_after:=v_result->'booking';
      IF coalesce((v_result->>'ok')::boolean,false) THEN v_disposition:='APPLIED_AND_VERIFIED';v_reason:='Existing canonical Sublet booking updated';v_applied:=v_applied+1; ELSE v_reason:=coalesce(v_result->>'error','canonical_sublet_update_rejected');END IF;
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
      'disposition',v_disposition,'reason',v_reason,'canonical_rpc',v_rpc,
      'before_state',v_before,'after_state',v_after,'verification',v_verification));
  END LOOP;

  v_readback:=public.get_pdc_email_vehicle_location_snapshot();
  v_readback_ok:=coalesce((v_readback->>'ok')::boolean,false);
  IF jsonb_array_length(p_plan->'instructions')=0 THEN v_aggregate:='NO_ACTIONS';
  ELSIF v_blocked=0 AND NOT EXISTS(SELECT 1 FROM unnest(v_action_dispositions) x WHERE x NOT IN('APPLIED_AND_VERIFIED','ALREADY_CORRECT')) THEN v_aggregate:='SUCCESS';
  ELSE v_aggregate:='PARTIAL_FAILURE'; END IF;
  INSERT INTO public.pdc_email_ai_successor_transaction_receipts(
    transaction_id,identity_id,source_receipt_id,source_digest,evidence_digest,plan_hash,
    aggregate_disposition,readback_parity,response)
  VALUES(v_transaction_id,v_identity.identity_id,v_source_id,v_source_hash,v_evidence_hash,v_plan_hash,
    v_aggregate,v_readback_ok,jsonb_build_object(
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

CREATE FUNCTION public.get_pdc_email_ai_successor_health()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $health$
DECLARE v_role text:=public.current_pdc_user_role()::text;
BEGIN
  IF v_role NOT IN('viewer','operator','importer','administrator') THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'code','pdc_email_ai_successor_health',
    'active_runtime_identities',(SELECT count(*) FROM public.pdc_email_ai_successor_runtime_identities WHERE active),
    'transactions',(SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts),
    'partial_failures',(SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts WHERE aggregate_disposition='PARTIAL_FAILURE'),
    'pending_or_blocked_actions',(SELECT count(*) FROM public.pdc_email_ai_successor_action_receipts WHERE disposition IN('BLOCKED_EXACT_REASON','FAILED_QUEUED_RETRY','GENUINELY_AMBIGUOUS')),
    'live_lane_continues',true,'historical_lane_isolated',true,'production_writes',false,
    'outbound_email',false,'transport_release_is_separate',true);
END $health$;
REVOKE ALL ON FUNCTION public.get_pdc_email_ai_successor_health() FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_successor_health() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260831260000','pdc_email_ai_transaction_successor',ARRAY[
  'Exact STAGING sentinel and 858 predecessor guard; Production sentinel rejected; current Email Monitor repair runtime is not modified',
  'Immutable source-linked transaction and per-action receipts with stable source/digest/vehicle/action/payload idempotency keys',
  'Dedicated authenticated successor identity only; no service_role, Administrator, direct table, browser or arbitrary SQL authority',
  'One typed plan RPC validates the complete plan before fixed canonical action dispatch and returns complete action dispositions',
  'Canonical Parts ETA, Parts Complete and existing Sublet booking update are the only currently available successor dispatches',
  'Location, Job Card, operation, workgroup, notes and RFT/Collected actions return exact typed blockers when reviewed capability is absent',
  'Authoritative Board snapshot readback is returned separately; HTTP success or UI appearance is never sufficient',
  'Transport, model, prompt, taxonomy, rule and Supabase action versions are recorded independently; historical lane is isolated'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
