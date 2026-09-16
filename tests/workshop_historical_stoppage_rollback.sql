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





DO $checks$
DECLARE v uuid; bay uuid; b uuid; tech uuid:=gen_random_uuid(); r jsonb; ver int; d jsonb; oldrow jsonb; histstart timestamptz;
 rejected boolean; start_value jsonb; end_value jsonb; sid uuid; admin_id uuid; n int; snap jsonb; nextslot jsonb; f date;
BEGIN
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Historical stop rollback','technician',true);
 v:=pg_temp.ou_vehicle('historical-stop'); bay:=pg_temp.ou_bay('historical-stop','FITTING');
 UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
 PERFORM pg_temp.ou_operation(v,'FITTING',1);
 SELECT value INTO start_value FROM public.workshop_settings WHERE key='day_start_time';
 SELECT value INTO end_value FROM public.workshop_settings WHERE key='day_end_time';
 UPDATE public.workshop_settings SET value='"07:00"' WHERE key='day_start_time';
 UPDATE public.workshop_settings SET value='"17:00"' WHERE key='day_end_time';
 histstart:=(((now() AT TIME ZONE 'Australia/Perth')::date-1)+time '16:43') AT TIME ZONE 'Australia/Perth';
 b:=pg_temp.ou_booking('historical-stop',v,'FITTING',bay,histstart,'started');
 UPDATE public.workshop_settings SET value=start_value WHERE key='day_start_time';
 UPDATE public.workshop_settings SET value=end_value WHERE key='day_end_time';
 SELECT to_jsonb(w),version INTO oldrow,ver FROM public.workshop_bookings w WHERE id=b;
 PERFORM pg_temp.ou_assert(NOT public.workshop_calendar_minute_available(histstart),'Historical start is outside new calendar');
 r:=public.fitter_job_command(tech,b,ver,NULL,gen_random_uuid(),'stop',NULL,NULL,'Parts: bracket missing');
 PERFORM pg_temp.ou_assert((r->>'ok')::bool,'Fitter can stop job started under old hours',r);
 PERFORM pg_temp.ou_assert((SELECT status='stoppage' AND stoppage_reason='Parts: bracket missing' AND scheduled_start_at=(oldrow->>'scheduled_start_at')::timestamptz AND scheduled_end_at=(oldrow->>'scheduled_end_at')::timestamptz AND actual_start_at=(oldrow->>'actual_start_at')::timestamptz FROM public.workshop_bookings WHERE id=b),'Stoppage preserves actual start and historical interval');
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=b;
 r:=public.fitter_job_command(tech,b,ver-1,NULL,gen_random_uuid(),'stop',NULL,NULL,'Stale request');
 PERFORM pg_temp.ou_assert(r->>'error'='version_conflict','Stale fitter stoppage rejected',r);
 r:=public.resume_workshop_work(b,ver,'{}');
 PERFORM pg_temp.ou_assert((r->>'ok')::bool AND (SELECT status='started' FROM public.workshop_bookings WHERE id=b),'Controller can resume after historical stoppage',r);
 PERFORM pg_temp.ou_assert((SELECT public.workshop_calendar_minute_available(scheduled_start_at) FROM public.workshop_bookings WHERE id=b),'Resume uses new working calendar');
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=b;
 r:=public.stop_workshop_work(b,ver,'Controller stop','{}');
 PERFORM pg_temp.ou_assert((r->>'ok')::bool,'Controller stoppage remains functional',r);
 -- A changed historical interval still receives full calendar validation.
 rejected:=false;
 BEGIN UPDATE public.workshop_bookings SET status='started',scheduled_start_at=histstart,scheduled_end_at=histstart+interval '1 hour' WHERE id=b;
 EXCEPTION WHEN SQLSTATE '22023' THEN rejected:=true; END;
 PERFORM pg_temp.ou_assert(rejected,'Moving a running booking outside new hours remains blocked');
 -- Existing completed history must not block Admin move/resize.
 UPDATE public.pdc_user_roles SET role='administrator' WHERE auth_user_id=auth.uid();
 v:=pg_temp.ou_vehicle('completed-admin');bay:=pg_temp.ou_bay('completed-admin','FITTING');
 UPDATE public.workshop_bays SET bay_number=9001 WHERE id=bay;
 PERFORM pg_temp.ou_operation(v,'FITTING',1);
 SELECT friday INTO f FROM ou_context;
 b:=pg_temp.ou_booking('completed-admin',v,'FITTING',bay,(f+time '07:00') AT TIME ZONE 'Australia/Perth','completed');
 SELECT workshop_bays.stage_id,bay_number INTO sid,n FROM public.workshop_bays WHERE id=bay;
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 VALUES(sid,bay,'admin','Rollback',(f+time '09:00') AT TIME ZONE 'Australia/Perth',(f+time '10:00') AT TIME ZONE 'Australia/Perth',60,auth.uid(),auth.uid()) RETURNING id INTO admin_id;
 r:=public.move_workshop_admin_block(admin_id,1,'FITTING',n,(f+time '07:00') AT TIME ZONE 'Australia/Perth','{}');
 PERFORM pg_temp.ou_assert((r->>'ok')::bool,'Completed history does not block Admin move',r);
 SELECT version INTO ver FROM public.workshop_admin_blocks WHERE id=admin_id;
 r:=public.resize_workshop_admin_block(admin_id,ver,120,'{}');
 PERFORM pg_temp.ou_assert((r->>'ok')::bool,'Completed history does not block Admin resize',r);
 -- The nearest slot jumps beyond a protected live booking.
 v:=pg_temp.ou_vehicle('fixed-slot');bay:=pg_temp.ou_bay('fixed-slot','FITTING');
 PERFORM pg_temp.ou_operation(v,'FITTING',2);
 b:=pg_temp.ou_booking('fixed-slot',v,'FITTING',bay,(f+time '07:00') AT TIME ZONE 'Australia/Perth','started');
 nextslot:=public.workshop_admin_nearest_available_slot(bay,(f+time '07:00') AT TIME ZONE 'Australia/Perth',60);
 PERFORM pg_temp.ou_assert((nextslot->>'ok')::bool AND (nextslot->>'scheduled_start_at')::timestamptz=public.workshop_booking_effective_end_at(b),'Nearest Admin slot uses protected effective end',nextslot);
END $checks$;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data<>to_jsonb(b)),'Existing bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data<>to_jsonb(v)),'Existing vehicles unchanged');
SELECT jsonb_agg(to_jsonb(r) ORDER BY name) results FROM ou_results r;
ROLLBACK;
