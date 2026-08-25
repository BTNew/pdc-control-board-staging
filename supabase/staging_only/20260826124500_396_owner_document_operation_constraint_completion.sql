-- STAGING ONLY: complete owner-document operation evidence constraints.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-owner-document-operation-constraints',0));
DO $pre$
DECLARE v_head text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR v_head IS DISTINCT FROM '20260826123000'
   OR (SELECT count(*) FROM public.pdc_owner_supplied_document_receipts_396)<>0
   OR (SELECT count(*) FROM public.vehicles WHERE stock_number='13080553' AND deleted_at IS NULL)<>0
   OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
   RAISE EXCEPTION 'PDC_OWNER_DOCUMENT_OPERATION_CONSTRAINT_GATE' USING errcode='55000';
 END IF;
END $pre$;
ALTER TABLE public.pdc_authenticated_email_operation_lines
 DROP CONSTRAINT pdc_authenticated_email_operation_lines_estimated_hours_source_,
 ADD CONSTRAINT pdc_authenticated_email_operation_lines_estimated_hours_source_
 CHECK(
   (estimated_hours IS NULL AND estimated_hours_source IS NULL)
   OR (estimated_hours IS NULL AND estimated_hours_source='owner_supplied_document_unknown')
   OR (estimated_hours IS NOT NULL AND estimated_hours_source IS NULL)
   OR (estimated_hours IS NOT NULL AND estimated_hours_source IN('job_card','ai_estimate','owner_supplied_document'))
 ),
 DROP CONSTRAINT pdc_authenticated_email_operation_lines_work_key_check,
 ADD CONSTRAINT pdc_authenticated_email_operation_lines_work_key_check
 CHECK(work_key IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS','sublet','owner_supplied_document'));
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_authenticated_email_operation_lines WHERE estimated_hours_source IN('owner_supplied_document','owner_supplied_document_unknown') OR work_key='owner_supplied_document')<>0
   OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
   RAISE EXCEPTION 'PDC_OWNER_DOCUMENT_OPERATION_CONSTRAINT_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826124500','396_owner_document_operation_constraint_completion',ARRAY[
 'Owner-supplied explicit hours, including genuine zero, retain owner_supplied_document provenance',
 'Owner-supplied unknown hours remain NULL with owner_supplied_document_unknown provenance and review receipt',
 'Unmapped descriptions remain evidence-only owner_supplied_document operations and do not create invented work routing',
 'Existing email operation sources and work keys remain accepted unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
