-- STAGING ONLY 389: include allowlisted detail fields in the exact synthetic route.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-389-salesperson-detail-route',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825232000' AND name='388_authoritative_vehicle_detail_fields')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825232000')
   OR to_regprocedure('public.pdc_salesperson_synthetic_route_387()') IS NULL THEN
  RAISE EXCEPTION 'PDC_389_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $pre$;
DROP TRIGGER IF EXISTS aa_pdc_salesperson_synthetic_route_387 ON public.vehicles;
CREATE TRIGGER aa_pdc_salesperson_synthetic_route_387
BEFORE UPDATE OF customer_name,key_number,job_card_number,salesperson_reference,salesperson_id,salesperson_manual_override,salesperson_manual_override_at,salesperson_manual_override_by
ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.pdc_salesperson_synthetic_route_387();
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825233000','389_salesperson_detail_route',ARRAY['Existing exact HERMES-TEST route now covers the allowlisted client, PMB key and JC detail columns']);
NOTIFY pgrst,'reload schema';
COMMIT;
