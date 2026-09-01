-- STAGING ONLY 20260901130000: expose canonical source-receipt digests
-- through the existing authenticated v2 inbox projection.
-- Digest values are bounded metadata only; direct table access remains denied.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901130000-successor-inbox-digest-projection',0));
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
         WHERE version='20260901120000'
           AND name='pdc_email_ai_typed_action_field_executor_identity_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901130000')
     OR to_regprocedure('public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901130000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- Preserve the deployed read contract and insert only validated, canonical
-- source/evidence digest fields bound to the parent intake receipt row.
DO $rebind$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)'::regprocedure
  ) INTO definition;
  IF definition IS NULL
     OR position($needle$'source_digest',p.source_hash$needle$ IN definition)>0
     OR position($needle$'thread_id',p.graph_thread_id,$needle$ IN definition)=0
     OR position($needle$'source_receipt_id',p.id,$needle$ IN definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901130000_INBOX_SOURCE_GUARD_FAILED' USING errcode='55000'; END IF;

  definition:=replace(
    definition,
    $needle$'thread_id',p.graph_thread_id,$needle$,
    $replacement$'thread_id',p.graph_thread_id,
    'source_digest',CASE
      WHEN lower(coalesce(p.source_hash,''))~'^[a-f0-9]{64}$'
      THEN lower(p.source_hash) ELSE NULL END,
    'evidence_digest',CASE
      WHEN lower(coalesce(p.extracted_data->>'pdc_email_ai_evidence_digest',''))~'^[a-f0-9]{64}$'
      THEN lower(p.extracted_data->>'pdc_email_ai_evidence_digest') ELSE NULL END,$replacement$
  );
  IF position($needle$p.source_hash$needle$ IN definition)<=0
     OR position($needle$p.extracted_data->>'pdc_email_ai_evidence_digest'$needle$ IN definition)<=0
  THEN RAISE EXCEPTION 'PDC_20260901130000_INBOX_DIGEST_PROJECTION_REBIND_FAILED' USING errcode='55000'; END IF;
  EXECUTE definition;
END $rebind$;

REVOKE ALL ON FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)
  FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)
  TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260901130000','pdc_email_ai_successor_inbox_digest_projection_20260901',ARRAY[
  'Existing authenticated v2 inbox RPC now projects source_digest from the canonical ai_email_intake.source_hash for the exact source_receipt_id',
  'Existing authenticated v2 inbox RPC now projects validated evidence_digest from ai_email_intake.extracted_data pdc_email_ai_evidence_digest',
  'Digest projection is source-receipt-bound metadata only; malformed or absent digests become null and strict plan validation remains fail closed',
  'Authenticated-only v2 RPC execute ACL is restored; public, anon and service_role execute remain denied',
  'Direct table access, immutable receipts, RLS, mailbox, outbound email, business writes and Production remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
