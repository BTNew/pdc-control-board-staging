-- STAGING ONLY 492: expose every genuine Job Card OP in the QC/Board operation projection.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='120s';SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-492-complete-qc-operation-projection',0));
DO $g$ DECLARE v_head text;BEGIN SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_head IS DISTINCT FROM '20260827041000' OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827041000' AND name='491_bind_uid635_archive_paused_floor') OR encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure),'UTF8'),'sha256'),'hex')<>'1370c14a3bac0c9a4f1cfcf3d16768dd32354971be8cbd6ba872e2c85fe62a74' OR (SELECT count(*) FROM public.pdc_authenticated_email_operation_lines WHERE vehicle_id='39570af7-804b-592a-b6f0-98f1d3157596')<>22 THEN RAISE EXCEPTION 'PDC_492_TARGET_HEAD_SCOPE_OR_FUNCTION_MISMATCH' USING errcode='55000';END IF;END $g$;
CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $function$
 WITH source_lines AS(
  SELECT 'source:'||ol.operation_line_id::text line_identity,'authenticated' source_kind,ol.operation_line_id source_line_id,
   ol.operation_no,ol.description,
   coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v.job_card_number),'')) job_card_number,
   coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
   coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key),'UNALLOCATED_MAPPING_REVIEW') stage_code,
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
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  ORDER BY CASE WHEN l.stage_code='UNALLOCATED_MAPPING_REVIEW' THEN 2 WHEN l.stage_code='SUBLET' THEN 1 ELSE 0 END,l.stage_code,substring(l.operation_no from '[0-9]+')::integer NULLS LAST,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l
 LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 LEFT JOIN public.pdc_qc_operation_rejections_381 r ON r.vehicle_id=p_vehicle_id AND r.line_identity=l.line_identity
 WHERE l.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','UNALLOCATED_MAPPING_REVIEW')
$function$;
REVOKE ALL ON FUNCTION public.pdc_qc_operation_lines_379(uuid) FROM public,anon;GRANT EXECUTE ON FUNCTION public.pdc_qc_operation_lines_379(uuid) TO authenticated,service_role;
CREATE TABLE public.pdc_complete_qc_operation_projection_receipts_492(receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),action_key text NOT NULL UNIQUE CHECK(action_key='stock-13000775-all-22-qc-operations'),vehicle_id uuid NOT NULL CHECK(vehicle_id='39570af7-804b-592a-b6f0-98f1d3157596'),stock_number text NOT NULL CHECK(stock_number='13000775'),job_card_number text NOT NULL CHECK(job_card_number='J139125494'),source_operation_count integer NOT NULL CHECK(source_operation_count=22),projected_operation_count integer NOT NULL CHECK(projected_operation_count=22),internal_station_count integer NOT NULL CHECK(internal_station_count=7),sublet_count integer NOT NULL CHECK(sublet_count=1),mapping_review_count integer NOT NULL CHECK(mapping_review_count=14),duplicate_count integer NOT NULL CHECK(duplicate_count=0),production_untouched boolean NOT NULL CHECK(production_untouched),created_at timestamptz NOT NULL DEFAULT clock_timestamp());ALTER TABLE public.pdc_complete_qc_operation_projection_receipts_492 ENABLE ROW LEVEL SECURITY;REVOKE ALL ON public.pdc_complete_qc_operation_projection_receipts_492 FROM public,anon,authenticated,service_role;
DO $p$ DECLARE lines jsonb;BEGIN lines:=public.pdc_qc_operation_lines_379('39570af7-804b-592a-b6f0-98f1d3157596');IF jsonb_array_length(lines)<>22 OR (SELECT count(*) FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'='UNALLOCATED_MAPPING_REVIEW')<>14 OR (SELECT count(*) FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'='SUBLET')<>1 OR (SELECT count(*) FROM jsonb_array_elements(lines) l WHERE l->>'stage_code' IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE'))<>7 OR (SELECT count(DISTINCT l->>'operation_no') FROM jsonb_array_elements(lines) l)<>22 OR has_function_privilege('public','public.pdc_qc_operation_lines_379(uuid)','EXECUTE') OR has_function_privilege('anon','public.pdc_qc_operation_lines_379(uuid)','EXECUTE') OR NOT has_function_privilege('authenticated','public.pdc_qc_operation_lines_379(uuid)','EXECUTE') THEN RAISE EXCEPTION 'PDC_492_COMPLETE_PROJECTION_OR_ACL_POSTCONDITION_FAILED' USING errcode='55000';END IF;INSERT INTO public.pdc_complete_qc_operation_projection_receipts_492(action_key,vehicle_id,stock_number,job_card_number,source_operation_count,projected_operation_count,internal_station_count,sublet_count,mapping_review_count,duplicate_count,production_untouched) VALUES('stock-13000775-all-22-qc-operations','39570af7-804b-592a-b6f0-98f1d3157596','13000775','J139125494',22,22,7,1,14,0,true);END $p$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827042000','492_complete_qc_operation_projection',ARRAY['Project every genuine authenticated Job Card operation into the QC/Board operation list','Keep seven mapped internal station lines, one Sublet line and fourteen unresolved lines visible','Label unresolved rows with the non-mutable UNALLOCATED_MAPPING_REVIEW stage until an approved mapping exists','Preserve exact operation identities, descriptions, zero hours, NULL unknown hours and QC completion history','Production untouched']);NOTIFY pgrst,'reload schema';COMMIT;
