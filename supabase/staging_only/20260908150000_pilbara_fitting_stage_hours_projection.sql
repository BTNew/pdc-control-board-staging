-- STAGING ONLY: project Pilbara Service operation hours into station planner duration.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-pilbara-fitting-stage-hours-20260908150000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT jsonb_build_array(version,name) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '["20260908103000","jobcard_hours_live_repair"]'::jsonb
     OR to_regclass('public.pdc_authenticated_email_operation_lines') IS NULL
     OR to_regclass('public.pdc_pilbara_service_operations') IS NULL
     OR to_regclass('public.pdc_pilbara_service_classification_current') IS NULL
     OR to_regclass('public.pdc_pilbara_service_classification_history') IS NULL
     OR to_regclass('public.vehicle_workshop_line_adjustments') IS NULL
     OR to_regclass('public.pdc_overnight_synthetic_estimates_369') IS NULL
     OR to_regclass('public.pdc_overnight_synthetic_fleet_registry_363') IS NULL
     OR to_regprocedure('public.workshop_vehicle_stage_estimated_hours(uuid,text)') IS NULL
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260908150000')
  THEN RAISE EXCEPTION 'PDC_PILBARA_FITTING_STAGE_HOURS_STAGING_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_hours(p_vehicle_id uuid,p_stage_code text)
RETURNS numeric
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $hours$
  WITH email_source_lines AS (
    SELECT
      CASE WHEN a.adjustment_id IS NOT NULL THEN a.stage_code
           ELSE public.workshop_stage_code_for_work_key(ol.work_key) END stage_code,
      CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours
           ELSE ol.estimated_hours END estimated_hours
    FROM public.pdc_authenticated_email_operation_lines ol
    LEFT JOIN public.vehicle_workshop_line_adjustments a
      ON a.vehicle_id=ol.vehicle_id
     AND a.line_key='source:'||ol.operation_line_id::text
    WHERE ol.vehicle_id=p_vehicle_id
      -- An inactive source adjustment is the durable explicit-removal marker;
      -- it must suppress, not resurrect, the immutable source line.
      AND coalesce(a.active,true)
  ), pilbara_source_lines AS (
    SELECT
      CASE WHEN a.adjustment_id IS NOT NULL THEN a.stage_code
           ELSE coalesce(h.category,'REVIEW') END stage_code,
      CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours
           ELSE o.effective_estimated_hours END estimated_hours
    FROM public.pdc_pilbara_service_operations o
    LEFT JOIN public.pdc_pilbara_service_classification_current cc USING(operation_id)
    LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    LEFT JOIN public.vehicle_workshop_line_adjustments a
      ON a.vehicle_id=o.vehicle_id
     AND a.line_key='source:'||o.operation_id::text
    WHERE o.vehicle_id=p_vehicle_id
      -- Keep the planner aligned with the detail/QC active-line projection.
      AND coalesce(a.active,true)
  ), manual_lines AS (
    SELECT a.stage_code,a.estimated_hours
    FROM public.vehicle_workshop_line_adjustments a
    WHERE a.vehicle_id=p_vehicle_id AND a.active AND a.source_kind='manual'
  ), synthetic_lines AS (
    SELECT e.stage_code,e.estimated_hours
    FROM public.pdc_overnight_synthetic_estimates_369 e
    JOIN public.pdc_overnight_synthetic_fleet_registry_363 r
      ON r.run_id=e.run_id AND r.vehicle_id=e.vehicle_id AND r.scenario_no=e.scenario_no
    WHERE e.vehicle_id=p_vehicle_id AND e.run_id='HERMES-TEST-RUN-20260824'
  )
  SELECT nullif(round(sum(q.estimated_hours)::numeric,2),0)
  FROM (
    SELECT * FROM email_source_lines
    UNION ALL SELECT * FROM pilbara_source_lines
    UNION ALL SELECT * FROM manual_lines
    UNION ALL SELECT * FROM synthetic_lines
  ) q
  WHERE q.stage_code=public.workshop_canonical_stage_code(p_stage_code)
    AND q.estimated_hours>0
$hours$;

REVOKE ALL ON FUNCTION public.workshop_vehicle_stage_estimated_hours(uuid,text) FROM public,anon,authenticated,service_role;
COMMENT ON FUNCTION public.workshop_vehicle_stage_estimated_hours(uuid,text) IS
'STAGING internal planner aggregate of active authenticated-email, Pilbara Service, audited manual and isolated synthetic operation hours. Existing source-line adjustments override stage and effective hours, including explicit unknown; immutable source rows are never changed.';

DO $verify$
DECLARE d text;
BEGIN
  d:=pg_get_functiondef('public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure);
  IF position('pdc_authenticated_email_operation_lines' in d)=0
     OR position('pdc_pilbara_service_operations' in d)=0
     OR position('pdc_pilbara_service_classification_current' in d)=0
     OR position('pdc_overnight_synthetic_estimates_369' in d)=0
     OR position('CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours' in d)=0
     OR has_function_privilege('authenticated','public.workshop_vehicle_stage_estimated_hours(uuid,text)','execute')
     OR has_function_privilege('anon','public.workshop_vehicle_stage_estimated_hours(uuid,text)','execute')
     OR has_function_privilege('service_role','public.workshop_vehicle_stage_estimated_hours(uuid,text)','execute')
  THEN RAISE EXCEPTION 'PDC_PILBARA_FITTING_STAGE_HOURS_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260908150000','pilbara_fitting_stage_hours_projection',ARRAY[
  'Include classified Pilbara Service operations in authoritative station planner stage-hour aggregation',
  'Apply audited source-line stage/hour overlays without falling back through an explicit unknown value',
  'Preserve authenticated-email, manual and isolated synthetic estimate sources without business-data writes'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
