-- STAGING. Read latest successful source evidence; never rewrite original operations.
CREATE OR REPLACE FUNCTION public.pdc_numeric_parts_flag_20260911(v jsonb)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog AS $$
 SELECT CASE WHEN jsonb_typeof(v) IN ('number','string') AND btrim(v #>> '{}') IN ('0','1') THEN (btrim(v #>> '{}'))::integer ELSE NULL END
$$;

CREATE OR REPLACE FUNCTION public.pdc_parts_flags_status_20260911(a integer,b integer,p integer)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path TO pg_catalog AS $$
 SELECT jsonb_build_object('parts_attached',a,'backorder',b,'backorder_with_po',p,'colour',
 CASE WHEN a IS NULL OR b IS NULL OR p IS NULL OR a NOT IN(0,1) OR b NOT IN(0,1) OR p NOT IN(0,1) OR (p=1 AND b=0) THEN 'review'
 WHEN b=1 AND (p=1 OR a=1) THEN 'orange' WHEN b=1 THEN 'red' WHEN a=1 THEN 'green' ELSE 'grey' END,
 'label',CASE WHEN a IS NULL OR b IS NULL OR p IS NULL OR a NOT IN(0,1) OR b NOT IN(0,1) OR p NOT IN(0,1) THEN 'Unknown / Needs review'
 WHEN p=1 AND b=0 THEN 'Inconsistent data / Needs review'
 WHEN b=1 AND p=1 THEN 'Parts on order — outstanding'
 WHEN a=1 AND b=1 THEN 'Parts attached; outstanding parts — check PO'
 WHEN b=1 THEN 'Outstanding parts — PO not confirmed'
 WHEN a=1 THEN 'Parts attached — no recorded backorders'
 ELSE 'No parts recorded — check whether required' END)
$$;

CREATE OR REPLACE FUNCTION public.pdc_parts_flags_vehicle_20260911(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO pg_catalog,public AS $$
 WITH evidence AS (
 SELECT o.operation_id,r.repair_order_number,r.original_line_number,
 coalesce(r.raw_row->>'Company',r.raw_row->>'company','') company,
 coalesce(r.raw_row->>'Division',r.raw_row->>'division','') division,
 r.raw_row,b.created_at,h.history_id
 FROM public.pdc_pilbara_service_operations o
 JOIN public.pdc_pilbara_service_operation_history h USING(operation_id)
 JOIN public.pdc_pilbara_service_import_batches b ON b.batch_id=h.batch_id AND b.batch_kind='apply'
 JOIN public.pdc_pilbara_service_import_batches preview ON preview.source_hash=b.source_hash AND preview.batch_kind='preview'
 JOIN public.pdc_pilbara_service_import_rows r ON r.batch_id=preview.batch_id
 AND r.normalized_payload->>'operation_identity_hash'=h.immutable_snapshot->>'operation_identity_hash'
 AND r.decision IN('insert','unchanged')
 WHERE o.vehicle_id=p_vehicle_id
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
 'operations',(SELECT jsonb_object_agg(operation_id::text,status) FROM ops),
 'last_successful_import_at',(SELECT max(created_at) FROM flags),
 'colour',CASE WHEN (SELECT count(*) FROM jobs)=1 THEN (SELECT status->>'colour' FROM jobs) ELSE 'review' END,
 'label',CASE WHEN (SELECT count(*) FROM jobs)=1 THEN (SELECT status->>'label' FROM jobs) ELSE 'Multiple jobs — review each job parts status' END,
 'meaning','Attached means at least one operation has parts recorded; PO means at least one outstanding part has a PO. Neither proves every required part is available.') END
$$;
REVOKE ALL ON FUNCTION public.pdc_numeric_parts_flag_20260911(jsonb),public.pdc_parts_flags_status_20260911(integer,integer,integer),public.pdc_parts_flags_vehicle_20260911(uuid) FROM PUBLIC,anon,authenticated;

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
$function$;
CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_codex_scoped boolean := public.pdc_email_ai_runtime_authorized_v1() IS NOT TRUE;
  v_candidate jsonb; v_stock text; v_tune boolean; v_code text; v_backend uuid;
  v_actor uuid:=pdc_codex_intake_private.import_actor();v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_actor_label text:=v_actor_email||':viewer:'||coalesce(v_actor::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;
  v_preview public.pdc_pilbara_service_import_batches%rowtype;v_prior public.pdc_pilbara_service_import_batches%rowtype;v_apply_batch uuid:=gen_random_uuid();
  v_row public.pdc_pilbara_service_import_rows%rowtype;v_op public.pdc_pilbara_service_operations%rowtype;v_vehicle_id uuid;v_first_ro text;v_operation_id uuid;v_identity_hash text;v_response jsonb;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF v_codex_scoped AND pdc_codex_intake_private.authorized('apply',NULL,p_source_hash,p_idempotency_key,p_preview_batch_id) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF v_codex_scoped THEN v_actor_label:=v_actor_email||':codex_workbook_importer:'||v_actor::text; END IF;
  IF pdc_codex_intake_private.management_connection() IS TRUE THEN v_actor_label:='codex_supabase_management:postgres:'||v_actor::text; END IF;
  IF p_preview_batch_id IS NULL OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request');END IF;
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches b WHERE b.batch_id=p_preview_batch_id AND b.importer_version='pilbara_service_open_jobcards_v1' AND b.batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR v_preview.source_hash<>v_source_hash OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');END IF;
  v_tune:=v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4','pmg_stock_v5');
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc_pilbara_service_apply_v1_dynamic_20260910','preview_batch_id',p_preview_batch_id,'source_hash',v_source_hash)::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||v_source_hash,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='apply' AND b.contract_revision=v_preview.contract_revision;
  IF FOUND THEN
    IF v_codex_scoped AND pdc_codex_intake_private.authorized('readback',NULL,NULL,NULL,v_prior.batch_id) IS NOT TRUE
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_apply_conflict');END IF;
    INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,'replay',v_prior.response||jsonb_build_object('code','apply_replay','replay',true),v_actor,v_actor_label);
    RETURN v_prior.response||jsonb_build_object('code','apply_replay','replay',true);END IF;
  IF v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4') AND v_preview.accepted_line_count>0 THEN
    RETURN jsonb_build_object('ok',false,'code','preview_refresh_required','contract_revision','pmg_stock_v5');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  IF NOT v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 LEFT JOIN public.navision_backend_records b ON b.id=r0.backend_record_id LEFT JOIN public.vehicles v ON v.id=r0.vehicle_id
    WHERE r0.batch_id=v_preview.batch_id AND r0.decision IN('insert','unchanged') AND (b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision'
      OR b.dealer_code<>'37047' OR b.canonical_vehicle_id IS DISTINCT FROM r0.vehicle_id
      OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) IS DISTINCT FROM btrim(r0.stock_number)
      OR v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.stock_number_normalized IS DISTINCT FROM btrim(r0.stock_number)
      OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision' AND x.dealer_code='37047' AND x.is_current AND x.record_status='current'
        AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r0.stock_number))<>1))
  THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='insert'
      AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'))
     OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='unchanged'
      AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'
        AND o.semantic_hash=r0.semantic_hash))
  THEN RETURN jsonb_build_object('ok',false,'code','operation_state_changed_after_preview');END IF;
  IF v_tune THEN
    -- Serialize Stock creation with all canonical writers and validate every candidate before any write.
    LOCK TABLE public.vehicles, public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
    FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_row.stock_number);
      IF (v_candidate->>'ok')::boolean IS NOT TRUE
        OR (v_row.vehicle_id IS NOT NULL AND v_row.vehicle_id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid)
        OR v_row.backend_record_id IS DISTINCT FROM (v_candidate->>'backend_record_id')::uuid
      THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed','stock_number',v_row.stock_number); END IF;
    END LOOP;
  END IF;
  IF v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_unidentified_tune_review u ON u.workbook_sha256=r.normalized_payload->>'workbook_sha256' AND u.operation_identity_hash=r.normalized_payload->>'operation_identity_hash'
    WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review' AND (u.source_estimated_hours IS DISTINCT FROM (r.normalized_payload->>'source_estimated_hours')::numeric OR u.raw_row IS DISTINCT FROM r.raw_row))
  THEN RETURN jsonb_build_object('ok',false,'code','unidentified_source_changed'); END IF;
  v_response:=jsonb_build_object('ok',true,'code','applied','replay',false,'apply_batch_id',v_apply_batch,'source_hash',v_source_hash,'source_link',v_preview.source_link,'unidentified_rows',(SELECT count(*) FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND reason='unidentified_tune_review'),'approvals_created',0,'insert',v_preview.insert_count,'update',0,
    'unchanged',v_preview.unchanged_count,'duplicate_ignored',coalesce((v_preview.response->'operations'->>'duplicate_ignored')::integer,0),'bookings_created',0,'completions_created',0,'atomic',true);
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,quarantined_line_count,
    matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_preview.contract_revision,v_preview.source_link,v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'apply',v_preview.source_row_count,v_preview.accepted_line_count,v_preview.quarantined_line_count,
    v_preview.matched_stock_count,v_preview.unmatched_stock_count,v_preview.ambiguous_stock_count,v_preview.insert_count,0,v_preview.unchanged_count,v_preview.conflict_count,v_response,v_actor,v_actor_label);
  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL THEN
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;
        -- Link only the unique current exact-Stock record accepted by this revision.
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')
        WHERE id=v_vehicle_id;
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);
      END IF;
    END LOOP;
    IF v_preview.contract_revision='pmg_stock_v5' THEN
      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;
        PERFORM public.pdc_apply_tune_vehicle_fields_v5(v_vehicle_id,v_apply_batch,v_preview.batch_id);
      END LOOP;
    END IF;
    INSERT INTO public.pdc_unidentified_tune_review(workbook_sha256,repair_order_number,department,original_line_number,operation_description,operation_identity_hash,source_estimated_hours,operation_code,proposed_station,raw_row,source_hash,source_batch_id)
    SELECT r.normalized_payload->>'workbook_sha256',r.repair_order_number,r.normalized_payload->>'department',r.original_line_number,r.normalized_payload->>'operation_description',r.normalized_payload->>'operation_identity_hash',
      (r.normalized_payload->>'source_estimated_hours')::numeric,r.normalized_payload->>'operation_code',r.normalized_payload->>'proposed_station',r.raw_row,v_source_hash,v_apply_batch
    FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review'
    ON CONFLICT(workbook_sha256,operation_identity_hash) DO NOTHING;
  END IF;
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') ORDER BY r.source_order LOOP
    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;
    v_identity_hash:=v_row.normalized_payload->>'operation_identity_hash';
    SELECT * INTO v_op FROM public.pdc_pilbara_service_operations x WHERE x.importer_version='pilbara_service_open_jobcards_v1'
      AND public.pdc_pilbara_service_operation_identity_hash_v3(x.department,x.stock_number,x.repair_order_number,x.original_line_number,x.operation_description)=v_identity_hash FOR SHARE;
    IF v_row.decision='insert' THEN
      IF FOUND THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
        source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
      VALUES(v_row.normalized_payload->>'department',v_row.normalized_payload->>'operation_code',v_row.normalized_payload->>'proposed_station','pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,v_row.vehicle_id,v_row.normalized_payload->>'operation_description',
        CASE WHEN v_row.normalized_payload->>'source_estimated_hours' IS NULL THEN NULL ELSE (v_row.normalized_payload->>'source_estimated_hours')::numeric END,
        (v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),
        v_row.normalized_payload->>'parts_semantics','Review',v_row.semantic_hash,v_row.evidence_id) RETURNING operation_id INTO v_operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'insert',NULL,v_row.semantic_hash,v_row.normalized_payload);
    ELSE
      IF NOT FOUND OR v_op.semantic_hash<>v_row.semantic_hash THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      v_operation_id:=v_op.operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'unchanged',v_op.semantic_hash,v_op.semantic_hash,v_row.normalized_payload);
    END IF;
  END LOOP;
  FOR v_vehicle_id IN SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operation_history h JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE h.batch_id=v_apply_batch LOOP
    -- Rolling imports retain operations absent from this file.
    SELECT CASE WHEN count(DISTINCT r0.repair_order_number)=1 THEN min(r0.repair_order_number) ELSE NULL END INTO v_first_ro FROM public.pdc_pilbara_service_import_rows r0
    WHERE r0.batch_id=v_preview.batch_id AND (r0.vehicle_id=v_vehicle_id OR (v_tune AND r0.stock_number=(SELECT stock_number FROM public.vehicles WHERE id=v_vehicle_id))) AND r0.decision IN('insert','unchanged');
    IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND NOT v.visible_on_board)
      AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v_vehicle_id AND r.status='closed') THEN
      INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,first_job_card,received_at,approved_at,approved_by,approval_key,approval_hash,approval_receipt)
      VALUES(v_vehicle_id,'pending',CASE WHEN v_tune THEN 'tune_pmg' ELSE 'revolution_report' END,v_first_ro,clock_timestamp(),NULL,NULL,NULL,NULL,NULL)
      ON CONFLICT(vehicle_id) DO UPDATE SET status='pending',source_kind=excluded.source_kind,first_job_card=excluded.first_job_card,received_at=clock_timestamp(),
        approved_at=NULL,approved_by=NULL,approval_key=NULL,approval_hash=NULL,approval_receipt=NULL;
      UPDATE public.vehicles SET job_card_number=v_first_ro,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=v_vehicle_id AND visible_on_board=false;
    END IF;
  END LOOP;
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response,v_actor,v_actor_label);
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  PERFORM public.workshop_bump_revision();
  RETURN v_response;
