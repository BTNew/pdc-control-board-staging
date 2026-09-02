-- STAGING-only append-only repair for immutable successful v2 plan replay.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260902274000-v2-exact-success-replay',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260902273000' AND name='navision_yh_location_authority_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260902274000')
     OR to_regclass('public.pdc_email_ai_successor_transaction_receipts') IS NULL
     OR to_regclass('public.pdc_email_ai_successor_action_receipts') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260902274000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_v2_exact_success_replay_history_20260903(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL,
  successor_head text NOT NULL,
  function_hashes_before jsonb NOT NULL,
  function_hashes_after jsonb NOT NULL,
  contract text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL DEFAULT false CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_v2_exact_success_replay_history_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_v2_exact_success_replay_history_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_v2_exact_success_replay_history_20260903 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_email_ai_v2_exact_success_replay_history_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_EMAIL_AI_V2_EXACT_SUCCESS_REPLAY_HISTORY_IMMUTABLE' USING errcode='55000';
END $immutable$;
CREATE TRIGGER pdc_email_ai_v2_exact_success_replay_history_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_v2_exact_success_replay_history_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_exact_success_replay_history_immutable_20260903();
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_exact_success_replay_history_immutable_20260903() FROM public,anon,authenticated,service_role;

-- This helper has no runtime grant. The identity-gated strict wrapper calls it
-- before current-schema validation solely to recognize an immutable exact replay.
CREATE FUNCTION public.pdc_email_ai_successor_exact_success_replay_20260903(
  p_plan jsonb,
  p_actor uuid,
  p_email text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path=pg_catalog,public,auth,extensions AS $replay$
DECLARE
  v_identity public.pdc_email_ai_successor_runtime_identities%rowtype;
  v_existing public.pdc_email_ai_successor_transaction_receipts%rowtype;
  v_matches integer:=0;
  v_action_receipt_ids jsonb:='[]'::jsonb;
BEGIN
  IF jsonb_typeof(p_plan)<>'object'
     OR p_actor IS NULL OR nullif(lower(btrim(p_email)),'') IS NULL
     OR coalesce(p_plan->>'source_receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR coalesce(p_plan->>'source_digest','') !~ '^[a-f0-9]{64}$'
     OR coalesce(p_plan->>'evidence_digest','') !~ '^[a-f0-9]{64}$'
  THEN RETURN NULL; END IF;

  SELECT * INTO v_identity
  FROM public.pdc_email_ai_successor_runtime_identities
  WHERE auth_user_id=p_actor AND normalized_email=lower(btrim(p_email))
    AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor'
    AND active AND revoked_at IS NULL;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT count(*) INTO v_matches
  FROM public.pdc_email_ai_successor_transaction_receipts t
  WHERE t.identity_id=v_identity.identity_id
    AND t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid
    AND t.source_digest=lower(p_plan->>'source_digest')
    AND t.evidence_digest=lower(p_plan->>'evidence_digest')
    AND t.aggregate_disposition::text='SUCCESS'
    AND t.readback_parity
    AND t.plan_hash=public.pdc_email_ai_successor_hash(p_plan)
    AND t.typed_plan=p_plan
    AND EXISTS(
      SELECT 1 FROM public.ai_email_intake i
      WHERE i.id=t.source_receipt_id AND i.duplicate_of IS NULL
        AND lower(coalesce(i.source_hash,''))=t.source_digest
        AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=t.evidence_digest
        AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->>'source_message_id')
        AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->>'source_thread_id')
    );
  IF v_matches=0 THEN RETURN NULL; END IF;
  IF v_matches<>1 THEN
    RETURN jsonb_build_object('ok',false,'code','exact_successful_replay_ambiguous','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb,'production_writes',false,'mailbox_contacted',false,'outbound_email',false);
  END IF;

  SELECT * INTO v_existing
  FROM public.pdc_email_ai_successor_transaction_receipts t
  WHERE t.identity_id=v_identity.identity_id
    AND t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid
    AND t.source_digest=lower(p_plan->>'source_digest')
    AND t.evidence_digest=lower(p_plan->>'evidence_digest')
    AND t.aggregate_disposition::text='SUCCESS' AND t.readback_parity
    AND t.plan_hash=public.pdc_email_ai_successor_hash(p_plan)
    AND t.typed_plan=p_plan;

  SELECT coalesce(jsonb_agg(a.action_receipt_id ORDER BY a.created_at,a.action_receipt_id),'[]'::jsonb)
  INTO v_action_receipt_ids
  FROM public.pdc_email_ai_successor_action_receipts a
  WHERE a.transaction_id=v_existing.transaction_id;

  RETURN coalesce(v_existing.response,'{}'::jsonb) || jsonb_build_object(
    'ok',true,
    'code','pdc_email_ai_typed_action_surface_verified',
    'disposition','SUCCESS',
    'transaction_id',v_existing.transaction_id,
    'source_receipt_id',v_existing.source_receipt_id,
    'plan_hash',v_existing.plan_hash,
    'readback_parity',true,
    'action_receipt_ids',v_action_receipt_ids,
    'exact_successful_replay',true,
    'production_writes',false,
    'mailbox_contacted',false,
    'outbound_email',false
  );
END $replay$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text) FROM public,anon,authenticated,service_role;

DO $patch$
DECLARE
  v_signature text;
  v_definition text;
  v_before jsonb:='{}'::jsonb;
  v_after jsonb:='{}'::jsonb;
  v_anchor text:=$anchor$  IF NOT public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan) THEN$anchor$;
  v_block text:=$block$  -- exact_successful_replay: immutable successful transaction resolution precedes current first-apply validation.
  DECLARE v_exact_successful_replay jsonb;
  BEGIN
    v_exact_successful_replay:=public.pdc_email_ai_successor_exact_success_replay_20260903(p_plan,actor,email);
    IF v_exact_successful_replay IS NOT NULL THEN RETURN v_exact_successful_replay; END IF;
  END;

