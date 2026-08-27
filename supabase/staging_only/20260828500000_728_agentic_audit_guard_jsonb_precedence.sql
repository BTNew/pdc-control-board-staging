-- STAGING ONLY 728: repair the proven canonical audit source-binding
-- JSONB precedence defect exposed after successful 684/502 apply.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-728-agentic-audit-guard-jsonb',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE audit_sha text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO audit_sha FROM pg_proc p WHERE p.oid='public.append_pdc_agentic_email_action_audit_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828490000' OR audit_sha<>'5efe7c886ac48762866e87b56cdce095aa4d201f870d3c902b001596f99e2266' OR to_regclass('public.pdc_authenticated_audit_guard_jsonb_history_728') IS NOT NULL THEN RAISE EXCEPTION 'PDC_728_EXACT_727_AUDIT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_audit_guard_jsonb_history_728(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_audit_guard_jsonb_precedence'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828490000'),successor_head text NOT NULL CHECK(successor_head='20260828500000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='5efe7c886ac48762866e87b56cdce095aa4d201f870d3c902b001596f99e2266'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_audit_guard_jsonb_history_728 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_audit_guard_jsonb_history_728 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_audit_guard_jsonb_history_728 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_audit_guard_jsonb_history_immutable_728() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_728_AUDIT_GUARD_JSONB_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_audit_guard_jsonb_history_immutable_728() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_audit_guard_jsonb_history_immutable_728 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_audit_guard_jsonb_history_728 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_audit_guard_jsonb_history_immutable_728();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.append_pdc_agentic_email_action_audit_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.append_pdc_agentic_email_action_audit_502(jsonb)'::regprocedure;
 old:=$old$(p_audit->'source_binding'-array['claim_token','gateway_instance_id']::text[])
        is distinct from (v_plan.plan->'source_binding'-array['claim_token','gateway_instance_id']::text[])$old$;
 new:=$new$((p_audit->'source_binding')-array['claim_token','gateway_instance_id']::text[])
        is distinct from ((v_plan.plan->'source_binding')-array['claim_token','gateway_instance_id']::text[])$new$;
 IF before_sha<>'5efe7c886ac48762866e87b56cdce095aa4d201f870d3c902b001596f99e2266' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_728_AUDIT_GUARD_JSONB_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.append_pdc_agentic_email_action_audit_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_audit_guard_jsonb_history_728(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-728-agentic-audit-guard-jsonb|forward','UTF8'),'sha256'),'hex'),'agentic_audit_guard_jsonb_precedence','20260828490000','20260828500000',before_sha,after_sha,'Parenthesize only audit source_binding JSONB key deletion for the valid acceptance receipt; preserve exact source authorization, plan/action binding, actor checks, audit idempotency and normal audit behavior',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_audit_guard_jsonb_history_728)<>1 OR position('(p_audit->''source_binding'')-array[''claim_token'',''gateway_instance_id'']::text[]' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.append_pdc_agentic_email_action_audit_502(jsonb)'::regprocedure))=0 OR position('(v_plan.plan->''source_binding'')-array[''claim_token'',''gateway_instance_id'']::text[]' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.append_pdc_agentic_email_action_audit_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_728_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828500000','728_agentic_audit_guard_jsonb_precedence',ARRAY['Exact 727 head and audit function hash guard','Parenthesize audit source_binding JSONB key deletion only','UID514/task/mailbox/outbound/Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
