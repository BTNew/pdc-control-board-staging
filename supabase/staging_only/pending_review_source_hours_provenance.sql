-- Preserve unknown Tune source hours as unknown when an effective estimate exists.
DO $guard$ BEGIN IF md5(pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure)) <> 'e089da4c3d195dc69b35969eb41e923f' OR public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'staging_projection_changed'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH source_lines AS(
  SELECT 'source:'||ol.operation_line_id::text line_identity,'authenticated' source_kind,ol.operation_line_id source_line_id,
   ol.operation_no,ol.description,
   coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v.job_card_number),'')) job_card_number,
   coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
   CASE
    WHEN coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(ol.description) THEN 'FITTING' ELSE public.workshop_stage_code_for_work_key(ol.work_key) END) IN
      ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
    THEN coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(ol.description) THEN 'FITTING' ELSE public.workshop_stage_code_for_work_key(ol.work_key) END)
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
 ), pilbara_lines AS(
  SELECT 'source:'||o.operation_id::text,'authenticated',o.operation_id,
   'PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
   coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description),o.repair_order_number,
   CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE o.effective_estimated_hours END,
   CASE WHEN CASE WHEN a.active AND a.manual_assignment_locked THEN a.stage_code WHEN o.department='138' THEN 'BUS_4X4' ELSE coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' END,h.category,o.proposed_station) END IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
        THEN CASE WHEN a.active AND a.manual_assignment_locked THEN a.stage_code WHEN o.department='138' THEN 'BUS_4X4' ELSE coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' END,h.category,o.proposed_station) END ELSE 'UNALLOCATED_MAPPING_REVIEW' END,
   coalesce(a.active,true)
  FROM public.pdc_pilbara_service_operations o
  JOIN public.vehicles v ON v.id=o.vehicle_id AND v.stock_number=o.stock_number
  LEFT JOIN public.pdc_pilbara_service_classification_current cc USING(operation_id)
  LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_id::text
  WHERE o.vehicle_id=p_vehicle_id
 ), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines UNION ALL SELECT * FROM pilbara_lines)
 SELECT coalesce(jsonb_agg(CASE WHEN review.status='pending' AND review_vehicle.visible_on_board IS NOT TRUE AND review_vehicle.deleted_at IS NULL AND review_vehicle.lifecycle_state='active' AND review_vehicle.qc_completed_at IS NULL AND saved.adjustment_id IS NULL AND NOT coalesce(c.completed,false) AND NOT coalesce(r.active,false) AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings wb WHERE wb.vehicle_id=p_vehicle_id AND wb.deleted_at IS NULL) THEN public.pdc_pending_work_category_20260912(jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',public.pdc_standard_operation_hours_20260910(l.description,l.estimated_hours),
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  || CASE WHEN public.pdc_is_pre_delivery_20260910(l.description) THEN jsonb_build_object('hours_provenance','craig_standard_pre_delivery_1_hour','source_estimated_hours',coalesce(ps.source_estimated_hours,l.estimated_hours)) ELSE '{}'::jsonb END
  || CASE WHEN ps.operation_id IS NOT NULL THEN jsonb_build_object('source_contract','pilbara_service_open_jobcards_v1','source_evidence_id',ps.raw_evidence_id,'department',ps.department,'original_line_number',ps.original_line_number,'operation_code',coalesce(public.pdc_tune_approved_operation_source_20260912(ps.operation_id)->>'operation_code',(SELECT h.immutable_snapshot->>'operation_code' FROM public.pdc_pilbara_service_operation_history h WHERE h.operation_id=ps.operation_id AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL ORDER BY h.created_at DESC LIMIT 1),ps.operation_code),'proposed_station',ps.proposed_station) ELSE '{}'::jsonb END||jsonb_build_object('source_estimated_hours',CASE WHEN ps.operation_id IS NOT NULL THEN ps.source_estimated_hours ELSE l.estimated_hours END)) ELSE jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',public.pdc_standard_operation_hours_20260910(l.description,l.estimated_hours),
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  || CASE WHEN public.pdc_is_pre_delivery_20260910(l.description) THEN jsonb_build_object('hours_provenance','craig_standard_pre_delivery_1_hour','source_estimated_hours',coalesce(ps.source_estimated_hours,l.estimated_hours)) ELSE '{}'::jsonb END
  || CASE WHEN ps.operation_id IS NOT NULL THEN jsonb_build_object('source_contract','pilbara_service_open_jobcards_v1','source_evidence_id',ps.raw_evidence_id,'department',ps.department,'original_line_number',ps.original_line_number,'operation_code',coalesce(public.pdc_tune_approved_operation_source_20260912(ps.operation_id)->>'operation_code',(SELECT h.immutable_snapshot->>'operation_code' FROM public.pdc_pilbara_service_operation_history h WHERE h.operation_id=ps.operation_id AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL ORDER BY h.created_at DESC LIMIT 1),ps.operation_code),'proposed_station',ps.proposed_station) ELSE '{}'::jsonb END END
  ORDER BY CASE WHEN l.stage_code='UNALLOCATED_MAPPING_REVIEW' THEN 2 WHEN l.stage_code='SUBLET' THEN 1 ELSE 0 END,l.stage_code,substring(l.operation_no from '[0-9]+')::integer NULLS LAST,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l
 LEFT JOIN public.pdc_pilbara_service_operations ps ON ps.vehicle_id=p_vehicle_id AND ps.operation_id=l.source_line_id AND l.source_kind='authenticated'
 LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 LEFT JOIN public.pdc_qc_operation_rejections_381 r ON r.vehicle_id=p_vehicle_id AND r.line_identity=l.line_identity
 LEFT JOIN public.pdc_new_vehicle_reviews review ON review.vehicle_id=p_vehicle_id
 LEFT JOIN public.vehicles review_vehicle ON review_vehicle.id=p_vehicle_id
 LEFT JOIN public.vehicle_workshop_line_adjustments saved ON saved.vehicle_id=p_vehicle_id AND saved.line_key=l.line_identity
$function$
;
