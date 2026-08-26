-- STAGING ONLY 493: fail closed unless every genuine Job Card operation is projected exactly once.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-493-all-vehicle-operation-projection-guard',0));

DO $guard$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head IS DISTINCT FROM '20260827042000'
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827042000' AND name='492_complete_qc_operation_projection')
     OR encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure),'UTF8'),'sha256'),'hex')<>'fd75fa62508384309d424b0c3ef964f2c28a721ead1308082562fc45cc5e550c'
  THEN RAISE EXCEPTION 'PDC_493_TARGET_HEAD_SCOPE_OR_FUNCTION_MISMATCH' USING errcode='55000';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $function$
 WITH source_lines AS(
  SELECT 'source:'||ol.operation_line_id::text line_identity,'authenticated' source_kind,ol.operation_line_id source_line_id,
   ol.operation_no,ol.description,
   coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v.job_card_number),'')) job_card_number,
   coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
   CASE
    WHEN coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key)) IN
      ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
    THEN coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key))
    ELSE 'UNALLOCATED_MAPPING_REVIEW'
   END stage_code,
   coalesce(a.active,true) active
  FROM public.pdc_authenticated_email_operation_lines ol
  JOIN public.vehicles v ON v.id=ol.vehicle_id
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=ol.vehicle_id AND a.line_key='source:'||ol.operation_line_id::text
  WHERE ol.vehicle_id=p_vehicle_id
 ), manual_lines AS(
  SELECT 'manual:'||a.adjustment_id::text,'manual',a.adjustment_id,'MANUAL',a.description,
   coalesce(nullif(btrim(a.job_card_number),''),nullif(btrim(v.job_card_number),'')),a.estimated_hours,
   CASE WHEN a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET') THEN a.stage_code ELSE 'UNALLOCATED_MAPPING_REVIEW' END,
   a.active
  FROM public.vehicle_workshop_line_adjustments a
  JOIN public.vehicles v ON v.id=a.vehicle_id
  WHERE a.vehicle_id=p_vehicle_id AND a.source_kind='manual'
 ), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines)
 SELECT coalesce(jsonb_agg(jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',l.estimated_hours,
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  ORDER BY CASE WHEN l.stage_code='UNALLOCATED_MAPPING_REVIEW' THEN 2 WHEN l.stage_code='SUBLET' THEN 1 ELSE 0 END,l.stage_code,substring(l.operation_no from '[0-9]+')::integer NULLS LAST,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l
 LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 LEFT JOIN public.pdc_qc_operation_rejections_381 r ON r.vehicle_id=p_vehicle_id AND r.line_identity=l.line_identity
$function$;
REVOKE ALL ON FUNCTION public.pdc_qc_operation_lines_379(uuid) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.pdc_qc_operation_lines_379(uuid) TO authenticated,service_role;

CREATE FUNCTION public.pdc_operation_projection_parity_493(p_vehicle_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $parity$
 WITH source_vehicles AS(
  SELECT ol.vehicle_id,count(*)::integer source_count
  FROM public.pdc_authenticated_email_operation_lines ol
  WHERE p_vehicle_id IS NULL OR ol.vehicle_id=p_vehicle_id
  GROUP BY ol.vehicle_id
 ), normalized AS(
  SELECT s.vehicle_id,v.stock_number,v.job_card_number,s.source_count,
   q.projected_count,q.distinct_projected_count,
   coalesce((
    SELECT jsonb_agg(ol.operation_line_id ORDER BY ol.operation_no)
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=s.vehicle_id AND NOT EXISTS(
      SELECT 1 FROM jsonb_array_elements(q.lines) projected
      WHERE projected->>'source_kind'='authenticated' AND projected->>'source_line_id'=ol.operation_line_id::text
    )
   ),'[]'::jsonb) missing_source_line_ids
  FROM source_vehicles s
  JOIN public.vehicles v ON v.id=s.vehicle_id
  CROSS JOIN LATERAL (
   SELECT lines,
    (SELECT count(*) FROM jsonb_array_elements(lines) p WHERE p->>'source_kind'='authenticated')::integer projected_count,
    (SELECT count(DISTINCT p->>'source_line_id') FROM jsonb_array_elements(lines) p WHERE p->>'source_kind'='authenticated')::integer distinct_projected_count
   FROM (SELECT public.pdc_qc_operation_lines_379(s.vehicle_id) lines) projected
  ) q
 ), mismatches AS(
  SELECT * FROM normalized
  WHERE source_count<>projected_count OR source_count<>distinct_projected_count OR jsonb_array_length(missing_source_line_ids)<>0
 )
 SELECT jsonb_build_object(
  'ok',NOT EXISTS(SELECT 1 FROM mismatches),
  'checked_vehicle_count',(SELECT count(*) FROM normalized),
  'source_operation_count',coalesce((SELECT sum(source_count) FROM normalized),0),
  'projected_operation_count',coalesce((SELECT sum(projected_count) FROM normalized),0),
  'mismatch_count',(SELECT count(*) FROM mismatches),
  'mismatches',coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY stock_number,vehicle_id) FROM mismatches m),'[]'::jsonb)
 )
