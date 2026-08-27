-- STAGING ONLY 689: bind v_run in the campaign run INSERT values.
-- Append-only exact-function-hash repair after 688.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-689-acceptance-run-values-binding',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) filter(where version~'^[0-9]{14}$') FROM supabase_migrations.schema_migrations)<>'20260828090000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828090000' AND name='688_acceptance_run_key_binding_repair')<>1
    OR to_regclass('public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_689') IS NOT NULL
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828100000')<>0
    OR h<>'147383f7d9d151111468b47e91441dbac3a0678222ca6725f7943d4779b9ae41'
    OR position('VALUES(v_namespace,v_actor,v_email,''authenticated'',''importer''' IN (SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)))=0
 THEN RAISE EXCEPTION 'PDC_689_EXACT_688_CREATE_FUNCTION_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_689(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='run_values_binding_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828090000'), successor_head text NOT NULL CHECK(successor_head='20260828100000'),
 predecessor_function_sha256 text NOT NULL, successor_function_sha256 text NOT NULL,
 repair_contract text NOT NULL, production_writes boolean NOT NULL CHECK(NOT production_writes),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_689 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_689 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_689 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_immutable_689() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_689_RUN_VALUES_REPAIR_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_authenticated_email_acceptance_campaign_run_values_repair_history_immutable_689 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_689 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_immutable_689();
DO $repair$
DECLARE d text; old text; new text; before_sha text; after_sha text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure) INTO d;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO before_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 old:=$old$VALUES(v_namespace,v_actor,v_email,'authenticated','importer'$old$;
 new:=$new$VALUES(v_run,v_namespace,v_actor,v_email,'authenticated','importer'$new$;
 IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_689_RUN_VALUES_ANCHOR_MISSING' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 INSERT INTO public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_689(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes) VALUES(encode(extensions.digest(convert_to('pdc-staging-689-acceptance-run-values-binding|forward','UTF8'),'sha256'),'hex'),'run_values_binding_repair','20260828090000','20260828100000',before_sha,after_sha,'Bind v_run in the run INSERT values to the same generated UUID already used by every synthetic fixture FK; no UID514/real vehicle/Production change',false);
END $repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_authenticated_email_acceptance_campaign_run_values_repair_history_689 WHERE event_kind='run_values_binding_repair')<>1
    OR position('VALUES(v_run,v_namespace,v_actor' IN (SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)))=0
 THEN RAISE EXCEPTION 'PDC_689_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828100000','689_acceptance_run_values_binding_repair',ARRAY['Exact 688 predecessor, create-function SHA and run-values anchor guard','Bind v_run explicitly in the run INSERT values so synthetic fixture foreign keys use the persisted run','Retain forced-RLS immutable repair history; no UID514, real vehicle, task, mailbox or Production mutation']);
NOTIFY pgrST,'reload schema';
COMMIT;
