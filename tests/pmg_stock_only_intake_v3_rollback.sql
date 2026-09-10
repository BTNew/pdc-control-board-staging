-- Run against the specified STAGING project only. All operational changes roll back.
-- Supply the original workbook's 105-row test JSON via psql variable unidentified_json.
BEGIN;
CREATE TEMP TABLE pmg_unbound_fixture AS SELECT :'unidentified_json'::jsonb rows;
CREATE TEMP TABLE pmg_test_results(name text,result jsonb);
DO $test$
DECLARE actor record; rows jsonb; pre jsonb; applied jsonb; replay jsonb; vid uuid; qty integer; hrs numeric; n integer;
BEGIN
 SELECT i.auth_user_id,i.normalized_email INTO STRICT actor FROM public.pdc_email_ai_successor_runtime_identities i
 JOIN public.pdc_user_roles r ON r.auth_user_id=i.auth_user_id
 WHERE i.active AND i.revoked_at IS NULL AND i.environment='staging' AND r.active AND r.role='viewer' AND r.account_status='approved'
 AND i.identity_purpose='pdc_email_ai_transaction_successor';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.normalized_email,'role','authenticated')::text,true);
 SELECT jsonb_agg(normalized_payload||jsonb_build_object('raw_row',raw_row) ORDER BY source_order) INTO rows
 FROM public.pdc_pilbara_service_import_rows WHERE batch_id='cc508308-ad1e-453f-a431-595bead4de2b';
 pre:=public.pdc_pilbara_service_preview_v1(rows,'056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814','pmg-v3-rollback-preview-20260910');
 IF (pre->>'apply_allowed')::boolean IS NOT TRUE OR (pre->>'accepted_lines')::integer<>1395 THEN RAISE EXCEPTION 'preview failed: %',pre; END IF;
 INSERT INTO pmg_test_results VALUES('preview',pre);
 replay:=public.pdc_pilbara_service_preview_v1(rows,'056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814','pmg-v3-rollback-preview-20260910');
 IF replay->>'preview_batch_id'<>pre->>'preview_batch_id' OR replay->>'replay'<>'true' THEN RAISE EXCEPTION 'preview replay failed'; END IF;
 applied:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,'056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814','pmg-v3-rollback-apply-20260910');
 IF applied->>'ok'<>'true' THEN RAISE EXCEPTION 'apply failed: %',applied; END IF;
 INSERT INTO pmg_test_results VALUES('apply',applied);
 SELECT count(DISTINCT o.vehicle_id),sum(o.source_estimated_hours) INTO qty,hrs FROM public.pdc_pilbara_service_operations o JOIN public.pdc_pilbara_service_operation_history h USING(operation_id) WHERE h.batch_id=(applied->>'apply_batch_id')::uuid;
 IF qty<>121 OR hrs<>1120.68 THEN RAISE EXCEPTION 'counts mismatch % %',qty,hrs; END IF;
 FOR vid IN SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operations o JOIN public.pdc_pilbara_service_operation_history h USING(operation_id) WHERE h.batch_id=(applied->>'apply_batch_id')::uuid LOOP
   IF NOT EXISTS(SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews r ON r.vehicle_id=v.id WHERE v.id=vid AND v.visible_on_board=false AND r.status='pending' AND v.current_location='Yard Hold' AND v.vin IS NULL) THEN RAISE EXCEPTION 'vehicle state failed %',vid; END IF;
   SELECT count(*) INTO n FROM public.pdc_pilbara_service_operations WHERE vehicle_id=vid;
   IF jsonb_array_length(public.pdc_new_vehicle_review_row(vid)->'operations')<>n THEN RAISE EXCEPTION 'UI readback count failed %',vid; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_new_vehicle_review_row(vid)->'operations') l
    JOIN public.pdc_pilbara_service_operations o ON l->>'source_line_id'=o.operation_id::text
    WHERE l->>'stage_code' IS DISTINCT FROM CASE WHEN o.department='138' THEN 'BUS_4X4' WHEN o.proposed_station='REVIEW' THEN 'UNALLOCATED_MAPPING_REVIEW' ELSE o.proposed_station END
    OR (l->>'estimated_hours')::numeric IS DISTINCT FROM o.source_estimated_hours OR l->>'completed'<>'false')
    THEN RAISE EXCEPTION 'per-operation station/hours/completion mismatch'; END IF;
 END LOOP;
 replay:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,'056493f56d49106162120b3b9c7aa63ab82984db9846bcb37de29c69814','pmg-v3-invalid-hash-20260910');
 IF replay->>'ok'='true' THEN RAISE EXCEPTION 'invalid hash accepted'; END IF;
 replay:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,'056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814','pmg-v3-rollback-apply-20260910');
 IF replay->>'replay'<>'true' OR replay->>'apply_batch_id'<>applied->>'apply_batch_id' THEN RAISE EXCEPTION 'apply replay failed'; END IF;
 INSERT INTO pmg_test_results VALUES('readback',jsonb_build_object('vehicles',qty,'hours',hrs,'replay',true,'all_operation_stations_hours_verified',true));
