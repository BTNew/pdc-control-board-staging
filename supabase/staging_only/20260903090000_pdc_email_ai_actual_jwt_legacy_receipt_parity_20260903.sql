-- STAGING-only correction: explicit legacy receipt lineage and attachment parity.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903090000-email-ai-actual-jwt-legacy-receipt-parity',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR v_head<>'20260903080000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903080000' AND name='pdc_email_ai_actual_jwt_replay_parity_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903090000')
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_runtime_identities p
         JOIN public.pdc_email_ai_successor_runtime_identities s ON s.identity_id='173c0d7f-8c36-4f73-a670-ee7fcf835af1'::uuid
         WHERE p.identity_id='a5be6642-a175-4abc-a7e2-45185b87d790'::uuid
           AND NOT p.active AND p.revoked_at IS NOT NULL AND s.active AND s.revoked_at IS NULL
           AND p.environment='staging' AND p.environment=s.environment
           AND p.identity_purpose='pdc_email_ai_transaction_successor' AND p.identity_purpose=s.identity_purpose
           AND p.created_at<s.created_at)<>1
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts t
         JOIN public.ai_email_intake i ON i.id=t.source_receipt_id
         WHERE t.transaction_id='0fec3e2a-bd49-4d98-a83d-42770edd9b23'::uuid
           AND t.identity_id='a5be6642-a175-4abc-a7e2-45185b87d790'::uuid
           AND t.aggregate_disposition::text='SUCCESS' AND t.readback_parity
           AND i.duplicate_of IS NULL AND lower(btrim(i.source_hash))=t.source_digest
           AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=t.evidence_digest)<>1
  THEN RAISE EXCEPTION 'PDC_20260903090000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_actual_jwt_legacy_receipt_parity_history_20260903(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260903080000'),
  successor_head text NOT NULL CHECK(successor_head='20260903090000'),
  replay_transaction_id uuid NOT NULL CHECK(replay_transaction_id='0fec3e2a-bd49-4d98-a83d-42770edd9b23'::uuid),
  predecessor_identity_id uuid NOT NULL CHECK(predecessor_identity_id='a5be6642-a175-4abc-a7e2-45185b87d790'::uuid),
  successor_identity_id uuid NOT NULL CHECK(successor_identity_id='173c0d7f-8c36-4f73-a670-ee7fcf835af1'::uuid),
  helper_sha256_before text NOT NULL CHECK(helper_sha256_before~'^[a-f0-9]{64}$'),
  helper_sha256_after text NOT NULL CHECK(helper_sha256_after~'^[a-f0-9]{64}$'),
  contract text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_actual_jwt_legacy_receipt_parity_history_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_actual_jwt_legacy_receipt_parity_history_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_actual_jwt_legacy_receipt_parity_history_20260903 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_actual_jwt_legacy_receipt_parity_history_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_actual_jwt_legacy_receipt_parity_history_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_actual_jwt_replay_parity_history_immutable_20260903();

DO $repair$
DECLARE v_before text;
BEGIN
  v_before:=encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex');

  INSERT INTO public.pdc_email_ai_successor_runtime_rotations_20260903(
    predecessor_identity_id,successor_identity_id,environment,identity_purpose,
    predecessor_created_at,predecessor_revoked_at,successor_created_at,contract
  )
  SELECT p.identity_id,s.identity_id,'staging','pdc_email_ai_transaction_successor',
    p.created_at,p.revoked_at,s.created_at,'explicit-predecessor-successor-rotation/20260903'
  FROM public.pdc_email_ai_successor_runtime_identities p
  JOIN public.pdc_email_ai_successor_runtime_identities s ON s.identity_id='173c0d7f-8c36-4f73-a670-ee7fcf835af1'::uuid
  WHERE p.identity_id='a5be6642-a175-4abc-a7e2-45185b87d790'::uuid
    AND NOT p.active AND p.revoked_at IS NOT NULL AND s.active AND s.revoked_at IS NULL
    AND p.environment=s.environment AND p.identity_purpose=s.identity_purpose
    AND p.created_at<s.created_at;

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
      AND (
        coalesce(i.extracted_data->'attachment_digests','[]'::jsonb)@>attachment_hashes.hashes
        OR (
          jsonb_typeof(coalesce(t.typed_plan->'attachment_digests','[]'::jsonb))='array'
          AND coalesce(t.typed_plan->'attachment_digests','[]'::jsonb)@>attachment_hashes.hashes
          AND attachment_hashes.hashes@>coalesce(t.typed_plan->'attachment_digests','[]'::jsonb)
          AND NOT EXISTS(
            SELECT 1 FROM jsonb_array_elements(coalesce(t.typed_plan->'attachment_digests','[]'::jsonb))
            WHERE value#>>'{}' !~ '^[a-f0-9]{64}$'
          )
        )
      )
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

  INSERT INTO public.pdc_email_ai_actual_jwt_legacy_receipt_parity_history_20260903(
    event_key,predecessor_head,successor_head,replay_transaction_id,predecessor_identity_id,successor_identity_id,
    helper_sha256_before,helper_sha256_after,contract,production_writes,mailbox_contacted,outbound_email
  ) VALUES(
    encode(extensions.digest(convert_to('pdc-staging|20260903090000|actual-jwt-legacy-receipt-parity','UTF8'),'sha256'),'hex'),
    '20260903080000','20260903090000','0fec3e2a-bd49-4d98-a83d-42770edd9b23',
    'a5be6642-a175-4abc-a7e2-45185b87d790','173c0d7f-8c36-4f73-a670-ee7fcf835af1',v_before,
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
    'Add the exact verified retired-to-active runtime lineage and accept immutable canonical plan attachment digests only when they exactly equal the protected current attachment set; all source/evidence/safe-plan/hash checks remain mandatory.',
    false,false,false
  );
END $repair$;

DO $post$
DECLARE v_def text:=pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure);
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_actual_jwt_legacy_receipt_parity_history_20260903)<>1
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_runtime_rotations_20260903 WHERE predecessor_identity_id='a5be6642-a175-4abc-a7e2-45185b87d790'::uuid AND successor_identity_id='173c0d7f-8c36-4f73-a670-ee7fcf835af1'::uuid AND contract='explicit-predecessor-successor-rotation/20260903')<>1
     OR position('public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan' IN v_def)=0
     OR position('t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,''UTF8''),''sha256''),''hex'')' IN v_def)=0
     OR position('coalesce(t.typed_plan->''attachment_digests'',''[]''::jsonb)@>attachment_hashes.hashes' IN v_def)=0
     OR position('attachment_hashes.hashes@>coalesce(t.typed_plan->''attachment_digests'',''[]''::jsonb)' IN v_def)=0
     OR has_function_privilege('authenticated','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR has_function_privilege('service_role','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR has_function_privilege('anon','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903090000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260903090000','pdc_email_ai_actual_jwt_legacy_receipt_parity_20260903',ARRAY[
  'Record the exact verified retired a5be6642 identity to active 173c0d7f identity STAGING runtime rotation without widening role or table grants',
  'For legacy successful evidence lacking intake attachment_digests, require the immutable canonical typed-plan digest set to exactly equal every protected current attachment hash',
  'Retain deterministic safe-inbox plan equality, canonical stored-plan hash integrity, source receipt/digest/evidence/message/thread binding and successful readback',
  'Keep all transaction, action, intake, attachment and vehicle rows unchanged',
  'Production, mailbox and outbound paths remain untouched and disabled'
 ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
