-- r471 (F84): contract checks for the service-operation supersession mechanism; no operational fixtures, no vehicles,
-- jobs, lines or operations are created or changed, and no supersession is recorded. Everything is rolled back.
BEGIN;
DO $test$ DECLARE x record; BEGIN
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='service_operation_supersede_471' AND added_in='r471') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r471 check failed: %',x.detail; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_tune_operation_change_candidate_20260912(uuid,jsonb)'::regprocedure)<>'3781d764a2aedf1bbfddab707a1ccfd9' THEN RAISE EXCEPTION 'candidate_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)<>'375bffc2dced95a7a5c74c3273dbccb3' THEN RAISE EXCEPTION 'preview_changed'; END IF;
 -- the SQL twin of the preparer rule (tools/import-rules/revolution_service_wsublet.py same_line_ignoring_bay_code)
 IF NOT pdc_service_supersede_private.bay_code_same_line_471('DE MINE SPEC','DE MINE SPEC 05K4F') THEN RAISE EXCEPTION 'code added'; END IF;
 IF NOT pdc_service_supersede_private.bay_code_same_line_471('FUEL CHARGE','FUEL CHARGE -- 04K2B') THEN RAISE EXCEPTION 'dashed code'; END IF;
 IF NOT pdc_service_supersede_private.bay_code_same_line_471('Pre-Delivery (Commercial)','PRE-DELIVERY (COMMERCIAL) 05K4C') THEN RAISE EXCEPTION 'case'; END IF;
 IF NOT pdc_service_supersede_private.bay_code_same_line_471('PLUG -- 05J3A','PLUG -- 04W3B') THEN RAISE EXCEPTION 'code changed'; END IF;
 IF pdc_service_supersede_private.bay_code_same_line_471('DE MINE SPEC','DE MINE SPEC') THEN RAISE EXCEPTION 'identical is not a bay-code pair'; END IF;
 IF pdc_service_supersede_private.bay_code_same_line_471('TRAY HAEVY DUTY','TRAY HEAVY DUTY 05K4F') THEN RAISE EXCEPTION 'wording change'; END IF;
 IF pdc_service_supersede_private.bay_code_same_line_471('SPEC','SPEC **SUSP 17C6B**') THEN RAISE EXCEPTION 'annotation'; END IF;
 IF pdc_service_supersede_private.bay_code_same_line_471('SPEC','SPEC 5K4F') OR pdc_service_supersede_private.bay_code_same_line_471('SPEC','SPEC 05k4f') THEN RAISE EXCEPTION 'loose code'; END IF;
 -- the table is private, append-only and refuses a supersession it cannot prove
 IF has_table_privilege('authenticated','public.pdc_service_operation_supersessions_471','SELECT') OR has_table_privilege('anon','public.pdc_service_operation_supersessions_471','SELECT')
    OR has_function_privilege('authenticated','pdc_service_supersede_private.supersede_operation_471(uuid,uuid,text,text,text,boolean)','EXECUTE') THEN RAISE EXCEPTION 'not private'; END IF;
 BEGIN
  PERFORM pdc_service_supersede_private.supersede_operation_471(gen_random_uuid(),gen_random_uuid(),'owner_decision','contract test','contract test',false);
  RAISE EXCEPTION 'unknown operations were accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='unknown operations were accepted' THEN RAISE; END IF; END;
END $test$;
SELECT 'PASS: supersession private and append-only, bay-code rule tight, candidate ignores superseded versions, preview unchanged' result;
ROLLBACK;
