-- STAGING ONLY 690: keep synthetic Job Card identifiers within parser bounds.
-- Append-only exact-function-hash repair after 689.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-690-acceptance-bounded-job-card',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) filter(where version~'^[0-9]{14}$') FROM supabase_migrations.schema_migrations)<>'20260828100000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828100000' AND name='689_acceptance_run_values_binding_repair')<>1
    OR to_regclass('public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_690') IS NOT NULL
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828110000')<>0
    OR h<>'53a0b949dc7a5d8143dbc25c041abc599dbce68166c861e77c387961e95a2275'
    OR position('v_job:=''PDC686-''||replace(v_run::text,''-'','''')||''-''||v_case' IN (SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)))=0
 THEN RAISE EXCEPTION 'PDC_690_EXACT_689_CREATE_FUNCTION_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_690(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='bounded_job_card_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828100000'), successor_head text NOT NULL CHECK(successor_head='20260828110000'),
 predecessor_function_sha256 text NOT NULL, successor_function_sha256 text NOT NULL,
 repair_contract text NOT NULL, production_writes boolean NOT NULL CHECK(NOT production_writes),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_690 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_690 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_690 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_immutable_690() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_690_JOB_CARD_REPAIR_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_authenticated_email_acceptance_campaign_job_card_repair_history_immutable_690 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_690 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_immutable_690();
DO $repair$
DECLARE d text; old text; new text; before_sha text; after_sha text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure) INTO d;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO before_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 old:=$old$v_job:='PDC686-'||replace(v_run::text,'-','')||'-'||v_case$old$;
 new:=$new$v_job:='PDC686-'||substring(replace(v_run::text,'-','') from 1 for 10)||'-'||case v_case when 'parts_complete' then 'PC' when 'parts_eta' then 'PE' when 'sublet_booking_date' then 'SB' when 'multi_action' then 'MA' when 'update_existing_not_duplicate' then 'UN' when 'exact_replay' then 'ER' else 'AN' end$new$;
 IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_690_JOB_CARD_ANCHOR_MISSING' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 INSERT INTO public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_690(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_contract,production_writes) VALUES(encode(extensions.digest(convert_to('pdc-staging-690-acceptance-bounded-job-card|forward','UTF8'),'sha256'),'hex'),'bounded_job_card_repair','20260828100000','20260828110000',before_sha,after_sha,'Keep each synthetic Job Card uniquely namespaced by run and case code while remaining within the reviewed 32-character parser bound; no UID514/real vehicle/Production change',false);
END $repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_authenticated_email_acceptance_campaign_job_card_repair_history_690 WHERE event_kind='bounded_job_card_repair')<>1
    OR position('substring(replace(v_run::text,''-'','''') from 1 for 10)' IN (SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)))=0
 THEN RAISE EXCEPTION 'PDC_690_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828110000','690_acceptance_bounded_job_card_repair',ARRAY['Exact 689 predecessor, create-function SHA and bounded Job Card anchor guard','Generate unique namespaced synthetic Job Cards within the 32-character parser bound','Retain forced-RLS immutable repair history; no UID514, real vehicle, task, mailbox or Production mutation']);
NOTIFY pgrST,'reload schema';
COMMIT;
