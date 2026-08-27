-- STAGING ONLY: append-only repair for live 502 evidence-reference validation.
-- The exact live validator source is preserved; only PostgreSQL string/JSONB
-- operator grouping is made explicit for attachment and thread references.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-agentic-plan-validator-evidence-ref-precedence-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE h text; d text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex'),pg_get_functiondef(p.oid)
 INTO h,d FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR lower(coalesce(current_setting('app.environment',true),''))='production'
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828230000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828230000' AND name='700_agentic_plan_validator_precedence_repair')<>1
    OR to_regclass('public.pdc_authenticated_email_plan_validator_evidence_ref_history_701') IS NOT NULL
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828240000')<>0
    OR h<>'7726eb8b97ba6ce622b26120f2132866c88f5fa6273e100e74e64b53c4cc2600'
    OR position('''attachment:''||a->>''attachment_id''' IN d)=0
    OR position('''thread:''||h->>''message_id''' IN d)=0
 THEN RAISE EXCEPTION 'PDC_701_EXACT_700_PLAN_VALIDATOR_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_authenticated_email_plan_validator_evidence_ref_history_701(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='plan_validator_evidence_ref_precedence_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828230000'),
 successor_head text NOT NULL CHECK(successor_head='20260828240000'),
 predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='7726eb8b97ba6ce622b26120f2132866c88f5fa6273e100e74e64b53c4cc2600'),
 successor_function_sha256 text NOT NULL,
 repair_contract text NOT NULL,
 production_writes boolean NOT NULL CHECK(NOT production_writes),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_authenticated_email_plan_validator_evidence_ref_history_701 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_email_plan_validator_evidence_ref_history_701 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_authenticated_email_plan_validator_evidence_ref_history_701 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_email_plan_validator_evidence_ref_history_immutable_701() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_701_PLAN_VALIDATOR_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_authenticated_email_plan_validator_evidence_ref_history_immutable_701 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_plan_validator_evidence_ref_history_701 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_email_plan_validator_evidence_ref_history_immutable_701();

DO $repair$
DECLARE d text; old_attachment text; new_attachment text; old_thread text; new_thread text; before_sha text; after_sha text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
 INTO d,before_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 old_attachment:=$old$'attachment:'||a->>'attachment_id'$old$; new_attachment:=$new$('attachment:'||(a->>'attachment_id'))$new$;
 old_thread:=$old$'thread:'||h->>'message_id'$old$; new_thread:=$new$('thread:'||(h->>'message_id'))$new$;
 IF before_sha<>'7726eb8b97ba6ce622b26120f2132866c88f5fa6273e100e74e64b53c4cc2600' OR position(old_attachment IN d)=0 OR position(old_thread IN d)=0 OR position(new_attachment IN d)>0 OR position(new_thread IN d)>0 THEN RAISE EXCEPTION 'PDC_701_REPAIR_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,old_attachment,new_attachment); d:=replace(d,old_thread,new_thread);
 EXECUTE d;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 INSERT INTO public.pdc_authenticated_email_plan_validator_evidence_ref_history_701(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes)
 VALUES(encode(extensions.digest(convert_to('pdc-staging-agentic-plan-validator-evidence-ref-precedence-repair|forward','UTF8'),'sha256'),'hex'),'plan_validator_evidence_ref_precedence_repair','20260828230000','20260828240000',before_sha,after_sha,'Parenthesize only attachment and thread evidence-reference concatenations in the live 502 validator; preserve all predicates, action semantics, hashes, source binding and denial behavior',false);
END $repair$;

DO $post$
DECLARE h text; d text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex'),p.prosrc INTO h,d FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 IF (SELECT count(*) FROM public.pdc_authenticated_email_plan_validator_evidence_ref_history_701 WHERE event_kind='plan_validator_evidence_ref_precedence_repair')<>1
    OR h='7726eb8b97ba6ce622b26120f2132866c88f5fa6273e100e74e64b53c4cc2600'
    OR position($new_attachment$('attachment:'||(a->>'attachment_id'))$new_attachment$ IN d)=0
    OR position($new_thread$('thread:'||(h->>'message_id'))$new_thread$ IN d)=0
    OR position($old_attachment$'attachment:'||a->>'attachment_id'$old_attachment$ IN d)>0
    OR position($old_thread$'thread:'||h->>'message_id'$old_thread$ IN d)>0
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_701_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828240000','701_agentic_plan_validator_evidence_ref_precedence_repair',ARRAY['Exact live 700 predecessor and pdc_agentic_email_plan_valid_502 SHA guard','Parenthesize only attachment and thread evidence-reference concatenations that otherwise coerce text as JSON','Retain every strict plan/action predicate, source binding, hashes, idempotency and negative behavior; forced-RLS immutable history','No UID514, vehicles, work, Sublet, task, mailbox, outbound or Production mutation']);
NOTIFY pgrst,'reload schema';
COMMIT;