END
$function$;
CREATE OR REPLACE FUNCTION public.pdc_apply_tune_vehicle_fields_v5(p_vehicle_id uuid, p_batch_id uuid, p_preview_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.pdc_pilbara_service_import_batches%rowtype; v public.vehicles%rowtype; fields jsonb; e public.pdc_tune_intake_evidence_v5%rowtype;
 details jsonb; p public.vehicle_parts_updates%rowtype; desired text; n public.navision_backend_records%rowtype; target_location text;
BEGIN
 SELECT * INTO STRICT b FROM public.pdc_pilbara_service_import_batches WHERE batch_id=p_batch_id AND batch_kind='apply' AND contract_revision='pmg_stock_v5';
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 SELECT jsonb_agg(r.normalized_payload->'tune_source_fields' ORDER BY r.source_order) INTO fields FROM public.pdc_pilbara_service_import_rows r
 WHERE r.batch_id=p_preview_batch_id
 AND r.stock_number=v.stock_number AND r.decision IN('insert','unchanged');
 -- Apply batches on this route bind their preview in request data, not a separate FK.
 IF fields IS NULL THEN RAISE EXCEPTION 'missing_tune_source_fields'; END IF;
 desired:=public.pdc_tune_parts_status_v5(fields);
 INSERT INTO public.pdc_tune_intake_evidence_v5(vehicle_id,batch_id,source_hash,workbook_sha256,customer_name,vehicle_description,tune_vin,parts_status,purchase_order_numbers,source_fields,created_by)
 SELECT v.id,b.batch_id,b.source_hash,b.source_link->>'workbook_sha256',min(nullif(f->>'customer_name','')),min(nullif(f->>'vehicle_description','')),min(nullif(f->>'vin','')),desired,
 coalesce(jsonb_agg(DISTINCT f->>'purchase_order_number') FILTER(WHERE nullif(f->>'purchase_order_number','') IS NOT NULL),'[]'),fields,b.created_by
 FROM jsonb_array_elements(fields) f RETURNING * INTO e;
 INSERT INTO public.pdc_tune_intake_current_v5(vehicle_id,evidence_id) VALUES(v.id,e.evidence_id) ON CONFLICT(vehicle_id) DO UPDATE SET evidence_id=excluded.evidence_id;
 details:=public.pdc_tune_vehicle_details_v5(v.id);
 UPDATE public.vehicles SET customer_name=details->>'customer_name',vehicle_description=details->>'vehicle_description',
 source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_details_evidence_id',e.evidence_id,'details_source',details->>'details_source'),
 version=version+1,updated_by=b.created_by,updated_at=clock_timestamp() WHERE id=v.id;

 -- Pending Tune intake follows its unique current Navision location.
 -- Owner rule: Delivered at Body Builder enters PMB; At Dealer uses delivery closure, never PMB.
 IF NOT v.visible_on_board AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
  AND v.qc_completed_at IS NULL AND v.rft_transferred_at IS NULL AND v.date_to_pmb IS NULL
  AND upper(btrim(coalesce(v.current_location,''))) IN('YARD HOLD','YH','IT','OTHER')
  AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status<>'pending')
  AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings w WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL)
  AND NOT EXISTS(SELECT 1 FROM public.vehicle_movements m WHERE m.vehicle_id=v.id)
  AND details->>'details_source'='microsoft_navision' THEN
  SELECT * INTO n FROM public.navision_backend_records
   WHERE id=(details->>'details_backend_record_id')::uuid AND canonical_vehicle_id=v.id
    AND is_current AND record_status='current';
  IF FOUND THEN
   target_location:=CASE WHEN public.navision_exact_lifecycle_status(n.normalized_data)='deliveredatdealer'
    THEN 'At Dealer' ELSE public.navision_operational_location(n.normalized_data) END;
   IF target_location IN('PMB','YH','IT','Other','At Dealer') THEN
    UPDATE public.vehicles SET current_location=target_location,
     eta_to_kewdale=coalesce(public.navision_kewdale_eta(n.normalized_data),eta_to_kewdale),
     source_payload=coalesce(source_payload,'{}')||jsonb_build_object(
      'tune_location_authority','navision_pending_intake_exact_sublocation',
      'tune_location_backend_record_id',n.id,'tune_location_backend_version',n.version,
      'tune_location_navision_code',n.normalized_data->>'navisionLocationStatus',
      'tune_location_navision_description',n.normalized_data->>'navisionSubLocationDescription'),
     version=version+1,updated_by=b.created_by,updated_at=clock_timestamp()
    WHERE id=v.id;
    IF target_location='At Dealer' THEN
     INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,closed_at,closure_reason)
     VALUES(v.id,'closed','tune_pmg',clock_timestamp(),'Navision: Delivered - At Dealer')
     ON CONFLICT(vehicle_id) DO UPDATE SET status='closed',closed_at=clock_timestamp(),closure_reason=excluded.closure_reason
      WHERE public.pdc_new_vehicle_reviews.status='pending';
    END IF;
   END IF;
  END IF;
 END IF;
 -- Numeric parts evidence never signs off receipt or overwrites staff Parts state.
 PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),jsonb_build_object('details',details,'parts_status',desired),jsonb_build_object('contract','tune_daily_fields_v5','evidence_id',e.evidence_id,'source_batch_id',p_batch_id));
 RETURN jsonb_build_object('vehicle_id',v.id,'evidence_id',e.evidence_id,'details_source',details->>'details_source','parts_status',desired);
