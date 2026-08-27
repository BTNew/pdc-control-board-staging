-- STAGING ONLY: append-only repair for the live 502 plan validator.
-- The exact live validator source is preserved; only the JSONB source-binding
-- subtraction is parenthesized to prevent PostgreSQL precedence from coercing
-- the key name as JSON. No plan semantics are widened.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-agentic-plan-validator-precedence-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE h text; d text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex'),pg_get_functiondef(p.oid)
 INTO h,d
 FROM pg_proc p
 WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR lower(coalesce(current_setting('app.environment',true),''))='production'
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828200000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828200000' AND name='699_agentic_candidate_id_delimiter_repair')<>1
    OR to_regclass('public.pdc_authenticated_email_plan_validator_precedence_history_700') IS NOT NULL
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828230000')<>0
    OR h<>'54830d6a5e1791467eb8d0347e7db077e870de90b00265e89e9996d5303ea12f'
    OR position('p_plan->''source_binding''-array[''claim_token'',''gateway_instance_id'']::text[]' IN d)=0
    OR position('(p_plan->''source_binding'')-array[''claim_token'',''gateway_instance_id'']::text[]' IN d)>0
 THEN RAISE EXCEPTION 'PDC_700_EXACT_699_PLAN_VALIDATOR_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_authenticated_email_plan_validator_precedence_history_700(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='plan_validator_precedence_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828200000'),
 successor_head text NOT NULL CHECK(successor_head='20260828230000'),
 predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='54830d6a5e1791467eb8d0347e7db077e870de90b00265e89e9996d5303ea12f'),
 successor_function_sha256 text NOT NULL,
 repair_contract text NOT NULL,
 production_writes boolean NOT NULL CHECK(NOT production_writes),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_authenticated_email_plan_validator_precedence_history_700 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_email_plan_validator_precedence_history_700 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_authenticated_email_plan_validator_precedence_history_700 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_email_plan_validator_precedence_history_immutable_700() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_700_PLAN_VALIDATOR_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_authenticated_email_plan_validator_precedence_history_immutable_700 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_plan_validator_precedence_history_700 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_email_plan_validator_precedence_history_immutable_700();

DO $repair$
DECLARE d text; old text; new text; before_sha text; after_sha text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex')
 INTO d,before_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 old:=$old$p_plan->'source_binding'-array['claim_token','gateway_instance_id']::text[]$old$;
 new:=$new$(p_plan->'source_binding')-array['claim_token','gateway_instance_id']::text[]$new$;
 IF before_sha<>'54830d6a5e1791467eb8d0347e7db077e870de90b00265e89e9996d5303ea12f' OR position(old IN d)=0 OR position(new IN d)>0 THEN RAISE EXCEPTION 'PDC_700_REPAIR_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 INSERT INTO public.pdc_authenticated_email_plan_validator_precedence_history_700(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes)
 VALUES(encode(extensions.digest(convert_to('pdc-staging-agentic-plan-validator-precedence-repair|forward','UTF8'),'sha256'),'hex'),'plan_validator_precedence_repair','20260828200000','20260828230000',before_sha,after_sha,'Parenthesize only the p_plan source_binding JSONB subtraction in the live 502 validator; preserve all predicates, hashes, source binding, action schema and denial behavior',false);
END $repair$;

DO $post$
DECLARE h text; d text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex'),p.prosrc INTO h,d FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)'::regprocedure;
 IF (SELECT count(*) FROM public.pdc_authenticated_email_plan_validator_precedence_history_700 WHERE event_kind='plan_validator_precedence_repair')<>1
    OR h='54830d6a5e1791467eb8d0347e7db077e870de90b00265e89e9996d5303ea12f'
    OR position('(p_plan->''source_binding'')-array[''claim_token'',''gateway_instance_id'']::text[]' IN d)=0
    OR position('p_plan->''source_binding''-array[''claim_token'',''gateway_instance_id'']::text[]' IN d)>0
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_700_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828230000','700_agentic_plan_validator_precedence_repair',ARRAY['Exact live 699 head and pdc_agentic_email_plan_valid_502 predecessor SHA guard','Parenthesize only the JSONB source_binding subtraction whose live PostgreSQL precedence raised invalid JSON on valid plans','Retain every validator predicate, strict plan/action schema, idempotency and source binding; forced-RLS immutable repair history','No UID514, vehicles, work, Sublet, task, mailbox, outbound or Production mutation']);
NOTIFY pgrst,'reload schema';
COMMIT;
