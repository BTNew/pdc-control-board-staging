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
 VALUES(bid,vid,sid,bay,state,start_at,CASE WHEN stage='BUS_4X4' THEN pdc_bus_private.add_minutes(start_at,mins,bay) ELSE public.workshop_add_operational_minutes(start_at,mins) END,mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;



CREATE FUNCTION pg_temp.rg_assignment(bid uuid, tech uuid, kind text DEFAULT 'secondary')
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT bid,tech,kind::public.workshop_assignment_type,auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=bid;
END $fn$;

CREATE FUNCTION pg_temp.rg_fitter_case(category text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v uuid; other_v uuid; bay uuid; b uuid; next_b uuid; extra_op uuid; tech uuid:=gen_random_uuid();
 stage text; at_time timestamptz; d jsonb; r jsonb; request uuid:=gen_random_uuid(); ver integer; catalog text;
 root_before jsonb; extra_before jsonb; root_after jsonb; result_source jsonb; end_at timestamptz; base_minutes integer; grown_minutes integer; follower_before jsonb;
BEGIN
 stage:=CASE WHEN category='HOIST' THEN 'HOIST' ELSE 'BUS_4X4' END;
 v:=pg_temp.ou_vehicle('fitter-'||category);other_v:=pg_temp.ou_vehicle('fitter-follower-'||category);
 bay:=pg_temp.ou_bay('fitter-'||category,stage,category);
 INSERT INTO public.workshop_technicians(id,name,role_type,active,can_fit_stages)
 VALUES(tech,'Rollback growth fitter '||tech,'technician',true,ARRAY['HOIST','FITTING','BUS_4X4','TINT']);
 IF stage='BUS_4X4' THEN
  PERFORM pg_temp.ou_operation(v,stage,CASE WHEN category='BUS_WHOLE_JOB' THEN 0.5 ELSE 1 END,1,'138',
   CASE WHEN category='BUS_ELECTRICAL' THEN 'Pre-Delivery (Commercial)' ELSE 'Coaster Bus 4x4 Conversion - 6 Speed 2.8' END);
  IF category='BUS_WHOLE_JOB' THEN PERFORM pg_temp.ou_operation(v,stage,0.5,2,'138','Pre-Delivery (Commercial)'); END IF;
  extra_op:=pg_temp.ou_operation(v,'TINT',5,3,'138','Window tint');
  PERFORM pg_temp.ou_operation(other_v,stage,1,1,'138',
   CASE WHEN category='BUS_ELECTRICAL' THEN 'Pre-Delivery (Commercial)' ELSE 'Coaster Bus 4x4 Conversion - 6 Speed 2.8' END);
 ELSE
  PERFORM pg_temp.ou_operation(v,stage,1);
  extra_op:=pg_temp.ou_operation(v,'FITTING',5,2);
  PERFORM pg_temp.ou_operation(other_v,stage,1);
 END IF;
 at_time:=((date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+185)+time '13:00') AT TIME ZONE 'Australia/Perth';
 IF stage='BUS_4X4' THEN at_time:=pdc_bus_private.clock_next_minute(at_time,bay);
 ELSE at_time:=public.workshop_admin_next_operational_minute(at_time); END IF;
 IF stage='BUS_4X4' THEN PERFORM pdc_work_categories_private.set_context(v,stage,jsonb_build_object('work_category',category)); END IF;
 -- Planned setup captures the actual capacity basis before the synthetic Start.
 b:=pg_temp.ou_booking('fitter-'||category,v,stage,bay,at_time,'planned');
 PERFORM set_config('pdc.work_category','',true);
 UPDATE public.workshop_bookings SET status='started',actual_start_at=at_time,version=version+1 WHERE id=b;
 PERFORM pg_temp.rg_assignment(b,tech,'primary');
 IF stage='BUS_4X4' THEN PERFORM pdc_work_categories_private.set_context(other_v,stage,jsonb_build_object('work_category',CASE WHEN category='BUS_WHOLE_JOB' THEN 'BUS_MECHANICAL' ELSE category END)); END IF;
 next_b:=pg_temp.ou_booking('fitter-follower-'||category,other_v,stage,bay,
  CASE WHEN stage='BUS_4X4' THEN pdc_bus_private.clock_next_minute(pdc_bus_private.add_minutes(at_time,120,bay),bay) ELSE public.workshop_add_operational_minutes(at_time,120) END,'planned');
 PERFORM set_config('pdc.work_category','',true);
 SELECT to_jsonb(x) INTO root_before FROM public.workshop_bookings x WHERE id=b;
 SELECT to_jsonb(x) INTO follower_before FROM public.workshop_bookings x WHERE id=next_b;
 SELECT to_jsonb(x) INTO extra_before FROM public.pdc_pilbara_service_operations x WHERE operation_id=extra_op;
 base_minutes:=(root_before->>'default_duration_minutes')::int;grown_minutes:=base_minutes+300;
 PERFORM pg_temp.ou_assert(base_minutes=public.workshop_booking_effective_duration_minutes(b) AND base_minutes>0
  AND (category='BUS_WHOLE_JOB' OR base_minutes=60),'Fitter fixture preserves canonical capacity basis '||category,root_before-'metadata');
 IF category='BUS_WHOLE_JOB' THEN PERFORM pg_temp.ou_assert(root_before->>'work_category'='BUS_WHOLE_JOB'
  AND (SELECT count(*)=2 FROM jsonb_object_keys(root_before->'work_category_scope')),'Whole job captured both original Bus lines'); END IF;
 d:=public.get_fitter_job(tech,b);
 IF stage='BUS_4X4' THEN
  -- The installed r450 outer catalog intentionally limits a Bus reservation
  -- to its category/held whole-job scope. r532 broadens the underlying catalog,
  -- but does not grant a Mechanical/Electrical/whole-job fitter access to Tint.
  PERFORM pg_temp.ou_assert(jsonb_array_length(d->'lines')>0 AND NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(d->'lines') l WHERE l->>'line_identity'='source:'||extra_op),
   'Bus fitter retains its category scope '||category);
  r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'item_start','source:'||extra_op,NULL,NULL);
  PERFORM pg_temp.ou_assert(r->>'ok'='false' AND r->>'error'='line_unavailable',
   'Bus refuses foreign-scope item Start '||category,r);
  r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line','source:'||extra_op,true,'Foreign-scope refusal fixture');
  PERFORM pg_temp.ou_assert(r->>'ok'='false' AND r->>'error'='line_unavailable',
   'Bus refuses foreign-scope Done '||category,r);
  PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=root_before FROM public.workshop_bookings x WHERE id=b)
   AND (SELECT to_jsonb(x)=follower_before FROM public.workshop_bookings x WHERE id=next_b)
   AND (SELECT to_jsonb(x)=extra_before FROM public.pdc_pilbara_service_operations x WHERE operation_id=extra_op)
   AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=b AND line_identity='source:'||extra_op)
   AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_timing WHERE booking_id=b AND line_identity='source:'||extra_op),
   'Foreign-scope refusal preserves work hours allocations and item timing '||category);
  PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings x ON x.id=o.id WHERE to_jsonb(x) IS DISTINCT FROM o.row_data),
   'Bus scope checks preserve copied operational bookings '||category);
  RETURN;
 END IF;
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(d->'lines') l WHERE l->>'line_identity'='source:'||extra_op),
  'Fitter catalog exposes permitted extra station '||category,d->'error');
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'item_start','source:'||extra_op,NULL,NULL);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Fitter starts extra station item '||category,r);
 d:=public.get_fitter_job(tech,b);ver:=(d->>'version')::int;catalog:=d->>'catalog_hash';
 r:=public.fitter_job_command(tech,b,ver,catalog,request,'line','source:'||extra_op,true,'Owned rollback growth fixture');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Fitter saves extra station item '||category,r);
 SELECT to_jsonb(x) INTO root_after FROM public.workshop_bookings x WHERE id=b;
 end_at:=CASE WHEN stage='BUS_4X4' THEN pdc_bus_private.add_minutes(at_time,grown_minutes,bay) ELSE public.workshop_add_operational_minutes(at_time,grown_minutes) END;
 PERFORM pg_temp.ou_assert((root_after->>'default_duration_minutes')::int=grown_minutes AND (root_after->>'scheduled_end_at')::timestamptz=end_at
  AND root_after->>'scheduled_start_at'=root_before->>'scheduled_start_at'
  AND root_after->>'actual_start_at'=root_before->>'actual_start_at' AND root_after->>'status'='started',
  'Extra work extends exactly once with fixed start and correct close calendar '||category,root_after-'metadata');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at>=end_at FROM public.workshop_bookings WHERE id=next_b),
  'Extra work cascades follower '||category);
 r:=public.fitter_job_command(tech,b,ver,catalog,request,'line','source:'||extra_op,true,'Owned rollback growth fixture');
 PERFORM pg_temp.ou_assert(r->>'replayed'='true' AND (SELECT to_jsonb(x)=root_after FROM public.workshop_bookings x WHERE id=b),
  'Extra work receipt replay does not inflate allocation '||category,r);
 r:=public.workshop_extend_running_booking_538(b,'repeat_extra_proof',NULL);
 PERFORM pg_temp.ou_assert(r->>'extended'='false' AND (SELECT to_jsonb(x)=root_after FROM public.workshop_bookings x WHERE id=b),
  'Rechecking identical extra work never counts it twice '||category,r);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=extra_before FROM public.pdc_pilbara_service_operations x WHERE operation_id=extra_op),
  'Fitter growth preserves imported source hours '||category);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings x ON x.id=o.id WHERE to_jsonb(x) IS DISTINCT FROM o.row_data),
  'Fitter scenario preserves copied operational bookings '||category);
END $fn$;

SAVEPOINT fitter_case;
SELECT pg_temp.rg_fitter_case('HOIST');
SELECT jsonb_build_object('scenario','HOIST fitter extra','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK TO fitter_case;
SELECT pg_temp.rg_fitter_case('BUS_MECHANICAL');
SELECT jsonb_build_object('scenario','Bus Mechanical category isolation','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK TO fitter_case;
SELECT pg_temp.rg_fitter_case('BUS_ELECTRICAL');
SELECT jsonb_build_object('scenario','Bus Electrical category isolation','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK TO fitter_case;
SELECT pg_temp.rg_fitter_case('BUS_WHOLE_JOB');
SELECT jsonb_build_object('scenario','Bus whole-job category isolation','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK;