END $function$;
CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_preview_v1(p_rows jsonb, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_codex_scoped boolean := public.pdc_email_ai_runtime_authorized_v1() IS NOT TRUE;
  v_revision text:='dynamic_v2'; v_tune boolean:=false; v_dept text; v_station text; v_code text; v_parent text; v_candidate jsonb; v_fields jsonb; v_stock_scope jsonb:='{}';
  v_actor uuid:=pdc_codex_intake_private.import_actor();v_actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':viewer:'||coalesce(auth.uid()::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;
  v_prior public.pdc_pilbara_service_import_batches%rowtype;v_batch_id uuid:=gen_random_uuid();v_item record;v_row jsonb;v_raw jsonb;
  v_stock text;v_ro text;v_descr text;v_parts_raw text;v_parts_sem text;v_provenance text;v_identity_hash text;v_semantic_hash text;v_prior_semantic text;
  v_source_hours numeric;v_effective_hours numeric;v_line_no integer;v_source_order integer;v_backend_count integer;v_backend_id uuid;v_vehicle_id uuid;v_vehicle_count integer;
  v_decision text;v_reason text;v_seen jsonb:='{}'::jsonb;v_outcomes jsonb:='[]'::jsonb;v_response jsonb;
  v_source_count integer:=0;v_accepted_count integer:=0;v_insert_count integer:=0;v_unchanged_count integer:=0;v_duplicate_count integer:=0;
  v_quarantine_count integer:=0;v_conflict_count integer:=0;v_matched_stocks text[]:='{}'::text[];v_unmatched_stocks text[]:='{}'::text[];v_ambiguous_stocks text[]:='{}'::text[];
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF v_codex_scoped AND pdc_codex_intake_private.authorized('preview',p_rows,p_source_hash,p_idempotency_key,NULL) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF v_codex_scoped THEN v_actor_label:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':codex_workbook_importer:'||v_actor::text; END IF;
  IF pdc_codex_intake_private.management_connection() IS TRUE THEN v_actor_label:='codex_supabase_management:postgres:'||v_actor::text; END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000000
     OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_source_contract');END IF;
  v_tune:=EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE x ? 'department' OR (x->'raw_row') ? 'Dept');
  IF v_tune THEN
    v_revision:='pmg_stock_v5';
    SELECT min(coalesce(x->>'workbook_sha256',x->'raw_row'->>'parent_attachment_sha256')) INTO v_parent FROM jsonb_array_elements(p_rows) x;
    IF v_parent IS NULL OR v_parent !~ '^[a-f0-9]{64}$' OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x
      WHERE coalesce(x->>'workbook_sha256',x->'raw_row'->>'parent_attachment_sha256','')<>v_parent
      OR coalesce(x->>'department',x->'raw_row'->>'Dept','') NOT IN('138','139'))
    THEN RETURN jsonb_build_object('ok',false,'code','invalid_tune_source_link'); END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x GROUP BY upper(btrim(x->>'repair_order_number'))
      HAVING count(DISTINCT coalesce(x->>'department',x->'raw_row'->>'Dept'))<>1
      OR count(DISTINCT nullif(btrim(x->>'stock_number'),''))>1)
    THEN RETURN jsonb_build_object('ok',false,'code','conflicting_job_card_identity'); END IF;
  END IF;
  IF v_tune THEN SELECT coalesce(jsonb_object_agg(ro,stock),'{}') INTO v_stock_scope FROM (SELECT upper(btrim(src->>'repair_order_number')) ro,min(nullif(btrim(src->>'stock_number'),'')) stock FROM jsonb_array_elements(p_rows) src WHERE nullif(btrim(src->>'repair_order_number'),'') IS NOT NULL GROUP BY upper(btrim(src->>'repair_order_number'))) jobcards; END IF;
  IF v_tune AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) src WHERE coalesce(nullif(btrim(src->>'stock_number'),''),v_stock_scope->>upper(btrim(src->>'repair_order_number'))) IS NOT NULL GROUP BY coalesce(nullif(btrim(src->>'stock_number'),''),v_stock_scope->>upper(btrim(src->>'repair_order_number'))) HAVING count(DISTINCT public.pdc_tune_source_fields_v5(src)->>'vin')>1) THEN RETURN jsonb_build_object('ok',false,'code','conflicting_stock_vin_evidence'); END IF;
  v_request_hash:=encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:source:'||v_source_hash||':'||v_revision,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:preview:'||v_idem,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.idempotency_key=v_idem;
  IF FOUND THEN
    IF v_codex_scoped AND (v_prior.created_by IS DISTINCT FROM v_actor OR v_prior.contract_revision<>'pmg_stock_v5'
      OR v_prior.batch_kind<>'preview' OR v_prior.source_link->>'workbook_sha256' IS DISTINCT FROM p_rows->0->>'workbook_sha256'
      OR v_prior.source_link->>'partition_sha256' IS DISTINCT FROM v_source_hash)
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
    IF v_prior.request_hash<>v_request_hash OR v_prior.source_hash<>v_source_hash OR (v_prior.contract_revision<>v_revision AND NOT(v_tune AND v_prior.contract_revision IN('pmg_stock_v3','pmg_stock_v4'))) THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict');END IF;
    RETURN v_prior.response||jsonb_build_object('code','preview_replay','replay',true);END IF;
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='preview' AND (b.contract_revision=v_revision OR (v_tune AND b.contract_revision IN('pmg_stock_v3','pmg_stock_v4'))) ORDER BY b.created_at DESC LIMIT 1;
  IF FOUND THEN
    IF v_codex_scoped AND (v_prior.created_by IS DISTINCT FROM v_actor OR v_prior.contract_revision<>'pmg_stock_v5'
      OR v_prior.batch_kind<>'preview' OR v_prior.source_link->>'workbook_sha256' IS DISTINCT FROM p_rows->0->>'workbook_sha256'
      OR v_prior.source_link->>'partition_sha256' IS DISTINCT FROM v_source_hash)
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_hash_payload_conflict');END IF;
    RETURN v_prior.response||jsonb_build_object('code','preview_replay','replay',true);END IF;
  FOR v_item IN SELECT value AS row_value,ordinality::integer AS ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP
    v_source_count:=v_source_count+1;v_row:=v_item.row_value;v_fields:=public.pdc_tune_source_fields_v5(v_row);
    v_raw:=CASE WHEN jsonb_typeof(v_row->'raw_row')='object' THEN v_row->'raw_row' WHEN jsonb_typeof(v_row)='object' THEN v_row ELSE jsonb_build_object('raw_value',v_row) END;
    v_dept:=CASE WHEN v_tune THEN coalesce(v_row->>'department',v_raw->>'Dept') END;
    v_station:=CASE WHEN v_dept='138' THEN 'BUS_4X4' ELSE upper(coalesce(v_row->>'proposed_station',v_raw->>'proposed_station','REVIEW')) END;
    v_code:=nullif(btrim(coalesce(v_row->>'operation_code',v_raw->>'operation_code')),'');
    IF v_tune AND (nullif(v_row->>'department','') IS NOT NULL AND nullif(v_raw->>'Dept','') IS NOT NULL AND v_row->>'department'<>v_raw->>'Dept')
    THEN RETURN jsonb_build_object('ok',false,'code','conflicting_department_evidence'); END IF;
    IF v_tune AND v_station NOT IN('BUS_4X4','FITTING','ELECTRICAL','TYRE','TINT','HOIST','FABRICATION','SUBLET','REVIEW')
    THEN RETURN jsonb_build_object('ok',false,'code','invalid_proposed_station'); END IF;
    v_source_order:=v_item.ordinality;v_stock:=btrim(coalesce(v_row->>'stock_number',''));v_ro:=upper(btrim(coalesce(v_row->>'repair_order_number','')));
    v_descr:=regexp_replace(btrim(coalesce(v_row->>'operation_description','')),'\s+',' ','g');v_parts_raw:=CASE WHEN v_tune THEN coalesce(v_fields->>'parts_on_backorder_raw','') ELSE btrim(coalesce(v_row->>'parts_on_backorder_raw','')) END;
    -- Numeric-flag export identity is exact R/O + Line within company/division.
    IF v_raw ? 'R/O #' AND upper(btrim(v_raw->>'R/O #')) IS DISTINCT FROM v_ro
      OR v_raw ? 'Line #' AND btrim(v_raw->>'Line #') IS DISTINCT FROM btrim(v_row->>'original_line_number')
    THEN RETURN jsonb_build_object('ok',false,'code','parts_export_identity_mismatch'); END IF;
    IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations prior
      JOIN public.pdc_pilbara_service_import_rows old ON old.evidence_id=prior.raw_evidence_id
      WHERE prior.stock_number=v_stock AND prior.repair_order_number=v_ro
      AND prior.original_line_number::text=btrim(v_row->>'original_line_number')
      AND (coalesce(old.raw_row->>'Company',old.raw_row->>'company','') IS DISTINCT FROM coalesce(v_raw->>'Company',v_raw->>'company','')
        OR coalesce(old.raw_row->>'Division',old.raw_row->>'division','') IS DISTINCT FROM coalesce(v_raw->>'Division',v_raw->>'division','')))
    THEN RETURN jsonb_build_object('ok',false,'code','company_division_identity_requires_review'); END IF;
    v_line_no:=NULL;v_source_hours:=NULL;v_effective_hours:=NULL;v_provenance:='';v_parts_sem:='';v_identity_hash:=NULL;v_semantic_hash:=NULL;v_prior_semantic:=NULL;
    v_backend_id:=NULL;v_vehicle_id:=NULL;v_backend_count:=0;v_vehicle_count:=0;v_decision:='quarantine';v_reason:='invalid_row';
    IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR (v_stock='' AND NOT v_tune) OR length(v_stock)>80 OR v_ro='' OR length(v_ro)>80 OR v_descr='' OR length(v_descr)>1000
       OR coalesce(v_row->>'original_line_number','') !~ '^[0-9]+$' THEN v_reason:='invalid_natural_identity';v_quarantine_count:=v_quarantine_count+1;
    ELSE
      IF v_tune AND v_stock='' THEN
        SELECT coalesce(min(nullif(btrim(x->>'stock_number'),'')),'') INTO v_stock FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(x->>'repair_order_number'))=v_ro;
      END IF;
      v_line_no:=(v_row->>'original_line_number')::integer;
      IF v_line_no<1 THEN v_reason:='invalid_line_number';v_quarantine_count:=v_quarantine_count+1;
      ELSIF v_tune AND nullif(btrim(v_row->>'source_estimated_hours'),'') IS NULL THEN v_reason:='missing_hours';v_quarantine_count:=v_quarantine_count+1;
      ELSIF v_row ? 'source_estimated_hours' AND v_row->'source_estimated_hours' IS NOT NULL AND btrim(coalesce(v_row->>'source_estimated_hours',''))<>'' THEN
        IF btrim(v_row->>'source_estimated_hours') !~ '^[0-9]+([.][0-9]{1,2})?$' OR (v_row->>'source_estimated_hours')::numeric NOT BETWEEN 0 AND 999.99
        THEN v_reason:='invalid_source_hours';v_quarantine_count:=v_quarantine_count+1;
        ELSE v_source_hours:=(v_row->>'source_estimated_hours')::numeric;v_effective_hours:=v_source_hours;v_provenance:='source_explicit';END IF;
      ELSE
        IF lower(regexp_replace(v_descr,'[^a-z0-9]+','','g')) IN('predelivery','predeliverycommercial','vehiclepredelivery')
        THEN v_effective_hours:=1.0;v_provenance:='pre_delivery_default_1_0';
        ELSIF coalesce(v_row->>'hours_provenance','')='ai_estimated' AND btrim(coalesce(v_row->>'effective_estimated_hours','')) ~ '^[0-9]+([.][0-9]{1,2})?$'
          AND (v_row->>'effective_estimated_hours')::numeric BETWEEN 0 AND 999.99
        THEN v_effective_hours:=(v_row->>'effective_estimated_hours')::numeric;v_provenance:='ai_estimated';
        ELSE v_provenance:='source_blank';v_reason:='missing_hours';v_quarantine_count:=v_quarantine_count+1;END IF;
      END IF;
      IF v_effective_hours IS NOT NULL THEN
        IF v_tune THEN v_source_hours:=trim_scale(v_source_hours);v_effective_hours:=trim_scale(v_effective_hours); END IF;
        v_parts_sem:=CASE lower(v_parts_raw) WHEN 'yes' THEN 'explicitly_backordered' WHEN 'no' THEN 'not_backordered' ELSE 'review' END;
        v_identity_hash:=public.pdc_pilbara_service_operation_identity_hash_v3(v_dept,v_stock,v_ro,v_line_no,v_descr);
        v_semantic_hash:=encode(extensions.digest(convert_to(concat_ws(chr(31),v_identity_hash,coalesce(v_source_hours::text,''),v_effective_hours::text,v_provenance,v_parts_raw,v_parts_sem,'Review'),'UTF8'),'sha256'),'hex');
        IF v_seen ? v_identity_hash THEN
          IF v_seen->>v_identity_hash=(v_semantic_hash||coalesce((v_raw->'Parts Attached')::text,'null')||coalesce((v_raw->'Parts on Backorder')::text,'null')||coalesce((v_raw->'Backorder with PO (1=Yes, 0=No)')::text,'null')||CASE WHEN v_tune THEN chr(31)||coalesce(v_code,'')||chr(31)||v_station ELSE '' END) THEN v_decision:='duplicate';v_reason:='exact_duplicate_row_ignored';v_duplicate_count:=v_duplicate_count+1;
          ELSE v_decision:='conflict';v_reason:='duplicate_operation_identity_conflict';v_conflict_count:=v_conflict_count+1;END IF;
        ELSE
          v_seen:=v_seen||jsonb_build_object(v_identity_hash,v_semantic_hash||coalesce((v_raw->'Parts Attached')::text,'null')||coalesce((v_raw->'Parts on Backorder')::text,'null')||coalesce((v_raw->'Backorder with PO (1=Yes, 0=No)')::text,'null')||CASE WHEN v_tune THEN chr(31)||coalesce(v_code,'')||chr(31)||v_station ELSE '' END);
          IF v_tune THEN
            IF v_stock='' THEN
              IF nullif(btrim(coalesce(v_row->>'vin',v_raw->>'VIN')),'') IS NOT NULL THEN v_decision:='conflict';v_reason:='vin_identity_requires_review';v_conflict_count:=v_conflict_count+1;
              ELSIF EXISTS(SELECT 1 FROM public.pdc_unidentified_tune_review u WHERE u.workbook_sha256=v_parent AND u.operation_identity_hash=v_identity_hash
                AND (u.source_estimated_hours IS DISTINCT FROM v_source_hours OR u.proposed_station IS DISTINCT FROM v_station OR u.operation_code IS DISTINCT FROM v_code OR u.raw_row IS DISTINCT FROM v_raw))
              THEN v_decision:='conflict';v_reason:='unidentified_source_changed';v_conflict_count:=v_conflict_count+1;
              ELSE v_decision:='quarantine';v_reason:='unidentified_tune_review';v_quarantine_count:=v_quarantine_count+1; END IF;
            ELSIF nullif(v_fields->>'vin','') IS NOT NULL AND (v_fields->>'vin')!~'^[A-HJ-NPR-Z0-9]{17}$' THEN v_decision:='conflict';v_reason:='invalid_vin_evidence';v_conflict_count:=v_conflict_count+1;
            ELSIF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.stock_number=v_stock AND o.repair_order_number=v_ro AND o.department IS NOT NULL AND o.department<>v_dept)
            THEN v_decision:='conflict';v_reason:='conflicting_job_card_department';v_conflict_count:=v_conflict_count+1;
            ELSE
              v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
              IF (v_candidate->>'ok')::boolean IS TRUE AND nullif(v_fields->>'vin','') IS NOT NULL AND (
 EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=(v_candidate->>'vehicle_id')::uuid AND nullif(btrim(v.vin),'') IS NOT NULL AND upper(btrim(v.vin))<>v_fields->>'vin')
 OR EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=(v_candidate->>'backend_record_id')::uuid AND nullif(btrim(n.normalized_data->>'vin'),'') IS NOT NULL AND upper(btrim(n.normalized_data->>'vin'))<>v_fields->>'vin')
 OR EXISTS(SELECT 1 FROM public.vehicles other WHERE upper(btrim(other.vin))=v_fields->>'vin' AND other.id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid)
 OR EXISTS(SELECT 1 FROM public.pdc_tune_intake_current_v5 c JOIN public.pdc_tune_intake_evidence_v5 e USING(evidence_id) WHERE nullif(e.tune_vin,'') IS NOT NULL AND ((c.vehicle_id=(v_candidate->>'vehicle_id')::uuid AND e.tune_vin<>v_fields->>'vin') OR (c.vehicle_id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid AND e.tune_vin=v_fields->>'vin'))))
 THEN v_candidate:=jsonb_build_object('ok',false,'code','stock_vin_conflict'); END IF;
 IF (v_candidate->>'ok')::boolean IS TRUE AND (v_candidate->>'backend_record_id') IS NULL AND EXISTS(
 SELECT 1 FROM jsonb_array_elements(p_rows) src WHERE coalesce(nullif(btrim(src->>'stock_number'),''),v_stock_scope->>upper(btrim(src->>'repair_order_number')))=v_stock
 HAVING count(DISTINCT lower(public.pdc_tune_source_fields_v5(src)->>'customer_name'))>1 OR count(DISTINCT lower(public.pdc_tune_source_fields_v5(src)->>'vehicle_description'))>1)
 THEN v_candidate:=jsonb_build_object('ok',false,'code','conflicting_tune_vehicle_details'); END IF;
 IF (v_candidate->>'ok')::boolean IS NOT TRUE THEN
                v_decision:='conflict';v_reason:=v_candidate->>'code';v_conflict_count:=v_conflict_count+1;
              ELSE
                v_vehicle_id:=(v_candidate->>'vehicle_id')::uuid;v_backend_id:=(v_candidate->>'backend_record_id')::uuid;
                IF NOT v_stock=ANY(v_matched_stocks) THEN v_matched_stocks:=array_append(v_matched_stocks,v_stock); END IF;
                IF v_code IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN public.pdc_pilbara_service_operation_history h USING(operation_id)
                  WHERE public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash
                  AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL AND h.immutable_snapshot->>'operation_code'<>v_code)
                THEN RETURN jsonb_build_object('ok',false,'code','operation_code_conflict'); END IF;
                SELECT o.semantic_hash INTO v_prior_semantic FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
                AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash;
                IF NOT FOUND THEN v_decision:='insert';v_reason:='new_operation';v_insert_count:=v_insert_count+1;v_accepted_count:=v_accepted_count+1;
                ELSIF v_prior_semantic=v_semantic_hash OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations prior
 WHERE prior.semantic_hash=v_prior_semantic AND public.pdc_pilbara_service_operation_identity_hash_v3(prior.department,prior.stock_number,prior.repair_order_number,prior.original_line_number,prior.operation_description)=v_identity_hash
 AND prior.source_estimated_hours IS NOT DISTINCT FROM v_source_hours AND prior.effective_estimated_hours IS NOT DISTINCT FROM v_effective_hours)
 THEN v_semantic_hash:=v_prior_semantic;v_decision:='unchanged';v_reason:='same_operation_daily_metadata';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
                ELSE v_decision:='conflict';v_reason:='semantic_identity_changed_requires_review';v_conflict_count:=v_conflict_count+1;END IF;
              END IF;
            END IF;
          ELSE
          SELECT count(*),min(b.id::text)::uuid INTO v_backend_count,v_backend_id FROM public.navision_backend_records b
          WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047' AND b.is_current AND b.record_status='current'
            AND btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=v_stock;
          IF v_backend_count=0 THEN v_decision:='quarantine';v_reason:='no_exact_current_navision_record';v_quarantine_count:=v_quarantine_count+1;
            IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
          ELSIF v_backend_count<>1 THEN v_decision:='conflict';v_reason:='ambiguous_current_navision_identity';v_conflict_count:=v_conflict_count+1;
            IF NOT v_stock=ANY(v_ambiguous_stocks) THEN v_ambiguous_stocks:=array_append(v_ambiguous_stocks,v_stock);END IF;
          ELSE
            SELECT b.canonical_vehicle_id INTO v_vehicle_id FROM public.navision_backend_records b WHERE b.id=v_backend_id;
            IF v_vehicle_id IS NULL THEN v_decision:='quarantine';v_reason:='navision_vehicle_not_activated';v_quarantine_count:=v_quarantine_count+1;
              IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
            ELSE
              SELECT count(*) INTO v_vehicle_count FROM public.vehicles v WHERE v.id=v_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state::text='active' AND v.stock_number_normalized=v_stock;
              IF v_vehicle_count<>1 THEN v_decision:='quarantine';v_reason:='canonical_vehicle_not_active_for_import';v_quarantine_count:=v_quarantine_count+1;
                IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
              ELSE
                IF NOT v_stock=ANY(v_matched_stocks) THEN v_matched_stocks:=array_append(v_matched_stocks,v_stock);END IF;
                SELECT o.semantic_hash INTO v_prior_semantic FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
                  AND o.department IS NULL AND public.pdc_pilbara_service_operation_identity_hash_v2(o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash;
                IF NOT FOUND THEN v_decision:='insert';v_reason:='new_operation';v_insert_count:=v_insert_count+1;v_accepted_count:=v_accepted_count+1;
                ELSIF v_prior_semantic=v_semantic_hash THEN v_decision:='unchanged';v_reason:='same_semantic_hash';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
                ELSE v_decision:='conflict';v_reason:='semantic_identity_changed_requires_review';v_conflict_count:=v_conflict_count+1;END IF;
              END IF;
            END IF;
          END IF;
          END IF;
        END IF;
      END IF;
    END IF;
    v_outcomes:=v_outcomes||jsonb_build_array(jsonb_build_object('source_order',v_source_order,'stock_number',nullif(v_stock,''),'repair_order_number',nullif(v_ro,''),
      'original_line_number',v_line_no,'backend_record_id',v_backend_id,'vehicle_id',v_vehicle_id,'operation_identity_hash',v_identity_hash,'semantic_hash',v_semantic_hash,
      'normalized_payload',CASE WHEN v_identity_hash IS NULL THEN NULL ELSE jsonb_build_object('importer_version','pilbara_service_open_jobcards_v1','stock_number',v_stock,
        'repair_order_number',v_ro,'original_line_number',v_line_no,'source_order',v_source_order,'operation_description',v_descr,'source_estimated_hours',v_source_hours,
        'effective_estimated_hours',v_effective_hours,'hours_provenance',v_provenance,'parts_on_backorder_raw',v_parts_raw,'parts_semantics',v_parts_sem,'classification','Review',
        'operation_identity_hash',v_identity_hash,'semantic_hash',v_semantic_hash,'department',v_dept,'operation_code',v_code,'proposed_station',CASE WHEN v_tune THEN v_station END,'workbook_sha256',v_parent,'tune_source_fields',CASE WHEN v_tune THEN v_fields END) END,'raw_row',v_raw,'decision',v_decision,'reason',v_reason));
  END LOOP;
  v_response:=jsonb_build_object('ok',true,'code','preview_created','preview_batch_id',v_batch_id,'importer_version','pilbara_service_open_jobcards_v1','source_hash',v_source_hash,
    'source_rows',v_source_count,'accepted_lines',v_accepted_count,'matched',jsonb_build_object('stocks',cardinality(v_matched_stocks),'matched_stock_numbers',to_jsonb(v_matched_stocks)),
    'unmatched',jsonb_build_object('stocks',cardinality(v_unmatched_stocks),'unmatched_stock_numbers',to_jsonb(v_unmatched_stocks)),
    'ambiguous',jsonb_build_object('stocks',cardinality(v_ambiguous_stocks),'ambiguous_stock_numbers',to_jsonb(v_ambiguous_stocks)),
    'operations',jsonb_build_object('insert',v_insert_count,'update',0,'unchanged',v_unchanged_count,'duplicate_ignored',v_duplicate_count,'quarantine',v_quarantine_count,'conflict',v_conflict_count),
    'apply_allowed',(v_accepted_count>0 OR (v_tune AND EXISTS(SELECT 1 FROM jsonb_array_elements(v_outcomes) x WHERE x->>'reason'='unidentified_tune_review'))) AND v_conflict_count=0,'contract_revision',v_revision,'workbook_sha256',v_parent,'partial_batch_policy',CASE WHEN v_tune THEN 'apply_valid_exact_stocks_and_persist_unidentified_separately' ELSE 'apply_exact_active_canonical_matches_and_hold_only_unresolved_rows' END);
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,
    quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_revision,CASE WHEN v_tune THEN jsonb_build_object('workbook_sha256',v_parent,'partition_sha256',v_source_hash) ELSE '{}'::jsonb END,v_batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'preview',v_source_count,v_accepted_count,v_quarantine_count,cardinality(v_matched_stocks),
    cardinality(v_unmatched_stocks),cardinality(v_ambiguous_stocks),v_insert_count,0,v_unchanged_count,v_conflict_count,v_response,v_actor,v_actor_label);
  FOR v_item IN SELECT value AS row_value FROM jsonb_array_elements(v_outcomes) LOOP v_row:=v_item.row_value;v_fields:=public.pdc_tune_source_fields_v5(v_row);
    INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,backend_record_id,semantic_hash,
      normalized_payload,raw_row,decision,reason,vehicle_id)
    VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',(v_row->>'source_order')::integer,v_row->>'stock_number',v_row->>'repair_order_number',
      CASE WHEN v_row->>'original_line_number' IS NULL THEN NULL ELSE (v_row->>'original_line_number')::integer END,
      CASE WHEN v_row->>'backend_record_id' IS NULL THEN NULL ELSE (v_row->>'backend_record_id')::uuid END,v_row->>'semantic_hash',v_row->'normalized_payload',
      coalesce(v_row->'raw_row','{}'::jsonb),v_row->>'decision',v_row->>'reason',CASE WHEN v_row->>'vehicle_id' IS NULL THEN NULL ELSE (v_row->>'vehicle_id')::uuid END);
  END LOOP;
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,CASE WHEN (v_response->>'apply_allowed')::boolean THEN 'preview' ELSE 'blocked' END,v_response,v_actor,v_actor_label);
  RETURN v_response;
