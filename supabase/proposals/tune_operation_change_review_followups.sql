CREATE FUNCTION public.pdc_tune_approved_operation_source_20260912(oid uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO pg_catalog,public AS $$
 SELECT proposed_source FROM public.pdc_tune_operation_change_reviews
 WHERE source_operation_id=oid AND status='approved' ORDER BY approved_at DESC,change_id DESC LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.pdc_tune_approved_operation_source_20260912(uuid) FROM PUBLIC,anon,authenticated;
CREATE INDEX pdc_tune_approved_operation_source_idx ON public.pdc_tune_operation_change_reviews(source_operation_id,approved_at DESC,change_id DESC) WHERE status='approved';
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
 'navision_jita_identity_verified',jita.match_count=1,
 'navision_jita_column_present',CASE WHEN jita.match_count=1 THEN jita.column_present ELSE false END,
 'navision_jita_number_authority',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.authority ELSE NULL END,
 'navision_jita_number',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.jita_number ELSE NULL END,
 'navision_jita_identity_status',CASE WHEN jita.match_count=0 THEN 'not_found' WHEN jita.match_count=1 THEN 'exact' ELSE 'ambiguous' END
)||CASE WHEN EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews nr WHERE nr.vehicle_id=canonical.id AND nr.source_kind='tune_pmg') THEN public.pdc_tune_vehicle_details_v5(canonical.id) ELSE '{}'::jsonb END||jsonb_build_object(
    'location_override',canonical.location_override,'location_override_reason',canonical.location_override_reason,'location_override_at',canonical.location_override_at,'location_override_by',canonical.location_override_by,'automatic_location',canonical.current_location,'qc_completed_at',canonical.qc_completed_at,
    'qc_completed_by',canonical.qc_completed_by,
    'rft_transferred_at',canonical.rft_transferred_at,
    'parts_flags',public.pdc_parts_flags_vehicle_20260911(canonical.id),'qc_rework',public.pdc_qc_rework_scope_20260909((row_value->>'id')::uuid),'pilbara_service_operations',service_lines,
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
  LEFT JOIN LATERAL (
   SELECT count(*) AS match_count,
    bool_or(coalesce((n.normalized_data->>'_navisionJitaNumberColumnPresent')::boolean,false)) AS column_present,
    max(n.normalized_data->>'navisionJitaNumberAuthority') AS authority,
    max(n.normalized_data->>'jitQty') AS jita_number
   FROM public.navision_backend_records n
   WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision'
    AND n.canonical_vehicle_id=canonical.id
    AND upper(btrim(coalesce(n.normalized_data->>'stock','')))=upper(btrim(canonical.stock_number))
  ) jita ON true
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',o.operation_id,
      'operation_no','PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
      'work_key',CASE CASE WHEN o.department='138' THEN 'BUS_4X4' WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(CASE WHEN o.department='138' THEN 'BUS_4X4' WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END) END,
      'job_card_number',o.repair_order_number,'description',coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description),
      'estimated_hours',o.effective_estimated_hours,
      'estimated_hours_source',CASE o.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',o.source_estimated_hours,'effective_estimated_hours',o.effective_estimated_hours,
      'hours_provenance',o.hours_provenance,'parts_on_backorder_raw',o.parts_on_backorder_raw,'parts_semantics',o.parts_semantics,
      'classification',CASE WHEN o.department='138' THEN 'BUS_4X4' WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END,'classification_method',coalesce(h.method,'review'),
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
$function$;
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
 SELECT coalesce(jsonb_agg(jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',public.pdc_standard_operation_hours_20260910(l.description,l.estimated_hours),
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  || CASE WHEN public.pdc_is_pre_delivery_20260910(l.description) THEN jsonb_build_object('hours_provenance','craig_standard_pre_delivery_1_hour','source_estimated_hours',coalesce(ps.source_estimated_hours,l.estimated_hours)) ELSE '{}'::jsonb END
  || CASE WHEN ps.operation_id IS NOT NULL THEN jsonb_build_object('source_contract','pilbara_service_open_jobcards_v1','source_evidence_id',ps.raw_evidence_id,'department',ps.department,'original_line_number',ps.original_line_number,'operation_code',coalesce(public.pdc_tune_approved_operation_source_20260912(ps.operation_id)->>'operation_code',(SELECT h.immutable_snapshot->>'operation_code' FROM public.pdc_pilbara_service_operation_history h WHERE h.operation_id=ps.operation_id AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL ORDER BY h.created_at DESC LIMIT 1),ps.operation_code),'proposed_station',ps.proposed_station) ELSE '{}'::jsonb END
  ORDER BY CASE WHEN l.stage_code='UNALLOCATED_MAPPING_REVIEW' THEN 2 WHEN l.stage_code='SUBLET' THEN 1 ELSE 0 END,l.stage_code,substring(l.operation_no from '[0-9]+')::integer NULLS LAST,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l
 LEFT JOIN public.pdc_pilbara_service_operations ps ON ps.vehicle_id=p_vehicle_id AND ps.operation_id=l.source_line_id AND l.source_kind='authenticated'
 LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 LEFT JOIN public.pdc_qc_operation_rejections_381 r ON r.vehicle_id=p_vehicle_id AND r.line_identity=l.line_identity
$function$;
CREATE OR REPLACE FUNCTION public.save_vehicle_workshop_line_hours_batch_768(p_vehicle_id uuid, p_stock_number text, p_job_card_number text, p_expected_vehicle_version bigint, p_estimated_rows jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_scope jsonb;
  v_vehicle_dealer text;
  v_vehicle public.vehicles%rowtype;
  v_receipt public.vehicle_workshop_hours_batch_receipts_768%rowtype;
  v_rows jsonb:=coalesce(p_estimated_rows,'[]'::jsonb);
  v_canonical_rows jsonb;
  v_request jsonb;
  v_request_hash text;
  v_current_rows jsonb:='[]'::jsonb;
  v_conflicts jsonb:='[]'::jsonb;
  v_changes jsonb:='[]'::jsonb;
  v_revision bigint;
  v_vehicle_after public.vehicles%rowtype;
  v_changed_count integer:=0;
  v_receipt_id uuid:=gen_random_uuid();
BEGIN
  IF v_actor IS NULL OR v_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;
  PERFORM public.require_pdc_role('operator');
  v_scope:=public.pdc_auditor_actor_scope();
  v_vehicle_dealer:=public.pdc_auditor_vehicle_dealer(p_vehicle_id);
  IF v_scope->>'environment' IS DISTINCT FROM 'staging'
     OR NOT public.pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,v_vehicle_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  IF p_vehicle_id IS NULL OR p_idempotency_key IS NULL
    OR nullif(btrim(coalesce(p_stock_number,'')),'') IS NULL
    OR nullif(btrim(coalesce(p_job_card_number,'')),'') IS NULL
    OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
    OR jsonb_typeof(v_rows)<>'array' OR jsonb_array_length(v_rows) NOT BETWEEN 1 AND 250
    OR EXISTS(
      SELECT 1 FROM jsonb_array_elements(v_rows) x
      WHERE jsonb_typeof(x)<>'object'
        OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x) k)
           IS DISTINCT FROM ARRAY['adjustment_id','estimated_hours','expected_line_version','line_key','operation_line_id','stage_code','work_key']::text[]
        OR coalesce(x->>'operation_line_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        OR coalesce(x->>'line_key','')<>('source:'||lower(coalesce(x->>'operation_line_id','')))
        OR coalesce(x->>'work_key','')<>lower(btrim(coalesce(x->>'work_key','')))
        OR coalesce(x->>'work_key','') IN ('parts','pit_inspection','unallocated_mapping_review')
        OR coalesce(x->>'stage_code','')<>upper(btrim(coalesce(x->>'stage_code','')))
        OR coalesce(x->>'stage_code','') !~ '^[A-Z][A-Z0-9_]{1,39}$'
        OR coalesce(x->>'expected_line_version','') !~ '^[0-9]+$'
        OR jsonb_typeof(x->'adjustment_id') IS NULL
        OR (jsonb_typeof(x->'adjustment_id')='string' AND coalesce(x->>'adjustment_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        OR jsonb_typeof(x->'adjustment_id') NOT IN ('string','null')
        OR jsonb_typeof(x->'estimated_hours') IS NULL
        OR jsonb_typeof(x->'estimated_hours') NOT IN ('number','null')
        OR (jsonb_typeof(x->'estimated_hours')='number' AND (
          coalesce(x->>'estimated_hours','') !~ '^(0|[0-9]+)(\.[0-9]{1,2})?$'
          OR (x->>'estimated_hours')::numeric<0 OR (x->>'estimated_hours')::numeric>999.99
        ))
    )
    OR (SELECT count(*) FROM jsonb_array_elements(v_rows))
      <>(SELECT count(DISTINCT lower(x->>'operation_line_id')) FROM jsonb_array_elements(v_rows) x)
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_hours_batch'); END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY lower(x->>'operation_line_id')),'[]'::jsonb)
    INTO v_canonical_rows FROM jsonb_array_elements(v_rows) x;
  v_request:=jsonb_build_object(
    'contract','vehicle_workshop_hours_batch_768.1','actor_id',v_actor,'vehicle_id',p_vehicle_id,
    'stock_number',btrim(p_stock_number),'job_card_number',btrim(p_job_card_number),
    'expected_vehicle_version',p_expected_vehicle_version,'estimated_rows',v_canonical_rows,
    'idempotency_key',p_idempotency_key);
  v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-workshop-hours-batch:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_receipt FROM public.vehicle_workshop_hours_batch_receipts_768
   WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_receipt.request_hash<>v_request_hash THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict','data',jsonb_build_object('receipt_id',v_receipt.receipt_id));
    END IF;
    RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
  END IF;

  SELECT * INTO v_vehicle FROM public.vehicles
   WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF btrim(coalesce(v_vehicle.stock_number::text,''))<>btrim(p_stock_number) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_identity_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_request_t780 ON COMMIT DROP AS
  SELECT lower(x->>'operation_line_id')::uuid operation_line_id,
    NULLIF(x->>'adjustment_id','')::uuid adjustment_id,
    (x->>'expected_line_version')::bigint expected_line_version,
    x->>'line_key' line_key,upper(x->>'stage_code') stage_code,lower(x->>'work_key') work_key,
    CASE WHEN jsonb_typeof(x->'estimated_hours')='null' THEN NULL ELSE (x->>'estimated_hours')::numeric END estimated_hours
  FROM jsonb_array_elements(v_rows) x;
  CREATE UNIQUE INDEX ON pdc_hours_batch_request_t780(operation_line_id);

  CREATE TEMP TABLE pdc_hours_batch_source_t780 ON COMMIT DROP AS
  SELECT ol.operation_line_id,ol.vehicle_id,'authenticated'::text source_contract,
    coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v_vehicle.job_card_number),'')) job_card_number,
    lower(ol.work_key) work_key,public.workshop_stage_code_for_work_key(ol.work_key) stage_code,
    ol.description,ol.estimated_hours source_estimated_hours,ol.estimated_hours effective_estimated_hours,
    ol.operation_no,ol.source_row_no display_order
  FROM public.pdc_authenticated_email_operation_lines ol
  JOIN pdc_hours_batch_request_t780 r ON r.operation_line_id=ol.operation_line_id
  WHERE ol.vehicle_id=p_vehicle_id
  UNION ALL
  SELECT o.operation_id,o.vehicle_id,'pilbara_service_open_jobcards_v1',o.repair_order_number,
    CASE coalesce(h.category,'REVIEW') WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(coalesce(h.category,'REVIEW')) END,
    coalesce(h.category,'REVIEW'),coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description),o.source_estimated_hours,o.effective_estimated_hours,
    'PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),o.original_line_number
  FROM public.pdc_pilbara_service_operations o
  JOIN pdc_hours_batch_request_t780 r ON r.operation_line_id=o.operation_id
  LEFT JOIN public.pdc_pilbara_service_classification_current cc USING(operation_id)
  LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
  WHERE o.vehicle_id=p_vehicle_id;
  CREATE UNIQUE INDEX ON pdc_hours_batch_source_t780(operation_line_id);

  IF EXISTS(SELECT 1 FROM pdc_hours_batch_request_t780 WHERE work_key='parts' OR stage_code='PARTS') THEN
    RETURN jsonb_build_object('ok',false,'code','parts_not_hour_bearing','data',jsonb_build_object('vehicle_id',p_vehicle_id,'booking_created',false,'parts_mutated',false));
  END IF;

  PERFORM 1 FROM public.vehicle_workshop_line_adjustments a
   JOIN pdc_hours_batch_request_t780 r ON r.line_key=a.line_key
   WHERE a.vehicle_id=p_vehicle_id FOR UPDATE;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'line_key',r.line_key,'work_key',r.work_key,'stage_code',r.stage_code,
    'source_contract',s.source_contract,'source_estimated_hours',s.source_estimated_hours,
    'adjustment_id',a.adjustment_id,'line_version',coalesce(a.version,0),
    'estimated_hours',CASE WHEN a.adjustment_id IS NOT NULL AND a.active THEN a.estimated_hours ELSE s.effective_estimated_hours END,
    'active',coalesce(a.active,true)
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_current_rows
  FROM pdc_hours_batch_request_t780 r
  LEFT JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key;

  IF v_vehicle.version<>p_expected_vehicle_version THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'current_rows',v_current_rows));
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'requested_work_key',r.work_key,'requested_stage_code',r.stage_code,
    'requested_line_version',r.expected_line_version,'source_contract',s.source_contract,
    'current_work_key',s.work_key,'current_stage_code',s.stage_code,
    'current_adjustment_id',a.adjustment_id,'current_line_version',coalesce(a.version,0),
    'reason',CASE
      WHEN s.operation_line_id IS NULL THEN 'operation_line_not_found'
      WHEN coalesce(a.active,true)=false THEN 'operation_line_adjustment_inactive'
      WHEN s.job_card_number<>btrim(p_job_card_number) THEN 'job_card_identity_conflict'
      WHEN s.work_key<>r.work_key THEN 'work_key_conflict'
      WHEN s.stage_code<>r.stage_code THEN 'stage_identity_conflict'
      WHEN a.adjustment_id IS DISTINCT FROM r.adjustment_id THEN 'adjustment_identity_conflict'
      WHEN coalesce(a.version,0)<>r.expected_line_version THEN 'line_version_conflict'
      ELSE 'row_drift'
    END
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_conflicts
  FROM pdc_hours_batch_request_t780 r
  LEFT JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE s.operation_line_id IS NULL OR coalesce(a.active,true)=false
     OR s.job_card_number IS DISTINCT FROM btrim(p_job_card_number)
     OR s.work_key IS DISTINCT FROM r.work_key OR s.stage_code IS DISTINCT FROM r.stage_code
     OR a.adjustment_id IS DISTINCT FROM r.adjustment_id OR coalesce(a.version,0)<>r.expected_line_version;
  IF jsonb_array_length(v_conflicts)>0 THEN
    RETURN jsonb_build_object('ok',false,'code','line_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'conflicts',v_conflicts,'current_rows',v_current_rows));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_changes_t780 ON COMMIT DROP AS
  SELECT r.operation_line_id,r.adjustment_id current_adjustment_id,r.expected_line_version,
    r.line_key,r.stage_code,r.work_key,r.estimated_hours,s.source_contract,s.description source_description,
    s.source_estimated_hours,s.effective_estimated_hours source_effective_hours,s.operation_no,s.display_order,
    CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE s.effective_estimated_hours END current_estimated_hours,
    coalesce(a.version,0) current_line_version
  FROM pdc_hours_batch_request_t780 r
  JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE r.estimated_hours IS DISTINCT FROM CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE s.effective_estimated_hours END;
  SELECT count(*) INTO v_changed_count FROM pdc_hours_batch_changes_t780;

  IF v_changed_count>0 THEN
    UPDATE public.vehicle_workshop_line_adjustments a SET
      stage_code=c.stage_code,
      description=c.source_description,
      estimated_hours=c.estimated_hours,
      correction_origin=CASE WHEN c.estimated_hours IS NULL THEN 'manual_operator_unknown' ELSE 'manual_operator' END,
      manual_assignment_locked=false,
      active=true,
      version=a.version+1,
      updated_by=v_actor,
      updated_at=clock_timestamp()
    FROM pdc_hours_batch_changes_t780 c
    WHERE a.adjustment_id=c.current_adjustment_id
      AND a.vehicle_id=p_vehicle_id;

    INSERT INTO public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,version,
      created_by,updated_by,source_operation_line_id,job_card_number,operation_code,display_order,manual_assignment_locked
    )
    SELECT p_vehicle_id,c.line_key,'source',c.stage_code,c.source_description,c.estimated_hours,
      CASE WHEN c.estimated_hours IS NULL THEN 'manual_operator_unknown' ELSE 'manual_operator' END,
      true,1,v_actor,v_actor,CASE WHEN c.source_contract='authenticated' THEN c.operation_line_id ELSE NULL END,
      p_job_card_number,c.operation_no,c.display_order,false
    FROM pdc_hours_batch_changes_t780 c WHERE c.current_adjustment_id IS NULL
    ON CONFLICT(vehicle_id,line_key) DO UPDATE SET
      stage_code=excluded.stage_code,description=excluded.description,estimated_hours=excluded.estimated_hours,
      correction_origin=excluded.correction_origin,manual_assignment_locked=false,
      active=true,version=public.vehicle_workshop_line_adjustments.version+1,updated_by=v_actor,updated_at=clock_timestamp();

    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operation_line_id',c.operation_line_id,'line_key',c.line_key,'work_key',c.work_key,'source_contract',c.source_contract,
      'source_estimated_hours',c.source_estimated_hours,
      'before',jsonb_build_object('adjustment_id',c.current_adjustment_id,'estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      'after',jsonb_build_object('adjustment_id',a.adjustment_id,'estimated_hours',a.estimated_hours,'version',a.version,'correction_origin',a.correction_origin)
    ) ORDER BY c.operation_line_id),'[]'::jsonb) INTO v_changes
    FROM pdc_hours_batch_changes_t780 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    SELECT CASE WHEN c.current_adjustment_id IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,
      'vehicle_workshop_line_adjustments',a.adjustment_id,p_vehicle_id,v_actor,v_email,
      jsonb_build_object('adjustment_id',c.current_adjustment_id,'operation_line_id',c.operation_line_id,
        'source_contract',c.source_contract,'source_estimated_hours',c.source_estimated_hours,
        'effective_estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      jsonb_build_object('adjustment_id',a.adjustment_id,'operation_line_id',c.operation_line_id,
        'source_contract',c.source_contract,'source_estimated_hours',c.source_estimated_hours,
        'effective_estimated_hours',a.estimated_hours,'version',a.version,'correction_origin',a.correction_origin),
      jsonb_build_object('source','vehicle_workshop_hours_batch_768.1','request_id',p_idempotency_key,
        'request_hash',v_request_hash,'bookings_changed',false,'parts_changed',false,'completion_changed',false)
    FROM pdc_hours_batch_changes_t780 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    UPDATE public.vehicles SET version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
    WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  ELSE
    v_vehicle_after:=v_vehicle;
  END IF;

  SELECT revision INTO v_revision FROM public.pdc_email_vehicle_revision WHERE singleton;
  v_receipt.response:=jsonb_build_object('ok',true,'code',CASE WHEN v_changed_count>0 THEN 'workshop_hours_batch_saved' ELSE 'workshop_hours_batch_no_changes' END,
    'replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_hash,'vehicle_id',p_vehicle_id,
    'vehicle_version_before',v_vehicle.version,'vehicle_version_after',v_vehicle_after.version,
    'revision',v_revision,'changed_count',v_changed_count,'changes',v_changes,
    'booking_created',false,'parts_mutated',false,'completion_changed',false);
  INSERT INTO public.vehicle_workshop_hours_batch_receipts_768(
    receipt_id,idempotency_key,actor_id,vehicle_id,request_hash,base_vehicle_version,response)
  VALUES(v_receipt_id,p_idempotency_key,v_actor,p_vehicle_id,v_request_hash,v_vehicle.version,v_receipt.response)
  RETURNING * INTO v_receipt;
  RETURN v_receipt.response;
