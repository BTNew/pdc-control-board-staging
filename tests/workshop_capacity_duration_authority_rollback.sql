-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the operation-approval migration.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';

-- APPLY CANDIDATE MIGRATIONS HERE FOR ROLLBACK REVIEW.
DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

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

CREATE FUNCTION pg_temp.ou_bay(tag text, stage text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE b uuid:=gen_random_uuid(); sid uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage AND active;
 INSERT INTO public.workshop_bays(id,stage_id,code,display_name,is_active)
 VALUES(b,sid,'OU-'||b,'Rollback fixture '||tag,true);
 INSERT INTO ou_refs VALUES('bay-'||tag,b);
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department','139','operation_description','Fixture work '||stage||' line '||line_no,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{}','insert','rollback_original',vid);
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(op,'pilbara_service_open_jobcards_v1',v.stock_number,v.job_card_number,line_no,line_no,vid,p->>'operation_description',hrs,hrs,'source_explicit','review','Review',repeat('c',64),ev,'139',stage);
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
 mins:=CASE WHEN state IN('queued','planned') THEN public.workshop_capacity_duration_minutes(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid),bay) ELSE public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid) END;
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;



-- Candidate schema + helper migrations may be prepended after BEGIN when reviewing before deployment.
CREATE TEMP TABLE capacity_original_bays AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bays b;
CREATE TEMP TABLE capacity_original_operations AS SELECT operation_id,to_jsonb(o) row_data FROM public.pdc_pilbara_service_operations o;

DO $checks$
DECLARE vid uuid; bay80 uuid; bay100 uuid; sid uuid; bid uuid; x uuid; r jsonb; oldjson jsonb; starts timestamptz; test_version integer;
 quoted integer; orig integer; dstn integer; opid uuid; liveid uuid; lv uuid;
