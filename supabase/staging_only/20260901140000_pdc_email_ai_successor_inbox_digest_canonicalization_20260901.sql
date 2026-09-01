-- STAGING ONLY 20260901140000: canonical source-receipt evidence digest.
-- This append-only successor keeps the digest inside the trusted read boundary;
-- correspondence and attachment content are hashed internally and never returned.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901140000-successor-inbox-digest-canonicalization',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260901130000'
           AND name='pdc_email_ai_successor_inbox_digest_projection_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901140000')
     OR to_regprocedure('public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901140000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- Prefer a previously persisted validated digest. For retained legacy intake
-- rows, derive one from the exact source-receipt metadata and attachment digest
-- list. No caller-supplied digest or direct table read is trusted.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_source_evidence_digest_20260901(
  p_source_hash text,
  p_explicit_digest text,
  p_message_id text,
  p_thread_id text,
  p_received_at timestamptz,
  p_sender text,
  p_subject text,
  p_provider_uid text,
  p_correspondence text,
  p_attachment_digests jsonb
)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path=pg_catalog,extensions
AS $digest$
  SELECT CASE
    WHEN lower(coalesce(p_explicit_digest,''))~'^[a-f0-9]{64}$'
    THEN lower(p_explicit_digest)
    ELSE encode(extensions.digest(convert_to(jsonb_build_object(
      'source_hash',lower(coalesce(p_source_hash,'')),
      'message_id',coalesce(p_message_id,''),
      'thread_id',coalesce(p_thread_id,''),
      'received_at',p_received_at,
      'sender',lower(coalesce(p_sender,'')),
      'subject',coalesce(p_subject,''),
      'provider_uid',coalesce(p_provider_uid,''),
      'correspondence',coalesce(p_correspondence,''),
      'attachment_digests',coalesce(p_attachment_digests,'[]'::jsonb)
    )::text,'UTF8'),'sha256'),'hex')
  END
$digest$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_source_evidence_digest_20260901(text,text,text,text,timestamptz,text,text,text,text,jsonb)
  FROM public,anon,authenticated,service_role;

DO $rebind$
DECLARE
  definition text;
  old_projection text := $old$'evidence_digest',CASE
      WHEN lower(coalesce(p.extracted_data->>'pdc_email_ai_evidence_digest',''))~'^[a-f0-9]{64}$'
      THEN lower(p.extracted_data->>'pdc_email_ai_evidence_digest') ELSE NULL END,$old$;
  new_projection text := $new$'evidence_digest',public.pdc_email_ai_successor_source_evidence_digest_20260901(
      p.source_hash,p.extracted_data->>'pdc_email_ai_evidence_digest',
      coalesce(p.internet_message_id,p.graph_message_id),p.graph_thread_id,
      coalesce(p.received_at,p.created_at),p.sender_email,p.subject,p.provider_uid,
      p.raw_body,p.attachment_summary->'digests'),$new$;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)'::regprocedure
  ) INTO definition;
  IF definition IS NULL
     OR position(old_projection IN definition)=0
     OR position($needle$'source_digest',CASE$needle$ IN definition)=0
     OR position($needle$'source_receipt_id',p.id$needle$ IN definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901140000_INBOX_SOURCE_GUARD_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old_projection,new_projection);
  IF position('pdc_email_ai_successor_source_evidence_digest_20260901' IN definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901140000_DIGEST_REBIND_FAILED' USING errcode='55000'; END IF;
  EXECUTE definition;
END $rebind$;

REVOKE ALL ON FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)
  FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)
  TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260901140000','pdc_email_ai_successor_inbox_digest_canonicalization_20260901',ARRAY[
  'Canonical source evidence digest helper prefers an existing validated v2 evidence digest and otherwise hashes source-receipt-bound message metadata, correspondence and attachment digests internally',
  'Existing authenticated v2 inbox RPC now returns a non-null validated evidence_digest for retained source receipts without returning correspondence or attachment content',
  'Digest helper is immutable and source-receipt-bound; no action or operation dispatch is introduced by this read-only projection repair',
  'Authenticated-only inbox ACL, direct table denial, immutable receipts, RLS, mailbox, outbound email, business writes and Production remain unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