END
$function$;
DO $$
BEGIN
 IF public.pdc_parts_flags_status_20260911(0,1,1)->>'colour'<>'orange'
 OR public.pdc_parts_flags_status_20260911(1,1,1)->>'colour'<>'orange'
 OR public.pdc_parts_flags_status_20260911(1,1,0)->>'colour'<>'orange'
 OR public.pdc_parts_flags_status_20260911(0,1,0)->>'colour'<>'red'
 OR public.pdc_parts_flags_status_20260911(1,0,0)->>'colour'<>'green'
 OR public.pdc_parts_flags_status_20260911(0,0,0)->>'colour'<>'grey'
 OR public.pdc_parts_flags_status_20260911(1,0,1)->>'colour'<>'review'
 OR public.pdc_parts_flags_status_20260911(NULL,1,1)->>'colour'<>'review'
 OR public.pdc_numeric_parts_flag_20260911('"All"') IS NOT NULL
 OR public.pdc_numeric_parts_flag_20260911('""') IS NOT NULL
 OR public.pdc_numeric_parts_flag_20260911('true') IS NOT NULL
 OR public.pdc_numeric_parts_flag_20260911('0') IS DISTINCT FROM 0
 OR public.pdc_numeric_parts_flag_20260911('"1"') IS DISTINCT FROM 1
 THEN RAISE EXCEPTION 'parts rule acceptance failed'; END IF;
 PERFORM public.pdc_parts_flags_vehicle_20260911(id) FROM public.vehicles WHERE deleted_at IS NULL;
END $$;


