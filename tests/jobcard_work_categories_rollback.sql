-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run only inside the owned disposable loopback database.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '20s';
SET LOCAL TIME ZONE 'Australia/Perth';

-- APPLY CANDIDATE MIGRATIONS HERE FOR ROLLBACK REVIEW.
DO $guard$
BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR current_database()<>'pdc_restore_check'
 THEN RAISE EXCEPTION 'Disposable loopback test database required'; END IF;
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

CREATE TEMP TABLE ou_context(actor uuid, email text, friday date, batch uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE ou_source_order;
CREATE TEMP TABLE ou_refs(name text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ou_results(name text PRIMARY KEY, status text, evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE ou_original_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
CREATE TEMP TABLE ou_original_vehicles AS SELECT id,to_jsonb(v) row_data FROM public.vehicles v;

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

CREATE FUNCTION pg_temp.ou_bay(tag text, stage text, category text DEFAULT 'BUS_MECHANICAL') RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE b uuid:=gen_random_uuid(); sid uuid; number integer; existing uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage AND active;
 IF stage='BUS_4X4' THEN
  number:=CASE category WHEN 'BUS_ELECTRICAL' THEN 8 WHEN 'BUS_QA' THEN 7 WHEN 'BUS_ACCESSORIES' THEN 10 ELSE 4 END;
  SELECT id INTO existing FROM public.workshop_bays WHERE stage_id=sid AND bay_number=number AND code LIKE 'OU-%';
  IF existing IS NOT NULL THEN RETURN existing; END IF;
  -- Owned loopback only: relocate the copied bay number, retaining its bookings unchanged.
  UPDATE public.workshop_bays SET bay_number=1000+number WHERE stage_id=sid AND bay_number=number;
 END IF;
 INSERT INTO public.workshop_bays(id,stage_id,code,display_name,is_active)
 VALUES(b,sid,'OU-'||b,'Rollback fixture '||tag,true);
 UPDATE public.workshop_bays SET bay_number=coalesce(number,(SELECT coalesce(max(bay_number),0)+1 FROM public.workshop_bays WHERE stage_id=sid)) WHERE id=b;
 INSERT INTO ou_refs VALUES('bay-'||tag,b);
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1, dept text DEFAULT '139', description text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',coalesce(description,'Fixture work '||stage||' line '||line_no),'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{}','insert','rollback_original',vid);
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
 mins:=CASE WHEN state IN('queued','planned') THEN public.workshop_capacity_duration_minutes(pdc_work_categories_private.minutes(bid,vid,sid),bay) ELSE pdc_work_categories_private.minutes(bid,vid,sid) END;
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;


DO $categories$
DECLARE v uuid; op uuid; bay uuid; eb uuid; sid uuid; t timestamptz; r jsonb; b uuid; elec uuid; h numeric; before_work jsonb;
BEGIN
 v:=pg_temp.ou_vehicle('work-categories');
 op:=pg_temp.ou_operation(v,'BUS_4X4',2,1,'138','Battery Compartment & Relay Box Protection');
 op:=pg_temp.ou_operation(v,'BUS_4X4',1.5,2,'138','Pre-Delivery (Commercial)');
 op:=pg_temp.ou_operation(v,'BUS_4X4',1,3,'138','POST REGO BUS 4X4 CERTIFICATION');
 op:=pg_temp.ou_operation(v,'BUS_4X4',0,4,'138','95 LITRES OF FUEL');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.hours(v,'BUS_MECHANICAL')=2,'Mechanical scope uses its own source hours');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.hours(v,'BUS_ELECTRICAL')=1.5,'138 pre-delivery retains 1.5 hours');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.hours(v,'BUS_QA')=1,'QA preserves explicit zero fuel plus certification');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.suggest('{"department":"138","description":"6 x Super Single Tyres & Rims - Coaster"}')='BUS_MECHANICAL','Coaster conversion tyres stay Mechanical');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.suggest('{"department":"138","description":"Tyre replacement"}')='TYRE','Ordinary tyres stay shared');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.suggest('{"department":"138","description":"External pit inspection"}')='SUBLET','Pit is external Sublet under the current owner rule');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.suggest('{"department":"138","operation_code":"BV2DC","description":"Dash cameras"}')='SUBLET','Known outsourced dash cameras stay Sublet');
 bay:=pg_temp.ou_bay('work-categories','BUS_4X4');
 eb:=pg_temp.ou_bay('electrical-categories','BUS_4X4','BUS_ELECTRICAL');
 SELECT stage_id INTO sid FROM public.workshop_bays WHERE id=bay;
 SELECT (friday::timestamp+interval '6 hours') AT TIME ZONE 'Australia/Perth' INTO t FROM ou_context;
 r:=public.workshop_validate_booking(NULL,v,sid,eb,t,public.workshop_add_operational_minutes(t,120),120,'planned',NULL,false);
 PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4','{"work_category":"BUS_MECHANICAL"}');
 r:=public.workshop_validate_booking(NULL,v,sid,eb,t,public.workshop_add_operational_minutes(t,120),120,'planned',NULL,false);
 PERFORM pg_temp.ou_assert(r->>'error'='category_bay_mismatch','Preview rejects Mechanical in Electrical bay',r);
 PERFORM set_config('pdc.work_category','',true);
 r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'BUS_4X4',(SELECT bay_number FROM public.workshop_bays WHERE id=bay),t,120,NULL,NULL,'{"work_category":"BUS_MECHANICAL"}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Mechanical category books with normal planner guards',r);
 b:=(r#>>'{booking,booking_id}')::uuid;
 BEGIN
  UPDATE public.workshop_bookings SET bay_id=eb WHERE id=b;
  RAISE EXCEPTION 'Unexpected category move accepted';
 EXCEPTION WHEN SQLSTATE '22023' THEN
  PERFORM pg_temp.ou_assert(SQLERRM LIKE '%category_bay_mismatch%','Direct writes reject a wrong category bay',jsonb_build_object('error',SQLERRM));
 END;
 PERFORM pg_temp.ou_assert((SELECT work_category='BUS_MECHANICAL' AND default_duration_minutes=120 FROM public.workshop_bookings WHERE id=b),'Booking stores category and exact category duration');
 PERFORM pg_temp.ou_assert(jsonb_array_length(pdc_fitter_private.lines(v,b))=1,'Mechanical fitter checklist excludes Electrical and QA');
 BEGIN
  r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'BUS_4X4',(SELECT bay_number FROM public.workshop_bays WHERE id=eb),t+interval '1 hour',90,NULL,NULL,'{"work_category":"BUS_ELECTRICAL"}');
 EXCEPTION WHEN SQLSTATE '22023' THEN
  IF SQLERRM NOT LIKE '%vehicle_overlap%' THEN RAISE; END IF;
  r:=jsonb_build_object('ok',false,'error','vehicle_overlap');
 END;
 PERFORM pg_temp.ou_assert(r->>'ok'='false','Different categories cannot bypass physical booking conflicts',r);
 r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'BUS_4X4',(SELECT bay_number FROM public.workshop_bays WHERE id=eb),t+interval '4 hours',90,NULL,NULL,'{"work_category":"BUS_ELECTRICAL"}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Another category can book the same vehicle later',r);
 elec:=(r#>>'{booking,booking_id}')::uuid;
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=90 FROM public.workshop_bookings WHERE id=elec),'Electrical booking does not use whole Bus hours');
 PERFORM pg_temp.ou_assert(jsonb_array_length(pdc_fitter_private.lines(v,elec))=1,'Electrical fitter sees only Electrical work');
 r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'BUS_4X4',(SELECT bay_number FROM public.workshop_bays WHERE id=bay),t+interval '1 day',120,NULL,NULL,'{"work_category":"BUS_MECHANICAL"}');
 PERFORM pg_temp.ou_assert(r->>'ok'='false' AND r->>'error'='active_booking_exists','Duplicate category reservation is rejected');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.minutes(b,v,sid)=120 AND pdc_work_categories_private.minutes(elec,v,sid)=90,'Later moves retain their own scope without request context');
 r:=public.get_vehicle_workshop_detail(v);
 PERFORM pg_temp.ou_assert(jsonb_array_length(r->'job_card_lines')=4 AND r#>>'{bookings,0,work_category}' IS NOT NULL,'Job card supplies authoritative categories and booking scopes');
 -- Project only owned fixtures: the full station reader also runs its existing
 -- overdue-booking clock, which legitimately changes restored staff bookings.
 r:=pdc_work_categories_private.snapshot(jsonb_build_object('scope',jsonb_build_object('stage_code','BUS_4X4'),
   'outstanding_candidates',jsonb_build_array(jsonb_build_object('vehicle_id',v)),'bookings','[]'::jsonb));
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'outstanding_candidates') c CROSS JOIN LATERAL jsonb_array_elements(c->'work_categories') x WHERE c->>'vehicle_id'=v::text AND x->>'work_category'='BUS_QA' AND x->>'existing_booking'='false'),'QA remains available while other categories are booked');
 -- The full reader runs its normal overdue clock in this restored copy. Roll
 -- that read's incidental changes back while retaining its response for checks.
 BEGIN
  r:=public.get_station_workshop_snapshot('BUS_4X4',(t AT TIME ZONE 'Australia/Perth')::date,(t AT TIME ZONE 'Australia/Perth')::date+1);
  RAISE EXCEPTION USING ERRCODE='PT001',MESSAGE='Rollback snapshot clock effects';
 EXCEPTION WHEN SQLSTATE 'PT001' THEN NULL;
 END;
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(r->'outstanding_candidates') c CROSS JOIN LATERAL jsonb_array_elements(c->'work_categories') x WHERE c->>'vehicle_id'=v::text AND x->>'work_category'='BUS_QA' AND x->>'schedule_enabled'='true'),'Actual station snapshot keeps remaining categories in the queue');
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('anon','public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)','execute'),'Anonymous users cannot change categories');
 SELECT (l->>'source_line_id')::uuid INTO op FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'work_category'='BUS_MECHANICAL';
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
 VALUES(v,'source:'||op,'source','BUS_4X4','Driving lights',3,auth.uid(),auth.uid());
 PERFORM public.workshop_sync_vehicle_stage_booking_duration(v,'BUS_4X4','Category rollback estimate change');
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=180 FROM public.workshop_bookings WHERE id=b) AND (SELECT default_duration_minutes=90 FROM public.workshop_bookings WHERE id=elec),'Changed operation hours resize only their own category booking');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.hours(v,'BUS_MECHANICAL')=3,'Changed wording cannot silently move a booked operation into another category');
END $categories$;

