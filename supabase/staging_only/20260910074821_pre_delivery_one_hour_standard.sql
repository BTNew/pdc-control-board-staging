-- STAGING only. Craig 2026-09-10: every pre-delivery is one hour.
-- Source rows, immutable receipts/hashes and historical evidence remain unchanged.
DO $$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING only'; END IF;
END $$;
DO $$ BEGIN
 IF md5(pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure))<>'4db8884805cd10d6cd9775404b5b7703' THEN RAISE EXCEPTION 'Definition changed: pdc_qc_operation_lines_379'; END IF;
 IF md5(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure))<>'3b06dc3c55fc15cc4bd73dfc550df80e' THEN RAISE EXCEPTION 'Definition changed: get_pdc_email_vehicle_location_snapshot'; END IF;
 IF md5(pg_get_functiondef('public.list_pdc_unidentified_tune_reviews(integer,integer)'::regprocedure))<>'c4c7a9eab1e36d34a2b2c23aaff23172' THEN RAISE EXCEPTION 'Definition changed: list_pdc_unidentified_tune_reviews'; END IF;
 IF md5(pg_get_functiondef('public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure))<>'1ea078b211a01bd5cb7b9b817982a9f5' THEN RAISE EXCEPTION 'Definition changed: workshop_vehicle_stage_estimated_hours'; END IF;
END $$;

CREATE FUNCTION public.pdc_is_pre_delivery_20260910(p_description text)
RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT lower(coalesce(p_description,'')) ~ '(^|[^a-z0-9])(pre[[:space:]‐‑–—-]*delivery|pdi)([^a-z0-9]|$)'
$$;
CREATE FUNCTION public.pdc_standard_operation_hours_20260910(p_description text,p_hours numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE SECURITY INVOKER SET search_path=pg_catalog,public AS $$
 SELECT CASE WHEN public.pdc_is_pre_delivery_20260910(p_description) THEN 1.0 ELSE p_hours END
$$;
CREATE FUNCTION public.pdc_standard_operation_display_20260910(p_line jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE SECURITY INVOKER SET search_path=pg_catalog,public AS $$
 SELECT CASE WHEN public.pdc_is_pre_delivery_20260910(p_line->>'description') THEN
 p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
 'estimated_hours',1.0,'effective_estimated_hours',1.0,'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_pre_delivery_1_hour')
 ELSE p_line END
$$;
REVOKE ALL ON FUNCTION public.pdc_is_pre_delivery_20260910(text),public.pdc_standard_operation_hours_20260910(text,numeric),public.pdc_standard_operation_display_20260910(jsonb) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION public.pdc_standard_operation_hours_20260910(text,numeric) IS 'Craig 2026-09-10: all pre-delivery one hour, overrides prior 1.5/zero/source hours in operational projections. Immutable import evidence is preserved.';
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
   o.operation_description,o.repair_order_number,
   CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE o.effective_estimated_hours END,
   CASE WHEN CASE WHEN o.department='138' THEN 'BUS_4X4' ELSE coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(o.operation_description) THEN 'FITTING' END,h.category,o.proposed_station) END IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
        THEN CASE WHEN o.department='138' THEN 'BUS_4X4' ELSE coalesce(a.stage_code,CASE WHEN public.pdc_is_pre_delivery_20260910(o.operation_description) THEN 'FITTING' END,h.category,o.proposed_station) END ELSE 'UNALLOCATED_MAPPING_REVIEW' END,
   coalesce(a.active,true)
  FROM public.pdc_pilbara_service_operations o
  JOIN public.vehicles v ON v.id=o.vehicle_id AND v.stock_number=o.stock_number
  LEFT JOIN public.pdc_pilbara_service_classification_current cc USING(operation_id)
  LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_id::text
  WHERE o.vehicle_id=p_vehicle_id
 ), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines UNION ALL SELECT * FROM pilbara_lines)
 SELECT coalesce(jsonb_agg(jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',public.pdc_standard_operation_hours_20260910(l.description,l.estimated_hours),
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  || CASE WHEN public.pdc_is_pre_delivery_20260910(l.description) THEN jsonb_build_object('hours_provenance','craig_standard_pre_delivery_1_hour','source_estimated_hours',coalesce(ps.source_estimated_hours,l.estimated_hours)) ELSE '{}'::jsonb END
  || CASE WHEN ps.operation_id IS NOT NULL THEN jsonb_build_object('source_contract','pilbara_service_open_jobcards_v1','source_evidence_id',ps.raw_evidence_id,'department',ps.department,'original_line_number',ps.original_line_number,'operation_code',coalesce((SELECT h.immutable_snapshot->>'operation_code' FROM public.pdc_pilbara_service_operation_history h WHERE h.operation_id=ps.operation_id AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL ORDER BY h.created_at DESC LIMIT 1),ps.operation_code),'proposed_station',ps.proposed_station) ELSE '{}'::jsonb END
  ORDER BY CASE WHEN l.stage_code='UNALLOCATED_MAPPING_REVIEW' THEN 2 WHEN l.stage_code='SUBLET' THEN 1 ELSE 0 END,l.stage_code,substring(l.operation_no from '[0-9]+')::integer NULLS LAST,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l
 LEFT JOIN public.pdc_pilbara_service_operations ps ON ps.vehicle_id=p_vehicle_id AND ps.operation_id=l.source_line_id AND l.source_kind='authenticated'
 LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 LEFT JOIN public.pdc_qc_operation_rejections_381 r ON r.vehicle_id=p_vehicle_id AND r.line_identity=l.line_identity
$function$
;
CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_hours(p_vehicle_id uuid, p_stage_code text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$ WITH rework AS (SELECT public.pdc_qc_rework_scope_20260909(p_vehicle_id) body), normal AS (
  WITH email_source_lines AS (
    SELECT
      CASE WHEN a.adjustment_id IS NOT NULL THEN a.stage_code
           WHEN public.pdc_is_pre_delivery_20260910(ol.description) THEN 'FITTING'
           ELSE public.workshop_stage_code_for_work_key(ol.work_key) END stage_code,
      public.pdc_standard_operation_hours_20260910(ol.description,CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE ol.estimated_hours END) estimated_hours
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
      CASE WHEN o.department='138' THEN 'BUS_4X4' WHEN a.adjustment_id IS NOT NULL THEN a.stage_code
           WHEN public.pdc_is_pre_delivery_20260910(o.operation_description) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END stage_code,
      public.pdc_standard_operation_hours_20260910(o.operation_description,CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE o.effective_estimated_hours END) estimated_hours
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
    SELECT a.stage_code,public.pdc_standard_operation_hours_20260910(a.description,a.estimated_hours)
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
) SELECT CASE WHEN (rework.body->>'active')::boolean THEN (SELECT (s->>'estimated_hours')::numeric FROM jsonb_array_elements(rework.body->'stages') s WHERE s->>'stage_code'=public.workshop_canonical_stage_code(p_stage_code)) ELSE (SELECT * FROM normal) END FROM rework $function$
;
CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_base jsonb; v_rows jsonb;
BEGIN
  v_base:=public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1();
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  SELECT coalesce(jsonb_agg(row_value||jsonb_build_object(
    'qc_completed_at',canonical.qc_completed_at,
    'qc_completed_by',canonical.qc_completed_by,
    'rft_transferred_at',canonical.rft_transferred_at,
    'qc_rework',public.pdc_qc_rework_scope_20260909((row_value->>'id')::uuid),'pilbara_service_operations',service_lines,
    'operation_lines',(SELECT coalesce(jsonb_agg(
   public.pdc_standard_operation_display_20260910(CASE WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE a.stage_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(a.stage_code) END,
     'classification',a.stage_code,'station_assignment_source','manual_operator') ELSE op END) ORDER BY ordinal),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines) WITH ORDINALITY x(op,ordinal)
   LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=(row_value->>'id')::uuid
     AND a.line_key='source:'||(op->>'operation_line_id') AND a.active AND a.manual_assignment_locked
     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'))
  ) ORDER BY coalesce(row_value->>'stock_number',row_value->>'id')),'[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(coalesce(v_base#>'{data,vehicles}','[]'::jsonb)) row_value
  JOIN public.vehicles canonical ON canonical.id=(row_value->>'id')::uuid
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',o.operation_id,
      'operation_no','PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
      'work_key',CASE CASE WHEN o.department='138' THEN 'BUS_4X4' WHEN public.pdc_is_pre_delivery_20260910(o.operation_description) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(CASE WHEN o.department='138' THEN 'BUS_4X4' WHEN public.pdc_is_pre_delivery_20260910(o.operation_description) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END) END,
      'job_card_number',o.repair_order_number,'description',o.operation_description,
      'estimated_hours',o.effective_estimated_hours,
      'estimated_hours_source',CASE o.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',o.source_estimated_hours,'effective_estimated_hours',o.effective_estimated_hours,
      'hours_provenance',o.hours_provenance,'parts_on_backorder_raw',o.parts_on_backorder_raw,'parts_semantics',o.parts_semantics,
      'classification',CASE WHEN o.department='138' THEN 'BUS_4X4' WHEN public.pdc_is_pre_delivery_20260910(o.operation_description) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END,'classification_method',coalesce(h.method,'review'),
      'classification_confidence',coalesce(h.confidence,0),'classification_rationale',coalesce(h.rationale,'No current classification; retained for Review.'),
      'source_description_hash',h.source_description_hash,'classifier_version',h.classifier_version,
      'source_uid','pilbara_service_open_jobcards_v1:'||o.stock_number||':'||o.repair_order_number||':'||o.original_line_number
    )) ORDER BY o.source_order),'[]'::jsonb) service_lines
    FROM public.pdc_pilbara_service_operations o
    LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
    LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    WHERE o.vehicle_id=(row_value->>'id')::uuid
  ) projected;
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$function$
;
CREATE OR REPLACE FUNCTION public.list_pdc_unidentified_tune_reviews(p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE items jsonb; total integer;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r
 WHERE r.auth_user_id=auth.uid() AND r.active AND r.account_status='approved' AND r.role IN('viewer','operator','importer','administrator')
 AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email',''))))
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 SELECT count(*) INTO total FROM (SELECT DISTINCT workbook_sha256,repair_order_number FROM public.pdc_unidentified_tune_review) x;
 SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') INTO items FROM (
  SELECT workbook_sha256,repair_order_number,department,count(*) operation_count,sum(public.pdc_standard_operation_hours_20260910(operation_description,source_estimated_hours)) hours,
   jsonb_agg(jsonb_build_object('description',operation_description,'line',original_line_number,'source_estimated_hours',source_estimated_hours,'hours',public.pdc_standard_operation_hours_20260910(operation_description,source_estimated_hours),'station',proposed_station,'operation_code',operation_code) ORDER BY original_line_number,operation_identity_hash) operations
  FROM public.pdc_unidentified_tune_review GROUP BY workbook_sha256,repair_order_number,department
  ORDER BY workbook_sha256,repair_order_number LIMIT p_limit OFFSET p_offset) q;
 RETURN jsonb_build_object('ok',true,'code','unidentified_tune_reviews','data',jsonb_build_object('items',items,'total',total));
END $function$
;
UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;

