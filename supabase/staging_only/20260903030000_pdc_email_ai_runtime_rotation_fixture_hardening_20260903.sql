-- STAGING-only hardening for explicit runtime rotation and fixture immutability.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260903030000-email-ai-runtime-rotation-hardening',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR v_head<>'20260903020000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903020000' AND name='pdc_email_ai_runtime_rotation_replay_fixtures_20260903')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903030000')
  THEN RAISE EXCEPTION 'PDC_20260903030000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_successor_runtime_rotations_20260903(
  rotation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  predecessor_identity_id uuid NOT NULL UNIQUE REFERENCES public.pdc_email_ai_successor_runtime_identities(identity_id),
  successor_identity_id uuid NOT NULL REFERENCES public.pdc_email_ai_successor_runtime_identities(identity_id),
  environment text NOT NULL CHECK(environment='staging'),
  identity_purpose text NOT NULL CHECK(identity_purpose='pdc_email_ai_transaction_successor'),
  predecessor_created_at timestamptz NOT NULL,
  predecessor_revoked_at timestamptz NOT NULL,
  successor_created_at timestamptz NOT NULL,
  contract text NOT NULL CHECK(contract='explicit-predecessor-successor-rotation/20260903'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(successor_identity_id,predecessor_identity_id),
  CHECK(predecessor_identity_id<>successor_identity_id),
  CHECK(predecessor_created_at<successor_created_at)
);
ALTER TABLE public.pdc_email_ai_successor_runtime_rotations_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_runtime_rotations_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_successor_runtime_rotations_20260903 FROM public,anon,authenticated,service_role;

INSERT INTO public.pdc_email_ai_successor_runtime_rotations_20260903(
  predecessor_identity_id,successor_identity_id,environment,identity_purpose,
  predecessor_created_at,predecessor_revoked_at,successor_created_at,contract
)
SELECT p.identity_id,s.identity_id,'staging','pdc_email_ai_transaction_successor',
  p.created_at,p.revoked_at,s.created_at,'explicit-predecessor-successor-rotation/20260903'
FROM public.pdc_email_ai_successor_runtime_identities p
JOIN public.pdc_email_ai_successor_runtime_identities s
  ON s.identity_id='173c0d7f-8c36-4f73-a670-ee7fcf835af1'::uuid
WHERE p.identity_id='6075c796-936c-40e8-9051-de00cd497df3'::uuid
  AND NOT p.active AND p.revoked_at IS NOT NULL
  AND s.active AND s.revoked_at IS NULL
  AND p.environment=s.environment AND p.identity_purpose=s.identity_purpose;

CREATE TRIGGER pdc_email_ai_runtime_rotations_immutable_20260903
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_successor_runtime_rotations_20260903
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_acceptance_fixture_immutable_20260903();

CREATE OR REPLACE FUNCTION public.pdc_email_ai_v2_fixture_attachment_immutable_20260903()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $immutable$
BEGIN
  IF TG_OP<>'INSERT' AND EXISTS(
    SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_20260903 f WHERE f.source_receipt_id=OLD.intake_id
  ) THEN
    RAISE EXCEPTION 'PDC_EMAIL_AI_V2_ACCEPTANCE_FIXTURE_ATTACHMENT_IMMUTABLE' USING errcode='55000';
  END IF;
  IF TG_OP<>'DELETE' AND EXISTS(
    SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_20260903 f WHERE f.source_receipt_id=NEW.intake_id
  ) THEN
    RAISE EXCEPTION 'PDC_EMAIL_AI_V2_ACCEPTANCE_FIXTURE_ATTACHMENT_IMMUTABLE' USING errcode='55000';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_v2_fixture_attachment_immutable_20260903() FROM public,anon,authenticated,service_role;
DROP TRIGGER pdc_email_ai_v2_acceptance_attachment_immutable_20260903 ON public.ai_email_attachments;
CREATE TRIGGER pdc_email_ai_v2_fixture_attachment_immutable_20260903
BEFORE INSERT OR UPDATE OR DELETE ON public.ai_email_attachments
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_v2_fixture_attachment_immutable_20260903();

CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_exact_success_replay_20260903(
  p_plan jsonb,p_actor uuid,p_email text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE
  v_successor public.pdc_email_ai_successor_runtime_identities%ROWTYPE;
  v_receipt public.pdc_email_ai_successor_transaction_receipts%ROWTYPE;
  v_action_ids jsonb;
BEGIN
  IF p_actor IS NULL OR p_plan IS NULL OR jsonb_typeof(p_plan)<>'object' THEN RETURN NULL; END IF;
  SELECT * INTO v_successor FROM public.pdc_email_ai_successor_runtime_identities i
  WHERE i.auth_user_id=p_actor AND i.normalized_email=lower(btrim(coalesce(p_email,'')))
    AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor'
    AND i.active AND i.revoked_at IS NULL;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT t.* INTO v_receipt
  FROM public.pdc_email_ai_successor_transaction_receipts t
  JOIN public.pdc_email_ai_successor_runtime_identities predecessor ON predecessor.identity_id=t.identity_id
  LEFT JOIN public.pdc_email_ai_successor_runtime_rotations_20260903 rotation
    ON rotation.predecessor_identity_id=predecessor.identity_id
   AND rotation.successor_identity_id=v_successor.identity_id
   AND rotation.environment=v_successor.environment
   AND rotation.identity_purpose=v_successor.identity_purpose
  JOIN public.ai_email_intake i ON i.id=t.source_receipt_id
  CROSS JOIN LATERAL(
    SELECT coalesce(jsonb_agg(lower(btrim(a.source_hash)) ORDER BY a.created_at,a.id),'[]'::jsonb) hashes
    FROM public.ai_email_attachments a WHERE a.intake_id=i.id AND a.source_hash IS NOT NULL
  ) attachment_hashes
  WHERE predecessor.environment=v_successor.environment
    AND predecessor.identity_purpose=v_successor.identity_purpose
    AND (
      predecessor.identity_id=v_successor.identity_id
      OR (
        rotation.rotation_id IS NOT NULL
        AND NOT predecessor.active AND predecessor.revoked_at IS NOT NULL
        AND predecessor.revoked_at=rotation.predecessor_revoked_at
        AND predecessor.created_at<v_successor.created_at
      )
    )
    AND t.aggregate_disposition::text='SUCCESS' AND t.readback_parity
    AND t.typed_plan=p_plan
    AND t.plan_hash=encode(extensions.digest(convert_to(p_plan::text,'UTF8'),'sha256'),'hex')
    AND i.duplicate_of IS NULL AND i.source_hash IS NOT NULL
    AND lower(btrim(i.source_hash))=t.source_digest
    AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(p_plan->>'source_message_id')
    AND coalesce(btrim(i.graph_thread_id),'')=btrim(p_plan->>'source_thread_id')
    AND public.pdc_email_ai_successor_source_evidence_digest_20260901(
      lower(btrim(i.source_hash)),NULL,coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id)),
      btrim(i.graph_thread_id),i.received_at,i.sender_email,i.subject,i.provider_uid,i.raw_body,attachment_hashes.hashes
    )=t.evidence_digest
    AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=t.evidence_digest
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

DO $post$
DECLARE v_def text:=pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure);
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_ai_successor_runtime_rotations_20260903)<>1
     OR position('rotation.predecessor_identity_id=predecessor.identity_id' IN v_def)=0
     OR position('attachment_hashes.hashes' IN v_def)=0
     OR has_table_privilege('authenticated','public.pdc_email_ai_successor_runtime_rotations_20260903','select')
  THEN RAISE EXCEPTION 'PDC_20260903030000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260903030000','pdc_email_ai_runtime_rotation_fixture_hardening_20260903',ARRAY[
  'Require an immutable explicit predecessor-to-successor rotation row for cross-identity exact replay',
  'Recompute evidence digest from current correspondence and attachment hashes before exact replay',
  'Block insert, update reparenting and delete for attachments belonging to immutable acceptance fixtures',
  'Retain same-current-identity exact replay while unrelated revoked identities remain ineligible',
  'Production, mailbox and outbound paths remain untouched and disabled'
 ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
