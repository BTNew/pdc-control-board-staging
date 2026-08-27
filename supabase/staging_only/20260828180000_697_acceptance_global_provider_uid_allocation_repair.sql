-- STAGING ONLY 697: global synthetic provider UID allocation for the 684-wrapper campaign.
-- Exact observed 696 predecessor; no operational or UID514 mutation.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-697-acceptance-global-provider-uid',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) filter(where version~'^[0-9]{14}$') FROM supabase_migrations.schema_migrations)<>'20260828170000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828170000' AND name='696_acceptance_run_primary_key_binding_repair')<>1
    OR to_regclass('public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_697') IS NOT NULL
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828180000')<>0
    OR h<>'18378940fd6b0fcfd730bd68bb89e29d709be69bb07f8f05b9c470ceac7c52d7'
    OR position('max(substring(provider_uid from 10)::bigint)' IN (SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)))=0
 THEN RAISE EXCEPTION 'PDC_697_EXACT_696_CREATE_FUNCTION_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_697(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='global_provider_uid_allocation_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828170000'), successor_head text NOT NULL CHECK(successor_head='20260828180000'),
 predecessor_function_sha256 text NOT NULL, successor_function_sha256 text NOT NULL,
 repair_contract text NOT NULL, production_writes boolean NOT NULL CHECK(NOT production_writes), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_697 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_697 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_697 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_immutable_697() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_697_GLOBAL_UID_REPAIR_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_immutable_697 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_697 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_immutable_697();
DO $repair$
DECLARE d text; old text; new text; before_sha text; after_sha text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure) INTO d;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO before_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 old:=$old$v_uid integer:=coalesce((SELECT max(substring(provider_uid from 10)::bigint)::integer FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686),514)$old$;
 new:=$new$v_uid integer:=coalesce((SELECT max(uid) FROM (SELECT max(substring(provider_uid from 10)::bigint)::integer uid FROM public.pdc_authenticated_email_acceptance_campaign_fixtures_686 UNION ALL SELECT max(substring(provider_uid from 10)::bigint)::integer uid FROM public.ai_email_intake WHERE provider_uid~'^imap_uid:[0-9]+$') u),514)$new$;
 IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_697_GLOBAL_UID_ANCHOR_MISSING' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 INSERT INTO public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_697(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes) VALUES(encode(extensions.digest(convert_to('pdc-staging-697-acceptance-global-provider-uid|forward','UTF8'),'sha256'),'hex'),'global_provider_uid_allocation_repair','20260828170000','20260828180000',before_sha,after_sha,'Allocate above every retained ai_email_intake and campaign fixture provider UID while preserving immutable receipts and UID >=515; no UID514/real vehicle/Production change',false);
END $repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_authenticated_email_acceptance_campaign_uid_global_repair_history_697 WHERE event_kind='global_provider_uid_allocation_repair')<>1
    OR position('FROM public.ai_email_intake WHERE provider_uid' IN (SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)))=0
 THEN RAISE EXCEPTION 'PDC_697_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828180000','697_acceptance_global_provider_uid_allocation_repair',ARRAY['Exact observed 696 predecessor, create-function SHA and global intake UID allocator guard','Allocate the next synthetic provider UID above retained campaign and all intake rows, never below 515','Retain forced-RLS immutable repair history; no UID514, real vehicle, task, mailbox or Production mutation']);
NOTIFY pgrST,'reload schema';
COMMIT;
