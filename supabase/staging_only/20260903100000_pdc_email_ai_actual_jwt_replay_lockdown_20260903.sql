-- STAGING-only lockdown: pin safe projection and allowlist exact approved replays.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903100000-email-ai-actual-jwt-replay-lockdown',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text; v_safe_sha text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  v_safe_sha:=encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_safe_plan(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex');
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR v_head<>'20260903090000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903090000' AND name='pdc_email_ai_actual_jwt_legacy_receipt_parity_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903100000')
     OR v_safe_sha<>'9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086'
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_runtime_rotations_20260903 WHERE predecessor_identity_id='a5be6642-a175-4abc-a7e2-45185b87d790'::uuid AND successor_identity_id='173c0d7f-8c36-4f73-a670-ee7fcf835af1'::uuid)<>1
  THEN RAISE EXCEPTION 'PDC_20260903100000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_actual_jwt_replay_lockdown_history_20260903(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  predecessor_head text NOT NULL CHECK(predecessor_head='20260903090000'),
  successor_head text NOT NULL CHECK(successor_head='20260903100000'),
  safe_plan_sha256 text NOT NULL CHECK(safe_plan_sha256='9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086'),
  allowed_transaction_ids jsonb NOT NULL CHECK(allowed_transaction_ids='["0fec3e2a-bd49-4d98-a83d-42770edd9b23","35726910-42d6-4c7a-aa54-71e75dd67083","541657d7-ef0b-4323-884c-2a1edc29aa2f"]'::jsonb),
  helper_sha256_before text NOT NULL CHECK(helper_sha256_before~'^[a-f0-9]{64}$'),
  helper_sha256_after text NOT NULL CHECK(helper_sha256_after~'^[a-f0-9]{64}$'),
  contract text NOT NULL,
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL DEFAULT false CHECK(NOT outbound_email),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_actual_jwt_replay_lockdown_history_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_actual_jwt_replay_lockdown_history_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_actual_jwt_replay_lockdown_history_20260903 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_ai_actual_jwt_replay_lockdown_history_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_actual_jwt_replay_lockdown_history_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_actual_jwt_replay_parity_history_immutable_20260903();

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
    IF encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_safe_plan(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
         <>'9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086'
       OR p_actor IS NULL OR p_plan IS NULL OR jsonb_typeof(p_plan)<>'object'
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
    WHERE t.transaction_id IN(
        '0fec3e2a-bd49-4d98-a83d-42770edd9b23'::uuid,
        '35726910-42d6-4c7a-aa54-71e75dd67083'::uuid,
        '541657d7-ef0b-4323-884c-2a1edc29aa2f'::uuid
      )
      AND predecessor.environment=v_successor.environment AND predecessor.identity_purpose=v_successor.identity_purpose
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

  INSERT INTO public.pdc_email_ai_actual_jwt_replay_lockdown_history_20260903(
    event_key,predecessor_head,successor_head,safe_plan_sha256,allowed_transaction_ids,
    helper_sha256_before,helper_sha256_after,contract,production_writes,mailbox_contacted,outbound_email
  ) VALUES(
    encode(extensions.digest(convert_to('pdc-staging|20260903100000|actual-jwt-replay-lockdown','UTF8'),'sha256'),'hex'),
    '20260903090000','20260903100000','9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086',
    '["0fec3e2a-bd49-4d98-a83d-42770edd9b23","35726910-42d6-4c7a-aa54-71e75dd67083","541657d7-ef0b-4323-884c-2a1edc29aa2f"]'::jsonb,
    v_before,encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
    'Fail closed if the safe-plan function changes and permit safe-projection replay only for the three explicitly approved immutable SUCCESS transactions; retain every source, evidence, canonical hash, attachment and runtime-lineage check.',
    false,false,false
  );
END $repair$;

DO $post$
DECLARE v_def text:=pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure);
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_actual_jwt_replay_lockdown_history_20260903)<>1
     OR position('9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086' IN v_def)=0
     OR position('t.transaction_id IN(' IN v_def)=0
     OR position('0fec3e2a-bd49-4d98-a83d-42770edd9b23' IN v_def)=0
     OR position('35726910-42d6-4c7a-aa54-71e75dd67083' IN v_def)=0
     OR position('541657d7-ef0b-4323-884c-2a1edc29aa2f' IN v_def)=0
     OR position('public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan' IN v_def)=0
     OR position('t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,''UTF8''),''sha256''),''hex'')' IN v_def)=0
     OR has_function_privilege('authenticated','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR has_function_privilege('service_role','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR has_function_privilege('anon','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260903100000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260903100000','pdc_email_ai_actual_jwt_replay_lockdown_20260903',ARRAY[
  'Pin the exact installed safe-plan function SHA-256 and fail closed at each replay if the dependency changes',
  'Restrict compatibility replay to the three explicitly approved immutable SUCCESS transaction UUIDs',
  'Retain canonical stored-plan hash, safe projection, source receipt/digest/evidence/message/thread, exact attachment and explicit runtime-rotation bindings',
  'Keep the helper ungranted and all application rows unchanged',
  'Production, mailbox and outbound paths remain untouched and disabled'
 ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
