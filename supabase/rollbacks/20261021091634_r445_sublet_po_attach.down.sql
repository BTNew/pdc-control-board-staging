-- r445 (F58) undo: removes the sublet PO attach feature. Drops the two storage policies first (from then on nobody but the
-- Storage service can reach the bucket), the r445 functions, the r445 check and 8 pins, then the document and pilot tables.
-- The bucket is deleted only when it is empty. Uploaded PDFs cannot be removed with SQL (Storage protects its tables), so
-- when objects exist the bucket is left in place, private and with no policies, and this script says so: remove them with the
-- Storage API (dashboard or service client) and delete the bucket there. BEFORE running: export
-- public.pdc_sublet_po_documents_445 (and the pilot table) to release_log/r445_sublet_po_attach/ - the rows go with the tables.
-- Revert the PR as well (the Attach PO controls then disappear; the r444 Sublet box is unchanged).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r445 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r445 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r445 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r445 undo: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r445' AND md5(p.prosrc)=e.prosrc_md5)<>8 THEN RAISE EXCEPTION 'r445 undo: r445 functions are not the pinned r445 versions; not undoing over unknown changes'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sublet_po_attach_445' AND added_in='r445') THEN RAISE EXCEPTION 'r445 undo: check missing (not applied?)'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>165 THEN RAISE EXCEPTION 'r445 undo: expected 165 pins'; END IF;
END $g$;
DROP POLICY pdc_sublet_po_upload_445 ON storage.objects;
DROP POLICY pdc_sublet_po_read_445 ON storage.objects;
DROP FUNCTION public.record_pdc_sublet_po_document_445(uuid,text,text,integer,text,text,text[],uuid,uuid);
DROP FUNCTION public.get_pdc_sublet_po_documents_445(uuid);
DROP FUNCTION public.get_pdc_sublet_po_attach_pilot_445();
DROP FUNCTION public.pdc_sublet_po_vehicle_lines_445(uuid);
DROP FUNCTION public.pdc_sublet_po_read_allowed_445(text,text);
DROP FUNCTION public.pdc_sublet_po_upload_allowed_445(text,text);
DROP FUNCTION public.pdc_sublet_po_attach_role_445();
DELETE FROM pdc_ops.regression_checks WHERE check_name='sublet_po_attach_445' AND added_in='r445';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r445';
DROP TABLE public.pdc_sublet_po_documents_445;
DROP FUNCTION public.pdc_sublet_po_documents_append_only_445();
DROP TABLE public.pdc_sublet_po_attach_pilot_445;
DO $b$ DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM storage.objects WHERE bucket_id='pdc-sublet-po-staging';
 IF n=0 THEN
  -- Empty bucket: nothing can be orphaned, so the Storage delete guard is lifted for this transaction only.
  PERFORM set_config('storage.allow_delete_query','true',true);
  DELETE FROM storage.buckets WHERE id='pdc-sublet-po-staging';
  PERFORM set_config('storage.allow_delete_query','false',true);
 ELSE
  RAISE NOTICE 'r445 undo: bucket pdc-sublet-po-staging kept (% object(s)); it is private with no policies. Remove the objects and the bucket with the Storage API.',n;
 END IF;
END $b$;
DO $g$ BEGIN
 IF to_regclass('public.pdc_sublet_po_documents_445') IS NOT NULL OR to_regclass('public.pdc_sublet_po_attach_pilot_445') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc WHERE proname LIKE '%sublet_po%445')
    OR EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND policyname LIKE 'pdc_sublet_po_%_445') THEN RAISE EXCEPTION 'r445 undo: objects left behind'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r445') OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>157
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r445') THEN RAISE EXCEPTION 'r445 undo: pins / check not restored'; END IF;
END $g$;
