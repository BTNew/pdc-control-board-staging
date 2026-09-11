DO $test$
DECLARE definition text; predicate text; value jsonb; blocked boolean; stage text;
BEGIN
 definition := pg_get_functiondef('public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure);
 predicate := split_part(split_part(definition,'WHERE (x->>''stage_code''',2),'OR (l->>''completed'')',1);
 IF predicate='' THEN RAISE EXCEPTION 'sublet_gate_missing'; END IF;
 predicate := '(x->>''stage_code''' || predicate;
 FOREACH stage IN ARRAY ARRAY['SUBLET','FITTING','ELECTRICAL','BUS_4X4','TINT','HOIST','FABRICATION','TYRE'] LOOP
  FOREACH value IN ARRAY ARRAY['null'::jsonb,'0'::jsonb] LOOP
   EXECUTE 'SELECT '||predicate||' FROM (SELECT $1 AS l,$2 AS x) q' INTO blocked
    USING jsonb_build_object('description','Kit','estimated_hours',value), jsonb_build_object('stage_code',stage,'estimated_hours',value);
   IF blocked IS DISTINCT FROM (stage<>'SUBLET') THEN RAISE EXCEPTION 'wrong_hours_gate: % %',stage,value; END IF;
  END LOOP;
 END LOOP;
 IF position('IF assignment->>''stage_code'' <> ''SUBLET'' AND' in definition)=0
  OR position('THEN oldline->''estimated_hours''' in definition)=0
  OR position('IS NOT DISTINCT FROM CASE' in definition)=0
  OR position('operation_hours_or_state_need_review' in definition)=0
  OR position('all_operations_need_stations' in definition)=0
 THEN RAISE EXCEPTION 'preservation_guard_missing'; END IF;
 IF public.approve_pdc_new_vehicle_review(null,null,'[]',null)->>'code'<>'not_authorized' THEN RAISE EXCEPTION 'actor_guard_changed'; END IF;
 IF public.pdc_review_positive_hours_20260911('{"description":"Pre-Delivery (Commercial)","estimated_hours":1}','{"estimated_hours":2}') IS NOT NULL THEN RAISE EXCEPTION 'predelivery_guard_changed'; END IF;
END $test$;
