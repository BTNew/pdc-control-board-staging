-- STAGING-only correction: actual JWT/PostgREST parity for safe inbox plan replay.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903080000-email-ai-actual-jwt-replay-parity',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR v_head<>'20260903070000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903070000' AND name='pdc_email_ai_final_replay_input_guard_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903080000')
     OR to_regprocedure('public.pdc_email_ai_successor_safe_plan(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260903080000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_actual_jwt_replay_parity_history_20260903(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260903070000'),
  successor_head text NOT NULL CHECK(successor_head='20260903080000'),
  helper_sha256_before text NOT NULL CHECK(helper_sha256_before~'^[a-f0-9]{64}$'),
  helper_sha256_after text NOT NULL CHECK(helper_sha256_after~'^[a-f0-9]{64}$'),
  contract text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_actual_jwt_replay_parity_history_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_actual_jwt_replay_parity_history_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_actual_jwt_replay_parity_history_20260903 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_email_ai_actual_jwt_replay_parity_history_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_EMAIL_AI_ACTUAL_JWT_REPLAY_PARITY_HISTORY_IMMUTABLE' USING errcode='55000';
END $immutable$;
CREATE TRIGGER pdc_email_ai_actual_jwt_replay_parity_history_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_actual_jwt_replay_parity_history_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_actual_jwt_replay_parity_history_immutable_20260903();
REVOKE ALL ON FUNCTION public.pdc_email_ai_actual_jwt_replay_parity_history_immutable_20260903() FROM public,anon,authenticated,service_role;