END $function$;
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
           WHEN public.pdc_is_pre_delivery_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)) THEN 'FITTING' ELSE coalesce(h.category,o.proposed_station,'REVIEW') END stage_code,
      public.pdc_standard_operation_hours_20260910(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description),CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE o.effective_estimated_hours END) estimated_hours
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
) SELECT CASE WHEN (rework.body->>'active')::boolean THEN (SELECT (s->>'estimated_hours')::numeric FROM jsonb_array_elements(rework.body->'stages') s WHERE s->>'stage_code'=public.workshop_canonical_stage_code(p_stage_code)) ELSE (SELECT * FROM normal) END FROM rework $function$;
CREATE OR REPLACE FUNCTION public.approve_pdc_tune_operation_change(p_change_id uuid,p_snapshot_hash text,p_stage_code text,p_estimated_hours numeric,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public,extensions SET lock_timeout TO '5s' SET statement_timeout TO '60s' AS $$
DECLARE actor uuid:=auth.uid(); q public.pdc_tune_operation_change_reviews%rowtype; v public.vehicles%rowtype;
 a public.vehicle_workshop_line_adjustments%rowtype; actual jsonb; result jsonb; reply jsonb; request_hash text;
 source_id uuid; key text; target_work text; h numeric; before_bookings jsonb; before_location text; p jsonb; new_line jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'authenticated' OR actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=actor
 AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email',''))) AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE)
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_change_id IS NULL OR p_snapshot_hash IS NULL OR p_snapshot_hash !~ '^[a-f0-9]{64}$' OR p_idempotency_key IS NULL
 OR p_stage_code IS NULL OR p_stage_code NOT IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 OR (p_stage_code<>'SUBLET' AND (p_estimated_hours IS NULL OR p_estimated_hours<=0 OR p_estimated_hours>999.99 OR mod(p_estimated_hours,0.01)<>0))
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_operation_hours_or_station'); END IF;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_change_id,p_snapshot_hash,p_stage_code,p_estimated_hours)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT vehicle_id INTO source_id FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id;
 SELECT * INTO v FROM public.vehicles WHERE id=source_id FOR UPDATE;
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_review_not_found'); END IF;
 IF q.status='approved' THEN
   IF q.approval_key=p_idempotency_key AND q.approval_hash=request_hash AND q.approved_by=actor THEN RETURN q.approval_receipt||jsonb_build_object('replay',true); END IF;
   RETURN jsonb_build_object('ok',false,'code','already_approved');
 END IF;
 IF q.status<>'pending' OR v.deleted_at IS NOT NULL OR NOT v.visible_on_board OR v.lifecycle_state::text<>'active'
 OR v.qc_completed_at IS NOT NULL OR upper(btrim(coalesce(v.current_location,''))) IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
 THEN RETURN jsonb_build_object('ok',false,'code','vehicle_or_review_state_protected'); END IF;
 IF public.pdc_tune_operation_change_row_20260912(q.change_id)->>'snapshot_hash' IS DISTINCT FROM p_snapshot_hash
 THEN RETURN jsonb_build_object('ok',false,'code','operation_review_changed'); END IF;
 p:=q.proposed_source;source_id:=q.source_operation_id;key:='source:'||source_id;
 IF v.stock_number IS DISTINCT FROM p->>'stock_number' THEN RETURN jsonb_build_object('ok',false,'code','stock_identity_changed'); END IF;
 SELECT work_key INTO target_work FROM public.workshop_stages WHERE code=p_stage_code AND active;
 IF target_work IS NULL THEN RETURN jsonb_build_object('ok',false,'code','invalid_station'); END IF;
 IF EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v.id AND work_key=target_work AND completed)
 THEN RETURN jsonb_build_object('ok',false,'code','completed_station_requires_rework_review'); END IF;
 IF source_id IS NOT NULL THEN
   SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
   IF actual IS NULL OR (actual->>'completed')::boolean OR (actual->>'active')::boolean IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','completed_or_removed_line_protected'); END IF;
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]') INTO before_bookings FROM public.workshop_bookings b WHERE b.vehicle_id=v.id;
 before_location:=v.current_location;
 h:=CASE WHEN p_stage_code='SUBLET' THEN coalesce(public.pdc_standard_operation_hours_20260910(p->>'operation_description',(p->>'source_estimated_hours')::numeric),0) ELSE p_estimated_hours END;
 IF source_id IS NULL THEN
   IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v.id AND repair_order_number=q.repair_order_number AND original_line_number=q.original_line_number)
   THEN RETURN jsonb_build_object('ok',false,'code','operation_identity_changed'); END IF;
   INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
     source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
   VALUES(p->>'department',p->>'operation_code','REVIEW','pilbara_service_open_jobcards_v1',v.stock_number,q.repair_order_number,q.original_line_number,(p->>'source_order')::integer,v.id,p->>'operation_description',
     (p->>'source_estimated_hours')::numeric,(p->>'effective_estimated_hours')::numeric,p->>'hours_provenance',coalesce(p->>'parts_on_backorder_raw',''),'review','Review',p->>'semantic_hash',q.evidence_id)
   RETURNING operation_id INTO source_id;
   key:='source:'||source_id;
   INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
   VALUES(source_id,q.batch_id,'insert',NULL,p->>'semantic_hash',p);
 END IF;
 -- Publish the accepted source version within this transaction so canonical readback uses it.
 -- Any later save/readback failure rolls this change back with the rest of the approval.
 UPDATE public.pdc_tune_operation_change_reviews SET status='approved',source_operation_id=source_id,
 approved_at=clock_timestamp(),approved_by=actor WHERE change_id=q.change_id;
 -- Establish only the approved target's required-work flag; do not reset completed work.
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 VALUES(v.id,target_work,true,false,'Approved Tune operation change')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp();
 SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 result:=public.move_vehicle_workshop_source_line_stage(v.id,a.adjustment_id,coalesce(a.version,0),key,p_stage_code);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'operation_station_save_failed'; END IF;
 SELECT * INTO STRICT a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 result:=public.upsert_vehicle_workshop_line_adjustment(v.id,a.adjustment_id,a.version,key,p_stage_code,
   a.description,h);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'operation_details_save_failed'; END IF;
 SELECT l INTO new_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF new_line IS NULL OR new_line->>'stage_code' IS DISTINCT FROM p_stage_code OR (new_line->>'estimated_hours')::numeric IS DISTINCT FROM h
 OR (new_line->>'completed')::boolean IS DISTINCT FROM false OR new_line->>'description' IS DISTINCT FROM p->>'operation_description'
 THEN RAISE EXCEPTION 'operation_approval_readback_mismatch'; END IF;
 IF before_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]') FROM public.workshop_bookings b WHERE b.vehicle_id=v.id)
 OR before_location IS DISTINCT FROM (SELECT current_location FROM public.vehicles WHERE id=v.id)
 THEN RAISE EXCEPTION 'operation_approval_protected_state_changed'; END IF;
 reply:=jsonb_build_object('ok',true,'code','operation_change_approved','data',jsonb_build_object('change_id',q.change_id,'vehicle_id',v.id,'operation',new_line,'bookings_changed',false,'location_changed',false));
 UPDATE public.pdc_tune_operation_change_reviews SET status='approved',source_operation_id=source_id,approved_at=clock_timestamp(),approved_by=actor,
 approval_key=p_idempotency_key,approval_hash=request_hash,approval_receipt=reply,version=version+1 WHERE change_id=q.change_id;
 PERFORM public.audit_pdc_event('update','pdc_tune_operation_change_reviews',q.change_id,v.id,q.before_source,p,
 jsonb_build_object('action','approve_tune_operation_change','source_evidence_id',q.evidence_id,'idempotency_key',p_idempotency_key,'bookings_changed',false));
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 PERFORM public.workshop_bump_revision();
 RETURN reply;
