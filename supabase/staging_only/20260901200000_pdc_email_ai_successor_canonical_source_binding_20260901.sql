-- STAGING ONLY 20260901200000: bind strict v2 source evidence to the
-- canonical source-receipt helper exposed by the trusted inbox projection.
-- The existing i.duplicate_of IS NULL guard is retained verbatim.
-- The existing intake row, source hash, message/thread identity and attachment
-- digests remain exact; only the evidence digest comparison accepts the same
-- canonical digest that the authenticated inbox read already returned.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901200000-successor-canonical-source-binding',0));
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
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901190000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901200000')
     OR to_regprocedure('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_source_evidence_digest_20260901(text,text,text,text,timestamptz,text,text,text,text,jsonb)') IS NULL
     OR current_hash<>'b87f8fd688d863d6270a19f479e1933f4cbecb27fb025f04552bb4c665d90944'
  THEN RAISE EXCEPTION 'PDC_20260901200000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_email_ai_successor_source_binding_history_20260901(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='canonical_source_binding'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260901190000'),
  successor_head text NOT NULL CHECK(successor_head='20260901200000'),
  predecessor_function_sha256 text NOT NULL,
  successor_function_sha256 text NOT NULL,
  binding_contract text NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  outbound_email boolean NOT NULL CHECK(NOT outbound_email),
  action_rpc_invoked boolean NOT NULL CHECK(NOT action_rpc_invoked),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_successor_source_binding_history_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_successor_source_binding_history_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_ai_successor_source_binding_history_20260901 FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $rebind$
DECLARE definition text; old_suffix text; new_suffix text; before_hash text; after_hash text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,before_hash;
  old_suffix := $old$AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=evidence_hash$old$;
  new_suffix := $new$AND public.pdc_email_ai_successor_source_evidence_digest_20260901(
        i.source_hash,
        nullif(btrim(i.extracted_data->>'pdc_email_ai_evidence_digest'),''),
        coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id)),
        i.graph_thread_id,
        coalesce(i.received_at,i.created_at),
        i.sender_email,i.subject,i.provider_uid,i.raw_body,i.attachment_summary->'digests')=evidence_hash$new$;
  IF position(old_suffix IN definition)=0 OR position('pdc_email_ai_successor_source_evidence_digest_20260901' IN definition)>0
  THEN RAISE EXCEPTION 'PDC_20260901200000_SOURCE_BINDING_ANCHOR_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,old_suffix,new_suffix);
  EXECUTE definition;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') INTO after_hash;
  INSERT INTO public.pdc_email_ai_successor_source_binding_history_20260901(
    event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,
    successor_function_sha256,binding_contract,production_writes,mailbox_contacted,
    outbound_email,action_rpc_invoked)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-20260901200000-canonical-source-binding|forward','UTF8'),'sha256'),'hex'),
    'canonical_source_binding','20260901190000','20260901200000',before_hash,after_hash,
    'Strict non-dispatch source validation compares the supplied evidence_digest with the immutable source-receipt canonical helper, while preserving exact source/message/thread identity and no dispatch for mixed plans',
    false,false,false,false);
END $rebind$;

DO $post$
DECLARE definition text; hash text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),
    encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')
    INTO definition,hash;
  IF (SELECT count(*) FROM public.pdc_email_ai_successor_source_binding_history_20260901)<>1
     OR position('pdc_email_ai_successor_source_evidence_digest_20260901' IN definition)=0
     OR position('coalesce(i.extracted_data->>''pdc_email_ai_evidence_digest'','''')=evidence_hash' IN definition)>0
     OR hash='b87f8fd688d863d6270a19f479e1933f4cbecb27fb025f04552bb4c665d90944'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901200000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901200000','pdc_email_ai_successor_canonical_source_binding_20260901',ARRAY[
  'Bind strict mixed-plan source validation to the canonical source-receipt evidence digest helper already used by the trusted inbox projection',
  'Preserve exact source hash, non-duplicate identity, message/thread identity, append-only receipts, authenticated-only ACL, FORCE RLS and no canonical dispatch for mixed planned/review plans',
  'Record immutable predecessor/successor function hashes and explicit zero production/mailbox/outbound/action-RPC proof'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
