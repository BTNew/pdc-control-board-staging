-- STAGING ONLY 395: restore QC operation lines on the final vehicle snapshot.
-- This is an additive projection wrapper. It preserves the underlying snapshot
-- contract and only overlays the canonical 379 QC lines for each returned row.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-395-restore-qc-operation-projection',0));

DO $pre$
DECLARE
  v_head text;
BEGIN
  SELECT max(version) INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version ~ '^[0-9]{14}$';
  IF current_user<>'postgres'
    OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
        WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR NOT public.pdc_monitor_staging_guard()
    OR v_head IS DISTINCT FROM '20260826100000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations
        WHERE version='20260826100000' AND name='394_admin_compaction_and_duration_bounds')<>1
    OR to_regprocedure('public.pdc_qc_operation_lines_379(uuid)') IS NULL
    OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>0
    OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM
       jsonb_build_object('rows',1512,'sha256','dc80e0b6b88557a8fef1de67c3b1d45afa915161d1ae6841d14a2b5403977c6b') THEN
    RAISE EXCEPTION 'PDC_395_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot()
  RENAME TO get_pdc_email_vehicle_location_snapshot_pre_395;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_395() FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $snapshot$
DECLARE
  v_result jsonb;
  v_rows jsonb;
BEGIN
  v_result:=public.get_pdc_email_vehicle_location_snapshot_pre_395();
  IF NOT coalesce((v_result->>'ok')::boolean,false) THEN RETURN v_result; END IF;

  SELECT coalesce(jsonb_agg(
    vehicle||jsonb_build_object(
      'qc_operation_lines',public.pdc_qc_operation_lines_379((vehicle->>'id')::uuid)
    ) ORDER BY ordinal
  ),'[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(coalesce(v_result#>'{data,vehicles}','[]'::jsonb))
    WITH ORDINALITY rows(vehicle,ordinal);

  RETURN jsonb_set(v_result,'{data,vehicles}',v_rows,true);
END $snapshot$;

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated,service_role;
COMMENT ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() IS
  'Staging authenticated-email vehicle snapshot preserving the current source contract and projecting canonical QC operation lines 379 for every returned vehicle.';

DO $post$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure)
    INTO v_definition;
  IF position('pdc_qc_operation_lines_379' IN v_definition)=0
    OR position('qc_operation_lines' IN v_definition)=0
    OR has_function_privilege('public','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR has_function_privilege('anon','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR NOT has_function_privilege('service_role','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>0
    OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM
       jsonb_build_object('rows',1512,'sha256','dc80e0b6b88557a8fef1de67c3b1d45afa915161d1ae6841d14a2b5403977c6b') THEN
    RAISE EXCEPTION 'PDC_395_QC_PROJECTION_OR_ACL_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826110000','395_restore_qc_operation_projection',ARRAY[
  'Final authenticated vehicle snapshot preserves every existing source field and contract',
  'Each returned vehicle receives canonical pdc_qc_operation_lines_379 output as qc_operation_lines',
  'snapshot_has_qc=true is proven by the live function definition and postcondition',
  'QC identity, hour, version, receipt, RLS, grants and fail-closed mutation rules are unchanged',
  'No operational evidence rows, notifications or protected acceptance rows are mutated'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
