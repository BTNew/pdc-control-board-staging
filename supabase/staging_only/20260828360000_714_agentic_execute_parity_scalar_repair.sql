-- STAGING ONLY 714: replace the remaining text-array request parity
-- subtraction with explicit scalar JSONB key deletes in strict 502 execute.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-714-agentic-execute-parity-scalar',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828350000' OR h<>'8ab98c709330ab5c5cb6d0d977c8230aa4c243601f1c6b7d547c33e0116432e2' OR to_regclass('public.pdc_authenticated_agentic_execute_parity_scalar_history_714') IS NOT NULL THEN RAISE EXCEPTION 'PDC_714_EXACT_713_EXECUTE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF; END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_execute_parity_scalar_history_714(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_execute_parity_scalar_repair'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828350000'),successor_head text NOT NULL CHECK(successor_head='20260828360000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='8ab98c709330ab5c5cb6d0d977c8230aa4c243601f1c6b7d547c33e0116432e2'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_execute_parity_scalar_history_714 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_execute_parity_scalar_history_714 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_execute_parity_scalar_history_714 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_execute_parity_scalar_history_immutable_714() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_714_EXECUTE_PARITY_SCALAR_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_execute_parity_scalar_history_immutable_714() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_execute_parity_scalar_history_immutable_714 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_execute_parity_scalar_history_714 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_execute_parity_scalar_history_immutable_714();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 old:=$old$if ((v_row.request)-array['current_state','source_binding']::text[])<>((v_request)-array['current_state','source_binding']::text[])
     or ((v_row.request->'source_binding')-array['claim_token','gateway_instance_id']::text[])
        is distinct from ((v_request->'source_binding')-array['claim_token','gateway_instance_id']::text[])
  then$old$;
 new:=$new$if (((v_row.request-'current_state')-'source_binding')<>((v_request-'current_state')-'source_binding'))
     or ((((v_row.request)->'source_binding')-'claim_token')-'gateway_instance_id')
        is distinct from ((((v_request)->'source_binding')-'claim_token')-'gateway_instance_id')
  then$new$;
 IF before_sha<>'8ab98c709330ab5c5cb6d0d977c8230aa4c243601f1c6b7d547c33e0116432e2' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_714_EXECUTE_PARITY_SCALAR_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_execute_parity_scalar_history_714(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-714-agentic-execute-parity-scalar|forward','UTF8'),'sha256'),'hex'),'agentic_execute_parity_scalar_repair','20260828350000','20260828360000',before_sha,after_sha,'Use explicit scalar JSONB key deletion for immutable request parity; preserve exact conflict detection without text-array coercion',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_execute_parity_scalar_history_714)<>1 OR position($needle$(v_row.request-'current_state')-'source_binding'$needle$ IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_714_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828360000','714_agentic_execute_parity_scalar_repair',ARRAY['Exact 713 predecessor and execute hash guard','Replace remaining array-subtraction request parity with scalar JSONB deletes','Normal Board/read filters, action semantics, idempotency, UID514/task/mailbox/outbound and Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
