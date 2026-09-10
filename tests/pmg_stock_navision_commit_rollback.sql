-- STAGING retained-file fixture, run before operational apply; all changes roll back.
BEGIN;
CREATE TEMP TABLE pmg_commit_test_results(name text,result jsonb);
DO $test$
DECLARE actor record; rows jsonb; pre jsonb; applied jsonb; replay jsonb; qty int; hrs numeric;
BEGIN
 SELECT i.auth_user_id,i.normalized_email INTO STRICT actor FROM public.pdc_email_ai_successor_runtime_identities i JOIN public.pdc_user_roles r ON r.auth_user_id=i.auth_user_id WHERE i.active AND i.revoked_at IS NULL AND i.environment='staging' AND r.active AND r.role='viewer' AND r.account_status='approved' AND i.identity_purpose='pdc_email_ai_transaction_successor';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.normalized_email,'role','authenticated')::text,true);
 SELECT jsonb_agg(normalized_payload||jsonb_build_object('raw_row',raw_row) ORDER BY source_order) INTO rows FROM public.pdc_pilbara_service_import_rows WHERE batch_id='562fef2a-c8f2-43bb-a1f1-2e5de21d7620';
 pre:=public.pdc_pilbara_service_preview_v1(rows,'056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814','pmg-v4-commit-rollback-preview');
 IF pre->>'contract_revision'<>'pmg_stock_v4' OR pre->>'apply_allowed'<>'true' OR (pre->>'accepted_lines')::int<>1395 THEN RAISE EXCEPTION 'preview: %',pre; END IF;
 applied:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,'056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814','pmg-v4-commit-rollback-apply');
 IF applied->>'ok'<>'true' THEN RAISE EXCEPTION 'apply: %',applied; END IF;
 IF (SELECT count(*) FROM public.vehicles WHERE deleted_at IS NULL AND NOT visible_on_board AND current_location='Yard Hold')<>121 THEN RAISE EXCEPTION 'hidden state changed'; END IF;
 IF (SELECT count(*) FROM public.pdc_new_vehicle_reviews WHERE status='pending')<>121 THEN RAISE EXCEPTION 'pending count'; END IF;
 IF (SELECT count(*) FROM public.navision_backend_records WHERE canonical_vehicle_id IS NOT NULL AND is_current AND record_status='current')<>78 THEN RAISE EXCEPTION 'Navision link count'; END IF;
 IF (SELECT count(*) FROM public.vehicles WHERE source_system='tune_pmg')<>43 THEN RAISE EXCEPTION 'stock-only count'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings) OR EXISTS(SELECT 1 FROM public.pdc_qc_operation_completions_379 WHERE completed) THEN RAISE EXCEPTION 'operational mutation'; END IF;
 replay:=public.pdc_pilbara_service_apply_v1((pre->>'preview_batch_id')::uuid,'056493f56d491061621737ae20b3b9c7aa63ab82984db9846bcb37de29c69814','pmg-v4-commit-rollback-apply');
 IF replay->>'replay'<>'true' OR replay->>'apply_batch_id'<>applied->>'apply_batch_id' THEN RAISE EXCEPTION 'replay failed'; END IF;
 SELECT count(*),sum(source_estimated_hours) INTO qty,hrs FROM public.pdc_pilbara_service_operations;
 IF qty<>1395 OR hrs<>1120.68 THEN RAISE EXCEPTION 'bound count/hours'; END IF;
 INSERT INTO pmg_commit_test_results VALUES('apply',applied),('parity',public.pdc_navision_vehicle_parity_494(NULL)),('readback',jsonb_build_object('vehicles',121,'pending',121,'linked',78,'stock_only',43,'operations',qty,'hours',hrs,'replay',true));
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT * FROM pmg_commit_test_results;
ROLLBACK;
