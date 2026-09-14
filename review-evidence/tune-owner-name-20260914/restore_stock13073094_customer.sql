-- STAGING ONLY. Execute in one transaction after the Owner Name alias migration.
-- Restores only the customer from retained report evidence. No import is replayed.
-- The immutable report rows, Tune evidence, and current evidence pointer are retained.
DO $repair$
DECLARE
 vid uuid; eid uuid; bid uuid; pid uuid; original_receipt_id uuid;
 expected_source constant text:='dd83770615a317eefacfbf5f9003d75c605699a8a4cf9985976cf8eadc60a94a';
 expected_workbook constant text:='3224e78b0944ea376f78992400a174fa3a6b19db52e252371523348d8bda379c';
 repair_code constant text:='tune_owner_name_customer_recovered_20260914';
 v public.vehicles%rowtype;
 e public.pdc_tune_intake_evidence_v5%rowtype;
 old_vehicle jsonb; new_vehicle jsonb; original_evidence jsonb; original_rows jsonb;
 row_ids jsonb; owners text[]; row_count integer; customer text;
 rid uuid; payload jsonb; receipt public.pdc_pilbara_service_import_receipts%rowtype;
 state_before jsonb:='{}'; state_after jsonb:='{}'; table_name text; table_state jsonb;
 protected_tables constant text[]:=ARRAY[
  'pdc_pilbara_service_operations','pdc_tune_operation_change_reviews',
  'workshop_bookings','workshop_booking_history',
  'pdc_sublet_bookings','pdc_sublet_booking_instances',
  'vehicle_movements','vehicle_parts_updates',
  'pdc_qc_operation_completions_379','pdc_qc_operation_rejections_381'];