$block$;
  v_patched integer:=0;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'
  ] LOOP
    SELECT pg_get_functiondef(v_signature::regprocedure) INTO v_definition;
    v_before:=v_before||jsonb_build_object(v_signature,encode(extensions.digest(convert_to(v_definition,'UTF8'),'sha256'),'hex'));
    IF position('pdc_email_ai_successor_exact_success_replay_20260903' IN v_definition)=0 AND position(v_anchor IN v_definition)>0 THEN
      v_definition:=replace(v_definition,v_anchor,v_block||v_anchor);
      EXECUTE v_definition;
      v_patched:=v_patched+1;
    END IF;
    SELECT pg_get_functiondef(v_signature::regprocedure) INTO v_definition;
    v_after:=v_after||jsonb_build_object(v_signature,encode(extensions.digest(convert_to(v_definition,'UTF8'),'sha256'),'hex'));
  END LOOP;
  IF v_patched<1 THEN RAISE EXCEPTION 'PDC_20260902274000_EXACT_REPLAY_PATCH_ANCHOR_FAILED' USING errcode='55000'; END IF;

  INSERT INTO public.pdc_email_ai_v2_exact_success_replay_history_20260903(
    event_key,predecessor_head,successor_head,function_hashes_before,function_hashes_after,contract,
    production_writes,mailbox_contacted,outbound_email,action_rpc_invoked
  ) VALUES(
    encode(extensions.digest(convert_to('pdc-staging|20260902274000|exact-successful-replay','UTF8'),'sha256'),'hex'),
    '20260902273000','20260902274000',v_before,v_after,
    'Resolve only an identity-bound, source-bound, canonical-plan-exact immutable SUCCESS receipt before current-schema validation; all unmatched, changed, hostile and new legacy plans continue through strict validation.',
    false,false,false,false
  );
END $patch$;

DO $post$
DECLARE
  v_strict text:=pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure);
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_v2_exact_success_replay_history_20260903)<>1
     OR position('exact_successful_replay' IN v_strict)=0
     OR position('pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)' IN v_strict)=0
     OR position('successor_runtime_identity_denied' IN v_strict)>position('exact_successful_replay' IN v_strict)
     OR position('exact_successful_replay' IN v_strict)>position('pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)' IN v_strict)
     OR has_function_privilege('service_role','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR has_function_privilege('authenticated','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260902274000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260902274000','pdc_email_ai_v2_exact_success_replay_20260903',ARRAY[
    'Exact identity/source/hash/jsonb match against one immutable SUCCESS transaction may return its existing transaction and action receipt IDs before current first-apply validation',
    'Unmatched, changed, hostile and new plans still use pdc_email_ai_successor_validate_v2_plan_20260901; no legacy normalization or write fallback exists',
    'Only the current strict v2 surface is patched; the separate legacy exported surface remains byte-for-byte unchanged',
    'Protected transaction/action receipts remain append-only and unchanged; helper has no runtime grant',
    'STAGING-only installation records immutable function hashes with production_writes=false, mailbox_contacted=false, outbound_email=false and action_rpc_invoked=false'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