$parity$;
REVOKE ALL ON FUNCTION public.pdc_operation_projection_parity_493(uuid) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.pdc_operation_projection_parity_493(uuid) TO authenticated,service_role;

CREATE FUNCTION public.pdc_enforce_operation_projection_parity_493()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $trigger$
DECLARE v_vehicle_id uuid:=coalesce(NEW.vehicle_id,OLD.vehicle_id);v_check jsonb;
BEGIN
  v_check:=public.pdc_operation_projection_parity_493(v_vehicle_id);
  IF coalesce((v_check->>'ok')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'PDC_OPERATION_PROJECTION_INCOMPLETE: %',v_check USING errcode='23514';
  END IF;
  RETURN coalesce(NEW,OLD);
END $trigger$;
REVOKE ALL ON FUNCTION public.pdc_enforce_operation_projection_parity_493() FROM public,anon,authenticated,service_role;

CREATE CONSTRAINT TRIGGER pdc_operation_projection_parity_source_493
AFTER INSERT OR UPDATE OR DELETE ON public.pdc_authenticated_email_operation_lines
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.pdc_enforce_operation_projection_parity_493();
CREATE CONSTRAINT TRIGGER pdc_operation_projection_parity_adjustment_493
AFTER INSERT OR UPDATE OR DELETE ON public.vehicle_workshop_line_adjustments
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.pdc_enforce_operation_projection_parity_493();

DO $post$
DECLARE v_check jsonb;
BEGIN
  v_check:=public.pdc_operation_projection_parity_493(NULL);
  IF coalesce((v_check->>'ok')::boolean,false) IS NOT TRUE
     OR coalesce((v_check->>'source_operation_count')::integer,0)<>coalesce((v_check->>'projected_operation_count')::integer,-1)
     OR (SELECT count(*) FROM pg_trigger WHERE tgname IN('pdc_operation_projection_parity_source_493','pdc_operation_projection_parity_adjustment_493') AND tgdeferrable AND tginitdeferred)<>2
     OR has_function_privilege('public','public.pdc_operation_projection_parity_493(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.pdc_operation_projection_parity_493(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.pdc_operation_projection_parity_493(uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'PDC_493_ALL_VEHICLE_PARITY_OR_ACL_POSTCONDITION_FAILED: %',v_check USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827043000','493_all_vehicle_operation_projection_guard',ARRAY[
  'Normalize every genuine Job Card operation to a visible mapped, Sublet or UNALLOCATED_MAPPING_REVIEW stage',
  'Expose authenticated all-vehicle source-versus-projection parity readback',
  'Fail every operation-line or mapping-adjustment transaction closed if a source operation is omitted or duplicated',
  'Verify zero existing staging mismatches before commissioning',
  'Production untouched'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