DO $completion$
DECLARE v uuid; bay uuid; b uuid; tech uuid:=gen_random_uuid(); cat text; l jsonb; d jsonb; r jsonb; op uuid; started_at timestamptz;
BEGIN
 v:=pg_temp.ou_vehicle('category-completion'); bay:=pg_temp.ou_bay('category-completion','BUS_4X4');
 -- Completion scope is under test, not starting outside a shift. Select a
 -- genuinely available past shift using the unchanged Bus calendar guard.
 -- This keeps overnight/weekend runs meaningful without bypassing that guard.
 SELECT max(candidate) INTO started_at
 FROM generate_series(0,14) AS days(n)
 CROSS JOIN LATERAL (SELECT ((current_date-days.n)::timestamp+interval '6 hours') AT TIME ZONE 'Australia/Perth' AS candidate) AS shifts
 WHERE candidate < now()-interval '1 minute' AND pdc_bus_private.minute_available(candidate,bay);
 IF started_at IS NULL THEN RAISE EXCEPTION 'No available past Bus shift for completion fixture'; END IF;
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Category rollback fitter','technician',true);
 UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',2,1,'138','Battery Compartment & Relay Box Protection');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',1.5,2,'138','Pre-Delivery (Commercial)');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,3,'138','POST REGO BUS 4X4 CERTIFICATION');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',0,4,'138','95 LITRES OF FUEL');
 FOREACH cat IN ARRAY ARRAY['BUS_MECHANICAL','BUS_ELECTRICAL','BUS_QA'] LOOP
  bay:=pg_temp.ou_bay('completion-'||cat,'BUS_4X4',cat);
  UPDATE public.workshop_bays SET default_technician_id=NULL WHERE default_technician_id=tech AND id<>bay;
  UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
  SELECT max(candidate) INTO started_at FROM generate_series(0,14) AS days(n)
  CROSS JOIN LATERAL (SELECT ((current_date-days.n)::timestamp+interval '10 hours') AT TIME ZONE 'Australia/Perth' AS candidate) shifts
  WHERE candidate<now()-interval '1 minute' AND pdc_bus_private.minute_available(candidate,bay);
  PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4',jsonb_build_object('work_category',cat));
  b:=pg_temp.ou_booking(cat,v,'BUS_4X4',bay,started_at,'started');
  PERFORM set_config('pdc.work_category','',true);
  d:=public.get_fitter_job(tech,b);
  FOR l IN SELECT x FROM jsonb_array_elements(d->'lines') x LOOP
   d:=public.get_fitter_job(tech,b);
   r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'item_start',l->>'line_identity');
   IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Category item Start failed %',r; END IF;
   d:=public.get_fitter_job(tech,b);
   r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line',l->>'line_identity',true,'Verified category fixture');
   IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Category line failed %',r; END IF;
  END LOOP;
  d:=public.get_fitter_job(tech,b);
  PERFORM pg_temp.ou_assert((d#>>'{progress,can_complete}')::boolean,'Fitter can finish all '||cat,d->'progress');
  r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'complete');
  PERFORM pg_temp.ou_assert(r->>'ok'='true' AND pdc_work_categories_private.completed(v,cat),'Only completed scope is recorded: '||cat,r);
  PERFORM pg_temp.ou_assert((SELECT completed=(cat='BUS_QA') FROM public.vehicle_work_items WHERE vehicle_id=v AND work_key=(SELECT work_key FROM public.workshop_stages WHERE code='BUS_4X4')),'Whole Bus work completes only after final category: '||cat);
 END LOOP;
 op:=pg_temp.ou_operation(v,'BUS_4X4',0.5,5,'138','Battery Compartment & Relay Box Protection');
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v]);
 PERFORM pg_temp.ou_assert(NOT pdc_work_categories_private.completed(v,'BUS_MECHANICAL') AND pdc_work_categories_private.completed(v,'BUS_ELECTRICAL'),'New accepted operation reopens only its changed category');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.hours(v,'BUS_MECHANICAL')=0.5,'Reopened category excludes unchanged completed hours');
 PERFORM pg_temp.ou_assert((SELECT NOT completed AND required FROM public.vehicle_work_items WHERE vehicle_id=v AND work_key=(SELECT work_key FROM public.workshop_stages WHERE code='BUS_4X4')),'New accepted work restores outstanding work without changing completed bookings');
 PERFORM pg_temp.ou_assert((SELECT count(*)=3 FROM public.workshop_bookings WHERE vehicle_id=v AND status='completed'),'Completed category booking history remains intact');
 PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4','{"work_category":"BUS_MECHANICAL"}');
 bay:=pg_temp.ou_bay('completion-mechanical','BUS_4X4');
 UPDATE public.workshop_bays SET default_technician_id=NULL WHERE default_technician_id=tech AND id<>bay;
 UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
 b:=pg_temp.ou_booking('category-added-work',v,'BUS_4X4',bay,started_at,'started');
 PERFORM set_config('pdc.work_category','',true);
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert(jsonb_array_length(d->'lines')=1 AND (d#>>'{progress,total_hours}')::numeric=0.5,'Fitter receives only the new outstanding operation');
END $completion$;

DO $split$
DECLARE v uuid; bay uuid; b uuid; op uuid; r jsonb; t timestamptz; before_booking jsonb; before_line jsonb;
BEGIN
 v:=pg_temp.ou_vehicle('legacy-split'); bay:=pg_temp.ou_bay('legacy-split','BUS_4X4');
 op:=pg_temp.ou_operation(v,'BUS_4X4',2,1,'138','Battery Compartment & Relay Box Protection');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,2,'138','Pre-Delivery (Commercial)');
 SELECT (friday::timestamp+interval '7 days 6 hours') AT TIME ZONE 'Australia/Perth' INTO t FROM ou_context;
 b:=pg_temp.ou_booking('legacy-split',v,'BUS_4X4',bay,t);
 SELECT to_jsonb(x) INTO before_booking FROM public.workshop_bookings x WHERE id=b;
 SELECT l INTO before_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op;
 -- A legacy NULL-category booking still contains every Bus subcategory. Moving
 -- to Tint leaves that stage and is the release-confirmation case under r536.
 r:=public.set_vehicle_work_category(v,(SELECT version FROM public.vehicles WHERE id=v),'source:'||op,'TINT',0);
 PERFORM pg_temp.ou_assert(r->>'error'='confirm_release'
  AND (SELECT to_jsonb(x)=before_booking FROM public.workshop_bookings x WHERE id=b)
  AND (SELECT l=before_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op),
  'Legacy unstarted reservation and category remain unchanged until release is confirmed or explicitly split',
  jsonb_build_object('reply',r,'before_category',before_line->>'work_category','before_stage',before_line->>'stage_code',
   'booking_category',before_booking->>'work_category','booking_scope',before_booking->'work_category_scope',
   'booking_status',before_booking->>'status',
   'after_category',(SELECT l->>'work_category' FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op)));
 r:=public.split_bus_booking_to_categories(b,(SELECT version FROM public.workshop_bookings WHERE id=b));
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND EXISTS(SELECT 1 FROM public.workshop_bookings WHERE id=b AND deleted_at IS NOT NULL),'Split releases reservation and retains original booking history',r);
 r:=public.set_vehicle_work_category(v,(SELECT version FROM public.vehicles WHERE id=v),'source:'||op,'BUS_ACCESSORIES',0);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND pdc_work_categories_private.hours(v,'BUS_ACCESSORIES')=2,'Saved operator category keeps original hours');
 r:=public.set_vehicle_work_category(v,(SELECT version FROM public.vehicles WHERE id=v),'source:'||op,'BUS_MECHANICAL',0);
 PERFORM pg_temp.ou_assert(r->>'error'='category_version_conflict','Stale category edits are rejected');
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v]);
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.hours(v,'BUS_ACCESSORIES')=2,'Saved category survives a subsequent projection/reconciliation');
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('anon','public.split_bus_booking_to_categories(uuid,integer)','execute'),'Anonymous users cannot split bookings');
END $split$;
DO $explicit_whole_job_guard$
DECLARE v uuid; bay uuid; b uuid; op uuid; r jsonb; t timestamptz; mins integer; before_booking jsonb; before_line jsonb;
BEGIN
 v:=pg_temp.ou_vehicle('explicit-whole-job-guard'); bay:=pg_temp.ou_bay('explicit-whole-job-guard','BUS_4X4');
 op:=pg_temp.ou_operation(v,'BUS_4X4',2,1,'138','Battery Compartment & Relay Box Protection');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,2,'138','Pre-Delivery (Commercial)');
 SELECT (friday::timestamp+interval '21 days 6 hours') AT TIME ZONE 'Australia/Perth' INTO t FROM ou_context;
 mins:=round(pdc_work_categories_private.whole_job_hours_450(v,NULL)*60)::integer;
 r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'BUS_4X4',
  (SELECT bay_number FROM public.workshop_bays WHERE id=bay),t,mins,NULL,NULL,'{"work_category":"BUS_WHOLE_JOB"}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Current explicit whole-job fixture schedules',r);
 b:=(r#>>'{booking,booking_id}')::uuid;
 SELECT to_jsonb(x) INTO before_booking FROM public.workshop_bookings x WHERE id=b;
 SELECT l INTO before_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op;
 PERFORM pg_temp.ou_assert(before_booking->>'work_category'='BUS_WHOLE_JOB'
  AND (before_booking->'work_category_scope') ? ('source:'||op), 'Current whole-job fixture holds the exact source line');
 r:=public.set_vehicle_work_category(v,(SELECT version FROM public.vehicles WHERE id=v),'source:'||op,'BUS_ACCESSORIES',0,true);
 PERFORM pg_temp.ou_assert(r->>'error'='category_booking_exists'
  AND (SELECT to_jsonb(x)=before_booking FROM public.workshop_bookings x WHERE id=b)
  AND (SELECT l=before_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l WHERE l->>'line_identity'='source:'||op),
  'Explicit whole-job scope remains protected even with release confirmation',r);
END $explicit_whole_job_guard$;
DO $bookall$
DECLARE v uuid; r jsonb;
BEGIN
 v:=pg_temp.ou_vehicle('category-book-all');
 UPDATE public.vehicles SET model='Toyota Coaster',vehicle_description='Synthetic Coaster category fixture' WHERE id=v;
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Battery Compartment & Relay Box Protection');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',9,2,'138','Pre-Delivery (Commercial)');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,3,'138','POST REGO BUS 4X4 CERTIFICATION');
 r:=public.book_all_vehicle_stations(v,(SELECT version FROM public.vehicles WHERE id=v));
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT count(DISTINCT work_category)=3 FROM public.workshop_bookings WHERE vehicle_id=v AND deleted_at IS NULL),'Book all stations creates separate category bookings',r);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id WHERE b.vehicle_id=v AND NOT pdc_work_categories_private.preferred_bay(b.work_category,bay.bay_number)),'Book all chooses the category preferred bays');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id WHERE b.vehicle_id=v AND bay.bay_number=3),'Book all skips HiAce-only Bay 3 for a Coaster');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v AND NOT pdc_bus_private.minute_available(b.scheduled_start_at,b.bay_id)),'Book all starts every Bus category within its own bay shift');
 PERFORM pg_temp.ou_assert((SELECT (scheduled_end_at AT TIME ZONE 'Australia/Perth')::date>(scheduled_start_at AT TIME ZONE 'Australia/Perth')::date FROM public.workshop_bookings WHERE vehicle_id=v AND work_category='BUS_ELECTRICAL'),'Long Electrical category continues into another Bus shift');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'bookings') item JOIN public.workshop_bookings b ON b.id=(item->>'booking_id')::uuid WHERE (item->>'end_at')::timestamptz IS DISTINCT FROM b.scheduled_end_at),'Book all reports the same Bus shift finish that booking validation saves');
