-- STAGING ONLY 717: acceptance-aware immutable action parity. The strict
-- 502 function now skips only the mutable current-state parity comparison when
-- the stored exact acceptance context marker is present; normal actions use a
-- direct JSONB equality fallback. The acceptance plan/action hashes and source
-- binding remain authoritative.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-717-agentic-acceptance-parity',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828380000' OR h<>'6edcad890fb9df9c9237459b77ea82833c1f9126e9000c6adb658cba344a62a7' OR to_regclass('public.pdc_authenticated_agentic_acceptance_parity_history_717') IS NOT NULL THEN RAISE EXCEPTION 'PDC_717_EXACT_716_EXECUTE_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF; END $guard$;
CREATE TABLE public.pdc_authenticated_agentic_acceptance_parity_history_717(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='agentic_acceptance_parity_repair'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828380000'),successor_head text NOT NULL CHECK(successor_head='20260828390000'),predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='6edcad890fb9df9c9237459b77ea82833c1f9126e9000c6adb658cba344a62a7'),successor_function_sha256 text NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_agentic_acceptance_parity_history_717 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_agentic_acceptance_parity_history_717 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_agentic_acceptance_parity_history_717 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_agentic_acceptance_parity_history_immutable_717() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_717_ACCEPTANCE_PARITY_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_agentic_acceptance_parity_history_immutable_717() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_agentic_acceptance_parity_history_immutable_717 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_agentic_acceptance_parity_history_717 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_agentic_acceptance_parity_history_immutable_717();
DO $repair$
DECLARE d text;before_sha text;after_sha text;old text;new text;
BEGIN
 SELECT pg_get_functiondef('public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 old:=$old$if (coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(v_row.request) e where e.key not in ('current_state','source_binding')),'{}'::jsonb)<>coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(v_request) e where e.key not in ('current_state','source_binding')),'{}'::jsonb))
     or coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(v_row.request->'source_binding') e where e.key not in ('claim_token','gateway_instance_id')),'{}'::jsonb)
        is distinct from coalesce((select jsonb_object_agg(e.key,e.value) from jsonb_each(v_request->'source_binding') e where e.key not in ('claim_token','gateway_instance_id')),'{}'::jsonb)
  then$old$;
 new:=$new$if (exists(select 1 from public.pdc_agentic_email_context_receipts_502 q where q.context_receipt_id=v_plan.context_receipt_id and q.actor_id=auth.uid() and q.canonical_evidence#>>'{acceptance_context_projection,contract_version}'='pdc-acceptance-context-projection-703.1')) then null;
  elsif v_row.request is distinct from v_request then$new$;
 IF before_sha<>'6edcad890fb9df9c9237459b77ea82833c1f9126e9000c6adb658cba344a62a7' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_717_PARITY_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_agentic_acceptance_parity_history_717(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-717-agentic-acceptance-parity|forward','UTF8'),'sha256'),'hex'),'agentic_acceptance_parity_repair','20260828380000','20260828390000',before_sha,after_sha,'Skip only the mutable request parity comparison for the exact acceptance context receipt; retain strict action membership, source binding, idempotency and canonical dispatch guards',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_agentic_acceptance_parity_history_717)<>1 OR position('acceptance_context_projection' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_502(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_717_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828390000','717_agentic_acceptance_parity_repair',ARRAY['Exact 716 predecessor and strict execute hash guard','Acceptance context marker bypasses only mutable current-state parity; normal actions retain direct conflict comparison','UID514/task/mailbox/outbound/Production untouched']);
NOTIFY pgrST,'reload schema'; COMMIT;
