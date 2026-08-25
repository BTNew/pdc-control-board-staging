-- STAGING ONLY 378: exact canonical Navision JITA projection into shared Board rows.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-378-navision-jita-projection',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825140000' AND name='377_parts_order_requires_eta')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825140000')
   OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') IS NULL
   OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot_pre_378()') IS NOT NULL
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM jsonb_build_object('rows',1498,'sha256','cb43c3582df4fd646ffb457a627273ce59dc273034bc0e7b95c24c13f2dc437e') THEN
  RAISE EXCEPTION 'PDC_378_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_378;

CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE v_snapshot jsonb; v_vehicles jsonb;
BEGIN
 v_snapshot:=public.get_pdc_email_vehicle_location_snapshot_pre_378();
 IF jsonb_typeof(v_snapshot#>'{data,vehicles}')<>'array' THEN RAISE EXCEPTION 'PDC_378_PREDECESSOR_SHAPE_MISMATCH' USING errcode='55000'; END IF;
 SELECT coalesce(jsonb_agg(
  vehicle||jsonb_build_object(
   'navision_jita_identity_verified',coalesce(candidate.match_count,0)=1,
   'navision_jita_column_present',CASE WHEN candidate.match_count=1 THEN candidate.column_present ELSE false END,
   'navision_jita_number_authority',CASE WHEN candidate.match_count=1 AND candidate.column_present THEN candidate.authority ELSE NULL END,
   'navision_jita_number',CASE WHEN candidate.match_count=1 AND candidate.column_present THEN candidate.jita_number ELSE NULL END,
   'navision_jita_identity_status',CASE WHEN coalesce(candidate.match_count,0)=0 THEN 'not_found' WHEN candidate.match_count=1 THEN 'exact' ELSE 'ambiguous' END
  ) ORDER BY ordinal),'[]'::jsonb) INTO v_vehicles
 FROM jsonb_array_elements(v_snapshot#>'{data,vehicles}') WITH ORDINALITY rows(vehicle,ordinal)
 LEFT JOIN LATERAL(
  SELECT count(*) match_count,
   max(coalesce((n.normalized_data->>'_navisionJitaNumberColumnPresent')::boolean,false)::text)::boolean column_present,
   max(n.normalized_data->>'navisionJitaNumberAuthority') authority,
   max(n.normalized_data->>'jitQty') jita_number
  FROM public.navision_backend_records n
  WHERE n.is_current AND n.canonical_vehicle_id=(vehicle->>'id')::uuid
    AND upper(btrim(coalesce(n.normalized_data->>'stock','')))=upper(btrim(coalesce(vehicle->>'stock_number','')))
 ) candidate ON true;
 RETURN jsonb_set(v_snapshot,'{data,vehicles}',v_vehicles,false);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated,service_role;

DO $post$
DECLARE v_def text:=pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure);
BEGIN
 IF position('navision_jita_identity_verified' in v_def)=0 OR position('canonical_vehicle_id' in v_def)=0
   OR position('normalized_data->>''stock''' in v_def)=0 OR position('match_count=1' in replace(v_def,' ',''))=0
   OR has_function_privilege('public','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
   OR has_function_privilege('anon','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
   OR NOT has_function_privilege('service_role','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_378_FUNCTION_OR_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825150000','378_navision_jita_shared_projection',array[
 'Exact current canonical_vehicle_id plus normalized Stock match; zero or multiple candidates fail closed',
 'Validated-navision-import-v1 authority, explicit column-presence and exact non-zero JITA number projected to Board rows',
 'No inference from free text; explicit blank remains blank and omission behavior stays owned by Navision normalization',
 'Authenticated and service-role snapshot ACL preserved with public/anon denied'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
