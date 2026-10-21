-- r459 (F72): read-only contract check for Dept 138 review routing (the reviewer's station drives routing). Nothing is
-- approved or written; no live vehicle is used as a fixture. Everything is rolled back.
BEGIN;
DO $test$ DECLARE x record; BEGIN
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='dept138_review_routing_459' AND added_in='r459') INTO x;
 PERFORM set_config('search_path','public, extensions',true);
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r459 contract check failed: %',x.detail; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r459' AND md5(p.prosrc)=e.prosrc_md5)<>2 THEN RAISE EXCEPTION 'r459_pins_changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'a50e6a6988ae3a106f959e3163b4121c'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'03e96225dc36891ec0d122aecd87b967' THEN RAISE EXCEPTION 'r459_functions_changed'; END IF;
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'f099baf746f35b500389749ac844bc2f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_require_department138_bus_20260916()'::regprocedure)<>'541414352f5a4f83ee44112f302da62b' THEN RAISE EXCEPTION 'base_approve_or_route_trigger_changed'; END IF;
 IF (public.approve_pdc_new_vehicle_review_446(NULL,NULL,'[]'::jsonb,NULL)->>'code')<>'invalid_approval'
    OR (public.approve_pdc_new_vehicle_review_446('00000000-0000-4000-8000-000000000459',repeat('0',64),'[]'::jsonb,'00000000-0000-4000-8000-000000000459')->>'code')<>'not_authorized' THEN RAISE EXCEPTION 'no_session_not_refused'; END IF;
 -- Mapping: Mechanical / Accessories / Electrical / QA / Pit - external -> BUS_4X4 card; Tint, Tyre, Sublet as chosen.
 BEGIN
  INSERT INTO pdc_bus_private.operation_review_station_459(operation_id,vehicle_id,stage_code,work_category,approval_key,recorded_by)
  VALUES('00000000-0000-4000-8000-000000000459','00000000-0000-4000-8000-000000000459','SUBLET','BUS_PIT','00000000-0000-4000-8000-000000000459','00000000-0000-4000-8000-000000000459');
  RAISE EXCEPTION 'mismatched_station_accepted';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
END $test$;
SELECT 'PASS: r459 any of the 8 Dept 138 stations approves; the reviewer''s station is recorded and read first by operation_station; base approve and route trigger unchanged' result;
ROLLBACK;
