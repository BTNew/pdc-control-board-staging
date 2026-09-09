-- STAGING ONLY: preserve modal scope and repair live Workshop candidate duration projection.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-workshop-live-shape-authority-20260909120000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT jsonb_build_array(version,name) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '["20260908151000","pilbara_workshop_cross_source_scope"]'::jsonb
     OR to_regprocedure('public.get_station_workshop_snapshot(text,date,date)') IS NULL
     OR to_regprocedure('public.get_station_workshop_snapshot_pre_397(text,date,date)') IS NULL
     OR to_regprocedure('public.workshop_overlay_canonical_booking_fields_397(jsonb)') IS NULL
     OR to_regprocedure('public.workshop_vehicle_stage_estimated_hours(uuid,text)') IS NULL
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260909120000')
  THEN RAISE EXCEPTION 'PDC_WORKSHOP_LIVE_SHAPE_AUTHORITY_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_overlay_authoritative_candidate_hours_175(p_snapshot jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $overlay$
DECLARE
  v_stage text;
  v_candidates jsonb;
BEGIN
  IF p_snapshot IS NULL
     OR jsonb_typeof(p_snapshot->'outstanding_candidates') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_snapshot->'scope') IS DISTINCT FROM 'object'
  THEN RETURN p_snapshot; END IF;

  v_stage:=public.workshop_canonical_stage_code(p_snapshot->'scope'->>'stage_code');
  IF v_stage IS NULL OR v_stage='' THEN RETURN p_snapshot; END IF;

  SELECT coalesce(jsonb_agg(
    candidate || jsonb_build_object(
      'estimated_hours',coalesce(to_jsonb(authority.estimated_hours),'null'::jsonb),
      'schedule_enabled',CASE
        WHEN authority.estimated_hours IS NULL THEN false
        ELSE coalesce((candidate->>'schedule_enabled')::boolean,false)
      END,
      'disabled_reason',CASE
        WHEN authority.estimated_hours IS NULL
          THEN coalesce(nullif(candidate->>'disabled_reason',''),'estimated_duration_missing')
        ELSE candidate->>'disabled_reason'
      END
    )
    ORDER BY ordinal
  ),'[]'::jsonb)
  INTO v_candidates
  FROM jsonb_array_elements(p_snapshot->'outstanding_candidates') WITH ORDINALITY item(candidate,ordinal)
  CROSS JOIN LATERAL (
    SELECT public.workshop_vehicle_stage_estimated_hours((candidate->>'vehicle_id')::uuid,v_stage) estimated_hours
  ) authority;

  RETURN jsonb_set(p_snapshot,'{outstanding_candidates}',v_candidates,false);
END
$overlay$;
REVOKE ALL ON FUNCTION public.workshop_overlay_authoritative_candidate_hours_175(jsonb) FROM public,anon,authenticated,service_role;
COMMENT ON FUNCTION public.workshop_overlay_authoritative_candidate_hours_175(jsonb) IS
'STAGING internal final projection for authoritative candidate duration. Preserves existing eligibility guards and forces missing duration to estimated_duration_missing without inventing hours.';

CREATE OR REPLACE FUNCTION public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $station_snapshot$
DECLARE
  v_snapshot jsonb;
BEGIN
  v_snapshot:=public.get_station_workshop_snapshot_pre_397(p_stage_code,p_date_from,p_date_to);
  v_snapshot:=public.workshop_overlay_canonical_booking_fields_397(v_snapshot);
  RETURN public.workshop_overlay_authoritative_candidate_hours_175(v_snapshot);
END
$station_snapshot$;
REVOKE ALL ON FUNCTION public.get_station_workshop_snapshot(text,date,date) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.get_station_workshop_snapshot(text,date,date) TO authenticated,service_role;

DO $verify$
DECLARE
  v_wrapper text;
  v_127 uuid;
  v_130 uuid;
  v_127_hours numeric;
  v_130_hours numeric;
  v_probe jsonb;
BEGIN
  SELECT id INTO STRICT v_127 FROM public.vehicles WHERE stock_number='12705177' AND lifecycle_state='active' AND deleted_at IS NULL;
  SELECT id INTO STRICT v_130 FROM public.vehicles WHERE stock_number='13007660' AND lifecycle_state='active' AND deleted_at IS NULL;
  v_127_hours:=public.workshop_vehicle_stage_estimated_hours(v_127,'FITTING');
  v_130_hours:=public.workshop_vehicle_stage_estimated_hours(v_130,'FITTING');
  IF v_127_hours IS DISTINCT FROM 2.25::numeric OR v_130_hours IS DISTINCT FROM 1.5::numeric
  THEN RAISE EXCEPTION 'PDC_WORKSHOP_LIVE_SHAPE_DURATION_SOURCE_DRIFT' USING errcode='55000'; END IF;

  v_probe:=public.workshop_overlay_authoritative_candidate_hours_175(jsonb_build_object(
    'scope',jsonb_build_object('stage_code','FITTING'),
    'outstanding_candidates',jsonb_build_array(
      jsonb_build_object('vehicle_id',v_127,'schedule_enabled',true,'disabled_reason',null),
      jsonb_build_object('vehicle_id',v_130,'schedule_enabled',true,'disabled_reason',null)
    )
  ));
  IF (v_probe#>>'{outstanding_candidates,0,estimated_hours}')::numeric IS DISTINCT FROM 2.25::numeric
     OR (v_probe#>>'{outstanding_candidates,1,estimated_hours}')::numeric IS DISTINCT FROM 1.5::numeric
     OR v_probe#>>'{outstanding_candidates,0,schedule_enabled}' IS DISTINCT FROM 'true'
     OR v_probe#>>'{outstanding_candidates,1,schedule_enabled}' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'PDC_WORKSHOP_LIVE_SHAPE_PROJECTION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;

  v_wrapper:=pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure);
  IF position('workshop_overlay_canonical_booking_fields_397' in v_wrapper)=0
     OR position('workshop_overlay_authoritative_candidate_hours_175' in v_wrapper)=0
     OR NOT has_function_privilege('authenticated','public.get_station_workshop_snapshot(text,date,date)','execute')
     OR has_function_privilege('anon','public.get_station_workshop_snapshot(text,date,date)','execute')
     OR NOT has_function_privilege('service_role','public.get_station_workshop_snapshot(text,date,date)','execute')
     OR has_function_privilege('authenticated','public.workshop_overlay_authoritative_candidate_hours_175(jsonb)','execute')
     OR has_function_privilege('anon','public.workshop_overlay_authoritative_candidate_hours_175(jsonb)','execute')
     OR has_function_privilege('service_role','public.workshop_overlay_authoritative_candidate_hours_175(jsonb)','execute')
  THEN RAISE EXCEPTION 'PDC_WORKSHOP_LIVE_SHAPE_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260909120000','workshop_live_shape_authority',ARRAY[
  'Project existing authoritative stage hours into the final live Workshop outstanding-candidate DTO',
  'Keep duration-less candidates fail-closed with estimated_duration_missing while preserving ETA, bay and capacity eligibility decisions',
  'Preserve the canonical-booking overlay, authenticated-only public snapshot grant, source hours and business rows'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
