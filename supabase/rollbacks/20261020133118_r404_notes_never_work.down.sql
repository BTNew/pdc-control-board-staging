-- r404 undo. Staging cdsmnqxtyyoeoznmbidd only. Restores the exact pre-r404 QC lines function.
DO $g$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r404: staging cdsmnqxtyyoeoznmbidd only'; END IF;
END $g$;
DO $b$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure)<>'97fc4caaf7b462163d35b4a3511bc487' THEN RAISE EXCEPTION 'r404 undo: uncached is not the r404 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb)'::regprocedure)<>'cfe0fd4c29d9eaf82c06ed1d0ffdd541' THEN RAISE EXCEPTION 'r404 undo: helper is not the r404 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r404 undo: fault_regression_check changed'; END IF;
END $b$;
CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379_uncached(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $r404u$
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
$r404u$;
DROP FUNCTION pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb);
DELETE FROM pdc_ops.regression_checks WHERE check_name='notes_lines_never_on_qc_checklist' AND added_in='r404';
DELETE FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb)' AND release='r404';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='b677d7bfdf67c046fd05922da249325c',release='baseline',note=NULL,updated_at=now()
 WHERE signature='public.pdc_qc_operation_lines_379_uncached(uuid)' AND release='r404';
DO $c$
DECLARE ids uuid[];
BEGIN
 SELECT coalesce(array_agg(c.vehicle_id ORDER BY c.vehicle_id),ARRAY[]::uuid[]) INTO ids
 FROM pdc_work_categories_private.qc_operation_lines_cache c
 WHERE c.lines IS DISTINCT FROM public.pdc_qc_operation_lines_379_uncached(c.vehicle_id);
 PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ids,false);
 DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = ANY(ids);
END $c$;
DO $p$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure)<>'b677d7bfdf67c046fd05922da249325c' THEN RAISE EXCEPTION 'r404 undo: restore md5'; END IF;
 IF to_regprocedure('pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r404 undo: helper still present'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.pdc_qc_operation_lines_379_uncached(uuid)')<>'b677d7bfdf67c046fd05922da249325c' THEN RAISE EXCEPTION 'r404 undo: pin'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='notes_lines_never_on_qc_checklist') THEN RAISE EXCEPTION 'r404 undo: check'; END IF;
END $p$;