DO $repair$
DECLARE v_before text;
BEGIN
  v_before:=encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex');

  CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_exact_success_replay_20260903(
    p_plan jsonb,p_actor uuid,p_email text
  ) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
  DECLARE
    v_successor public.pdc_email_ai_successor_runtime_identities%ROWTYPE;
    v_receipt public.pdc_email_ai_successor_transaction_receipts%ROWTYPE;
    v_action_ids jsonb;
  BEGIN
    IF p_actor IS NULL OR p_plan IS NULL OR jsonb_typeof(p_plan)<>'object'
       OR coalesce(p_plan->>'source_receipt_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       OR coalesce(p_plan->>'source_digest','') !~ '^[a-f0-9]{64}$'
       OR coalesce(p_plan->>'evidence_digest','') !~ '^[a-f0-9]{64}$'
    THEN RETURN NULL; END IF;
    SELECT * INTO v_successor FROM public.pdc_email_ai_successor_runtime_identities i
    WHERE i.auth_user_id=p_actor AND i.normalized_email=lower(btrim(coalesce(p_email,'')))
      AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor'
      AND i.active AND i.revoked_at IS NULL;
    IF NOT FOUND THEN RETURN NULL; END IF;
    SELECT t.* INTO v_receipt
    FROM public.pdc_email_ai_successor_transaction_receipts t
    JOIN public.pdc_email_ai_successor_runtime_identities predecessor ON predecessor.identity_id=t.identity_id
    LEFT JOIN public.pdc_email_ai_successor_runtime_rotations_20260903 rotation
      ON rotation.predecessor_identity_id=predecessor.identity_id AND rotation.successor_identity_id=v_successor.identity_id
     AND rotation.environment=v_successor.environment AND rotation.identity_purpose=v_successor.identity_purpose
    JOIN public.ai_email_intake i ON i.id=t.source_receipt_id
    CROSS JOIN LATERAL(
      SELECT coalesce(jsonb_agg(lower(btrim(a.source_hash)) ORDER BY a.created_at,a.id),'[]'::jsonb) hashes
      FROM public.ai_email_attachments a WHERE a.intake_id=i.id AND a.source_hash IS NOT NULL
    ) attachment_hashes
    WHERE predecessor.environment=v_successor.environment AND predecessor.identity_purpose=v_successor.identity_purpose
      AND (predecessor.identity_id=v_successor.identity_id OR (
        rotation.rotation_id IS NOT NULL AND NOT predecessor.active AND predecessor.revoked_at IS NOT NULL
        AND predecessor.revoked_at=rotation.predecessor_revoked_at AND predecessor.created_at<v_successor.created_at
      ))
      AND t.aggregate_disposition::text='SUCCESS' AND t.readback_parity
      AND t.source_receipt_id=(p_plan->>'source_receipt_id')::uuid
      AND t.source_digest=lower(p_plan->>'source_digest')
      AND t.evidence_digest=lower(p_plan->>'evidence_digest')
      AND (t.typed_plan=p_plan OR public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan)
      AND t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,'UTF8'),'sha256'),'hex')
      AND i.duplicate_of IS NULL AND lower(btrim(i.source_hash))=t.source_digest
      AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->>'source_message_id')
      AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->>'source_thread_id')
      AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=t.evidence_digest
      AND jsonb_typeof(coalesce(i.extracted_data->'attachment_digests','[]'::jsonb))='array'
      AND coalesce(i.extracted_data->'attachment_digests','[]'::jsonb)@>attachment_hashes.hashes
    ORDER BY t.created_at DESC LIMIT 1;
    IF NOT FOUND THEN RETURN NULL; END IF;
    SELECT coalesce(jsonb_agg(a.action_receipt_id ORDER BY a.created_at,a.action_receipt_id),'[]'::jsonb) INTO v_action_ids
    FROM public.pdc_email_ai_successor_action_receipts a WHERE a.transaction_id=v_receipt.transaction_id;
    RETURN v_receipt.response||jsonb_build_object(
      'exact_successful_replay',true,'runtime_rotation_replay',v_receipt.identity_id<>v_successor.identity_id,
      'original_identity_id',v_receipt.identity_id,'current_identity_id',v_successor.identity_id,
      'transaction_id',v_receipt.transaction_id,'action_receipt_ids',v_action_ids,
      'mailbox_contacted',false,'outbound_email',false,'production_writes',false
    );
  END $fn$;
  REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text) FROM public,anon,authenticated,service_role;

  INSERT INTO public.pdc_email_ai_actual_jwt_replay_parity_history_20260903(
    event_key,predecessor_head,successor_head,helper_sha256_before,helper_sha256_after,contract,
    production_writes,mailbox_contacted,outbound_email
  ) VALUES(
    encode(extensions.digest(convert_to('pdc-staging|20260903080000|actual-jwt-replay-parity','UTF8'),'sha256'),'hex'),
    '20260903070000','20260903080000',v_before,
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
    'Permit only the exact deterministic safe inbox projection or exact canonical JSONB for one immutable source/evidence-bound successful receipt; stored canonical plan hash, rotation, intake and attachment attestations remain mandatory.',
    false,false,false
  );
END $repair$;

DO $post$
DECLARE v_def text:=pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure);
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_actual_jwt_replay_parity_history_20260903)<>1
     OR position('public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan' IN v_def)=0
     OR position('t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,''UTF8''),''sha256''),''hex'')' IN v_def)=0
     OR position('t.source_receipt_id=(p_plan->>''source_receipt_id'')::uuid' IN v_def)=0
     OR position('t.source_digest=lower(p_plan->>''source_digest'')' IN v_def)=0
     OR position('t.evidence_digest=lower(p_plan->>''evidence_digest'')' IN v_def)=0
     OR position('attachment_hashes.hashes' IN v_def)=0
     OR position('pdc_email_ai_successor_runtime_rotations_20260903' IN v_def)=0
     OR has_function_privilege('authenticated','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR has_function_privilege('service_role','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR has_function_privilege('anon','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903080000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260903080000','pdc_email_ai_actual_jwt_replay_parity_20260903',ARRAY[
  'Accept only the deterministic safe-plan projection actually returned by the authenticated successor inbox, while preserving exact canonical JSONB replay',
  'Verify the immutable stored canonical plan hash rather than hashing the deliberately redacted inbox projection',
  'Retain exact source receipt, source digest, evidence digest, message, thread, attachment and explicit runtime-rotation bindings',
  'Keep the helper ungranted and all transaction, action, evidence and source rows unchanged',
  'Production, mailbox and outbound paths remain untouched and disabled'
 ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
