-- r446 (F59): read-only contract check for the Dept 138 review categories approval wrapper. Nothing is approved or written.
BEGIN;
DO $test$ DECLARE x record; BEGIN
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='dept138_review_categories_446' AND added_in='r446') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r446 contract check failed: %',x.detail; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release IN('r446','r459') AND e.signature IN('public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)','public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','public.pdc_new_vehicle_review_row(uuid)') AND md5(p.prosrc)=e.prosrc_md5)<>3 THEN RAISE EXCEPTION 'r446_pins_changed'; END IF; -- r459 (F72) moved the wrapper's pin to r459
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'f099baf746f35b500389749ac844bc2f' THEN RAISE EXCEPTION 'approve_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) NOT IN('84af7607bfd0ce9907c89bae8644d5b6','0aaaa15690ca286ed0db87fc72271d5a') /* r452 (F65) */ THEN RAISE EXCEPTION 'clock_tick_changed'; END IF;
 IF (public.approve_pdc_new_vehicle_review_446(NULL,NULL,'[]'::jsonb,NULL)->>'code')<>'invalid_approval' THEN RAISE EXCEPTION 'null_input_not_refused'; END IF;
END $test$;
SELECT 'PASS: r446 wrapper present, pinned, delegates to the unchanged approve, refuses without a session' result;
ROLLBACK;
