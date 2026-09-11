DO $test$
DECLARE assignment jsonb; line jsonb:='{"description":"Supplied kit","estimated_hours":0}';
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
  FOREACH assignment IN ARRAY ARRAY['{}'::jsonb,'{"estimated_hours":0}','{"estimated_hours":null}',
    '{"estimated_hours":""}','{"estimated_hours":"1"}','{"estimated_hours":false}',
    '{"estimated_hours":-1}','{"estimated_hours":1000}','{"estimated_hours":0.001}'] LOOP
    IF public.pdc_review_positive_hours_20260911(line,assignment) IS NOT NULL THEN RAISE EXCEPTION 'invalid_hours_allowed: %',assignment; END IF;
  END LOOP;
  IF public.pdc_review_positive_hours_20260911(line,'{"estimated_hours":0.25}')<>0.25
    OR public.pdc_review_positive_hours_20260911('{"description":"Kit","estimated_hours":2.5}','{}')<>2.5
    OR public.pdc_review_positive_hours_20260911('{"description":"Pre-Delivery (Commercial)","estimated_hours":1}','{"estimated_hours":2}') IS NOT NULL
    OR public.pdc_review_positive_hours_20260911('{"description":"Pre-Delivery (Commercial)","estimated_hours":0}','{"estimated_hours":1}')<>1
  THEN RAISE EXCEPTION 'positive_or_standard_hours_wrong'; END IF;
  IF has_function_privilege('authenticated','public.pdc_review_positive_hours_20260911(jsonb,jsonb)','execute')
    OR has_function_privilege('anon','public.pdc_review_positive_hours_20260911(jsonb,jsonb)','execute')
  THEN RAISE EXCEPTION 'internal_helper_exposed'; END IF;
  IF public.approve_pdc_new_vehicle_review(null,null,'[]',null)->>'code'<>'not_authorized'
  THEN RAISE EXCEPTION 'approval_actor_guard_changed'; END IF;
END $test$;
SELECT 'PASS: positive hours, rejected zero/missing/invalid, one-hour pre-delivery, private helper and approval actor guard' result;
