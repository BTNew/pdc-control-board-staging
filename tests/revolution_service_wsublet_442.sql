-- r442 (F54): pure contract checks for the 'PMG PD Service Complete w/Sublet' service report; no operational fixtures,
-- no source imports, no vehicles, jobs, lines or POs. Everything is rolled back.
BEGIN;
DO $test$ DECLARE x record; BEGIN
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='service_wsublet_contract_and_po_feed' AND added_in='r442') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r442 contract check failed: %',x.detail; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)<>'375bffc2dced95a7a5c74c3273dbccb3' THEN RAISE EXCEPTION 'preview_contract_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)<>'6083fb5bcf03d341d9101831c2217cb8' THEN RAISE EXCEPTION 'po_import_changed'; END IF;
 IF (SELECT banned_until FROM auth.users WHERE id='0640d2f1-9f97-4e20-8a4f-cb6069b005df') IS DISTINCT FROM '2126-08-21T11:05:10.641388+00:00'::timestamptz THEN RAISE EXCEPTION 'importer_state_changed'; END IF;
END $test$;
SELECT 'PASS: w/Sublet manifest and row contract, old title kept, PO feed private and wired before the single apply receipt' result;
ROLLBACK;