END $$;
REVOKE ALL ON FUNCTION public.approve_pdc_tune_operation_change(uuid,text,text,numeric,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.approve_pdc_tune_operation_change(uuid,text,text,numeric,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.approve_pdc_tune_operation_change(p_change_id uuid,p_snapshot_hash text,p_stage_code text,p_estimated_hours numeric,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog,public,extensions SET lock_timeout TO '5s' SET statement_timeout TO '60s' AS $$
DECLARE actor uuid:=auth.uid(); q public.pdc_tune_operation_change_reviews%rowtype; v public.vehicles%rowtype;
 a public.vehicle_workshop_line_adjustments%rowtype; actual jsonb; result jsonb; reply jsonb; request_hash text;
 source_id uuid; key text; target_work text; h numeric; before_bookings jsonb; before_location text; p jsonb; new_line jsonb;
BEGIN
 IF auth.role() IS DISTINCT FROM 'authenticated' OR actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=actor
 AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email',''))) AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE)
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_change_id IS NULL OR p_snapshot_hash IS NULL OR p_snapshot_hash !~ '^[a-f0-9]{64}$' OR p_idempotency_key IS NULL
 OR p_stage_code IS NULL OR p_stage_code NOT IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 OR (p_stage_code<>'SUBLET' AND (p_estimated_hours IS NULL OR p_estimated_hours<=0 OR p_estimated_hours>999.99 OR mod(p_estimated_hours,0.01)<>0))
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_operation_hours_or_station'); END IF;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_change_id,p_snapshot_hash,p_stage_code,p_estimated_hours)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT vehicle_id INTO source_id FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id;
 SELECT * INTO v FROM public.vehicles WHERE id=source_id FOR UPDATE;
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_review_not_found'); END IF;
 IF q.status='approved' THEN
   IF q.approval_key=p_idempotency_key AND q.approval_hash=request_hash AND q.approved_by=actor THEN RETURN q.approval_receipt||jsonb_build_object('replay',true); END IF;
   RETURN jsonb_build_object('ok',false,'code','already_approved');
 END IF;
 IF q.status<>'pending' OR v.deleted_at IS NOT NULL OR NOT v.visible_on_board OR v.lifecycle_state::text<>'active'
 OR v.qc_completed_at IS NOT NULL OR upper(btrim(coalesce(v.current_location,''))) IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
 THEN RETURN jsonb_build_object('ok',false,'code','vehicle_or_review_state_protected'); END IF;
 IF public.pdc_tune_operation_change_row_20260912(q.change_id)->>'snapshot_hash' IS DISTINCT FROM p_snapshot_hash
 THEN RETURN jsonb_build_object('ok',false,'code','operation_review_changed'); END IF;
 p:=q.proposed_source;source_id:=q.source_operation_id;key:='source:'||source_id;
 IF v.stock_number IS DISTINCT FROM p->>'stock_number' THEN RETURN jsonb_build_object('ok',false,'code','stock_identity_changed'); END IF;
 SELECT work_key INTO target_work FROM public.workshop_stages WHERE code=p_stage_code AND active;
 IF target_work IS NULL THEN RETURN jsonb_build_object('ok',false,'code','invalid_station'); END IF;
 IF EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v.id AND work_key=target_work AND completed)
 THEN RETURN jsonb_build_object('ok',false,'code','completed_station_requires_rework_review'); END IF;
 IF source_id IS NOT NULL THEN
   SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
   IF actual IS NULL OR (actual->>'completed')::boolean OR (actual->>'active')::boolean IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','completed_or_removed_line_protected'); END IF;
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]') INTO before_bookings FROM public.workshop_bookings b WHERE b.vehicle_id=v.id;
 before_location:=v.current_location;
 h:=CASE WHEN p_stage_code='SUBLET' THEN coalesce(public.pdc_standard_operation_hours_20260910(p->>'operation_description',(p->>'source_estimated_hours')::numeric),0) ELSE p_estimated_hours END;
 IF source_id IS NULL THEN
   IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v.id AND repair_order_number=q.repair_order_number AND original_line_number=q.original_line_number)
   THEN RETURN jsonb_build_object('ok',false,'code','operation_identity_changed'); END IF;
   INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
     source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
   VALUES(p->>'department',p->>'operation_code','REVIEW','pilbara_service_open_jobcards_v1',v.stock_number,q.repair_order_number,q.original_line_number,(p->>'source_order')::integer,v.id,p->>'operation_description',
     (p->>'source_estimated_hours')::numeric,(p->>'effective_estimated_hours')::numeric,p->>'hours_provenance',coalesce(p->>'parts_on_backorder_raw',''),'review','Review',p->>'semantic_hash',q.evidence_id)
   RETURNING operation_id INTO source_id;
   key:='source:'||source_id;
   INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
   VALUES(source_id,q.batch_id,'insert',NULL,p->>'semantic_hash',p);
 END IF;
 -- Publish the accepted source version within this transaction so canonical readback uses it.
 -- Any later save/readback failure rolls this change back with the rest of the approval.
 UPDATE public.pdc_tune_operation_change_reviews SET status='approved',source_operation_id=source_id,
 approved_at=clock_timestamp(),approved_by=actor WHERE change_id=q.change_id;
 -- Establish only the approved target's required-work flag; do not reset completed work.
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 VALUES(v.id,target_work,true,false,'Approved Tune operation change')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp();
 SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 IF q.change_kind='added' THEN
   INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,manual_assignment_locked,created_by,updated_by)
   VALUES(v.id,key,'source',p_stage_code,btrim(left(btrim(regexp_replace(p->>'operation_description','[[:cntrl:]]',' ','g')),180)),h,true,1,true,actor,actor);
   result:=jsonb_build_object('ok',true);
 ELSE
   result:=public.move_vehicle_workshop_source_line_stage(v.id,a.adjustment_id,coalesce(a.version,0),key,p_stage_code);
 END IF;
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'operation_station_save_failed'; END IF;
 SELECT * INTO STRICT a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 result:=public.upsert_vehicle_workshop_line_adjustment(v.id,a.adjustment_id,a.version,key,p_stage_code,
   a.description,h);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'operation_details_save_failed'; END IF;
 SELECT l INTO new_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF new_line IS NULL OR new_line->>'stage_code' IS DISTINCT FROM p_stage_code OR (new_line->>'estimated_hours')::numeric IS DISTINCT FROM h
 OR (new_line->>'completed')::boolean IS DISTINCT FROM false OR new_line->>'description' IS DISTINCT FROM p->>'operation_description'
 THEN RAISE EXCEPTION 'operation_approval_readback_mismatch'; END IF;
 IF before_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]') FROM public.workshop_bookings b WHERE b.vehicle_id=v.id)
 OR before_location IS DISTINCT FROM (SELECT current_location FROM public.vehicles WHERE id=v.id)
 THEN RAISE EXCEPTION 'operation_approval_protected_state_changed'; END IF;
 reply:=jsonb_build_object('ok',true,'code','operation_change_approved','data',jsonb_build_object('change_id',q.change_id,'vehicle_id',v.id,'operation',new_line,'bookings_changed',false,'location_changed',false));
 UPDATE public.pdc_tune_operation_change_reviews SET status='approved',source_operation_id=source_id,approved_at=clock_timestamp(),approved_by=actor,
 approval_key=p_idempotency_key,approval_hash=request_hash,approval_receipt=reply,version=version+1 WHERE change_id=q.change_id;
 PERFORM public.audit_pdc_event('update','pdc_tune_operation_change_reviews',q.change_id,v.id,q.before_source,p,
 jsonb_build_object('action','approve_tune_operation_change','source_evidence_id',q.evidence_id,'idempotency_key',p_idempotency_key,'bookings_changed',false));
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 PERFORM public.workshop_bump_revision();
 RETURN reply;
