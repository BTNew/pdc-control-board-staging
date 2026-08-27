-- STAGING ONLY 707: use a namespaced transaction-local setting for the
-- acceptance-only vehicle projection. PostgreSQL rejects unqualified custom
-- GUC names; this repair changes only the exact 703 setting literal.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-707-acceptance-context-guc-namespace',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h1 text; h2 text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h1 FROM pg_proc p WHERE p.oid='public.read_pdc_agentic_email_vehicle_502(uuid)'::regprocedure;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h2 FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_authenticated_684(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828280000' OR h1<>'81f652ed07c0ed326caf936a8b8a9a26193fa19afec0d6712933d26bf372c65a' OR h2<>'4ac4791d5e9ac98d942433c9d7f7ad9853e7a6d492aa7e4adb14f76ce8648db8' OR to_regclass('public.pdc_authenticated_acceptance_context_guc_history_707') IS NOT NULL THEN RAISE EXCEPTION 'PDC_707_EXACT_706_GUC_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_acceptance_context_guc_history_707(history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),event_key text NOT NULL UNIQUE,event_kind text NOT NULL CHECK(event_kind='acceptance_context_guc_namespace_repair'),predecessor_head text NOT NULL CHECK(predecessor_head='20260828280000'),successor_head text NOT NULL CHECK(successor_head='20260828290000'),predecessor_function_hashes jsonb NOT NULL,successor_function_hashes jsonb NOT NULL,repair_contract text NOT NULL,production_writes boolean NOT NULL CHECK(NOT production_writes),task_enabled boolean NOT NULL CHECK(NOT task_enabled),mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_acceptance_context_guc_history_707 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_acceptance_context_guc_history_707 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_acceptance_context_guc_history_707 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_acceptance_context_guc_history_immutable_707() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_707_CONTEXT_GUC_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_acceptance_context_guc_history_immutable_707() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_acceptance_context_guc_history_immutable_707 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_acceptance_context_guc_history_707 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_acceptance_context_guc_history_immutable_707();
DO $repair$
DECLARE d text; old text; new text; b1 text; b2 text; a1 text; a2 text;
BEGIN
 SELECT pg_get_functiondef('public.read_pdc_agentic_email_vehicle_502(uuid)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,b1 FROM pg_proc p WHERE p.oid='public.read_pdc_agentic_email_vehicle_502(uuid)'::regprocedure;
 old:=$old$pdc_acceptance_context_receipt_703$old$; new:=$new$pdc.acceptance_context_receipt_703$new$;
 IF b1<>'81f652ed07c0ed326caf936a8b8a9a26193fa19afec0d6712933d26bf372c65a' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_707_READ_GUC_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO a1 FROM pg_proc p WHERE p.oid='public.read_pdc_agentic_email_vehicle_502(uuid)'::regprocedure;
 SELECT pg_get_functiondef('public.execute_pdc_agentic_email_action_authenticated_684(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,b2 FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_authenticated_684(jsonb)'::regprocedure;
 IF b2<>'4ac4791d5e9ac98d942433c9d7f7ad9853e7a6d492aa7e4adb14f76ce8648db8' OR position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_707_EXECUTE_GUC_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO a2 FROM pg_proc p WHERE p.oid='public.execute_pdc_agentic_email_action_authenticated_684(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_acceptance_context_guc_history_707(event_key,event_kind,predecessor_head,successor_head,predecessor_function_hashes,successor_function_hashes,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-707-acceptance-context-guc-namespace|forward','UTF8'),'sha256'),'hex'),'acceptance_context_guc_namespace_repair','20260828280000','20260828290000',jsonb_build_object('read_vehicle',b1,'execute_684',b2),jsonb_build_object('read_vehicle',a1,'execute_684',a2),'Namespace the transaction-local acceptance projection context setting so the exact 684 wrapper can set it without changing normal 502 behavior',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_acceptance_context_guc_history_707)<>1 OR position('pdc.acceptance_context_receipt_703' IN (SELECT prosrc FROM pg_proc WHERE oid='public.read_pdc_agentic_email_vehicle_502(uuid)'::regprocedure))=0 OR position('pdc.acceptance_context_receipt_703' IN (SELECT prosrc FROM pg_proc WHERE oid='public.execute_pdc_agentic_email_action_authenticated_684(jsonb)'::regprocedure))=0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_707_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828290000','707_acceptance_context_guc_namespace_repair',ARRAY['Exact 706 predecessor and read/execute function hashes','Namespace only the transaction-local acceptance projection setting to pdc.acceptance_context_receipt_703','Normal Board snapshot, normal vehicle reads, UID514, task, mailbox, outbound and Production remain unchanged']);
NOTIFY pgrST,'reload schema'; COMMIT;
