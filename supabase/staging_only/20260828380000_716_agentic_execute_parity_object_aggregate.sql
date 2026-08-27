-- STAGING ONLY 716: use jsonb_each/object_agg for strict action request
-- parity, avoiding every overloaded JSONB subtraction operator.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-716-agentic-execute-parity-object-aggregate',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828370000' OR h<>'9809a80fc7c0031a6cbc4fb3f3e97427f82ec5b7e5b02ff39fa93b9103c5cfbd' OR to_regclass('public.pdc_authenticated_agentic_execute_parity_object_history_716') IS NOT NULL THEN RAISE EXCEPTION 'PDC_716_EXACT_715_EXECUTE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF; END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_execute_parity_object_history_716(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_execute_parity_object_aggregate'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828370000'),successor_head text NOT NULL CHECK(successor_head='20260828380000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='9809a80fc7c0031a6cbc4fb3f3e97427f82ec5b7e5b02ff39fa93b9103c5cfbd'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_execute_parity_object_history_716 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_execute_parity_object_history_716 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_execute_parity_object_history_716 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_execute_parity_object_history_immutable_716() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_716_EXECUTE_OBJECT_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_execute_parity_object_history_immutable_716() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_execute_parity_object_history_immutable_716 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_execute_parity_object_history_716 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_execute_parity_object_history_immutable_716();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 old:=$old$if (((v_row.request-'current_state'::text)-'source_binding'::text)<>((v_request-'current_state'::text)-'source_binding'::text))
     or (((((v_row.request)->'source_binding')-'claim_token'::text)-'gateway_instance_id'::text))
        is distinct from (((((v_request)->'source_binding')-'claim_token'::text)-'gateway_instance_id'::text))
  then$old$;
 new:=$new$if (coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(v_row.request) e where e.key not in ('current_state','source_binding')),'{}'::jsonb)<>coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(v_request) e where e.key not in ('current_state','source_binding')),'{}'::jsonb))
     or coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(v_row.request->'source_binding') e where e.key not in ('claim_token','gateway_instance_id')),'{}'::jsonb)
        is distinct from coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(v_request->'source_binding') e where e.key not in ('claim_token','gateway_instance_id')),'{}'::jsonb)
  then$new$;
 IF before_sha<>'9809a80fc7c0031a6cbc4fb3f3e97427f82ec5b7e5b02ff39fa93b9103c5cfbd' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_716_EXECUTE_OBJECT_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_execute_parity_object_history_716(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-716-agentic-execute-parity-object-aggregate|forward','UTF8'),'sha256'),'hex'),'agentic_execute_parity_object_aggregate','20260828370000','20260828380000',before_sha,after_sha,'Compare immutable action requests with explicit jsonb_each/object_agg projection, excluding only server current_state and claim transport fields; preserve all conflict detection and action semantics',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_execute_parity_object_history_716)<>1 OR position('jsonb_object_agg' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_716_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828380000','716_agentic_execute_parity_object_aggregate',ARRAY['Exact 715 predecessor and strict execute hash guard','Use explicit jsonb_each/object_agg request parity projection to avoid overloaded JSONB subtraction coercion','Normal Board/read filters, action semantics, idempotency, UID514/task/mailbox/outbound and Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
