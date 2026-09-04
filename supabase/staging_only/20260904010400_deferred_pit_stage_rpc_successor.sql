-- STAGING ONLY: reviewed successor for stale PIT stage/booking handling in the authenticated Ready-for-QC RPC.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010400-deferred-pit-stage-rpc-successor',0));
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
    OR v_head IS DISTINCT FROM '20260904010300'
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904010400')
    OR v_gate NOT LIKE '%PITINSPECTION%'
    OR v_ready NOT LIKE '%require_pdc_role(''operator'')%'
    OR v_ready NOT LIKE '%vehicle_version_conflict%'
 THEN RAISE EXCEPTION 'PDC_20260904010400_STAGING_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_qc_gate_issues(p_vehicle_id uuid)
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH vehicle AS (
    SELECT id,upper(btrim(coalesce(current_location,''))) location,
           CASE WHEN regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g')='PITINSPECTION' THEN ''
                ELSE regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g') END stage
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
      AND b.status IN ('queued','planned','started','stoppage') AND s.planner_enabled AND s.code<>'PIT_INSPECTION'
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

CREATE OR REPLACE FUNCTION public.mark_vehicle_ready_for_qc(p_vehicle_id uuid,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_issues text[];
  v_stage text;
  v_bay_stage text;
BEGIN
  PERFORM public.require_pdc_role('operator');
  SELECT * INTO v_before FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','vehicle_not_found'); END IF;
  IF p_expected_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','missing_expected_version'); END IF;
  IF v_before.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict'); END IF;
  IF upper(btrim(coalesce(v_before.current_location,'')))='QC' THEN
    RETURN jsonb_build_object('ok',false,'error','already_ready_for_qc','vehicle',to_jsonb(v_before));
  END IF;
  IF v_before.lifecycle_state<>'active' OR v_before.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'error','not_in_active_lifecycle');
  END IF;
  v_stage:=regexp_replace(upper(btrim(coalesce(v_before.pmb_stage,''))),'[^A-Z0-9]+','','g');
  v_bay_stage:=regexp_replace(upper(btrim(coalesce(v_before.pmb_bay_stage,''))),'[^A-Z0-9]+','','g');
  IF upper(btrim(coalesce(v_before.current_location,'')))<>'PMB'
     OR v_stage NOT IN ('','PITINSPECTION')
     OR v_bay_stage NOT IN ('','PITINSPECTION')
     OR (nullif(btrim(coalesce(v_before.pmb_bay_number,'')),'') IS NOT NULL AND v_stage<>'PITINSPECTION' AND v_bay_stage<>'PITINSPECTION') THEN
    RETURN jsonb_build_object('ok',false,'error','qc_gate_blocked','issues',jsonb_build_array('vehicle_must_be_pmb_unallocated'));
  END IF;
  v_issues:=public.pdc_qc_gate_issues(p_vehicle_id);
  IF coalesce(array_length(v_issues,1),0)>0 THEN
    RETURN jsonb_build_object('ok',false,'error','qc_gate_blocked','issues',to_jsonb(v_issues));
  END IF;
  UPDATE public.vehicles
  SET current_location='QC',pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,
      version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE id=p_vehicle_id RETURNING * INTO v_after;
  INSERT INTO public.vehicle_movements(
    vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,
    reason,moved_by
  ) VALUES (
    p_vehicle_id,v_before.current_location,'QC',v_before.pmb_stage,NULL,
    v_before.pmb_bay_stage,NULL,v_before.pmb_bay_number,NULL,
    'All required work complete - moved to QC Gate',auth.uid()
  );
  PERFORM public.audit_pdc_event(
    'update','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('action','mark_vehicle_ready_for_qc','from','PMB','to','QC','deferred_pit_stage_cleared',v_stage='PITINSPECTION' OR v_bay_stage='PITINSPECTION')
  );
  RETURN jsonb_build_object('ok',true,'vehicle',to_jsonb(v_after),'ready_for_qc',true);
END;
$function$;
ALTER FUNCTION public.mark_vehicle_ready_for_qc(uuid,integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.mark_vehicle_ready_for_qc(uuid,integer) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.mark_vehicle_ready_for_qc(uuid,integer) TO authenticated,service_role;

DO $post$
DECLARE v_gate text; v_ready text;
BEGIN
 v_gate:=pg_get_functiondef('public.pdc_qc_gate_issues(uuid)'::regprocedure);
 v_ready:=pg_get_functiondef('public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure);
 IF public.pdc_qc_gate_issues('f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid) IS DISTINCT FROM ARRAY[]::text[]
    OR v_gate NOT LIKE '%s.code<>''PIT_INSPECTION''%'
    OR v_gate NOT LIKE '%THEN ''''%ELSE regexp_replace%'
    OR v_ready NOT LIKE '%require_pdc_role(''operator'')%'
    OR v_ready NOT LIKE '%vehicle_version_conflict%'
    OR v_ready NOT LIKE '%pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL%'
    OR NOT EXISTS(
      SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid
        AND wi.work_key='pitInspection' AND wi.required AND NOT wi.completed
    )
    OR NOT EXISTS(
      SELECT 1 FROM public.pdc_authenticated_email_operation_lines o WHERE o.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'::uuid
        AND o.operation_no='OP9' AND o.work_key='pitInspection' AND upper(o.description) LIKE '%PIT%'
    )
    OR NOT EXISTS(
      SELECT 1 FROM pg_proc p WHERE p.oid='public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure
        AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
        AND NOT has_function_privilege('public',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
    )
 THEN RAISE EXCEPTION 'PDC_20260904010400_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904010400','deferred_pit_stage_rpc_successor',ARRAY[
 'Reviewed successor: deferred PIT stage and PIT planner rows cannot block the physical QC gate',
 'Authenticated mark_vehicle_ready_for_qc retains operator authorization and expected-version conflict handling',
 'The real user click atomically moves to QC and clears only obsolete PIT workshop placement fields',
 'PIT completion remains false and OP9 PIT AND WEIGH immutable source evidence remains retained',
 'Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
