BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $$
DECLARE o public.pdc_pilbara_service_operations%rowtype; r public.pdc_pilbara_service_import_rows%rowtype;
 b public.pdc_pilbara_service_import_batches%rowtype; original jsonb; payload jsonb; c jsonb; saved jsonb;
 first_id uuid; second_id uuid; base_row jsonb; before_ops jsonb; before_bookings jsonb; before_vehicle jsonb;
 n integer; test_hash text; test_batch uuid; test_apply uuid; parts jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT op.* INTO STRICT o FROM public.pdc_pilbara_service_operations op JOIN public.vehicles v ON v.id=op.vehicle_id
 WHERE v.visible_on_board AND v.deleted_at IS NULL AND v.lifecycle_state='active' ORDER BY op.operation_id LIMIT 1;
 SELECT * INTO STRICT r FROM public.pdc_pilbara_service_import_rows WHERE evidence_id=o.raw_evidence_id;
 SELECT * INTO STRICT b FROM public.pdc_pilbara_service_import_batches WHERE batch_id=r.batch_id;
 original:=to_jsonb(o)||jsonb_build_object('raw_row',r.raw_row);
 SELECT jsonb_agg(to_jsonb(x) ORDER BY operation_id) INTO before_ops FROM public.pdc_pilbara_service_operations x WHERE vehicle_id=o.vehicle_id;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') INTO before_bookings FROM public.workshop_bookings x WHERE vehicle_id=o.vehicle_id;
 SELECT to_jsonb(v) INTO before_vehicle FROM public.vehicles v WHERE id=o.vehicle_id;
 base_row:=to_jsonb(r);
 FOR n IN 1..5 LOOP
   test_batch:=gen_random_uuid();test_hash:=encode(extensions.digest(test_batch::text,'sha256'),'hex');
   b.batch_id:=test_batch;b.source_hash:=test_hash;b.request_hash:=test_hash;b.idempotency_key:='rollback-test:'||test_batch;b.created_actor:='Synthetic rollback-only operation review test';b.created_at:=clock_timestamp();
   INSERT INTO public.pdc_pilbara_service_import_batches SELECT b.*;
   test_apply:=gen_random_uuid();b.batch_id:=test_apply;b.batch_kind:='apply';b.idempotency_key:='rollback-apply:'||test_apply;
   INSERT INTO public.pdc_pilbara_service_import_batches SELECT b.*;
   b.batch_kind:='preview';
   payload:=original||jsonb_build_object('operation_description',o.operation_description||CASE WHEN n<3 THEN ' test revision A' ELSE ' test revision B' END);
   IF n=5 THEN payload:=original; END IF;
   r:=jsonb_populate_record(NULL::public.pdc_pilbara_service_import_rows,base_row);
   r.evidence_id:=gen_random_uuid();r.batch_id:=test_batch;r.vehicle_id:=o.vehicle_id;r.normalized_payload:=payload-'raw_row';
   r.raw_row:=r.raw_row||jsonb_build_object('Parts Attached',1,'Parts on Backorder',CASE WHEN n=4 THEN 0 ELSE 1 END,'Backorder with PO (1=Yes, 0=No)',CASE WHEN n=4 THEN 0 ELSE 1 END);
   r.reason:=CASE WHEN n=5 THEN 'accepted_operation_version' ELSE 'operation_update_review' END;
   r.decision:=CASE WHEN n=5 THEN 'unchanged' ELSE 'quarantine' END;
   INSERT INTO public.pdc_pilbara_service_import_rows SELECT r.*;
   PERFORM public.pdc_capture_tune_operation_changes_20260912(test_batch,test_apply);
   IF n<5 THEN
     parts:=public.pdc_parts_flags_vehicle_20260911(o.vehicle_id)->'operations'->o.operation_id::text;
     IF (parts->>'last_successful_import_at')::timestamptz IS DISTINCT FROM b.created_at THEN RAISE EXCEPTION 'pending_parts_metadata_failed: %',parts;END IF;
   END IF;
   IF n=1 THEN
     SELECT change_id INTO STRICT first_id FROM public.pdc_tune_operation_change_reviews WHERE evidence_id=r.evidence_id;
     saved:=public.pdc_tune_operation_change_row_20260912(first_id);
     IF saved->>'stock_number' IS DISTINCT FROM o.stock_number OR saved->>'change_kind'<>'modified' OR saved->'proposed'->>'operation_description' IS DISTINCT FROM payload->>'operation_description' THEN RAISE EXCEPTION 'review_readback_failed';END IF;
   ELSIF n=2 THEN
     IF (SELECT count(*) FROM public.pdc_tune_operation_change_reviews WHERE change_id=first_id AND status='pending')<>1 OR EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews WHERE evidence_id=r.evidence_id) THEN RAISE EXCEPTION 'repeat_deduplication_failed';END IF;
   ELSIF n=3 THEN
     IF (SELECT status FROM public.pdc_tune_operation_change_reviews WHERE change_id=first_id)<>'superseded' THEN RAISE EXCEPTION 'supersession_failed';END IF;
     SELECT change_id INTO STRICT second_id FROM public.pdc_tune_operation_change_reviews WHERE evidence_id=r.evidence_id;
     IF public.pdc_tune_operation_change_row_20260912(first_id)->>'snapshot_hash'=saved->>'snapshot_hash' THEN RAISE EXCEPTION 'stale_snapshot_failed';END IF;
   ELSIF n=4 THEN
     IF EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews WHERE evidence_id=r.evidence_id) THEN RAISE EXCEPTION 'second_repeat_failed';END IF;
   ELSIF n=5 THEN
     IF (SELECT status FROM public.pdc_tune_operation_change_reviews WHERE change_id=second_id)<>'superseded' THEN RAISE EXCEPTION 'reverted_source_failed';END IF;
   END IF;
 END LOOP;
 -- Baseline comparison only: a transaction-only review fixture, never an operational approval.
 UPDATE public.pdc_tune_operation_change_reviews SET status='approved',approved_at=clock_timestamp() WHERE change_id=second_id;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(o.vehicle_id)) line
 WHERE line->>'line_identity'='source:'||o.operation_id AND line->>'description'=o.operation_description||' test revision B')
 THEN RAISE EXCEPTION 'approved_description_projection_failed';END IF;
 c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,original||jsonb_build_object('operation_description',o.operation_description||' test revision B'));
 IF (c->>'needs_review')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'accepted_baseline_failed';END IF;
 c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,original||jsonb_build_object('operation_description',o.operation_description||' test revision C'));
 IF (c->>'needs_review')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'subsequent_change_failed';END IF;
 c:=public.pdc_tune_operation_change_candidate_20260912(o.vehicle_id,original||jsonb_build_object('original_line_number',2147483000));
 IF c->>'change_kind'<>'added' OR (c->>'needs_review')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'new_line_failed';END IF;
 IF before_ops IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY operation_id) FROM public.pdc_pilbara_service_operations x WHERE vehicle_id=o.vehicle_id)
 OR before_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM public.workshop_bookings x WHERE vehicle_id=o.vehicle_id)
 OR before_vehicle IS DISTINCT FROM (SELECT to_jsonb(v) FROM public.vehicles v WHERE id=o.vehicle_id)
 THEN RAISE EXCEPTION 'existing_work_changed';END IF;
END $$;
ROLLBACK;
SELECT 'capture, deduplication, supersession, stale snapshot, reversion, accepted baseline, added line, source/bookings/vehicle preservation: passed; all fixtures rolled back' AS result;
