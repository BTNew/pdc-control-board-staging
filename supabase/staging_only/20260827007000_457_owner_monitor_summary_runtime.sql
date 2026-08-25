-- STAGING ONLY 457: bind concise owner-facing monitor output bytes.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-457-owner-monitor-summary',0));
DO $pre$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827006000' AND name='456_final_inbox_monitor_runtime')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827006000')
 THEN RAISE EXCEPTION 'PDC_457_STAGING_HEAD_MISMATCH' USING errcode='55000';END IF;
END $pre$;
CREATE TABLE public.pdc_email_monitor_owner_summary_receipts_457(
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),project_ref text NOT NULL CHECK(project_ref='cdsmnqxtyyoeoznmbidd'),
 actor_id uuid NOT NULL CHECK(actor_id='69846ef4-a74c-4569-9e35-376cf0837888'::uuid),
 monitor_sha256 text NOT NULL CHECK(monitor_sha256~'^[a-f0-9]{64}$'),bridge_sha256 text NOT NULL CHECK(bridge_sha256~'^[a-f0-9]{64}$'),processor_sha256 text NOT NULL CHECK(processor_sha256~'^[a-f0-9]{64}$'),manifest_sha256 text NOT NULL CHECK(manifest_sha256~'^[a-f0-9]{64}$'),
 output_policy text NOT NULL CHECK(output_policy='silent when idle; concise Stock Job Card operation and archive-review counts on activity'),
 production_untouched boolean NOT NULL CHECK(production_untouched),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
REVOKE ALL ON public.pdc_email_monitor_owner_summary_receipts_457 FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.pdc_email_monitor_owner_summary_immutable_457() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN RAISE EXCEPTION 'PDC_457_RECEIPT_IMMUTABLE' USING errcode='55000';END$$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_owner_summary_immutable_457() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_monitor_owner_summary_immutable_457 BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_owner_summary_receipts_457 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_owner_summary_immutable_457();
INSERT INTO public.pdc_email_monitor_owner_summary_receipts_457(project_ref,actor_id,monitor_sha256,bridge_sha256,processor_sha256,manifest_sha256,output_policy,production_untouched)
VALUES('cdsmnqxtyyoeoznmbidd','69846ef4-a74c-4569-9e35-376cf0837888','2ff34699e9dd576f8d985cb779a220c8b56a1c4626d3052d11df18e4cc0bb75d','b12a2a9b8d601cac4e66b3d54930807860f5fa54f6c60e1878cf38f9c033860d','89de3a94ef6d8ec4840f60017d40747b76f2080e316b9eeb28a105b33a1b01a3','83b3e2ac3a1d71a6ab0dc55f215d6d154dee0a8b9d4be081b9c0151b42e2cd2d','silent when idle; concise Stock Job Card operation and archive-review counts on activity',true);
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827007000','457_owner_monitor_summary_runtime',ARRAY['Owner-facing activity output is concise and omits internal receipt, UID and hash details','Idle cycles remain silent; Production and outbound email remain untouched']);
COMMIT;
