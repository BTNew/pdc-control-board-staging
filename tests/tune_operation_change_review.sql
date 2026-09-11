DO $$
DECLARE o public.pdc_pilbara_service_operations%rowtype; p jsonb;c jsonb;
BEGIN
 IF public.pdc_tune_operation_source_signature_20260912('{"operation_description":"Fit light", "source_estimated_hours":1,"department":"139"}')
 IS DISTINCT FROM public.pdc_tune_operation_source_signature_20260912('{"operation_description":" Fit  light ", "source_estimated_hours":1.0,"department":"139","raw_row":{"Parts Attached":1}}') THEN RAISE EXCEPTION 'unchanged_signature_failed'; END IF;
 SELECT op.* INTO o FROM public.pdc_pilbara_service_operations op JOIN public.vehicles v ON v.id=op.vehicle_id WHERE v.visible_on_board AND v.deleted_at IS NULL ORDER BY op.operation_id LIMIT 1;
 IF o.operation_id IS NOT NULL THEN
  p:=to_jsonb(o)||jsonb_build_object('raw_row',(SELECT raw_row FROM public.pdc_pilbara_service_import_rows WHERE evidence_id=o.raw_evidence_id));
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p);
  IF (c->>'needs_review')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'unchanged_line_failed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p||jsonb_build_object('source_estimated_hours',o.source_estimated_hours+1));
  IF (c->>'needs_review')::boolean IS DISTINCT FROM true OR c->>'change_kind'<>'modified' THEN RAISE EXCEPTION 'changed_hours_failed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p||jsonb_build_object('operation_description','Synthetic changed description'));
  IF (c->>'needs_review')::boolean IS DISTINCT FROM true OR c->>'change_kind'<>'modified' THEN RAISE EXCEPTION 'changed_description_failed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p||jsonb_build_object('original_line_number',2147483000));
  IF (c->>'needs_review')::boolean IS DISTINCT FROM true OR c->>'change_kind'<>'added' THEN RAISE EXCEPTION 'added_line_failed'; END IF;
  c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,p||jsonb_build_object('stock_number','MISMATCH'));
  IF c->>'conflict' IS DISTINCT FROM 'stock_identity_changed' THEN RAISE EXCEPTION 'stock_guard_failed'; END IF;
 END IF;
 IF public.approve_pdc_tune_operation_change(NULL,NULL,NULL,NULL,NULL)->>'code'<>'not_authorized' THEN RAISE EXCEPTION 'approval_auth_guard_failed'; END IF;
 IF public.list_pdc_tune_operation_changes()->>'code'<>'not_authorized' THEN RAISE EXCEPTION 'read_auth_guard_failed'; END IF;
END $$;
