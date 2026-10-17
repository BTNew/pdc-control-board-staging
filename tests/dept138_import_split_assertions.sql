BEGIN;
CREATE FUNCTION pg_temp.line(description text,department text DEFAULT '138',hours numeric DEFAULT 1.5)
RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('line_identity','source:synthetic',
'description',description,'department',department,'estimated_hours',hours,'active',true,
'completed',false,'rejected',false,'stage_code','BUS_4X4','work_category','BUS_MECHANICAL',
'category_version',0,'zero_hour_task',false,'job_card_number','SYNTHETIC','original_line_number',1) $$;
CREATE FUNCTION pg_temp.assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS NOT TRUE THEN RAISE EXCEPTION 'Assertion failed: %',label; END IF; END $$;
DO $$ DECLARE item record; original jsonb; result jsonb; v uuid:='00000000-0000-4000-8000-000000000138'; s uuid:='00000000-0000-4000-8000-000000000001';
BEGIN
 FOR item IN SELECT * FROM (VALUES
 ('Battery Isolator Mounted on Bull Bar','BUS_ELECTRICAL'),
 ('LED Lightbar - For Bull Bar','BUS_ELECTRICAL'),
 ('Pre-Delivery (Commercial)','BUS_ELECTRICAL'),
 ('6 x Super Single Tyres & Rims - Coaster','BUS_MECHANICAL'),
 ('Cargo Barrier','BUS_ACCESSORIES'),
 ('1.0 KG FIRE EXTINGUISHER','BUS_ACCESSORIES'),
 ('95 Litres of Fuel','BUS_QA'),
 ('Pit & Weigh','BUS_PIT'),
 ('Darkest Legal Window Tint','TINT'),
 ('Second Spare Alloy Rim & Aftermarket Tyre','TYRE'),
 ('SUB - MMT Multiple Row Canvas Seat Covers','SUBLET'),
 ('Unreviewed future conversion package','UNALLOCATED_MAPPING_REVIEW'),
 ('New Rental Mine Bar & Acc Kit','UNALLOCATED_MAPPING_REVIEW'),
 ('Bus 4x4 LWB Hamertone Bull Bar with headlight conversion','UNALLOCATED_MAPPING_REVIEW')
 ) t(description,category) LOOP
  original:=pg_temp.line(item.description);
  result:=pdc_work_categories_private.route_import_line_20261017(original,false);
  PERFORM pg_temp.assert(result->>'work_category'=item.category,'Exact rule: '||item.description);
  PERFORM pg_temp.assert(result-ARRAY['work_category','stage_code','zero_hour_task']=original-ARRAY['work_category','stage_code','zero_hour_task'],'Only category fields change');
 END LOOP;
 original:=pg_temp.line('  battery   isolator mounted on bull bar  ');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(original,false)->>'work_category'='BUS_ELECTRICAL','Case and whitespace normalization');
 original:=pg_temp.line('Battery Isolator Mounted on Bull Bar','139');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(original,false)=original,'139 unchanged');
 original:=pg_temp.line('Battery Isolator Mounted on Bull Bar');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(original,true)=original,'Protected line unchanged');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(original||'{"completed":true}',false)=original||'{"completed":true}','Completed unchanged');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(original||'{"active":false}',false)=original||'{"active":false}','Inactive unchanged');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(original||'{"rejected":true}',false)=original||'{"rejected":true}','Rejected unchanged');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(pg_temp.line('Battery Isolator Mounted on Bull Bar','138',0.01),false)->>'work_category'='UNALLOCATED_MAPPING_REVIEW','Nominal internal hours held');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(pg_temp.line('Battery Isolator Mounted on Bull Bar','138',NULL),false)->>'work_category'='UNALLOCATED_MAPPING_REVIEW','Missing internal hours held');
 PERFORM pg_temp.assert(pdc_work_categories_private.route_import_line_20261017(pg_temp.line('95 Litres of Fuel','138',0)||'{"zero_hour_task":true}',false)->>'work_category'='BUS_QA','Explicit zero-hour QA retained');
 INSERT INTO public.synthetic_lines VALUES(v,original);
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'work_category'='BUS_ELECTRICAL','New source reaches canonical category');
 INSERT INTO pdc_work_categories_private.import_baseline_20261017 VALUES(v,original->>'line_identity',pdc_work_categories_private.source_signature(original));
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0=original,'Baseline exact line preserved');
 UPDATE public.synthetic_lines SET line=line||'{"estimated_hours":4}' WHERE vehicle_id=v;
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'estimated_hours'='4','Updated hours retained');
 UPDATE public.synthetic_lines SET line=line||'{"description":"Cargo Barrier"}' WHERE vehicle_id=v;
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'work_category'='BUS_ACCESSORIES','Changed description gets new rule');
 INSERT INTO public.vehicle_workshop_line_adjustments VALUES(v,'source:synthetic',true);
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'work_category'='BUS_MECHANICAL','Manual station protected');
 DELETE FROM public.vehicle_workshop_line_adjustments;
 UPDATE public.synthetic_lines SET line=line||'{"category_version":2}' WHERE vehicle_id=v;
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'work_category'='BUS_MECHANICAL','Explicit category version protected');
 UPDATE public.synthetic_lines SET line=line||'{"category_version":0}' WHERE vehicle_id=v;
 INSERT INTO public.workshop_stages VALUES(s,'BUS_4X4','bus');
 INSERT INTO public.workshop_bookings VALUES(v,s,NULL,'planned',NULL,NULL);
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'work_category'='BUS_MECHANICAL','Whole booking scope protected');
 UPDATE public.workshop_bookings SET work_category='BUS_MECHANICAL',work_category_scope='{"source:synthetic":"hash"}';
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'work_category'='BUS_MECHANICAL','Category booking scope protected');
 DELETE FROM public.workshop_bookings;
 INSERT INTO public.vehicle_work_items VALUES(v,'bus',true);
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'work_category'='BUS_MECHANICAL','Completed stage protected');
 DELETE FROM public.vehicle_work_items;
 INSERT INTO pdc_work_categories_private.owner_line_reviews SELECT v,'source:synthetic',pdc_work_categories_private.source_signature(line) FROM public.synthetic_lines;
 PERFORM pg_temp.assert(public.pdc_qc_operation_lines_379(v)->0->>'work_category'='BUS_MECHANICAL','Owner reviewed scope protected');
 PERFORM pg_temp.assert(NOT has_table_privilege('anon','pdc_work_categories_private.import_rules_20261017','SELECT'),'Rule catalog not public');
 PERFORM pg_temp.assert(NOT has_function_privilege('authenticated','pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)','EXECUTE'),'Rule helper not publicly callable');
END $$;
ROLLBACK;
SELECT 'Department 138 import split SQL assertions passed' AS result;