BEGIN
 SELECT id INTO sid FROM public.workshop_stages WHERE code='FITTING';
 starts:=((SELECT friday FROM ou_context)+3)::timestamp AT TIME ZONE 'Australia/Perth'+interval '7 hours';
 bay80:=pg_temp.ou_bay('capacity-80','FITTING'); bay100:=pg_temp.ou_bay('capacity-100','FITTING');
 UPDATE public.workshop_bays SET efficiency_percent=80,bay_number=(SELECT coalesce(max(bay_number),0)+1 FROM public.workshop_bays WHERE stage_id=sid) WHERE id=bay80;
 UPDATE public.workshop_bays SET bay_number=(SELECT coalesce(max(bay_number),0)+1 FROM public.workshop_bays WHERE stage_id=sid) WHERE id=bay100;
 PERFORM pg_temp.ou_assert(public.workshop_capacity_duration_minutes(240,bay100)=240,'100 percent keeps four quoted hours');
 PERFORM pg_temp.ou_assert(public.workshop_capacity_duration_minutes(240,bay80)=300,'80 percent allocates five hours');
 PERFORM pg_temp.ou_assert(public.workshop_capacity_duration_minutes(24,bay80)=30,'Short work scales exactly');
 PERFORM pg_temp.ou_assert(public.workshop_capacity_duration_minutes(1,bay80)=2,'Fractional allocation rounds upward once');
 vid:=pg_temp.ou_vehicle('capacity-main'); opid:=pg_temp.ou_operation(vid,'FITTING',4);
 bid:=pg_temp.ou_booking('capacity-main',vid,'FITTING',bay80,starts);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=300 AND capacity_base_minutes=240 AND capacity_efficiency_percent=80 AND capacity_estimate_minutes=240 FROM public.workshop_bookings WHERE id=bid),'Initial booking captures base quote and applied factor');
 PERFORM pg_temp.ou_assert(public.workshop_booking_effective_duration_minutes(bid)=300,'Clock reads allocated planned duration');
 SELECT to_jsonb(b) INTO oldjson FROM public.workshop_bookings b WHERE id=bid;
 UPDATE public.workshop_bays SET efficiency_percent=50 WHERE id=bay80;
 PERFORM pg_temp.ou_assert(public.workshop_booking_effective_duration_minutes(bid)=300 AND public.workshop_booking_capacity_duration_minutes(bid,vid,sid,bay80)=480,'Changing bay factor does not extend unmoved blockers');
 UPDATE public.workshop_bays SET efficiency_percent=80 WHERE id=bay80;
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(b)=oldjson FROM public.workshop_bookings b WHERE id=bid),'Factor preview leaves booking unchanged');

 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 r:=public.resize_workshop_booking(bid,test_version,360,'{"source":"capacity_rollback_manual"}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Manual allocation resize is accepted',r);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=360 AND capacity_base_minutes=288 AND capacity_estimate_minutes=240 FROM public.workshop_bookings WHERE id=bid),'Manual resize stores exact inverse base without changing quote');
 PERFORM pg_temp.ou_assert(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid)=240 AND public.workshop_booking_effective_duration_minutes(bid)=360,'Manual allocation remains independent from source hours');
 PERFORM pg_temp.ou_assert(current_setting('pdc.workshop_capacity_manual',true)='','Manual context is cleared after success');
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 BEGIN
  r:=public.resize_workshop_booking(bid,test_version,299,'{}');
  PERFORM pg_temp.ou_assert(false,'Manual allocation cannot shrink below quoted work',r);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL Manual allocation cannot%' THEN RAISE; END IF;
  PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=360 AND b.version=test_version FROM public.workshop_bookings b WHERE id=bid),'Rejected too-short resize is atomic',jsonb_build_object('error',SQLERRM));
 END;
 PERFORM pg_temp.ou_assert(public.workshop_booking_capacity_base_minutes(bid)=288,'Failed resize does not change durable base');

 PERFORM pg_temp.ou_operation(vid,'FITTING',1,2);
 r:=public.pdc_tune_reconcile_booking_plan_20260913(vid,ARRAY['FITTING'],gen_random_uuid());
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=435 AND capacity_base_minutes=348 AND capacity_estimate_minutes=300 FROM public.workshop_bookings WHERE id=bid),'New operation extends quote delta plus existing manual base',r);
 PERFORM pg_temp.ou_assert(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid)=300,'Operation quote remains five hours after capacity reconciliation');
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 r:=public.pdc_tune_reconcile_booking_plan_20260913(vid,ARRAY['FITTING'],gen_random_uuid());
 PERFORM pg_temp.ou_assert((r->>'changed_count')::integer=0 AND (SELECT b.version=test_version FROM public.workshop_bookings b WHERE id=bid),'Repeated import reconciliation does not compound');
 SELECT bay_number INTO dstn FROM public.workshop_bays WHERE id=bay100;
 r:=public.workshop_move_booking(bid,test_version,'FITTING',dstn,starts,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=348 AND capacity_base_minutes=348 AND capacity_efficiency_percent=100 FROM public.workshop_bookings WHERE id=bid),'Moving to normal bay uses durable base',r);
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 SELECT bay_number INTO dstn FROM public.workshop_bays WHERE id=bay80;
 r:=public.workshop_move_booking(bid,test_version,'FITTING',dstn,starts,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=435 AND capacity_base_minutes=348 AND capacity_efficiency_percent=80 FROM public.workshop_bookings WHERE id=bid),'Moving back to slower bay does not compound',r);
 PERFORM pg_temp.ou_assert((r#>>'{booking,capacity_base_minutes}')::numeric=348 AND (r#>>'{booking,capacity_efficiency_percent}')::integer=80,'Mutation snapshot exposes durable basis');
 r:=public.workshop_overlay_canonical_booking_fields_397(jsonb_build_object('bookings',jsonb_build_array(jsonb_build_object('booking_id',bid))));
 PERFORM pg_temp.ou_assert((r#>>'{bookings,0,capacity_base_minutes}')::numeric=348 AND (r#>>'{bookings,0,default_duration_minutes}')::integer=435,'Station snapshot exposes base and allocation separately');


 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 r:=public.set_workshop_stage_estimated_minutes_407(vid,(SELECT v.version FROM public.vehicles v WHERE v.id=vid),bid,test_version,'FITTING',360,gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=510 AND capacity_base_minutes=408 AND capacity_estimate_minutes=360 FROM public.workshop_bookings WHERE id=bid),'Explicit quoted stage time converts allocation and preserves separate manual base',r);
 PERFORM pg_temp.ou_assert(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid)=360,'Explicit stage edit retains quoted-minute contract');
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 SELECT bay_number INTO dstn FROM public.workshop_bays WHERE id=bay80;
 r:=public.cascade_workshop_schedule('extend',bid,test_version,'FITTING',dstn,starts,540,NULL,30,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=540 AND capacity_base_minutes=432 AND capacity_estimate_minutes=360 FROM public.workshop_bookings WHERE id=bid),'Manual extend persists allocated base through cascade',r);
 PERFORM pg_temp.ou_assert(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid)=360 AND current_setting('pdc.workshop_capacity_manual',true)='','Manual cascade leaves quote and context clean');
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 r:=public.workshop_move_booking(bid,test_version,'FITTING',dstn,starts+interval '21 days',540,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=540 AND capacity_base_minutes=432 FROM public.workshop_bookings WHERE id=bid),'Same-bay time move retains manual allocation',r);

 x:=pg_temp.ou_vehicle('capacity-manual-follower'); PERFORM pg_temp.ou_operation(x,'FITTING',1);
 x:=pg_temp.ou_booking('capacity-manual-follower',x,'FITTING',bay80,starts+interval '21 days 9 hours');
 r:=public.resize_workshop_booking(x,(SELECT b.version FROM public.workshop_bookings b WHERE id=x),105,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Follower has durable manual allocation before cascade',r);
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 r:=public.cascade_workshop_schedule('extend',bid,test_version,'FITTING',dstn,starts+interval '21 days',600,NULL,60,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=105 AND capacity_base_minutes=84 AND scheduled_start_at>starts+interval '21 days 9 hours' FROM public.workshop_bookings WHERE id=x),'Extending one job moves its follower without resetting manual allocation',r);
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=bid;
 r:=public.cascade_workshop_schedule('extend',bid,test_version-1,'FITTING',dstn,starts+interval '21 days',660,NULL,60,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='false' AND current_setting('pdc.workshop_capacity_manual',true)='' AND (SELECT b.version=test_version AND default_duration_minutes=600 FROM public.workshop_bookings b WHERE id=bid),'Stale manual cascade rejects atomically and clears context',r);

 x:=pg_temp.ou_vehicle('capacity-create'); PERFORM pg_temp.ou_operation(x,'FITTING',4);
 r:=public.schedule_vehicle_work(x,(SELECT v.version FROM public.vehicles v WHERE v.id=x),'FITTING',dstn,starts+interval '28 days',240,NULL,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (r#>>'{booking,default_duration_minutes}')::integer=300 AND (r#>>'{booking,capacity_base_minutes}')::numeric=240,'New booking applies server bay duration before collision checks',r);
 PERFORM pg_temp.ou_assert(NOT EXISTS(
  SELECT 1 FROM ou_original_bookings x JOIN public.workshop_bookings b ON b.id=x.id
  WHERE b.capacity_base_minutes IS NULL AND public.workshop_booking_capacity_base_minutes(b.id)
   IS DISTINCT FROM greatest(public.workshop_vehicle_stage_estimated_duration_minutes(b.vehicle_id,b.stage_id),b.default_duration_minutes)::numeric
 ),'Legacy booking basis preserves longer existing allocations');

 x:=pg_temp.ou_vehicle('capacity-short'); PERFORM pg_temp.ou_operation(x,'FITTING',0.4);
 x:=pg_temp.ou_booking('capacity-short',x,'FITTING',bay80,starts+interval '7 days');
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=30 AND capacity_base_minutes=24 FROM public.workshop_bookings WHERE id=x),'Adjusted short real booking passes provenance guard');


 r:=public.workshop_start_booking(x,(SELECT b.version FROM public.workshop_bookings b WHERE id=x),starts+interval '7 days','{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Adjusted short booking starts with unchanged allocation',r);
 UPDATE public.workshop_bays SET efficiency_percent=100 WHERE id=bay80;
 r:=public.stop_workshop_work(x,(SELECT b.version FROM public.workshop_bookings b WHERE id=x),'Fixture stoppage','{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=30 AND capacity_efficiency_percent=80 FROM public.workshop_bookings WHERE id=x),'Short live booking can stop after bay factor changes',r);
 UPDATE public.workshop_bays SET efficiency_percent=80 WHERE id=bay80;
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=x;
 r:=public.return_work_to_queue(x,test_version,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT status='queued' AND bay_id IS NULL AND default_duration_minutes=30 AND capacity_efficiency_percent=80 FROM public.workshop_bookings WHERE id=x),'Short capacity booking returns unallocated without duration reset',r);
 SELECT b.version INTO test_version FROM public.workshop_bookings b WHERE id=x;
 r:=public.workshop_move_booking(x,test_version,'FITTING',dstn,starts+interval '7 days',NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT default_duration_minutes=30 AND capacity_base_minutes=24 FROM public.workshop_bookings WHERE id=x),'Returned queue booking uses target bay capacity when reassigned',r);


 r:=public.workshop_start_booking(x,(SELECT b.version FROM public.workshop_bookings b WHERE id=x),starts+interval '7 days','{}');
 UPDATE public.workshop_bays SET efficiency_percent=100 WHERE id=bay80;
 r:=public.complete_workshop_work(x,(SELECT b.version FROM public.workshop_bookings b WHERE id=x),'FITTING',starts+interval '7 days 30 minutes','{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT status='completed' AND default_duration_minutes=30 AND capacity_efficiency_percent=80 FROM public.workshop_bookings WHERE id=x),'Short live job completes after bay efficiency changes without rewriting allocation',r);
 UPDATE public.workshop_bays SET efficiency_percent=80 WHERE id=bay80;

 lv:=pg_temp.ou_vehicle('capacity-live'); PERFORM pg_temp.ou_operation(lv,'FITTING',4);
 liveid:=pg_temp.ou_booking('capacity-live',lv,'FITTING',bay100,starts+interval '14 days','started');
 SELECT default_duration_minutes INTO orig FROM public.workshop_bookings WHERE id=liveid;
 UPDATE public.workshop_bays SET efficiency_percent=50 WHERE id=bay100;
 PERFORM pg_temp.ou_assert(public.workshop_booking_effective_duration_minutes(liveid)=orig AND (SELECT default_duration_minutes=orig FROM public.workshop_bookings WHERE id=liveid),'Started work stays fixed after capacity setting');
 UPDATE public.workshop_bays SET efficiency_percent=100 WHERE id=bay100;


 x:=pg_temp.ou_vehicle('capacity-book-all');
 PERFORM pg_temp.ou_operation(x,'FITTING',4);
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=((starts+interval '35 days') AT TIME ZONE 'Australia/Perth')::date-7 WHERE id=x;
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT sid,b.id,'admin','Rollback capacity Book all fixture',starts+interval '35 days',starts+interval '35 days 10 hours',600,(SELECT actor FROM ou_context),(SELECT actor FROM ou_context)
 FROM public.workshop_bays b WHERE b.stage_id=sid AND b.is_active AND b.id<>bay80;
 r:=public.book_all_vehicle_stations(x,(SELECT v.version FROM public.vehicles v WHERE v.id=x));
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=x AND b.bay_id=bay80
  AND b.default_duration_minutes=300 AND b.capacity_base_minutes=240 AND b.scheduled_start_at=starts+interval '35 days'),'Book all chooses and schedules capacity-adjusted duration per available bay',r);

 PERFORM pg_temp.ou_assert(NOT has_function_privilege('authenticated','public.workshop_capacity_duration_minutes(numeric,uuid)','execute')
 AND NOT has_function_privilege('anon','public.workshop_capacity_manual_minutes(uuid,uuid,uuid,uuid,integer)','execute'),'New internal conversion functions are not client RPCs');
END $checks$;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings x LEFT JOIN public.workshop_bookings b ON b.id=x.id WHERE to_jsonb(b) IS DISTINCT FROM x.row_data),'Pre-existing bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles x LEFT JOIN public.vehicles v ON v.id=x.id WHERE to_jsonb(v) IS DISTINCT FROM x.row_data),'Pre-existing vehicles unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM capacity_original_bays x LEFT JOIN public.workshop_bays b ON b.id=x.id WHERE to_jsonb(b) IS DISTINCT FROM x.row_data),'Pre-existing bay settings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM capacity_original_operations x LEFT JOIN public.pdc_pilbara_service_operations o ON o.operation_id=x.operation_id WHERE to_jsonb(o) IS DISTINCT FROM x.row_data),'Pre-existing quoted operation lines unchanged');
SELECT * FROM ou_results ORDER BY name;
ROLLBACK;
