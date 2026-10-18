BEGIN;
DO $test$
DECLARE original jsonb; mapped jsonb; variant jsonb; estimate jsonb; d text; c text;
BEGIN
 FOR d,c IN SELECT * FROM (VALUES ('LED Lightbar - For Bull Bar','ELECTRICAL'),('Snorkel - Ram Head','FITTING')) t(description,category) LOOP
  original:=jsonb_build_object('department','139','stage_code','UNALLOCATED_MAPPING_REVIEW','work_category','UNALLOCATED_MAPPING_REVIEW','description',d,'estimated_hours',1.33,'active',true,'completed',false,'rejected',false);
  mapped:=pdc_work_categories_private.route_import_line_20261017(original,false);
  IF mapped->>'stage_code' IS DISTINCT FROM c OR mapped->>'work_category' IS DISTINCT FROM c OR mapped->'estimated_hours' IS DISTINCT FROM original->'estimated_hours' THEN RAISE EXCEPTION 'Approved description did not route with source hours'; END IF;
  IF pdc_work_categories_private.route_import_line_20261017(original,true) IS DISTINCT FROM original THEN RAISE EXCEPTION 'Preserved line changed'; END IF;
  FOREACH variant IN ARRAY ARRAY[original||'{"completed":true}',original||'{"active":false}',original||'{"rejected":true}',original||'{"department":"140"}',original||'{"stage_code":"FABRICATION"}',original||'{"estimated_hours":0}',original||'{"estimated_hours":null}',original||'{"estimated_hours":-1}',original||'{"estimated_hours":1000}',original||'{"description":"Unknown supplier package"}']::jsonb[] LOOP
   IF pdc_work_categories_private.route_import_line_20261017(variant,false) IS DISTINCT FROM variant THEN RAISE EXCEPTION 'Review, existing routing, lifecycle or department guard failed'; END IF;
  END LOOP;
  estimate:=pdc_work_categories_private.reviewed_import_choice_139_20261018(original);
  IF estimate->>'stage_code' IS DISTINCT FROM c OR (estimate->>'estimated_hours')::numeric<>1.33 THEN RAISE EXCEPTION 'Pending import lost approved routing or hours'; END IF;
  estimate:=pdc_work_categories_private.reviewed_import_choice_139_20261018(original||'{"estimated_hours":null}');
  IF estimate->>'stage_code' IS DISTINCT FROM 'REVIEW' OR estimate->>'estimated_hours' IS NOT NULL THEN RAISE EXCEPTION 'Missing hours were invented'; END IF;
  estimate:=pdc_work_categories_private.reviewed_import_choice_139_20261018(original||'{"estimated_hours":0}');
  IF estimate->>'stage_code' IS DISTINCT FROM 'REVIEW' OR (estimate->>'estimated_hours')::numeric<>0 THEN RAISE EXCEPTION 'Zero hours were silently replaced'; END IF;
 END LOOP;
 IF has_table_privilege('anon','pdc_work_categories_private.import_rules_139_20261018','SELECT') OR has_table_privilege('authenticated','pdc_work_categories_private.import_rules_139_20261018','SELECT') THEN RAISE EXCEPTION 'Private routing rules exposed'; END IF;
END $test$;
SELECT 'PASS: approved Department 139 routing, source hours, review holds, lifecycle/manual preservation and private rule access' result;
ROLLBACK;
