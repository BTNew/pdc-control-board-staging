-- STAGING ONLY 729: repair the proven canonical finalization
-- source-binding JSONB precedence defect revealed after audit receipt success.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-729-agentic-finalize-guard-jsonb',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE finalize_sha text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO finalize_sha FROM pg_proc p WHERE p.oid='public.finalize_pdc_agentic_email_plan_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828500000' OR finalize_sha<>'2118db555bf055d92358783b317a5ff4a1e6f28518c3470ffccc73d432d179f9' OR to_regclass('public.pdc_authenticated_finalize_guard_jsonb_history_729') IS NOT NULL THEN RAISE EXCEPTION 'PDC_729_EXACT_728_FINALIZE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_finalize_guard_jsonb_history_729(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_finalize_guard_jsonb_precedence'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828500000'),successor_head text NOT NULL CHECK(successor_head='20260828510000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='2118db555bf055d92358783b317a5ff4a1e6f28518c3470ffccc73d432d179f9'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_finalize_guard_jsonb_history_729 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_finalize_guard_jsonb_history_729 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_finalize_guard_jsonb_history_729 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_finalize_guard_jsonb_history_immutable_729() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_729_FINALIZE_GUARD_JSONB_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_finalize_guard_jsonb_history_immutable_729() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_finalize_guard_jsonb_history_immutable_729 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_finalize_guard_jsonb_history_729 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_finalize_guard_jsonb_history_immutable_729();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.finalize_pdc_agentic_email_plan_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.finalize_pdc_agentic_email_plan_502(jsonb)'::regprocedure;
 old:=$old$(p_result->'source_binding'-array['claim_token','gateway_instance_id']::text[])
        is distinct from (v_plan.plan->'source_binding'-array['claim_token','gateway_instance_id']::text[])$old$;
 new:=$new$((p_result->'source_binding')-array['claim_token','gateway_instance_id']::text[])
        is distinct from ((v_plan.plan->'source_binding')-array['claim_token','gateway_instance_id']::text[])$new$;
 IF before_sha<>'2118db555bf055d92358783b317a5ff4a1e6f28518c3470ffccc73d432d179f9' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_729_FINALIZE_GUARD_JSONB_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.finalize_pdc_agentic_email_plan_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_finalize_guard_jsonb_history_729(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-729-agentic-finalize-guard-jsonb|forward','UTF8'),'sha256'),'hex'),'agentic_finalize_guard_jsonb_precedence','20260828500000','20260828510000',before_sha,after_sha,'Parenthesize only finalization source_binding JSONB key deletion for valid acceptance receipts; preserve final receipt counts, action/audit binding, replay and normal finalization behavior',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_finalize_guard_jsonb_history_729)<>1 OR position('(p_result->''source_binding'')-array[''claim_token'',''gateway_instance_id'']::text[]' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.finalize_pdc_agentic_email_plan_502(jsonb)'::regprocedure))=0 OR position('(v_plan.plan->''source_binding'')-array[''claim_token'',''gateway_instance_id'']::text[]' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.finalize_pdc_agentic_email_plan_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_729_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828510000','729_agentic_finalize_guard_jsonb_precedence',ARRAY['Exact 728 head and finalization hash guard','Parenthesize finalization source_binding JSONB key deletion only','UID514/task/mailbox/outbound/Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
