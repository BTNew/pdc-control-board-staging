-- r445 (F58): read-only contract check for the sublet PO attach (bucket, policies, pilot gate, append-only history).
-- No vehicles, jobs, lines, POs or documents written. Everything is rolled back.
BEGIN;
DO $test$ DECLARE x record; BEGIN
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='sublet_po_attach_445' AND added_in='r445') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r445 contract check failed: %',x.detail; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r445')<>8 THEN RAISE EXCEPTION 'r445_pins_missing'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.import_sublet_pos_439(jsonb,text,boolean)'::regprocedure)<>'6083fb5bcf03d341d9101831c2217cb8' THEN RAISE EXCEPTION 'import_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)'::regprocedure)<>'709b0156a11db82721e6acb40c2c947b' THEN RAISE EXCEPTION 'tick_rpc_changed'; END IF;
END $test$;
SELECT 'PASS: sublet PO attach bucket private and PDF only, two storage policies, pilot gate, append-only documents' result;
ROLLBACK;