END $bookall$;
DO $incompatible_bookall$
DECLARE v uuid; r jsonb; rule jsonb; booking_count integer;
BEGIN
 v:=pg_temp.ou_vehicle('category-book-all-incompatible');
 UPDATE public.vehicles SET model='Toyota Coaster',vehicle_description='Synthetic incompatible-bay category fixture' WHERE id=v;
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Battery Compartment & Relay Box Protection');
 -- Exercise the real physical guard with only its incompatible Mechanical bay
 -- available. Restore bay configuration and any incidental effects afterward.
 BEGIN
  UPDATE public.workshop_bays SET is_active=(bay_number=3)
   WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='BUS_4X4') AND bay_number IN(1,2,3,4);
  SELECT pdc_bus_private.booking_rule(v,b.id,NULL) INTO STRICT rule FROM public.workshop_bays b
   JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='BUS_4X4' AND b.bay_number=3;
  r:=public.book_all_vehicle_stations(v,(SELECT version FROM public.vehicles WHERE id=v));
  SELECT count(*) INTO booking_count FROM public.workshop_bookings WHERE vehicle_id=v;
  RAISE EXCEPTION USING ERRCODE='PT002',MESSAGE='Restore incompatible-bay fixture configuration';
 EXCEPTION WHEN SQLSTATE 'PT002' THEN NULL;
 END;
 PERFORM pg_temp.ou_assert(rule->>'error'='bus_bay_vehicle_incompatible','Physical HiAce-only bay guard remains enforced');
 PERFORM pg_temp.ou_assert(r->>'ok'='false' AND r->>'error'='no_available_slot','Book all reports no slot when every preferred bay is incompatible',r);
 PERFORM pg_temp.ou_assert(booking_count=0,'Incompatible category booking leaves no partial reservation');