END $$;
REVOKE ALL ON FUNCTION public.approve_pdc_tune_operation_change(uuid,text,text,numeric,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.approve_pdc_tune_operation_change(uuid,text,text,numeric,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_parts_flags_vehicle_20260911(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH evidence AS (
 SELECT o.operation_id,r.repair_order_number,r.original_line_number,
 coalesce(r.raw_row->>'Company',r.raw_row->>'company','') company,
 coalesce(r.raw_row->>'Division',r.raw_row->>'division','') division,
 r.raw_row,b.created_at,h.history_id::text history_id
 FROM public.pdc_pilbara_service_operations o
 JOIN public.pdc_pilbara_service_operation_history h USING(operation_id)
 JOIN public.pdc_pilbara_service_import_batches b ON b.batch_id=h.batch_id AND b.batch_kind='apply'
 JOIN public.pdc_pilbara_service_import_batches preview ON preview.source_hash=b.source_hash AND preview.batch_kind='preview'
 JOIN public.pdc_pilbara_service_import_rows r ON r.batch_id=preview.batch_id
 AND r.normalized_payload->>'operation_identity_hash'=h.immutable_snapshot->>'operation_identity_hash'
 AND r.decision IN('insert','unchanged')
 WHERE o.vehicle_id=p_vehicle_id
 UNION ALL
 SELECT o.operation_id,r.repair_order_number,r.original_line_number,
 coalesce(r.raw_row->>'Company',r.raw_row->>'company',''),
 coalesce(r.raw_row->>'Division',r.raw_row->>'division',''),
 r.raw_row,b.created_at,r.evidence_id::text
 FROM public.pdc_pilbara_service_import_rows r
 JOIN public.pdc_pilbara_service_import_batches preview ON preview.batch_id=r.batch_id AND preview.batch_kind='preview'
 JOIN public.pdc_pilbara_service_import_batches b ON b.source_hash=preview.source_hash AND b.batch_kind='apply'
 LEFT JOIN public.pdc_pilbara_service_operations o ON o.vehicle_id=r.vehicle_id AND o.repair_order_number=r.repair_order_number AND o.original_line_number=r.original_line_number
 WHERE r.vehicle_id=p_vehicle_id AND r.reason='operation_update_review'
 ), latest AS (
 SELECT DISTINCT ON(company,division,repair_order_number,original_line_number) * FROM evidence
 ORDER BY company,division,repair_order_number,original_line_number,created_at DESC,history_id DESC
 ), flags AS (
 SELECT *,public.pdc_numeric_parts_flag_20260911(raw_row->'Parts Attached') a,
 public.pdc_numeric_parts_flag_20260911(raw_row->'Parts on Backorder') b,
 public.pdc_numeric_parts_flag_20260911(raw_row->'Backorder with PO (1=Yes, 0=No)') p FROM latest
 ), jobs AS (
 SELECT company,division,repair_order_number,max(created_at) imported_at,
 CASE WHEN bool_or(a IS NULL OR b IS NULL OR p IS NULL OR (p=1 AND b=0)) THEN public.pdc_parts_flags_status_20260911(NULL,NULL,NULL)
 ELSE public.pdc_parts_flags_status_20260911(max(a),max(b),max(p)) END status,
 max(b) job_backorder,max(p) job_po FROM flags GROUP BY company,division,repair_order_number
 ), ops AS (
 SELECT f.operation_id,CASE WHEN j.status->>'colour'='review' THEN public.pdc_parts_flags_status_20260911(NULL,NULL,NULL) ELSE public.pdc_parts_flags_status_20260911(f.a,j.job_backorder,j.job_po) END||jsonb_build_object(
 'job_label',CASE WHEN j.job_backorder=1 THEN 'Job has outstanding parts' WHEN j.status->>'colour'='review' THEN 'Job parts need review' ELSE 'Job has no recorded backorders' END,
 'last_successful_import_at',f.created_at,'job_number',f.repair_order_number,'line_number',f.original_line_number,
 'company',f.company,'division',f.division) status
 FROM flags f JOIN jobs j USING(company,division,repair_order_number)
 )
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM flags) THEN NULL ELSE jsonb_build_object(
 'jobs',(SELECT jsonb_agg(status||jsonb_build_object('job_number',repair_order_number,'company',company,'division',division,'last_successful_import_at',imported_at)) FROM jobs),
 'operations',(SELECT coalesce(jsonb_object_agg(operation_id::text,status),'{}') FROM ops WHERE operation_id IS NOT NULL),
 'last_successful_import_at',(SELECT max(created_at) FROM flags),
 'colour',CASE WHEN (SELECT count(*) FROM jobs)=1 THEN (SELECT status->>'colour' FROM jobs) ELSE 'review' END,
 'label',CASE WHEN (SELECT count(*) FROM jobs)=1 THEN (SELECT status->>'label' FROM jobs) ELSE 'Multiple jobs — review each job parts status' END,
 'meaning','Attached means at least one operation has parts recorded; PO means at least one outstanding part has a PO. Neither proves every required part is available.') END
$function$
;
