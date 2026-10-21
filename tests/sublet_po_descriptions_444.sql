-- r444 (F57): pure contract checks for sublet descriptions; no operational fixtures, no imports, no vehicles, jobs, lines or
-- POs written. Everything is rolled back.
BEGIN;
DO $test$ DECLARE x record; BEGIN
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='sublet_po_descriptions_444' AND added_in='r444') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r444 contract check failed: %',x.detail; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure)<>'fc3717a5215de94c93ebb2c7facfe744' THEN RAISE EXCEPTION 'service_apply_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)'::regprocedure)<>'709b0156a11db82721e6acb40c2c947b' THEN RAISE EXCEPTION 'tick_rpc_changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r444')<>4 THEN RAISE EXCEPTION 'r444_pins_missing'; END IF;
END $test$;
SELECT 'PASS: sublet descriptions stored, never cleared by imports, passed by the w/Sublet feed, po_details in the vehicle payload' result;
ROLLBACK;
