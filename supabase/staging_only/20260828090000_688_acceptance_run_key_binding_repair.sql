-- STAGING ONLY 688: bind the campaign run primary key used by fixtures.
-- Append-only exact-function-hash repair after 687. No operational data path.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-688-acceptance-run-key-binding',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) filter(where version~'^[0-9]{14}$') FROM supabase_migrations.schema_migrations)<>'20260828080000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828070000' AND name='686_authenticated_acceptance_campaign_fixtures')<>1
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828080000' AND name='687_acceptance_fixture_date_cast_repair')<>1
    OR to_regclass('public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_688') IS NOT NULL
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828090000')<>0
    OR h<>'c58893dc9fdb7d03c8f614ba3a86c8a25b0f7c98412201f4d573dde533b14256'
    OR position('INSERT INTO public.pdc_authenticated_email_acceptance_campaign_runs_686(namespace' IN (SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)))=0
 THEN RAISE EXCEPTION 'PDC_688_EXACT_687_CREATE_FUNCTION_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_688(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='run_key_binding_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828080000'), successor_head text NOT NULL CHECK(successor_head='20260828090000'),
 predecessor_function_sha256 text NOT NULL, successor_function_sha256 text NOT NULL,
 repair_contract text NOT NULL, production_writes boolean NOT NULL CHECK(NOT production_writes),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_688 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_688 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_688 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_immutable_688() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_688_RUN_KEY_REPAIR_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_authenticated_email_acceptance_campaign_run_key_repair_history_immutable_688 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_688 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_immutable_688();
DO $repair$
DECLARE d text; old text; new text; before_sha text; after_sha text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure) INTO d;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO before_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 old:=$old$INSERT INTO public.pdc_authenticated_email_acceptance_campaign_runs_686(namespace,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,status,acceptance_case_count)$old$;
 new:=$new$INSERT INTO public.pdc_authenticated_email_acceptance_campaign_runs_686(run_id,namespace,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,status,acceptance_case_count)$new$;
 IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_688_RUN_KEY_INSERT_ANCHOR_MISSING' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 INSERT INTO public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_688(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes) VALUES(encode(extensions.digest(convert_to('pdc-staging-688-acceptance-run-key-binding|forward','UTF8'),'sha256'),'hex'),'run_key_binding_repair','20260828080000','20260828090000',before_sha,after_sha,'Use the generated v_run UUID as the campaign run primary key so all synthetic fixture foreign keys bind to that run; no UID514/real vehicle/Production change',false);
END $repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_authenticated_email_acceptance_campaign_run_key_repair_history_688 WHERE event_kind='run_key_binding_repair')<>1
    OR position('runs_686(run_id,namespace' IN (SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)))=0
    OR (SELECT count(*) FROM public.pdc_provider_email_observations WHERE intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid)<>1
    OR (SELECT count(*) FROM public.vehicles WHERE public.normalize_vehicle_stock_number(stock_number)='13016925')<>1
 THEN RAISE EXCEPTION 'PDC_688_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828090000','688_acceptance_run_key_binding_repair',ARRAY['Exact 687 predecessor, create-function SHA and run-insert anchor guard','Bind generated v_run explicitly as the campaign run primary key for all synthetic fixture foreign keys','Retain forced-RLS immutable repair history; no UID514, real vehicle, task, mailbox or Production mutation']);
NOTIFY pgrST,'reload schema';
COMMIT;
