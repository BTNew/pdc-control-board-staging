-- STAGING ONLY: PIT remains immutable deferred-QC evidence and is not a physical Workshop/QC gate.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010300-defer-pit-from-physical-qc-gate',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text; v_gate text; v_ready text;
BEGIN
 SELECT version INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 v_gate:=pg_get_functiondef('public.pdc_qc_gate_issues(uuid)'::regprocedure);
 v_ready:=pg_get_functiondef('public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure);
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260904010200'
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904010300')
    OR v_gate NOT LIKE '%wi.required and not wi.completed%'
    OR v_gate NOT LIKE '%not in (''QC'',''PARTS'')%'
    OR v_ready NOT LIKE '%perform public.require_pdc_role(''operator'')%'
    OR v_ready NOT LIKE '%v_before.version<>p_expected_version%'
    OR v_ready NOT LIKE '%vehicle_version_conflict%'
    OR v_ready NOT LIKE '%set current_location=''QC'',version=version+1,updated_by=auth.uid()%'
    OR v_ready NOT LIKE '%public.audit_pdc_event(%'
 THEN RAISE EXCEPTION 'PDC_20260904010300_STAGING_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_qc_gate_issues(p_vehicle_id uuid)
RETURNS text[]
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH vehicle AS (
    SELECT id,upper(btrim(coalesce(current_location,''))) location,
           regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g') stage
    FROM public.vehicles WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL
  ), outstanding AS (
    SELECT string_agg(distinct upper(btrim(wi.work_key)),', ' ORDER BY upper(btrim(wi.work_key))) labels
    FROM public.vehicle_work_items wi
    WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed
      AND regexp_replace(upper(btrim(coalesce(wi.work_key,''))),'[^A-Z0-9]+','','g') NOT IN ('QC','PARTS','PITINSPECTION')
  ), active_planner AS (
    SELECT string_agg(distinct s.code,', ' ORDER BY s.code) labels
    FROM public.workshop_bookings b
    JOIN public.workshop_stages s ON s.id=b.stage_id
    WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL
      AND b.status IN ('queued','planned','started','stoppage') AND s.planner_enabled
  )
  SELECT array_remove(array[
    CASE WHEN NOT EXISTS(SELECT 1 FROM vehicle) THEN 'active_vehicle_required' END,
    CASE WHEN (SELECT location FROM vehicle) NOT IN ('PMB','QC') THEN 'vehicle_must_be_at_pmb_or_qc_gate' END,
    CASE WHEN coalesce((SELECT stage FROM vehicle),'')<>'' THEN 'vehicle_still_in_workshop_stage:'||(SELECT stage FROM vehicle) END,
    CASE WHEN (SELECT labels FROM outstanding) IS NOT NULL THEN 'outstanding_required_work:'||(SELECT labels FROM outstanding) END,
    CASE WHEN (SELECT labels FROM active_planner) IS NOT NULL THEN 'active_workshop_booking:'||(SELECT labels FROM active_planner) END
  ],null::text)
$function$;
ALTER FUNCTION public.pdc_qc_gate_issues(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.pdc_qc_gate_issues(uuid) FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_qc_gate_issues(uuid) TO service_role;

DO $post$
DECLARE v_ready text;
BEGIN
 v_ready:=pg_get_functiondef('public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure);
 IF public.pdc_qc_gate_issues('f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid) IS DISTINCT FROM ARRAY[]::text[]
    OR NOT EXISTS(
      SELECT 1 FROM public.vehicles v JOIN public.vehicle_work_items wi ON wi.vehicle_id=v.id
      WHERE v.id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid AND v.stock_number_normalized='13048501'
        AND v.version=11 AND upper(btrim(v.current_location))='PMB'
        AND nullif(btrim(coalesce(v.pmb_stage,'')),'') IS NULL
        AND nullif(btrim(coalesce(v.pmb_bay_stage,'')),'') IS NULL
        AND nullif(btrim(coalesce(v.pmb_bay_number,'')),'') IS NULL
        AND wi.work_key='pitInspection' AND wi.required=true AND wi.completed=false
    )
    OR EXISTS(
      SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid
        AND b.deleted_at IS NULL AND lower(b.status::text) IN ('queued','planned','started','stoppage')
    )
    OR NOT EXISTS(
      SELECT 1 FROM public.pdc_authenticated_email_operation_lines o
      WHERE o.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid AND o.operation_no='OP9'
        AND o.work_key='pitInspection' AND upper(o.description) LIKE '%PIT%'
    )
    OR v_ready NOT LIKE '%perform public.require_pdc_role(''operator'')%'
    OR v_ready NOT LIKE '%v_before.version<>p_expected_version%'
    OR v_ready NOT LIKE '%vehicle_version_conflict%'
    OR v_ready NOT LIKE '%update public.vehicles%set current_location=''QC'',version=version+1%'
    OR v_ready NOT LIKE '%return jsonb_build_object(''ok'',true,''vehicle'',to_jsonb(v_after)%'
    OR NOT EXISTS(
      SELECT 1 FROM pg_proc p WHERE p.oid='public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure
        AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
        AND NOT has_function_privilege('public',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
    )
 THEN RAISE EXCEPTION 'PDC_20260904010300_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904010300','defer_pit_from_physical_qc_gate',ARRAY[
 'pdc_qc_gate_issues excludes deferred PITINSPECTION while preserving all non-PIT physical requirements',
 'Stock 13048501 remains PMB Unallocated and eligible for the real authenticated mark_vehicle_ready_for_qc click',
 'OP9 PIT AND WEIGH source evidence and incomplete pitInspection work item remain immutable and unmodified',
 'Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
