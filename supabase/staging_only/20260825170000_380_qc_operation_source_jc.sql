-- STAGING ONLY 380: preserve source Job Card on every QC operation line.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-380-qc-operation-source-jc',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825160000' AND name='379_qc_per_operation_completion')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825160000')
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM jsonb_build_object('rows',1512,'sha256','dc80e0b6b88557a8fef1de67c3b1d45afa915161d1ae6841d14a2b5403977c6b') THEN
  RAISE EXCEPTION 'PDC_380_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $lines$
 WITH source_lines AS(
  SELECT 'source:'||ol.operation_line_id::text line_identity,'authenticated' source_kind,ol.operation_line_id source_line_id,
   ol.operation_no,ol.description,
   coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v.job_card_number),'')) job_card_number,
   coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
   coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key)) stage_code,
   coalesce(a.active,true) active
  FROM public.pdc_authenticated_email_operation_lines ol
  JOIN public.vehicles v ON v.id=ol.vehicle_id
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=ol.vehicle_id AND a.line_key='source:'||ol.operation_line_id::text
  WHERE ol.vehicle_id=p_vehicle_id
 ), manual_lines AS(
  SELECT 'manual:'||a.adjustment_id::text,'manual',a.adjustment_id,'MANUAL',a.description,
   coalesce(nullif(btrim(a.job_card_number),''),nullif(btrim(v.job_card_number),'')),a.estimated_hours,a.stage_code,a.active
  FROM public.vehicle_workshop_line_adjustments a
  JOIN public.vehicles v ON v.id=a.vehicle_id
  WHERE a.vehicle_id=p_vehicle_id AND a.source_kind='manual'
 ), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines)
 SELECT coalesce(jsonb_agg(jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',l.estimated_hours,
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0)) ORDER BY l.stage_code,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 WHERE l.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE')
$lines$;
REVOKE ALL ON FUNCTION public.pdc_qc_operation_lines_379(uuid) FROM public,anon,authenticated,service_role;

DO $post$
DECLARE v_def text:=pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure); v jsonb;
BEGIN
 IF position('JOIN public.vehicles v ON v.id=ol.vehicle_id' in v_def)=0
   OR position('coalesce(nullif(btrim(ol.job_card_number),''''),nullif(btrim(v.job_card_number),''''))' in v_def)=0
   OR has_function_privilege('public','public.pdc_qc_operation_lines_379(uuid)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_qc_operation_lines_379(uuid)','EXECUTE')
   OR has_function_privilege('authenticated','public.pdc_qc_operation_lines_379(uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_qc_operation_lines_379(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_380_FUNCTION_OR_ACL_POSTCONDITION' USING errcode='55000'; END IF;
 SELECT public.get_pdc_email_vehicle_location_snapshot() INTO v;
 IF EXISTS(
  SELECT 1 FROM jsonb_array_elements(v#>'{data,vehicles}') vehicle
  WHERE nullif(btrim(vehicle->>'job_card_number'),'') IS NOT NULL
    AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(vehicle->'qc_operation_lines','[]'::jsonb)) line
      WHERE coalesce((line->>'active')::boolean,false) AND nullif(btrim(line->>'job_card_number'),'') IS NULL)
 ) OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM jsonb_build_object('rows',1512,'sha256','dc80e0b6b88557a8fef1de67c3b1d45afa915161d1ae6841d14a2b5403977c6b')
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_380_SOURCE_JC_OR_CONTAINMENT_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825170000','380_qc_operation_source_jc',array[
 'QC operation lines preserve their authenticated source Job Card and fall back only to the exact canonical vehicle Job Card',
 'Manual audited lines preserve their own Job Card and fall back to the exact bound vehicle Job Card',
 'No vehicle, operation, work, completion, receipt, history, notification or protected row is mutated'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
