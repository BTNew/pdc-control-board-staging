-- STAGING only. Project retained Pilbara Job Card operations into the existing QC contract.
-- No vehicle, completion, photo, receipt, source evidence, permission or scheduler is changed.
DO $migration$
DECLARE d text; patched text; old_block text; start_at integer; end_at integer;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
    OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:qc-pilbara-sources:20260909',0));
 IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN public.pdc_authenticated_email_operation_lines e ON e.operation_line_id=o.operation_id AND e.vehicle_id=o.vehicle_id) THEN
  RAISE EXCEPTION 'QC operation source identity collision requires review';
 END IF;
 SELECT pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure) INTO d;
 IF md5(d)<>'30219e493caace45f5c8473fa64c3f76' THEN RAISE EXCEPTION 'QC projection changed since review'; END IF;
 patched:=replace(d,
 '), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines)',
 $sources$), pilbara_lines AS(
  SELECT 'source:'||o.operation_id::text,'authenticated',o.operation_id,
   'PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
   o.operation_description,o.repair_order_number,
   CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE o.effective_estimated_hours END,
   CASE WHEN coalesce(a.stage_code,h.category) IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
        THEN coalesce(a.stage_code,h.category) ELSE 'UNALLOCATED_MAPPING_REVIEW' END,
   coalesce(a.active,true)
  FROM public.pdc_pilbara_service_operations o
  JOIN public.vehicles v ON v.id=o.vehicle_id AND v.stock_number=o.stock_number
  LEFT JOIN public.pdc_pilbara_service_classification_current cc USING(operation_id)
  LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_id::text
  WHERE o.vehicle_id=p_vehicle_id
 ), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines UNION ALL SELECT * FROM pilbara_lines)$sources$);
 patched:=replace(patched,
  '''rework_booking_id'',case when r.active then r.rejection_id else null end)',
  $provenance$'rework_booking_id',case when r.active then r.rejection_id else null end)
  || CASE WHEN ps.operation_id IS NOT NULL THEN jsonb_build_object('source_contract','pilbara_service_open_jobcards_v1','source_evidence_id',ps.raw_evidence_id) ELSE '{}'::jsonb END$provenance$);
 patched:=replace(patched,' FROM all_lines l',
  E' FROM all_lines l\n LEFT JOIN public.pdc_pilbara_service_operations ps ON ps.vehicle_id=p_vehicle_id AND ps.operation_id=l.source_line_id AND l.source_kind=''authenticated''');
 IF patched=d OR position('UNION ALL SELECT * FROM pilbara_lines' in patched)=0 OR position('source_evidence_id' in patched)=0 THEN RAISE EXCEPTION 'QC projection patch mismatch'; END IF;
 EXECUTE patched;

 -- The checkbox writer and rejection writer resolve the same canonical line
 -- projection that the mobile screen and finalization gate read. Existing
 -- identity, role, active-QC, version, idempotency and audit checks remain intact.
 SELECT pg_get_functiondef('public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure) INTO d;
 IF md5(d)<>'68fc0c900f580ce85baffa36ae0e340f' THEN RAISE EXCEPTION 'QC checkbox writer changed since review'; END IF;
 start_at:=position(' IF v_line LIKE ''source:%'' THEN' in d);
 end_at:=position(' IF public.pdc_qc_operation_line_is_deferred_pit_10700' in d);
 IF start_at<1 OR end_at<=start_at THEN RAISE EXCEPTION 'QC writer source block not found'; END IF;
 old_block:=substring(d FROM start_at FOR end_at-start_at);
 patched:=replace(d,old_block,$resolve$
 IF (SELECT count(*) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l WHERE l->>'line_identity'=v_line)<>1 THEN
  RAISE EXCEPTION 'PDC_379_LINE_UNKNOWN_OR_AMBIGUOUS' USING errcode='22023';
 END IF;
 SELECT l->>'source_kind',(l->>'source_line_id')::uuid,
        nullif(l->>'stage_code','UNALLOCATED_MAPPING_REVIEW'),(l->>'active')::boolean,(l->>'estimated_hours')::numeric
 INTO v_source_kind,v_source_id,v_stage,v_active,v_hours
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 WHERE l->>'line_identity'=v_line;
$resolve$);
 IF patched=d OR position('PDC_379_LINE_UNKNOWN_OR_AMBIGUOUS' in patched)=0 THEN RAISE EXCEPTION 'QC writer patch mismatch'; END IF;
 EXECUTE patched;

 SELECT pg_get_functiondef('public.reject_pdc_qc_operation_381(uuid,integer,text,integer,uuid,text)'::regprocedure) INTO d;
 IF md5(d)<>'db4d837b27e79037aedd3cfdd7444aa1' THEN RAISE EXCEPTION 'QC rejection writer changed since review'; END IF;
 start_at:=position(' IF v_line LIKE ''source:%'' THEN' in d);
 end_at:=position(' IF v_stage IS NULL OR NOT coalesce(v_active,false)' in d);
 IF start_at<1 OR end_at<=start_at THEN RAISE EXCEPTION 'QC rejection source block not found'; END IF;
 old_block:=substring(d FROM start_at FOR end_at-start_at);
 patched:=replace(d,old_block,$resolve$
 IF (SELECT count(*) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l WHERE l->>'line_identity'=v_line)<>1 THEN
  RAISE EXCEPTION 'PDC_381_LINE_UNKNOWN_OR_AMBIGUOUS' USING errcode='22023';
 END IF;
 SELECT l->>'source_kind',(l->>'source_line_id')::uuid,
        nullif(l->>'stage_code','UNALLOCATED_MAPPING_REVIEW'),(l->>'active')::boolean,l->>'operation_no',l->>'description'
 INTO v_source_kind,v_source_id,v_stage,v_active,v_operation_no,v_description
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 WHERE l->>'line_identity'=v_line;
$resolve$);
 IF patched=d OR position('PDC_381_LINE_UNKNOWN_OR_AMBIGUOUS' in patched)=0 THEN RAISE EXCEPTION 'QC rejection patch mismatch'; END IF;
 EXECUTE patched;
END $migration$;
