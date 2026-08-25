-- STAGING ONLY 405: route canonical Sublet provider updates for an exact
-- HERMES-TEST vehicle through the existing migration-365 guard.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-405-sublet-provider-synthetic-wrapper',0));
DO $fix$
DECLARE v_head text; v_definition text; v_corrected text;
DECLARE v_anchor text:='  UPDATE public.pdc_sublet_booking_instances SET provider_id=';
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826151500'
    OR to_regprocedure('public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_405_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
  SELECT pg_get_functiondef('public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)'::regprocedure) INTO v_definition;
  IF position(v_anchor in v_definition)=0 OR position('pdc.hermes_test_wrapper_vehicle_365' in v_definition)>0 THEN
    RAISE EXCEPTION 'PDC_405_SYNTHETIC_WRAPPER_PATCH_ANCHOR_MISMATCH' USING errcode='55000';
  END IF;
  v_corrected:=replace(v_definition,v_anchor,
    '  PERFORM set_config(''pdc.hermes_test_wrapper_vehicle_365'',v_before.vehicle_id::text,true);'||chr(10)||v_anchor);
  EXECUTE v_corrected;
END $fix$;
REVOKE ALL ON FUNCTION public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid) TO authenticated;
DO $post$
DECLARE d text:=pg_get_functiondef('public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)'::regprocedure);
BEGIN
  IF position('pdc.hermes_test_wrapper_vehicle_365' in d)=0
    OR has_function_privilege('public','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_405_SYNTHETIC_WRAPPER_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826153000','405_sublet_provider_exact_synthetic_wrapper',ARRAY[
  'Set the existing migration-365 transaction-local guard to the exact canonical Sublet booking vehicle UUID before provider mutation',
  'No authority broadening and no operational row mutation in this migration'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