END $incompatible_bookall$;
DO $shared_override$
DECLARE v uuid; bay uuid; op uuid; r jsonb; t timestamptz;
BEGIN
 v:=pg_temp.ou_vehicle('shared-category-override'); bay:=pg_temp.ou_bay('shared-category-override','TINT');
 op:=pg_temp.ou_operation(v,'BUS_4X4',1.5,1,'138','Accessory work');
 r:=public.set_vehicle_work_category(v,(SELECT version FROM public.vehicles WHERE id=v),'source:'||op,'TINT',0);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND public.workshop_vehicle_stage_estimated_hours(v,'TINT')=1.5,'Shared category uses saved routing and exact original hours');
 SELECT (friday::timestamp+interval '6 hours') AT TIME ZONE 'Australia/Perth' INTO t FROM ou_context;
 r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'TINT',(SELECT bay_number FROM public.workshop_bays WHERE id=bay),t,90,NULL,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=90 FROM public.workshop_bookings WHERE id=(r#>>'{booking,booking_id}')::uuid),'Split shared work books through the ordinary shared station',r);
END $shared_override$;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE to_jsonb(b) IS DISTINCT FROM o.row_data),'Existing operational bookings unchanged');
SELECT name,status FROM ou_results ORDER BY name;
ROLLBACK;
