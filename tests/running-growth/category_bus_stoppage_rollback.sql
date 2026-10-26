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



DO $allowed_category_growth$
DECLARE v uuid; follower uuid; bay uuid; b uuid; nextb uuid; qb uuid; qbay uuid; tech uuid:=gen_random_uuid(); op uuid; at_time timestamptz; ver integer; result jsonb;
 before_root jsonb; before_next jsonb; before_queue jsonb; before_source jsonb; before_queue_assignments jsonb; before_queue_history jsonb;
BEGIN
 v:=pg_temp.ou_vehicle('allowed-root-bus-stoppage'); follower:=pg_temp.ou_vehicle('allowed-follower-bus-stoppage');

 bay:=pg_temp.ou_bay('allowed-growth-bus','BUS_4X4','BUS_MECHANICAL');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Coaster Bus 4x4 Conversion - 6 Speed 2.8');
 op:=pg_temp.ou_operation(v,'BUS_4X4',5,2,'138','Pre-Delivery (Commercial)');
 PERFORM pg_temp.ou_operation(v,'TINT',1,3,'138','Darkest legal window tint');
 PERFORM pg_temp.ou_operation(follower,'BUS_4X4',1,1,'138','Coaster Bus 4x4 Conversion - 6 Speed 2.8');
 PERFORM pg_temp.ou_assert(pdc_work_categories_private.hours(v,'BUS_MECHANICAL')=1
  AND pdc_work_categories_private.hours(v,'BUS_ELECTRICAL')=5,
  'original Mechanical and Electrical categories are separate');
 at_time:=pdc_bus_private.clock_next_minute(((date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+182)+time '06:00') AT TIME ZONE 'Australia/Perth',bay);
 PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4','{"work_category":"BUS_MECHANICAL"}');
 b:=pg_temp.ou_booking('allowed-root',v,'BUS_4X4',bay,at_time,'started');
 PERFORM set_config('pdc.work_category','',true);
 PERFORM pdc_work_categories_private.set_context(follower,'BUS_4X4','{"work_category":"BUS_MECHANICAL"}');
 nextb:=pg_temp.ou_booking('allowed-follower',follower,'BUS_4X4',bay,pdc_bus_private.add_minutes(at_time,120,bay),'planned');
 PERFORM set_config('pdc.work_category','',true);


 UPDATE public.workshop_bookings SET status='stoppage',stoppage_reason='Synthetic allowed growth pause',
  stoppage_started_at=public.workshop_add_operational_minutes(at_time,15),version=version+1 WHERE id=b;

 -- Establish canonical returned history through the actual API. The same
 -- technician's old TINT interval will overlap the expanded root, but its
 -- released assignment must retain history without reserving capacity.
 qbay:=pg_temp.ou_bay('allowed-return-tint','TINT');
 qb:=pg_temp.ou_booking('allowed-bayless-history',v,'TINT',qbay,public.workshop_add_operational_minutes(at_time,180),'planned');
 INSERT INTO public.workshop_technicians(id,name,role_type,active)
 VALUES(tech,'Synthetic allowed growth history '||tech,'technician',true);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,tech,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id IN(b,qb);
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=qb;
 result:=public.return_work_to_queue(qb,ver,NULL,'{"source":"allowed_growth_return_history"}');
 PERFORM pg_temp.ou_assert(result->>'ok'='true','actual return API establishes canonical bayless history',result);
 PERFORM pg_temp.ou_assert((SELECT status='queued' AND bay_id IS NULL FROM public.workshop_bookings WHERE id=qb)
  AND EXISTS(SELECT 1 FROM public.workshop_booking_assignments WHERE booking_id=qb AND technician_id=tech AND released_at IS NOT NULL)
  AND NOT EXISTS(SELECT 1 FROM public.workshop_booking_assignments WHERE booking_id=qb AND released_at IS NULL),
  'returned booking retains released technician assignment and has no active reservation');
 SELECT to_jsonb(x) INTO before_root FROM public.workshop_bookings x WHERE id=b;
 SELECT to_jsonb(x) INTO before_next FROM public.workshop_bookings x WHERE id=nextb;
 SELECT to_jsonb(x) INTO before_queue FROM public.workshop_bookings x WHERE id=qb;
 SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) INTO before_queue_assignments FROM public.workshop_booking_assignments a WHERE booking_id=qb;
 SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) INTO before_queue_history FROM public.workshop_booking_history h WHERE booking_id=qb;
 SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_id) INTO before_source
  FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id IN(v,follower);
 PERFORM pg_temp.ou_assert(before_root->>'status'='stoppage' AND (before_root->>'default_duration_minutes')::integer=60,
  'one-hour root fixture has the requested lifecycle state',before_root-'vehicle_id'-'id');
 SELECT version INTO ver FROM public.vehicles WHERE id=v;
 result:=public.set_vehicle_work_category(v,ver,'source:'||op,'BUS_MECHANICAL',0,true,NULL);
 PERFORM pg_temp.ou_assert(result->>'ok'='true','actual category setter accepts allowed growth bus-stoppage',result);
 PERFORM pg_temp.ou_assert((SELECT status='stoppage' AND scheduled_start_at=(before_root->>'scheduled_start_at')::timestamptz
  AND actual_start_at=(before_root->>'actual_start_at')::timestamptz
  AND stoppage_started_at IS NOT DISTINCT FROM (before_root->>'stoppage_started_at')::timestamptz
  AND stoppage_reason IS NOT DISTINCT FROM before_root->>'stoppage_reason'
  AND default_duration_minutes=360 AND scheduled_end_at=pdc_bus_private.add_minutes(scheduled_start_at,360,bay)
  FROM public.workshop_bookings WHERE id=b),'root finish grows by five work hours with lifecycle, pause and start preserved');
 PERFORM pg_temp.ou_assert((SELECT status='planned' AND actual_start_at IS NULL
  AND default_duration_minutes=(before_next->>'default_duration_minutes')::integer
  AND scheduled_start_at>(before_next->>'scheduled_start_at')::timestamptz
  AND scheduled_start_at>=(SELECT scheduled_end_at FROM public.workshop_bookings WHERE id=b)
  FROM public.workshop_bookings WHERE id=nextb),'planned follower cascades forward with work duration retained');
 PERFORM pg_temp.ou_assert(before_queue=(SELECT to_jsonb(x) FROM public.workshop_bookings x WHERE id=qb),
  'bayless unrelated queued reservation retains exact history without blocking growth');
 PERFORM pg_temp.ou_assert(before_queue_assignments=(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.workshop_booking_assignments a WHERE booking_id=qb)
  AND before_queue_history=(SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM public.workshop_booking_history h WHERE booking_id=qb),
  'released assignment intervals and complete returned audit history remain unchanged');
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.workshop_booking_assignments a JOIN public.workshop_bookings r ON r.id=a.booking_id
  WHERE r.id=b AND a.technician_id=tech AND a.released_at IS NULL AND a.scheduled_start_at=r.scheduled_start_at AND a.scheduled_end_at=r.scheduled_end_at),
  'running technician assignment extends with the root despite overlapping released history');
 PERFORM pg_temp.ou_assert(before_source=(SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_id)
  FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id IN(v,follower)),
  'all imported source operations and original hours remain byte-equivalent JSON');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o FULL JOIN
  (SELECT id,to_jsonb(x) row_data FROM public.workshop_bookings x WHERE id IN(SELECT id FROM ou_original_bookings))n USING(id)
  WHERE o.row_data IS DISTINCT FROM n.row_data),'existing customer bookings unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o FULL JOIN
  (SELECT id,to_jsonb(x) row_data FROM public.vehicles x WHERE id IN(SELECT id FROM ou_original_vehicles))n USING(id)
  WHERE o.row_data IS DISTINCT FROM n.row_data),'existing customer vehicles unchanged');
END $allowed_category_growth$;
SELECT jsonb_build_object('status','PASS','scenario','bus-stoppage','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK;