END $test$;
SELECT * FROM pmg_test_results;
DO $test$
DECLARE rows jsonb; pre jsonb; app jsonb; r jsonb; n integer; before_vehicles integer; h text:=repeat('a',64);
BEGIN
 SELECT count(*) INTO before_vehicles FROM public.vehicles;
 SELECT f.rows INTO rows FROM pmg_unbound_fixture f;
 pre:=public.pdc_pilbara_service_preview_v1(rows,h,'pmg-unbound-rollback-preview');
 IF pre->>'apply_allowed'<>'true' THEN RAISE EXCEPTION 'unbound preview %',pre; END IF;
 app:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,h,'pmg-unbound-rollback-apply');
 IF app->>'ok'<>'true' THEN RAISE EXCEPTION 'unbound apply %',app; END IF;
 IF (SELECT count(*) FROM public.vehicles)<>before_vehicles THEN RAISE EXCEPTION 'fabricated vehicle'; END IF;
 IF (SELECT count(*) FROM public.pdc_unidentified_tune_review)<>105 OR (SELECT sum(source_estimated_hours) FROM public.pdc_unidentified_tune_review)<>112.56 THEN RAISE EXCEPTION 'unbound reconciliation'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_unidentified_tune_review WHERE department='138' AND proposed_station<>'BUS_4X4') THEN RAISE EXCEPTION 'unbound department routing'; END IF;
 r:=public.pdc_pmg_intake_readback_v3((app->>'apply_batch_id')::uuid);
 IF r->>'unidentified_row_count'<>'105' OR r->>'vehicle_count'<>'0' THEN RAISE EXCEPTION 'unbound readback %',r; END IF;
 r:=public.list_pdc_unidentified_tune_reviews(0,50);
 IF r->'data'->>'total'<>'10' THEN RAISE EXCEPTION 'unbound UI readback %',r; END IF;
 r:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,h,'pmg-unbound-rollback-apply');
 IF r->>'replay'<>'true' OR (SELECT count(*) FROM public.pdc_unidentified_tune_review)<>105 THEN RAISE EXCEPTION 'unbound replay'; END IF;
 rows:=jsonb_set(rows,'{0,source_estimated_hours}','9'::jsonb);
 r:=public.pdc_pilbara_service_preview_v1(rows,repeat('b',64),'pmg-unbound-change-preview');
 IF r->>'apply_allowed'='true' THEN RAISE EXCEPTION 'changed unbound accepted'; END IF;
 INSERT INTO pmg_test_results VALUES('unidentified',jsonb_build_object('groups',10,'rows',105,'hours',112.56,'vehicles_created',0,'replay',true));
