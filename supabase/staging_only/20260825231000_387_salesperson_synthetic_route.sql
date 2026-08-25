-- STAGING ONLY 387: route registry-bound salesperson writes through the
-- existing HERMES-TEST wrapper containment trigger without broad DML access.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-387-salesperson-synthetic-route',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825230000' AND name='386_authoritative_salesperson_assignment')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825230000')
   OR to_regprocedure('public.assign_pdc_vehicle_salesperson_386(uuid,integer,text,uuid)') IS NULL
   OR to_regprocedure('public.pdc_hermes_test_actor_route_guard_365()') IS NULL THEN
  RAISE EXCEPTION 'PDC_387_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.pdc_salesperson_synthetic_route_387()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $route$
BEGIN
 IF auth.uid() IS NOT NULL
   AND EXISTS(
     SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
     WHERE r.run_id='HERMES-TEST-RUN-20260824' AND r.vehicle_id=NEW.id AND r.actor_id=auth.uid()
   ) THEN
   PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',NEW.id::text,true);
 END IF;
 RETURN NEW;
END $route$;
REVOKE ALL ON FUNCTION public.pdc_salesperson_synthetic_route_387() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS aa_pdc_salesperson_synthetic_route_387 ON public.vehicles;
CREATE TRIGGER aa_pdc_salesperson_synthetic_route_387
BEFORE UPDATE OF salesperson_reference,salesperson_id,salesperson_manual_override,salesperson_manual_override_at,salesperson_manual_override_by
ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.pdc_salesperson_synthetic_route_387();

DO $post$
BEGIN
 IF NOT EXISTS(
   SELECT 1 FROM pg_trigger
   WHERE tgname='aa_pdc_salesperson_synthetic_route_387'
     AND tgrelid='public.vehicles'::regclass AND tgenabled='O' AND NOT tgisinternal
     AND tgfoid='public.pdc_salesperson_synthetic_route_387()'::regprocedure
 ) OR has_function_privilege('public','public.pdc_salesperson_synthetic_route_387()','EXECUTE')
   OR has_function_privilege('anon','public.pdc_salesperson_synthetic_route_387()','EXECUTE')
   OR has_function_privilege('authenticated','public.pdc_salesperson_synthetic_route_387()','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_salesperson_synthetic_route_387()','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_387_ROUTE_ACL_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825231000','387_salesperson_synthetic_route',ARRAY[
 'Registry-bound HERMES-TEST salesperson assignment invokes the existing exact-vehicle wrapper route guard',
 'No direct table privileges, no protected-vehicle bypass, no notifications'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
