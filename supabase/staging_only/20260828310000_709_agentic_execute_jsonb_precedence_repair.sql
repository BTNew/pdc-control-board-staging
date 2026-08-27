-- STAGING ONLY 709: repair PostgreSQL JSONB subtraction precedence in the
-- existing strict 502 execute wrapper. This is required after the narrow
-- synthetic pre-read succeeds; no action semantics or normal Board filters
-- change.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-709-agentic-execute-precedence',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828300000' OR h<>'001dba460680264492ef6afc1b6f9381fc36399e4574a79178118fa5c1abf851' OR to_regclass('public.pdc_authenticated_agentic_execute_precedence_history_709') IS NOT NULL THEN RAISE EXCEPTION 'PDC_709_EXACT_707_EXECUTE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_execute_precedence_history_709(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_execute_jsonb_precedence_repair'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828300000'),successor_head text NOT NULL CHECK(successor_head='20260828310000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='001dba460680264492ef6afc1b6f9381fc36399e4574a79178118fa5c1abf851'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_execute_precedence_history_709 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_execute_precedence_history_709 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_execute_precedence_history_709 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_execute_precedence_history_immutable_709() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_709_EXECUTE_PRECEDENCE_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_execute_precedence_history_immutable_709() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_execute_precedence_history_immutable_709 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_execute_precedence_history_709 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_execute_precedence_history_immutable_709();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old1 text;new1 text;old2 text;new2 text;old3 text;new3 text;old4 text;new4 text;
BEGIN
 SELECT pg_get_functiondef('public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 old1:=$old$(p_action->'source_binding'-array['claim_token','gateway_instance_id']::text[])$old$; new1:=$new$((p_action->'source_binding')-array['claim_token','gateway_instance_id']::text[])$new$;
 old2:=$old$(v_plan.plan->'source_binding'-array['claim_token','gateway_instance_id']::text[])$old$; new2:=$new$((v_plan.plan->'source_binding')-array['claim_token','gateway_instance_id']::text[])$new$;
 old3:=$old$(v_row.request->'source_binding'-array['claim_token','gateway_instance_id']::text[])$old$; new3:=$new$((v_row.request->'source_binding')-array['claim_token','gateway_instance_id']::text[])$new$;
 old4:=$old$(v_request->'source_binding'-array['claim_token','gateway_instance_id']::text[])$old$; new4:=$new$((v_request->'source_binding')-array['claim_token','gateway_instance_id']::text[])$new$;
 IF before_sha<>'001dba460680264492ef6afc1b6f9381fc36399e4574a79178118fa5c1abf851' OR position(old1 IN d)=0 OR position(old2 IN d)=0 OR position(old3 IN d)=0 OR position(old4 IN d)=0 THEN RAISE EXCEPTION 'PDC_709_EXECUTE_PRECEDENCE_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,old1,new1); d:=replace(d,old2,new2); d:=replace(d,old3,new3); d:=replace(d,old4,new4); EXECUTE d;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_execute_precedence_history_709(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-709-agentic-execute-precedence|forward','UTF8'),'sha256'),'hex'),'agentic_execute_jsonb_precedence_repair','20260828300000','20260828310000',before_sha,after_sha,'Parenthesize only source-binding JSONB subtraction in the strict 502 execute wrapper so synthetic acceptance actions reach the already-proven authoritative pre-read; preserve action validation, idempotency, canonical dispatch, normal reads and all negative behavior',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_execute_precedence_history_709)<>1 OR position('(p_action->''source_binding'')-array' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_709_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828310000','709_agentic_execute_jsonb_precedence_repair',ARRAY['Exact live 708 head and strict 502 execute function hash guard','Parenthesize four source-binding JSONB subtractions only','Normal Board/read filters, action semantics, idempotency, UID514/task/mailbox/outbound and Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
