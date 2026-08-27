-- STAGING ONLY 687: repair the 686 synthetic fixture date expression.
-- Append-only, exact-function-hash guarded, and limited to the test campaign seed.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-687-acceptance-fixture-date-cast',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) filter(where version~'^[0-9]{14}$') FROM supabase_migrations.schema_migrations)<>'20260828070000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828070000' AND name='686_authenticated_acceptance_campaign_fixtures')<>1
    OR to_regclass('public.pdc_authenticated_email_acceptance_campaign_repair_history_687') IS NOT NULL
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828080000')<>0
    OR h<>'d05d9ee11d9ad2b3e7bd9e01f26e67aa5d878535d2bfb3eaf90a94213184c0c4'
    OR position('case when v_case=''parts_eta'' then null else null end' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure))=0
    OR (SELECT count(*) FROM public.ai_email_intake WHERE id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid AND provider_uid='imap_uid:514' AND queue_attempts=10)<>1
    OR (SELECT count(*) FROM public.pdc_jobcard_attachment_import_receipts WHERE receipt_id='d9eebe4a-1b7b-4c98-97bd-fc49fcd8fa6f'::uuid AND estimated_hours_sum=7.46 AND operation_count=5)<>1
 THEN RAISE EXCEPTION 'PDC_687_EXACT_686_OR_UID514_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
END $guard$;
CREATE TABLE public.pdc_authenticated_email_acceptance_campaign_repair_history_687(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='fixture_date_cast_repair'),
 predecessor_head text NOT NULL CHECK(predecessor_head='20260828070000'), successor_head text NOT NULL CHECK(successor_head='20260828080000'),
 predecessor_function_sha256 text NOT NULL, successor_function_sha256 text NOT NULL,
 repair_anchor text NOT NULL, repair_contract text NOT NULL,
 production_writes boolean NOT NULL CHECK(NOT production_writes), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_repair_history_687 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_authenticated_email_acceptance_campaign_repair_history_687 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_authenticated_email_acceptance_campaign_repair_history_687 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_authenticated_email_acceptance_campaign_repair_history_immutable_687() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_687_REPAIR_HISTORY_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_authenticated_email_acceptance_campaign_repair_history_immutable_687 BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_acceptance_campaign_repair_history_687 FOR EACH ROW EXECUTE FUNCTION public.pdc_authenticated_email_acceptance_campaign_repair_history_immutable_687();
DO $repair$
DECLARE d text; old text; new text; before_sha text; after_sha text;
BEGIN
 SELECT pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure) INTO d;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO before_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 old:=$old$case when v_case='parts_eta' then null else null end$old$;
 new:=$new$case when v_case='parts_eta' then null::date else null::date end$new$;
 IF position(old IN d)=0 THEN RAISE EXCEPTION 'PDC_687_DATE_CAST_ANCHOR_MISSING' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO after_sha FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure;
 INSERT INTO public.pdc_authenticated_email_acceptance_campaign_repair_history_687(event_key,event_kind,predecessor_head,successor_head,predecessor_function_sha256,successor_function_sha256,repair_anchor,repair_contract,production_writes) VALUES(encode(extensions.digest(convert_to('pdc-staging-687-acceptance-fixture-date-cast|forward','UTF8'),'sha256'),'hex'),'fixture_date_cast_repair','20260828070000','20260828080000',before_sha,after_sha,'case when v_case=''parts_eta'' then null else null end','Only the synthetic campaign seed date expression was typed as date; no UID514 or operational source was changed',false);
END $repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_authenticated_email_acceptance_campaign_repair_history_687 WHERE event_kind='fixture_date_cast_repair')<>1
    OR position('null::date' IN (SELECT p.prosrc FROM pg_proc p WHERE p.oid='public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure))=0
    OR (SELECT count(*) FROM public.pdc_provider_email_observations WHERE intake_id='102e286d-1799-4c97-8e45-e0da9fb31c63'::uuid)<>1
    OR (SELECT count(*) FROM public.vehicles WHERE public.normalize_vehicle_stock_number(stock_number)='13016925')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'PDC_687_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828080000','687_acceptance_fixture_date_cast_repair',ARRAY['Exact applied 686 head, create-function hash, date-expression anchor and terminal UID514 safety guards','Patch only the synthetic acceptance campaign parts_eta date CASE to explicit date NULL casts','Retain forced-RLS immutable repair history; no task, mailbox, UID514, vehicle or Production mutation']);
NOTIFY pgrst,'reload schema';
COMMIT;