END $test$;
SELECT * FROM pmg_test_results;
DO $test$
DECLARE rowj jsonb; rows jsonb; p jsonb; a jsonb; p2 jsonb; a2 jsonb; v uuid; h text; base_bookings bigint; base_completions bigint;
BEGIN
 SELECT count(*) INTO base_bookings FROM public.workshop_bookings;
 SELECT count(*) INTO base_completions FROM public.pdc_qc_operation_completions_379;
 rowj:=jsonb_build_object('department','138','stock_number','U158863','repair_order_number','PMG-REPLAY-TEST','original_line_number',8,
 'operation_description','First   distinct operation','source_estimated_hours',0,'proposed_station','ELECTRICAL','operation_code',NULL,'workbook_sha256',repeat('d',64),'raw_row','{}'::jsonb);
 rows:=jsonb_build_array(rowj,rowj||jsonb_build_object('operation_description','Second distinct operation'),rowj);
 p:=public.pdc_pilbara_service_preview_v1(rows,repeat('c',64),'pmg-v3-same-line-preview');
 IF p->>'accepted_lines'<>'2' OR p->'operations'->>'duplicate_ignored'<>'1' THEN RAISE EXCEPTION 'same line identity failed %',p; END IF;
 a:=public.pdc_pilbara_service_apply_v1((p->>'preview_batch_id')::uuid,repeat('c',64),'pmg-v3-same-line-apply');
 IF a->>'ok'<>'true' THEN RAISE EXCEPTION 'same line apply %',a; END IF;
 SELECT id INTO v FROM public.vehicles WHERE stock_number='U158863' AND deleted_at IS NULL;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_new_vehicle_review_row(v)->'operations') l WHERE l->>'stage_code'<>'BUS_4X4') THEN RAISE EXCEPTION 'department override failed'; END IF;
 rows:=jsonb_build_array(rowj||jsonb_build_object('operation_description','First distinct operation','operation_code','REAL-TUNE-CODE','source_estimated_hours',0.00),rowj||jsonb_build_object('operation_description','Second distinct operation'));
 p2:=public.pdc_pilbara_service_preview_v1(rows,repeat('e',64),'pmg-v3-enrich-preview');
 IF p2->>'accepted_lines'<>'2' OR p2->'operations'->>'unchanged'<>'2' THEN RAISE EXCEPTION 'code enrichment identity %',p2; END IF;
 a2:=public.pdc_pilbara_service_apply_v1((p2->>'preview_batch_id')::uuid,repeat('e',64),'pmg-v3-enrich-apply');
 IF a2->>'ok'<>'true' OR (SELECT count(*) FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v AND repair_order_number='PMG-REPLAY-TEST')<>2 THEN RAISE EXCEPTION 'code enrichment duplicates %',a2; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_new_vehicle_review_row(v)->'operations') l WHERE l->>'operation_code'='REAL-TUNE-CODE') THEN RAISE EXCEPTION 'code enrichment readback'; END IF;
 p2:=public.pdc_pilbara_service_preview_v1(jsonb_build_array(rowj,rowj||jsonb_build_object('department','139')),repeat('f',64),'pmg-v3-dept-conflict-preview');
 IF p2->>'code'<>'conflicting_job_card_identity' THEN RAISE EXCEPTION 'conflicting department allowed %',p2; END IF;
 p2:=public.pdc_pilbara_service_preview_v1(rows,repeat('1',64),'pmg-v3-enrich-preview');
 IF p2->>'code'<>'idempotency_conflict' THEN RAISE EXCEPTION 'different source hash replay accepted %',p2; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 p2:=public.pdc_pilbara_service_preview_v1(rows,repeat('2',64),'pmg-v3-unauthorized-preview');
 IF p2->>'code'<>'not_authorized' THEN RAISE EXCEPTION 'unauthorized preview accepted'; END IF;
 IF (SELECT count(*) FROM public.workshop_bookings)<>base_bookings OR (SELECT count(*) FROM public.pdc_qc_operation_completions_379)<>base_completions THEN RAISE EXCEPTION 'protected work changed'; END IF;
 INSERT INTO pmg_test_results VALUES('edge_cases',jsonb_build_object('same_line_distinct',true,'duplicate_ignored',true,'explicit_zero',true,'department_override',true,'code_enrichment_no_duplicates',true,'unauthorized_rejected',true,'bookings_delta',0,'completions_delta',0));
END $test$;
SELECT * FROM pmg_test_results;
ROLLBACK;
