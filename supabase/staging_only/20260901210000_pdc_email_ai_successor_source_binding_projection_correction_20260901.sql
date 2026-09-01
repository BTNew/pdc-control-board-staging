-- STAGING ONLY 20260901210000: correct the canonical source digest
-- binding to the actual attachment projection relation.
-- This append-only repair changes only the helper argument; source identity,
-- duplicate exclusion, receipts, RLS, ACL and all dispatch boundaries remain.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901210000-successor-source-binding-projection-correction',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE current_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO current_hash;
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901200000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901210000')
     OR to_regprocedure('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_source_evidence_digest_20260901(text,text,text,text,timestamptz,text,text,text,text,jsonb)') IS NULL
     OR current_hash<>'0b56aa404f0dbe528cb78bc17967c5b6cb3e839cf16c3ffbdcf57955a4d42a40'
  THEN RAISE EXCEPTION 'PDC_20260901210000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_successor_source_binding_projection_history_20260901(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='canonical_source_binding_projection_correction'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260901200000'),
  successor_head text NOT NULL CHECK(successor_head='20260901210000'),
  predecessor_function_sha256 text NOT NULL,
  successor_function_sha256 text NOT NULL,
  correction_contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_successor_source_binding_projection_history_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_source_binding_projection_history_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_successor_source_binding_projection_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $rebind$
DECLARE definition text; old_suffix text; new_suffix text; before_hash text; after_hash text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  old_suffix := $old$AND public.pdc_email_ai_successor_source_evidence_digest_20260901(
        i.source_hash,
        nullif(btrim(i.extracted_data->>'pdc_email_ai_evidence_digest'),''),
        coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id)),
        i.graph_thread_id,
        coalesce(i.received_at,i.created_at),
        i.sender_email,i.subject,i.provider_uid,i.raw_body,i.attachment_summary->'digests')=evidence_hash$old$;
  new_suffix := $new$AND public.pdc_email_ai_successor_source_evidence_digest_20260901(
        i.source_hash,
        nullif(btrim(i.extracted_data->>'pdc_email_ai_evidence_digest'),''),
        coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id)),
        i.graph_thread_id,
        coalesce(i.received_at,i.created_at),
        i.sender_email,i.subject,i.provider_uid,i.raw_body,
        (SELECT coalesce(jsonb_agg(lower(a.source_hash) ORDER BY lower(a.source_hash)),'[]'::jsonb)
         FROM public.ai_email_attachments a WHERE a.intake_id=i.id))=evidence_hash$new$;
  IF position(old_suffix IN definition)=0 OR position('public.ai_email_attachments' IN definition)>0
  THEN RAISE EXCEPTION 'PDC_20260901210000_SOURCE_BINDING_PROJECTION_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old_suffix,new_suffix);
  EXECUTE definition;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
  INSERT INTO public.pdc_email_ai_successor_source_binding_projection_history_20260901(
    event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,
    successor_function_sha256,correction_contract,production_writes,mailbox_contacted,
    outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-20260901210000-source-binding-projection-correction|forward','UTF8'),'sha256'),'hex'),
    'canonical_source_binding_projection_correction','20260901200000','20260901210000',before_hash,after_hash,
    'Use the protected ai_email_attachments projection to reproduce the canonical digest input without exposing attachment bytes or weakening source identity, duplicate exclusion, receipts or dispatch guards',
    false,false,false,false);
END $rebind$;

DO $post$
DECLARE definition text; hash text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,hash;
  IF (SELECT count(*) FROM public.pdc_email_ai_successor_source_binding_projection_history_20260901)<>1
     OR position('public.ai_email_attachments' IN definition)=0
     OR position('i.attachment_summary' IN definition)>0
     OR position('pdc_email_ai_successor_source_evidence_digest_20260901' IN definition)=0
     OR hash='0b56aa404f0dbe528cb78bc17967c5b6cb3e839cf16c3ffbdcf57955a4d42a40'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901210000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901210000','pdc_email_ai_successor_source_binding_projection_correction_20260901',ARRAY[
  'Correct the canonical source digest helper argument to use the protected ai_email_attachments projection relation present in STAGING',
  'Preserve exact source hash, duplicate exclusion, message/thread identity, append-only receipts, authenticated-only ACL, FORCE RLS and mixed-plan non-dispatch isolation',
  'Record immutable predecessor/successor hashes and explicit zero production/mailbox/outbound/action-RPC proof'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
