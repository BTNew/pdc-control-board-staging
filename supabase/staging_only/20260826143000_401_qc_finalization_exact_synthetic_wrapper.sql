-- STAGING ONLY 401: allow migration-399 finalization to mutate only its exact
-- HERMES-TEST vehicle through the existing migration-365 guard.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-401-qc-finalization-synthetic-wrapper',0));

DO $fix$
DECLARE v_head text; v_definition text; v_corrected text; v_anchor text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826141500'
    OR to_regprocedure('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)') IS NULL
    OR to_regprocedure('public.pdc_hermes_test_actor_route_guard_365()') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_401_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;

  SELECT pg_get_functiondef('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure) INTO v_definition;
  v_anchor:='  UPDATE public.vehicles SET qc_completed_at=';
  IF position(v_anchor in v_definition)=0 OR position('pdc.hermes_test_wrapper_vehicle_365' in v_definition)>0 THEN
    RAISE EXCEPTION 'PDC_401_SYNTHETIC_WRAPPER_PATCH_ANCHOR_MISMATCH' USING errcode='55000';
  END IF;
  v_corrected:=replace(v_definition,v_anchor,
    '  PERFORM set_config(''pdc.hermes_test_wrapper_vehicle_365'',p_vehicle_id::text,true);'||chr(10)||v_anchor);
  EXECUTE v_corrected;
END $fix$;

REVOKE ALL ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) TO authenticated;

DO $post$
BEGIN
  IF position('pdc.hermes_test_wrapper_vehicle_365' in pg_get_functiondef('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure))=0
    OR has_function_privilege('public','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_401_SYNTHETIC_WRAPPER_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826143000','401_qc_finalization_exact_synthetic_wrapper',ARRAY[
  'Set the existing migration-365 transaction-local guard to the exact finalization vehicle UUID before QC-to-RFT mutation',
  'No authority broadening and no operational row mutation in the migration'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
