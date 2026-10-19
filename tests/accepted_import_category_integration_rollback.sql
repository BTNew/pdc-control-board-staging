-- DISPOSABLE LOCAL DATABASE ONLY. Synthetic actor, vehicles, operations and bays.
-- Department retry also exercises the copied backlog. Everything rolls back.
-- Run this complete file in one connection after the operation-approval migration.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';

DO $guard$
BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN
  RAISE EXCEPTION 'Disposable loopback database required';
 END IF;
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

-- This regression graph deliberately covers a configured Saturday shift.
-- Keep its calendar fixture independent of the deployed Monday-Friday calendar.
-- Both this setting and every synthetic record are undone by the final ROLLBACK.
UPDATE public.workshop_settings
SET value='["monday","tuesday","wednesday","thursday","friday","saturday"]'::jsonb
WHERE key='working_week';
UPDATE public.workshop_settings
SET value='[{"scope":"saturday","start":"07:00","end":"08:00"},{"scope":"saturday","start":"12:00","end":"17:00"}]'::jsonb
WHERE key='break_windows';

CREATE TEMP TABLE ou_context(actor uuid, email text, friday date, batch uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE ou_source_order;
CREATE TEMP TABLE ou_refs(name text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ou_results(name text PRIMARY KEY, status text, evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE ou_original_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
CREATE TEMP TABLE ou_original_vehicles AS SELECT id,to_jsonb(v) row_data FROM public.vehicles v;
CREATE TEMP TABLE ou_original_reviews AS SELECT change_id,status FROM public.pdc_tune_operation_change_reviews;

CREATE FUNCTION pg_temp.ou_assert(pass boolean, label text, evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO ou_results VALUES(label,'PASS',evidence);
END $fn$;

DO $setup$
DECLARE a uuid:=gen_random_uuid(); e text; b uuid:=gen_random_uuid();
BEGIN
 e:='operation-update-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',e,clock_timestamp(),'{"provider":"email","providers":["email"]}','{"full_name":"Temporary operation update rollback fixture"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=a AND email=e;
 INSERT INTO ou_context VALUES(a,e,(date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+18),b);
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(b,'pilbara_service_open_jobcards_v1',encode(extensions.digest(b::text,'sha256'),'hex'),repeat('b',64),'rollback-base-'||b,'apply',1,1,0,1,0,0,'{}',a,e);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 PERFORM pg_temp.ou_assert(public.workshop_is_planner_operator(),'Synthetic operator is authorized');
END $setup$;

CREATE FUNCTION pg_temp.ou_vehicle(tag text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid:=gen_random_uuid(); stock text:='OU-'||substr(v::text,1,8); actor_id uuid;
BEGIN
 SELECT actor INTO actor_id FROM ou_context;
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,current_location,visible_on_board,
 source_system,source_record_id,source_payload,created_by,updated_by)
 VALUES(v,'operation-update-rollback-'||v,stock,'OU-JC-'||substr(v::text,1,8),'ROLLBACK FIXTURE '||tag,'Synthetic vehicle','PMB',true,
 'operation_update_rollback_20260913',v::text,'{"rollback_fixture":true}',actor_id,actor_id);
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,first_job_card,approved_at,approved_by)
 VALUES(v,'approved','OU-JC-'||substr(v::text,1,8),clock_timestamp(),actor_id);
 INSERT INTO ou_refs VALUES('vehicle-'||tag,v);
 RETURN v;
END $fn$;

CREATE FUNCTION pg_temp.ou_bay(tag text, stage text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE b uuid:=gen_random_uuid(); sid uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage AND active;
 INSERT INTO public.workshop_bays(id,stage_id,code,display_name,is_active)
 VALUES(b,sid,'OU-'||b,'Rollback fixture '||tag,true);
 INSERT INTO ou_refs VALUES('bay-'||tag,b);
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1,dept text DEFAULT '139',descr text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',coalesce(descr,'Fixture work '||stage||' line '||line_no),'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{"Company":"01","Division":"1"}','insert','rollback_original',vid);
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(op,'pilbara_service_open_jobcards_v1',v.stock_number,v.job_card_number,line_no,line_no,vid,p->>'operation_description',hrs,hrs,'source_explicit','review','Review',repeat('c',64),ev,dept,stage);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed) VALUES(vid,wk,true,false)
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true;
 RETURN op;
END $fn$;

CREATE FUNCTION pg_temp.ou_booking(tag text, vid uuid, stage text, bay uuid, start_at timestamptz, state public.workshop_booking_status DEFAULT 'planned')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE bid uuid:=gen_random_uuid(); sid uuid; mins integer; actor_id uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage;
 SELECT actor INTO actor_id FROM ou_context;
 mins:=public.workshop_capacity_duration_minutes(pdc_work_categories_private.minutes(bid,vid,sid),bay);
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;

CREATE FUNCTION pg_temp.ou_change(vid uuid, source_id uuid, hrs numeric, description text, new_line_no integer DEFAULT 1,dept text DEFAULT '139')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE ev uuid:=gen_random_uuid(); change_batch_id uuid:=gen_random_uuid(); cid uuid; a uuid; e text; v public.vehicles%rowtype; p jsonb; line_no integer;
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT actor,email INTO a,e FROM ou_context;
 IF source_id IS NOT NULL THEN SELECT original_line_number INTO STRICT line_no FROM public.pdc_pilbara_service_operations WHERE operation_id=source_id;
 ELSE line_no:=new_line_no; END IF;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',description,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station','REVIEW','hours_provenance','source_explicit','semantic_hash',encode(extensions.digest(description||hrs::text||ev::text,'sha256'),'hex'),
 'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(change_batch_id,'pilbara_service_open_jobcards_v1',encode(extensions.digest(change_batch_id::text,'sha256'),'hex'),repeat('e',64),'rollback-change-'||change_batch_id,'apply',1,1,0,1,0,0,'{}',a,e);
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,change_batch_id,'pilbara_service_open_jobcards_v1',line_no,v.stock_number,v.job_card_number,line_no,p->>'semantic_hash',p,'{"Company":"01","Division":"1"}','unchanged','operation_update_review',vid);
 PERFORM public.pdc_capture_tune_operation_changes_20260912(change_batch_id,change_batch_id);
 SELECT q.change_id INTO STRICT cid FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=vid AND q.original_line_number=line_no AND q.batch_id=change_batch_id;
 -- Replayed imports must not insert duplicate accepted source lines.
 PERFORM public.pdc_capture_tune_operation_changes_20260912(change_batch_id,change_batch_id);
 RETURN cid;
END $fn$;


DO $integration$
DECLARE v uuid; cid uuid; r jsonb; line jsonb; item record; op uuid;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  ('Battery Isolator Mounted on Bull Bar','BUS_ELECTRICAL',1.5),
  ('6 x Super Single Tyres & Rims - Coaster','BUS_MECHANICAL',10.0),
  ('Cargo Barrier','BUS_ACCESSORIES',2.0),
  ('Second Spare Alloy Rim & Aftermarket Tyre','TYRE',1.0),
  ('LED Lightbar - For Bull Bar','BUS_ELECTRICAL',2.0),
  ('Pre-Delivery (Commercial)','BUS_ELECTRICAL',1.5),
  ('SUB - MMT Multiple Row Canvas Seat Covers','SUBLET',0.01),
  ('95 Litres of Fuel','BUS_QA',0.15),
  ('95 LITRES OF FUEL -- 05E2A **MINEBAR 04X4B**','BUS_QA',0.0),
  ('Pit & Weigh','BUS_PIT',1.0),
  ('Unreviewed future conversion package','UNALLOCATED_MAPPING_REVIEW',2.0),
  ('Darkest Legal Window Tint','TINT',1.0)
 ) t(description,category,hours) LOOP
  v:=pg_temp.ou_vehicle('category integration '||item.description);
  cid:=pg_temp.ou_change(v,NULL,item.hours,item.description,1,'138');
  SELECT automation_result INTO r FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
  SELECT l INTO line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l LIMIT 1;
  INSERT INTO ou_results VALUES(item.description,
   CASE WHEN (line->>'work_category'=item.category AND (line->>'estimated_hours')::numeric=item.hours)
     OR (item.category='UNALLOCATED_MAPPING_REVIEW' AND line IS NULL AND r->>'code'='station_needs_review')
    THEN 'PASS' ELSE 'FAIL' END,
   jsonb_build_object('expected_category',item.category,'actual_category',line->>'work_category',
    'estimated_hours',line->'estimated_hours','automation_code',r->>'code','detail',r->>'detail'));
  IF item.category<>'UNALLOCATED_MAPPING_REVIEW' AND line IS NOT NULL THEN
   op:=(line->>'source_line_id')::uuid;
   cid:=pg_temp.ou_change(v,op,item.hours+1,item.description,1,'138');
   SELECT automation_result INTO r FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
   SELECT l INTO line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l LIMIT 1;
   INSERT INTO ou_results VALUES('Hours update: '||item.description,
    CASE WHEN line->>'work_category'=item.category AND (line->>'estimated_hours')::numeric=item.hours+1 AND r->>'ok'='true' THEN 'PASS' ELSE 'FAIL' END,
    jsonb_build_object('actual_category',line->>'work_category','estimated_hours',line->'estimated_hours','automation_code',r->>'code','detail',r->>'detail'));
  END IF;
 END LOOP;
END $integration$;
DO $booked$
DECLARE v uuid; cid uuid; r jsonb; line jsonb; op uuid; bay uuid; bid uuid; d date;
BEGIN
 v:=pg_temp.ou_vehicle('existing whole-job booking');
 op:=pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Coaster Bus 4x4 Conversion - 6 Speed 2.8');
 SELECT b.id INTO STRICT bay FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE s.code='BUS_4X4' AND b.bay_number=1 AND b.is_active;
 -- Choose an open fixture day; the moving date can otherwise land on Good Friday.
 SELECT candidate::date INTO d FROM ou_context c
 CROSS JOIN LATERAL generate_series(c.friday+140,c.friday+160,interval '1 day') candidate
 WHERE pdc_bus_private.minute_available((candidate::date+time '06:00') AT TIME ZONE 'Australia/Perth',bay)
 ORDER BY candidate LIMIT 1;
 IF d IS NULL THEN RAISE EXCEPTION 'No open whole-job fixture day'; END IF;
 bid:=pg_temp.ou_booking('whole-job',v,'BUS_4X4',bay,(d+time '06:00') AT TIME ZONE 'Australia/Perth');
 cid:=pg_temp.ou_change(v,NULL,1.5,'Battery Isolator Mounted on Bull Bar',2,'138');
 SELECT automation_result INTO r FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 SELECT l INTO line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'description'='Battery Isolator Mounted on Bull Bar';
 INSERT INTO ou_results VALUES('New electrical line with a whole-job booking',
  CASE WHEN line->>'work_category'='BUS_ELECTRICAL' THEN 'PASS' ELSE 'FAIL' END,
  jsonb_build_object('actual_category',line->>'work_category','automation_code',r->>'code','detail',r->>'detail'));
END $booked$;
DO $split_bookings$
DECLARE v uuid; cid uuid; r jsonb; m uuid; e uuid; mb uuid; eb uuid; mech uuid; elec uuid; d date; line jsonb;
BEGIN
 v:=pg_temp.ou_vehicle('separate Mechanical Electrical bookings');
 m:=pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Coaster Bus 4x4 Conversion - 6 Speed 2.8');
 e:=pg_temp.ou_operation(v,'BUS_4X4',1,2,'138','Coaster Bus Side Insert with Jump Start and Battery Isolator');
 SELECT b.id INTO STRICT mech FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='BUS_4X4' AND b.bay_number=1 AND b.is_active;
 SELECT b.id INTO STRICT elec FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='BUS_4X4' AND b.bay_number=8 AND b.is_active;
 SELECT candidate::date INTO d FROM ou_context c
 CROSS JOIN LATERAL generate_series(c.friday+147,c.friday+180,interval '1 day') candidate
 WHERE pdc_bus_private.minute_available((candidate::date+time '06:00') AT TIME ZONE 'Australia/Perth',mech)
  AND pdc_bus_private.minute_available((candidate::date+time '10:00') AT TIME ZONE 'Australia/Perth',elec)
 ORDER BY candidate LIMIT 1;
 IF d IS NULL THEN RAISE EXCEPTION 'No valid split-booking fixture day'; END IF;
 PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4','{"work_category":"BUS_MECHANICAL"}');
 mb:=pg_temp.ou_booking('split-mechanical',v,'BUS_4X4',mech,(d+time '06:00') AT TIME ZONE 'Australia/Perth');
 PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4','{"work_category":"BUS_ELECTRICAL"}');
 eb:=pg_temp.ou_booking('split-electrical',v,'BUS_4X4',elec,(d+time '10:00') AT TIME ZONE 'Australia/Perth');
 PERFORM set_config('pdc.work_category','',true);
 cid:=pg_temp.ou_change(v,NULL,1.5,'Battery Isolator Mounted on Bull Bar',3,'138');
 SELECT automation_result INTO r FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 INSERT INTO ou_results VALUES('New line with two category bookings',CASE WHEN r->>'ok'='true'
  AND (SELECT default_duration_minutes=60 FROM public.workshop_bookings WHERE id=mb)
  AND (SELECT default_duration_minutes=150 FROM public.workshop_bookings WHERE id=eb) THEN 'PASS' ELSE 'FAIL' END,r);
 cid:=pg_temp.ou_change(v,e,2,'Coaster Bus Side Insert with Jump Start and Battery Isolator',2,'138');
 SELECT automation_result INTO r FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 INSERT INTO ou_results VALUES('Hour update with two category bookings',CASE WHEN r->>'ok'='true'
  AND (SELECT default_duration_minutes=60 FROM public.workshop_bookings WHERE id=mb)
  AND (SELECT default_duration_minutes=210 FROM public.workshop_bookings WHERE id=eb) THEN 'PASS' ELSE 'FAIL' END,r);
 PERFORM pg_temp.ou_assert(jsonb_array_length(pdc_fitter_private.lines(v,mb))=1 AND jsonb_array_length(pdc_fitter_private.lines(v,eb))=2,'New operation appears only in Electrical fitter checklist');
END $split_bookings$;
DO $started_scope$
DECLARE v uuid; m uuid; e uuid; bay uuid; sid uuid; mb uuid; eb uuid; cid uuid; r jsonb; past timestamptz; d date;
BEGIN
 v:=pg_temp.ou_vehicle('started category estimate');
 m:=pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Coaster Bus 4x4 Conversion - 6 Speed 2.8');
 e:=pg_temp.ou_operation(v,'BUS_4X4',2,2,'138','Coaster Bus Side Insert with Jump Start and Battery Isolator');
 bay:=pg_temp.ou_bay('started scope','BUS_4X4');
 SELECT stage_id INTO sid FROM public.workshop_bays WHERE id=bay;
 UPDATE public.workshop_bays SET bay_number=(SELECT max(bay_number)+1 FROM public.workshop_bays WHERE stage_id=sid) WHERE id=bay;
 SELECT (candidate::date+time '06:00') AT TIME ZONE 'Australia/Perth' INTO past
 FROM generate_series((clock_timestamp() AT TIME ZONE 'Australia/Perth')::date-14,(clock_timestamp() AT TIME ZONE 'Australia/Perth')::date-1,interval '1 day') candidate
 WHERE pdc_bus_private.minute_available((candidate::date+time '06:00') AT TIME ZONE 'Australia/Perth',bay)
 ORDER BY candidate DESC LIMIT 1;
 IF past IS NULL THEN RAISE EXCEPTION 'No available past started-booking fixture shift'; END IF;
 PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4','{"work_category":"BUS_MECHANICAL"}');
 mb:=pg_temp.ou_booking('started mechanical',v,'BUS_4X4',bay,past,'started');
 SELECT candidate::date INTO d FROM ou_context c
 CROSS JOIN LATERAL generate_series(c.friday+140,c.friday+160,interval '1 day') candidate
 WHERE pdc_bus_private.minute_available((candidate::date+time '06:00') AT TIME ZONE 'Australia/Perth',bay)
 ORDER BY candidate LIMIT 1;
 IF d IS NULL THEN RAISE EXCEPTION 'No open later-booking fixture day'; END IF;
 PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4','{"work_category":"BUS_ELECTRICAL"}');
 eb:=pg_temp.ou_booking('later electrical',v,'BUS_4X4',bay,(d+time '06:00') AT TIME ZONE 'Australia/Perth');
 PERFORM set_config('pdc.work_category','',true);
 cid:=pg_temp.ou_change(v,m,2.5,'Coaster Bus 4x4 Conversion - 6 Speed 2.8',1,'138');
 SELECT automation_result INTO r FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=150 FROM public.workshop_bookings WHERE id=mb)
  AND (SELECT default_duration_minutes=120 FROM public.workshop_bookings WHERE id=eb),'Started category retains its own hours',r);
 cid:=pg_temp.ou_change(v,m,0.5,'Coaster Bus 4x4 Conversion - 6 Speed 2.8',1,'138');
 SELECT automation_result INTO r FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=150 FROM public.workshop_bookings WHERE id=mb),'Started reservation never shrinks below time already reserved',r);