BEGIN
 IF current_database()<>'postgres' OR current_user<>'postgres' THEN
  RAISE EXCEPTION 'management_database_role_required';
 END IF;
 SELECT * INTO STRICT v FROM public.vehicles WHERE stock_number_normalized='13073094'
  AND job_card_number='J139125725' AND lifecycle_state::text='active' AND deleted_at IS NULL FOR UPDATE;
 vid:=v.id;
 IF v.stock_number IS DISTINCT FROM '13073094' OR v.stock_number_normalized IS DISTINCT FROM '13073094'
  OR v.job_card_number IS DISTINCT FROM 'J139125725' OR v.source_system IS DISTINCT FROM 'tune_pmg'
  OR v.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'vehicle_identity_changed'; END IF;
 SELECT c.evidence_id INTO STRICT eid FROM public.pdc_tune_intake_current_v5 c WHERE c.vehicle_id=vid FOR UPDATE;
 SELECT * INTO STRICT e FROM public.pdc_tune_intake_evidence_v5 WHERE evidence_id=eid;
 bid:=e.batch_id;
 IF e.vehicle_id<>vid OR e.source_hash<>expected_source
  OR e.workbook_sha256<>expected_workbook OR e.customer_name IS NOT NULL THEN
  RAISE EXCEPTION 'retained_tune_evidence_mismatch'; END IF;
 SELECT * INTO receipt FROM public.pdc_pilbara_service_import_receipts r
  WHERE r.batch_id=bid AND r.receipt_kind='replay' AND r.outcome->>'code'=repair_code
   AND r.outcome->>'vehicle_id'=vid::text;
 IF FOUND THEN
  IF v.customer_name IS DISTINCT FROM receipt.outcome->>'customer_name'
   OR v.source_payload->>'tune_customer_repair_receipt_id' IS DISTINCT FROM receipt.receipt_id::text THEN
   RAISE EXCEPTION 'prior_repair_no_longer_matches_vehicle';
  END IF;
  RAISE NOTICE 'customer_repair_already_applied'; RETURN;
 END IF;
 IF nullif(btrim(v.customer_name),'') IS NOT NULL THEN RAISE EXCEPTION 'customer_already_populated'; END IF;
 IF EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.source_system='microsoft_navision'
  AND n.is_current AND n.record_status='current'
  AND public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch',n.normalized_data->>'stock'))='13073094')
  THEN RAISE EXCEPTION 'navision_authority_now_exists'; END IF;
 SELECT r.receipt_id INTO STRICT original_receipt_id FROM public.pdc_pilbara_service_import_batches b
  JOIN public.pdc_pilbara_service_import_receipts r ON r.batch_id=b.batch_id
  WHERE b.batch_id=bid AND b.batch_kind='apply' AND b.contract_revision='pmg_stock_v5'
   AND b.source_hash=expected_source AND b.source_link->>'workbook_sha256'=expected_workbook
   AND r.receipt_kind='apply' AND r.source_hash=expected_source AND r.outcome->>'ok'='true';
 SELECT b.batch_id INTO STRICT pid FROM public.pdc_pilbara_service_import_batches b WHERE
   b.batch_kind='preview' AND b.contract_revision='pmg_stock_v5'
   AND b.source_hash=expected_source AND b.source_link->>'workbook_sha256'=expected_workbook;
 SELECT count(*),array_agg(DISTINCT public.pdc_tune_source_fields_v5(jsonb_build_object('raw_row',r.raw_row))->>'customer_name'),
  jsonb_agg(r.evidence_id ORDER BY r.source_order),jsonb_agg(to_jsonb(r) ORDER BY r.source_order)
 INTO row_count,owners,row_ids,original_rows
 FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=pid AND r.stock_number='13073094'
  AND r.repair_order_number='J139125725' AND r.decision IN('insert','unchanged');
 IF row_count<>18 OR cardinality(owners)<>1 OR owners[1] IS DISTINCT FROM 'HERTZ AUSTRALIA PTY LTD **'
  OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r
   WHERE r.batch_id=pid AND r.stock_number='13073094' AND r.decision IN('insert','unchanged')
    AND (r.repair_order_number IS DISTINCT FROM 'J139125725'
     OR r.raw_row->>'Stock #' IS DISTINCT FROM '13073094'
     OR r.raw_row->>'R/O #' IS DISTINCT FROM 'J139125725'
     OR r.raw_row->>'Owner Name' IS DISTINCT FROM owners[1]
     OR r.raw_row->>'parent_attachment_sha256' IS DISTINCT FROM expected_workbook))
 THEN RAISE EXCEPTION 'retained_owner_rows_mismatch'; END IF;
 customer:=owners[1]; old_vehicle:=to_jsonb(v); original_evidence:=to_jsonb(e);
 FOREACH table_name IN ARRAY protected_tables LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM public.%I t WHERE vehicle_id=$1',table_name)
   INTO table_state USING vid;
  state_before:=state_before||jsonb_build_object(table_name,table_state);
 END LOOP;
 rid:=gen_random_uuid();
 payload:=coalesce(v.source_payload,'{}')||jsonb_build_object('tune_customer_repair_receipt_id',rid);
 INSERT INTO public.pdc_pilbara_service_import_receipts(receipt_id,batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
 VALUES(rid,bid,'pilbara_service_open_jobcards_v1',expected_source,'replay',jsonb_build_object(
  'ok',true,'code',repair_code,'vehicle_id',vid,'stock_number',v.stock_number,'job_card_number',v.job_card_number,
  'customer_name',customer,'previous_customer_name',v.customer_name,'original_tune_evidence_id',eid,
  'original_apply_receipt_id',original_receipt_id,'preview_batch_id',pid,
  'source_row_evidence_ids',row_ids,'source_column','Owner Name','workbook_sha256',expected_workbook,
  'repair_scope','canonical_customer_only','operations_replayed',false,'immutable_evidence_preserved',true),
  auth.uid(),'codex_supabase_management:'||current_user||':tune_owner_name_recovery_20260914');
 UPDATE public.vehicles SET customer_name=customer,source_payload=payload,
  version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE id=vid;
 SELECT to_jsonb(x) INTO new_vehicle FROM public.vehicles x WHERE id=vid;
 IF (old_vehicle-ARRAY['customer_name','source_payload','version','updated_by','updated_at'])
  IS DISTINCT FROM (new_vehicle-ARRAY['customer_name','source_payload','version','updated_by','updated_at'])
  OR new_vehicle->>'customer_name' IS DISTINCT FROM customer OR new_vehicle->'source_payload' IS DISTINCT FROM payload
  OR (new_vehicle->>'version')::bigint<>v.version+1
 THEN RAISE EXCEPTION 'customer_repair_changed_other_vehicle_fields'; END IF;
 FOREACH table_name IN ARRAY protected_tables LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM public.%I t WHERE vehicle_id=$1',table_name)
   INTO table_state USING vid;
  state_after:=state_after||jsonb_build_object(table_name,table_state);
 END LOOP;
 IF state_before IS DISTINCT FROM state_after THEN RAISE EXCEPTION 'customer_repair_changed_operational_state'; END IF;
 IF original_evidence IS DISTINCT FROM (SELECT to_jsonb(x) FROM public.pdc_tune_intake_evidence_v5 x WHERE evidence_id=eid)
  OR original_rows IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.source_order)
   FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=pid AND r.stock_number='13073094'
    AND r.repair_order_number='J139125725' AND r.decision IN('insert','unchanged'))
  OR NOT EXISTS(SELECT 1 FROM public.pdc_tune_intake_current_v5 WHERE vehicle_id=vid AND evidence_id=eid)
 THEN RAISE EXCEPTION 'customer_repair_changed_immutable_evidence'; END IF;
 IF public.pdc_tune_vehicle_details_v5(vid)->>'customer_name' IS DISTINCT FROM customer THEN
  RAISE EXCEPTION 'customer_projection_not_restored'; END IF;
END $repair$;
