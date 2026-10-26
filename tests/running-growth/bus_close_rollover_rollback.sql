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



-- Positive Bus close rollover. Mechanical/Electrical use the actual category
-- setter. Whole-job is explicitly a private planner contract test: it does not
-- claim that a category endpoint accepts BUS_WHOLE_JOB or foreign fitter work.
CREATE FUNCTION pg_temp.rg_bus_close(category text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v uuid; next_v uuid; bay uuid; b uuid; nextb uuid; op uuid; tech uuid:=gen_random_uuid();
 at_time timestamptz; expected_end timestamptz; ver integer; base_minutes integer; grown_minutes integer; invocation text;
 root_before jsonb; next_before jsonb; source_before jsonb; assignments_before jsonb; history_before jsonb; r jsonb;
BEGIN
 v:=pg_temp.ou_vehicle('close-root-'||category);next_v:=pg_temp.ou_vehicle('close-follower-'||category);
 bay:=pg_temp.ou_bay('close-'||category,'BUS_4X4',category);
 IF category='BUS_ELECTRICAL' THEN
  PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Pre-Delivery (Commercial)');
  op:=pg_temp.ou_operation(v,'BUS_4X4',5,2,'138','Coaster Bus 4x4 Conversion - 6 Speed 2.8');
  PERFORM pg_temp.ou_operation(next_v,'BUS_4X4',1,1,'138','Pre-Delivery (Commercial)');
 ELSE
  PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,1,'138','Coaster Bus 4x4 Conversion - 6 Speed 2.8');
  op:=pg_temp.ou_operation(v,'BUS_4X4',CASE WHEN category='BUS_WHOLE_JOB' THEN 1 ELSE 5 END,2,'138','Pre-Delivery (Commercial)');
  PERFORM pg_temp.ou_operation(next_v,'BUS_4X4',1,1,'138','Coaster Bus 4x4 Conversion - 6 Speed 2.8');
 END IF;
 base_minutes:=CASE WHEN category='BUS_WHOLE_JOB' THEN round(pdc_work_categories_private.whole_job_hours_450(v,NULL)*60)::integer
  ELSE round(pdc_work_categories_private.hours(v,category)*60)::integer END;
 -- Select an actually open 13:00 on the configured calendar, rather than
 -- assuming a holiday-free date or treating a close boundary as a valid start.
 SELECT min(candidate) INTO at_time FROM generate_series(182,196) days(n)
 CROSS JOIN LATERAL (SELECT ((date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+days.n)+time '13:00') AT TIME ZONE 'Australia/Perth' candidate) dates
 WHERE pdc_bus_private.minute_available(candidate,bay)
  AND (pdc_bus_private.add_minutes(candidate,base_minutes,bay) AT TIME ZONE 'Australia/Perth')::date=(candidate AT TIME ZONE 'Australia/Perth')::date;
 IF at_time IS NULL THEN RAISE EXCEPTION 'Fixture capability missing: open Bus 13:00 with original scope fitting before close'; END IF;
 PERFORM pdc_work_categories_private.set_context(v,'BUS_4X4',jsonb_build_object('work_category',category));
 b:=pg_temp.ou_booking('close-root-'||category,v,'BUS_4X4',bay,at_time,'planned');
 PERFORM set_config('pdc.work_category','',true);
 UPDATE public.workshop_bookings SET status='started',actual_start_at=at_time,version=version+1 WHERE id=b;
 PERFORM pdc_work_categories_private.set_context(next_v,'BUS_4X4',
  jsonb_build_object('work_category',CASE WHEN category='BUS_WHOLE_JOB' THEN 'BUS_MECHANICAL' ELSE category END));
 nextb:=pg_temp.ou_booking('close-follower-'||category,next_v,'BUS_4X4',bay,
  pdc_bus_private.clock_next_minute(pdc_bus_private.add_minutes(at_time,base_minutes+60,bay),bay),'planned');
 PERFORM set_config('pdc.work_category','',true);
 INSERT INTO public.workshop_technicians(id,name,role_type,active,can_fit_stages)
 VALUES(tech,'Owned Bus close technician '||tech,'technician',true,ARRAY['BUS_4X4']);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,tech,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id IN(b,nextb);
 SELECT to_jsonb(x) INTO root_before FROM public.workshop_bookings x WHERE id=b;
 SELECT to_jsonb(x) INTO next_before FROM public.workshop_bookings x WHERE id=nextb;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY operation_id) INTO source_before FROM public.pdc_pilbara_service_operations x WHERE vehicle_id IN(v,next_v);
 SELECT jsonb_agg(to_jsonb(x) ORDER BY id) INTO assignments_before FROM public.workshop_booking_assignments x WHERE booking_id IN(b,nextb);
 PERFORM public.workshop_write_history(b,'operation_change_schedule_updated',public.workshop_booking_snapshot(b),public.workshop_booking_snapshot(b),
  '{"source":"owned_bus_calendar_prior_history"}');
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') INTO history_before FROM public.workshop_booking_history x WHERE booking_id IN(b,nextb);
 base_minutes:=(root_before->>'default_duration_minutes')::integer;
 grown_minutes:=base_minutes+300;
 expected_end:=pdc_bus_private.add_minutes(at_time,grown_minutes,bay);
 PERFORM pg_temp.ou_assert(base_minutes>0 AND base_minutes=public.workshop_booking_effective_duration_minutes(b)
  AND (category='BUS_WHOLE_JOB' OR base_minutes=60),'Original canonical scope and allocation agree '||category);
 IF category='BUS_WHOLE_JOB' THEN
  PERFORM pg_temp.ou_assert(root_before->>'work_category'='BUS_WHOLE_JOB'
   AND (SELECT count(*)=2 FROM jsonb_object_keys(root_before->'work_category_scope')),'Whole-job holds both original category lines before growth');
  invocation:='private explicit-duration planner';
  r:=pdc_operation_updates_private.reconcile_running_growth_20261026(b,grown_minutes,auth.uid(),'owned_bus_whole_job_close_probe');
  PERFORM pg_temp.ou_assert((r->>'changed_count')::integer=2,'Private whole-job planner grows root and moves follower',r);
 ELSE
  invocation:='actual category endpoint';
  SELECT version INTO ver FROM public.vehicles WHERE id=v;
  r:=public.set_vehicle_work_category(v,ver,'source:'||op,category,0,true,NULL);
  PERFORM pg_temp.ou_assert(r->>'ok'='true','Actual category endpoint grows across Bus close '||category,r);
 END IF;
 PERFORM pg_temp.ou_assert((expected_end AT TIME ZONE 'Australia/Perth')::date>(at_time AT TIME ZONE 'Australia/Perth')::date
  AND pdc_bus_private.minute_available(expected_end-interval '1 minute',bay),
  'Extended finish crosses close and ends in configured working time '||category,
  jsonb_build_object('invocation',invocation,'start',at_time,'expected_end',expected_end,'minutes',grown_minutes));
 PERFORM pg_temp.ou_assert((SELECT status='started' AND actual_start_at=(root_before->>'actual_start_at')::timestamptz
  AND scheduled_start_at=(root_before->>'scheduled_start_at')::timestamptz AND scheduled_end_at=expected_end
  AND default_duration_minutes=grown_minutes AND work_category=category
  AND work_category_scope IS NOT DISTINCT FROM root_before->'work_category_scope'
  FROM public.workshop_bookings WHERE id=b),'Close rollover preserves start lifecycle scope and exact allocated minutes '||category);
 PERFORM pg_temp.ou_assert((SELECT status='planned' AND actual_start_at IS NULL AND scheduled_start_at>=expected_end
  AND scheduled_start_at>(next_before->>'scheduled_start_at')::timestamptz
  AND pdc_bus_private.minute_available(scheduled_start_at,bay)
  AND scheduled_end_at=pdc_bus_private.add_minutes(scheduled_start_at,default_duration_minutes,bay)
  AND default_duration_minutes=(next_before->>'default_duration_minutes')::integer
  FROM public.workshop_bookings WHERE id=nextb),'Planned follower moves to its next valid Bus interval '||category);
 PERFORM pg_temp.ou_assert((SELECT jsonb_agg(to_jsonb(x)-ARRAY['scheduled_start_at','scheduled_end_at','updated_at'] ORDER BY id)
  FROM public.workshop_booking_assignments x WHERE booking_id IN(b,nextb))
  =(SELECT jsonb_agg(x-ARRAY['scheduled_start_at','scheduled_end_at','updated_at'] ORDER BY x->>'id') FROM jsonb_array_elements(assignments_before) x)
  AND NOT EXISTS(SELECT 1 FROM public.workshop_booking_assignments x JOIN public.workshop_bookings q ON q.id=x.booking_id
   WHERE x.booking_id IN(b,nextb) AND (x.scheduled_start_at<>q.scheduled_start_at OR x.scheduled_end_at<>q.scheduled_end_at)),
  'Close rollover preserves technician assignment identities and exact booking ranges '||category);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(history_before) old
  LEFT JOIN public.workshop_booking_history h ON h.id=(old->>'id')::uuid WHERE to_jsonb(h) IS DISTINCT FROM old)
  AND (SELECT count(*)=2 FROM public.workshop_booking_history WHERE booking_id IN(b,nextb) AND metadata->>'source'='running_growth_cascade_20261026'),
  'Existing history remains exact and both calendar moves append history '||category);
 PERFORM pg_temp.ou_assert(source_before=(SELECT jsonb_agg(to_jsonb(x) ORDER BY operation_id) FROM public.pdc_pilbara_service_operations x WHERE vehicle_id IN(v,next_v)),
  'Close rollover preserves every imported source row and original hour '||category);
 r:=public.workshop_extend_running_booking_538(b,'owned_bus_close_repeat',NULL);
 PERFORM pg_temp.ou_assert(r->>'extended'='false' AND (SELECT default_duration_minutes=grown_minutes AND scheduled_end_at=expected_end FROM public.workshop_bookings WHERE id=b),
  'Public helper repeat does not double count or shorten closed-calendar allocation '||category,r);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings x ON x.id=o.id WHERE to_jsonb(x) IS DISTINCT FROM o.row_data),
  'Close rollover leaves copied operational bookings unchanged '||category);
END $fn$;
SAVEPOINT close_case;
SELECT pg_temp.rg_bus_close('BUS_MECHANICAL');
SELECT jsonb_build_object('scenario','Bus Mechanical close via actual category endpoint','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK TO close_case;
SELECT pg_temp.rg_bus_close('BUS_ELECTRICAL');
SELECT jsonb_build_object('scenario','Bus Electrical close via actual category endpoint','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK TO close_case;
SELECT pg_temp.rg_bus_close('BUS_WHOLE_JOB');
SELECT jsonb_build_object('scenario','Bus whole-job close via private planner','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK;

