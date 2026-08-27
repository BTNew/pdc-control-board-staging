-- STAGING ONLY 705: volatility repair for the 703/704 acceptance context
-- projection. The projection persists a strict 502 receipt, so it must be
-- VOLATILE; all exact scope, synthetic markers and normal-path guards remain.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-705-acceptance-context-projection-volatility',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828260000' OR (SELECT count(*) FROM public.pdc_authenticated_acceptance_context_projection_repair_history_704)=1 AND h<>'b5bafd6f3460aa9bf8ccb0bffac67aa3a030e2592a3f7c70cd04f90f97647788' OR to_regclass('public.pdc_authenticated_acceptance_context_projection_volatility_history_705') IS NOT NULL THEN RAISE EXCEPTION 'PDC_705_EXACT_704_PROJECTION_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_acceptance_context_projection_volatility_history_705(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='acceptance_context_projection_volatility_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828260000'), successor_head text NOT NULL CHECK(successor_head='20260828270000'),
 predecessor_function_sha256 text NOT NULL CHECK(predecessor_function_sha256='b5bafd6f3460aa9bf8ccb0bffac67aa3a030e2592a3f7c70cd04f90f97647788'), successor_function_sha256 text NOT NULL,
 repair_contract text NOT NULL, production_writes boolean NOT NULL CHECK(NOT production_writes), task_enabled boolean NOT NULL CHECK(NOT task_enabled), mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted), uid514_processed boolean NOT NULL CHECK(NOT uid514_processed), created_at timestamptz NOT NULL DEFAULT clock_timestamp());
ALTER TABLE public.pdc_authenticated_acceptance_context_projection_volatility_history_705 ENABLE ROW LEVEL SECURITY; ALTER TABLE public.pdc_authenticated_acceptance_context_projection_volatility_history_705 FORCE ROW LEVEL SECURITY; REVOKE ALL ON public.pdc_authenticated_acceptance_context_projection_volatility_history_705 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_acceptance_context_projection_volatility_history_immutable_705() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_705_CONTEXT_PROJECTION_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_authenticated_acceptance_context_projection_volatility_history_immutable_705() FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE TRIGGER pdc_authenticated_acceptance_context_projection_volatility_history_immutable_705 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_acceptance_context_projection_volatility_history_705 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_acceptance_context_projection_volatility_history_immutable_705();
DO $repair$
DECLARE d text; before_sha text; after_sha text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb)'::regprocedure),encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO d,before_sha FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb)'::regprocedure;
 IF before_sha<>'b5bafd6f3460aa9bf8ccb0bffac67aa3a030e2592a3f7c70cd04f90f97647788' OR position('STABLE SECURITY DEFINER' IN d)=0 THEN RAISE EXCEPTION 'PDC_705_VOLATILITY_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(d,'STABLE SECURITY DEFINER','VOLATILE SECURITY DEFINER');
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb)'::regprocedure;
 INSERT INTO public.pdc_authenticated_acceptance_context_projection_volatility_history_705(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes,task_enabled,mailbox_contacted,uid514_processed) VALUES(encode(extensions.digest(convert_to('pdc-staging-705-acceptance-context-projection-volatility|forward','UTF8'),'sha256'),'hex'),'acceptance_context_projection_volatility_repair','20260828260000','20260828270000',before_sha,after_sha,'Mark the receipt-persisting exact acceptance context projection VOLATILE; no predicate, state projection, normal Board behavior or 684 wrapper semantics change',false,false,false,false);
END $repair$;
DO $post$ BEGIN IF (SELECT count(*) FROM public.pdc_authenticated_acceptance_context_projection_volatility_history_705)<>1 OR to_regprocedure('public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb)') IS NULL OR (SELECT provolatile FROM pg_proc WHERE oid='public.pdc_monitor_authenticated_acceptance_context_projection_703(jsonb)'::regprocedure)<>'v' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_705_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828270000','705_acceptance_context_projection_volatility_repair',ARRAY['Exact live 704 projection hash and staging-only predecessor guard','Receipt-persisting acceptance context projection is VOLATILE as required for strict 502 receipt persistence','No scope, state projection, normal Board path, UID514/task/mailbox/outbound or Production behavior changed']);
NOTIFY pgrST,'reload schema'; COMMIT;
