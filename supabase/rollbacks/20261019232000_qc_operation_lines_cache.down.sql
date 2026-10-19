-- Drop the QC operation-line cache and restore the reviewed function body.
-- Rollback for supabase/migrations/20261019232000_qc_operation_lines_cache.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON pdc_bus_private.operation_routing_history_20261015;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON pdc_bus_private.operation_routing_history_20261015;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON pdc_operation_updates_private.ai_routing_20261019;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON pdc_operation_updates_private.ai_routing_20261019;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON pdc_work_categories_private.import_baseline_20261017;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON pdc_work_categories_private.import_baseline_20261017;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON pdc_work_categories_private.import_rules_139_20261018;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON pdc_work_categories_private.import_rules_139_20261018;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON pdc_work_categories_private.import_rules_20261017;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON pdc_work_categories_private.import_rules_20261017;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON pdc_work_categories_private.line_overrides;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON pdc_work_categories_private.line_overrides;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON pdc_work_categories_private.owner_line_reviews;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON pdc_work_categories_private.owner_line_reviews;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.navision_backend_records;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.navision_backend_records;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_authenticated_email_operation_lines;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_authenticated_email_operation_lines;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_new_vehicle_reviews;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_new_vehicle_reviews;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_pilbara_service_classification_current;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_pilbara_service_classification_current;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_pilbara_service_classification_history;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_pilbara_service_classification_history;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_pilbara_service_import_batches;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_pilbara_service_import_batches;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_pilbara_service_import_rows;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_pilbara_service_import_rows;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_pilbara_service_operation_history;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_pilbara_service_operation_history;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_pilbara_service_operations;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_pilbara_service_operations;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_qc_operation_completions_379;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_qc_operation_completions_379;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_qc_operation_rejections_381;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_qc_operation_rejections_381;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.pdc_tune_operation_change_reviews;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.pdc_tune_operation_change_reviews;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.vehicle_work_items;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.vehicle_work_items;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.vehicle_workshop_line_adjustments;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.vehicle_workshop_line_adjustments;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.vehicles;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.vehicles;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.workshop_bookings;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.workshop_bookings;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.workshop_stage_aliases;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.workshop_stage_aliases;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON public.workshop_stages;
DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON public.workshop_stages;

DROP FUNCTION IF EXISTS pdc_work_categories_private.invalidate_qc_operation_lines_cache();
DROP TABLE IF EXISTS pdc_work_categories_private.qc_operation_lines_cache;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 WITH source AS MATERIALIZED(
  SELECT l,ord FROM jsonb_array_elements(pdc_work_categories_private.before_import_rules_20261017(p_vehicle_id)) WITH ORDINALITY x(l,ord)
 ), routed AS(
 SELECT ord,pdc_work_categories_private.route_import_line_20261017(
  CASE WHEN a.manual_assignment_locked IS FALSE AND a.correction_origin='job_card_source_correction'
   THEN l||jsonb_build_object('estimated_hours',a.estimated_hours,
    'zero_hour_task',a.estimated_hours=0 AND EXISTS(SELECT 1 FROM pdc_work_categories_private.import_rules_20261017 r
     WHERE r.description_hash=pdc_work_categories_private.import_description_hash_20261017(l->>'description') AND r.category='BUS_QA'))
   ELSE l END,
  h.source_signature=pdc_work_categories_private.source_signature(l)
  OR coalesce((l->>'category_version')::integer,0)>0
  OR coalesce(a.manual_assignment_locked,false)
  OR EXISTS(SELECT 1 FROM pdc_work_categories_private.owner_line_reviews r
   WHERE r.vehicle_id=p_vehicle_id AND r.line_identity=l->>'line_identity'
   AND r.source_signature=pdc_work_categories_private.source_signature(l))
  OR EXISTS(SELECT 1 FROM public.vehicle_work_items w JOIN public.workshop_stages s ON s.work_key=w.work_key
   WHERE w.vehicle_id=p_vehicle_id AND w.completed AND s.code=l->>'stage_code')
  OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
    AND ((b.work_category IS NOT NULL AND b.work_category_scope ? (l->>'line_identity'))
     OR (b.work_category IS NULL AND s.code=l->>'stage_code'
      AND NOT (a.manual_assignment_locked IS FALSE AND a.correction_origin='job_card_source_correction' AND EXISTS(
       SELECT 1 FROM public.pdc_tune_operation_change_reviews q
       WHERE q.vehicle_id=p_vehicle_id AND 'source:'||q.source_operation_id::text=l->>'line_identity'
        AND q.change_kind='added' AND q.status='approved' AND q.approved_at>b.created_at)))))
 ) l
 FROM source
 LEFT JOIN pdc_work_categories_private.import_baseline_20261017 h ON h.vehicle_id=p_vehicle_id AND h.line_identity=l->>'line_identity'
 LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=l->>'line_identity'
 ) SELECT coalesce(jsonb_agg(l ORDER BY ord),'[]'::jsonb) FROM routed
$function$;

DROP FUNCTION IF EXISTS public.pdc_qc_operation_lines_379_uncached(uuid);

DO $check$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src
  FROM pg_proc
  WHERE oid = 'public.pdc_qc_operation_lines_379(uuid)'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM 'b677d7bfdf67c046fd05922da249325c'
     OR to_regprocedure('public.pdc_qc_operation_lines_379_uncached(uuid)') IS NOT NULL
     OR to_regclass('pdc_work_categories_private.qc_operation_lines_cache') IS NOT NULL THEN
    RAISE EXCEPTION 'qc_operation_lines_cache_rollback_incomplete';
  END IF;
END
$check$;
