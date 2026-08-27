-- STAGING ONLY 715: explicitly type JSONB key-delete operands in the strict
-- 502 request parity comparison. The previous scalar repair still allowed
-- PostgreSQL to resolve unknown literals as JSON.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-715-agentic-execute-parity-typed-keys',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828360000' OR h<>'0fd91bf4252c53e2f46cbe33ca8af5078a82cbe2e37d49d59b4c17d40a0089c4' OR to_regclass('public.pdc_authenticated_agentic_execute_parity_typed_history_715') IS NOT NULL THEN RAISE EXCEPTION 'PDC_715_EXACT_714_EXECUTE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF; END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_execute_parity_typed_history_715(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_execute_parity_typed_keys'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828360000'),successor_head text NOT NULL CHECK(successor_head='20260828370000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='0fd91bf4252c53e2f46cbe33ca8af5078a82cbe2e37d49d59b4c17d40a0089c4'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_execute_parity_typed_history_715 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_execute_parity_typed_history_715 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_execute_parity_typed_history_715 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_execute_parity_typed_history_immutable_715() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_715_EXECUTE_TYPED_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_execute_parity_typed_history_immutable_715() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_execute_parity_typed_history_immutable_715 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_execute_parity_typed_history_715 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_execute_parity_typed_history_immutable_715();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 old:=$old$if (((v_row.request-'current_state')-'source_binding')<>((v_request-'current_state')-'source_binding'))
     or ((((v_row.request)->'source_binding')-'claim_token')-'gateway_instance_id')
        is distinct from ((((v_request)->'source_binding')-'claim_token')-'gateway_instance_id')
  then$old$;
 new:=$new$if (((v_row.request-'current_state'::text)-'source_binding'::text)<>((v_request-'current_state'::text)-'source_binding'::text))
     or (((((v_row.request)->'source_binding')-'claim_token'::text)-'gateway_instance_id'::text))
        is distinct from (((((v_request)->'source_binding')-'claim_token'::text)-'gateway_instance_id'::text))
  then$new$;
 IF before_sha<>'0fd91bf4252c53e2f46cbe33ca8af5078a82cbe2e37d49d59b4c17d40a0089c4' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_715_TYPED_KEY_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_execute_parity_typed_history_715(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-715-agentic-execute-parity-typed-keys|forward','UTF8'),'sha256'),'hex'),'agentic_execute_parity_typed_keys','20260828360000','20260828370000',before_sha,after_sha,'Type all scalar JSONB key-delete operands explicitly so strict immutable action parity cannot coerce a text key into JSON',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_execute_parity_typed_history_715)<>1 OR position($needle$v_row.request-'current_state'::text$needle$ IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_715_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828370000','715_agentic_execute_parity_typed_keys',ARRAY['Exact 714 predecessor and execute hash guard','Type scalar JSONB key-delete operands in the request parity comparison','Normal Board/read filters, action semantics, idempotency, UID514/task/mailbox/outbound and Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