END $started_scope$;
DO $guards$
DECLARE v uuid; cid uuid; r jsonb; line jsonb; op uuid; actor uuid;
BEGIN
 v:=pg_temp.ou_vehicle('explicit manual category');
 cid:=pg_temp.ou_change(v,NULL,1.5,'Battery Isolator Mounted on Bull Bar',1,'138');
 SELECT l INTO line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l LIMIT 1;
 op:=(line->>'source_line_id')::uuid;
 SELECT c.actor INTO actor FROM ou_context c;
 INSERT INTO pdc_work_categories_private.line_overrides(vehicle_id,line_identity,category,updated_by)
 VALUES(v,line->>'line_identity','BUS_ACCESSORIES',actor);
 cid:=pg_temp.ou_change(v,op,2.5,'Battery Isolator Mounted on Bull Bar',1,'138');
 SELECT l INTO line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l LIMIT 1;
 PERFORM pg_temp.ou_assert(line->>'work_category'='BUS_ACCESSORIES' AND (line->>'estimated_hours')::numeric=2.5,'Manual category retained with new hours');
 UPDATE public.vehicles SET current_location='QC' WHERE id=v;
 cid:=pg_temp.ou_change(v,NULL,2,'LED Lightbar - For Bull Bar',2,'138');
 PERFORM pg_temp.ou_assert((SELECT status='pending' AND automation_result->>'code'='vehicle_or_review_state_protected' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid),'Completed or QC vehicles protected');
 v:=pg_temp.ou_vehicle('missing hours');
 cid:=pg_temp.ou_change(v,NULL,0,'Battery Isolator Mounted on Bull Bar',1,'138');
 PERFORM pg_temp.ou_assert((SELECT status='pending' AND automation_result->>'code'='estimated_hours_required' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid),'Missing internal estimate remains explicit');
 v:=pg_temp.ou_vehicle('PMB unchanged');
 op:=pg_temp.ou_operation(v,'FITTING',2);
 cid:=pg_temp.ou_change(v,op,3,'Fixture fitting work revised');
 SELECT automation_result INTO r FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(r->>'ok'='true','PMB automatic updates preserved',r);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'Existing copied bookings unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles b USING(id) WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'Existing copied vehicles unchanged');
END $guards$;
SELECT name,status,evidence FROM ou_results ORDER BY name;
DO $check$ BEGIN
 IF EXISTS(SELECT 1 FROM ou_results WHERE status='FAIL') THEN RAISE EXCEPTION 'Accepted operation category integration failed'; END IF;
END $check$;
ROLLBACK;
