-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the operation-approval migration.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';

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
 mins:=public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid);
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;

DO $gap_tests$
DECLARE f date; floor_at timestamptz; b uuid; bh uuid; vb uuid; va uuid; vc uuid; vd uuid; a uuid;
 waiting uuid; ready uuid; fixed uuid; late_job uuid; p jsonb; item record; old_ready jsonb;
BEGIN
 SELECT friday,actor INTO f,a FROM ou_context;
 floor_at:=(f+time '07:00') AT TIME ZONE 'Australia/Perth';
 b:=pg_temp.ou_bay('gap-fill','TYRE');
 bh:=pg_temp.ou_bay('gap-prerequisite','HOIST');
 va:=pg_temp.ou_vehicle('waiting'); PERFORM pg_temp.ou_operation(va,'HOIST',3); PERFORM pg_temp.ou_operation(va,'TYRE',1,2);
 PERFORM pg_temp.ou_booking('prerequisite',va,'HOIST',bh,floor_at);
 waiting:=pg_temp.ou_booking('waiting',va,'TYRE',b,floor_at+interval '4 hours');
 vb:=pg_temp.ou_vehicle('ready'); PERFORM pg_temp.ou_operation(vb,'TYRE',1);
 ready:=pg_temp.ou_booking('ready',vb,'TYRE',b,floor_at+interval '6 hours');
 vc:=pg_temp.ou_vehicle('live'); PERFORM pg_temp.ou_operation(vc,'TYRE',1);
 fixed:=pg_temp.ou_booking('live',vc,'TYRE',b,floor_at+interval '1 hour','started');
 vd:=pg_temp.ou_vehicle('later-ready'); PERFORM pg_temp.ou_operation(vd,'TYRE',1);
 late_job:=pg_temp.ou_booking('later-ready',vd,'TYRE',b,floor_at+interval '7 hours');
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,b,'admin','Gap fixture reservation',floor_at,floor_at+interval '30 minutes',30,a,a FROM public.workshop_bays WHERE id=b;
 SELECT to_jsonb(w) INTO old_ready FROM public.workshop_bookings w WHERE id=ready;
 p:=public.workshop_capacity_plan('TYRE',NULL,NULL,floor_at);
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true','Gap fill has an applicable plan',p);
 PERFORM pg_temp.ou_assert((SELECT final_start=floor_at+interval '2 hours' FROM pg_temp.workshop_capacity_plan WHERE booking_id=ready),
   'Ready job overtakes waiting job while avoiding admin block and live job',p);
 PERFORM pg_temp.ou_assert((SELECT final_start=floor_at+interval '3 hours' FROM pg_temp.workshop_capacity_plan WHERE booking_id=late_job),
   'Next ready job fills the remaining gap',p);
 PERFORM pg_temp.ou_assert((SELECT NOT changed AND final_start=floor_at+interval '4 hours' FROM pg_temp.workshop_capacity_plan WHERE booking_id=waiting),
   'Vehicle still waits for predecessor and full one-hour handover',p);
 PERFORM pg_temp.ou_assert((SELECT NOT changed FROM pg_temp.workshop_capacity_plan WHERE booking_id=fixed),'Started job remains fixed',p);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(w)=old_ready FROM public.workshop_bookings w WHERE id=ready),'Preview does not change ready booking');
 FOR item IN SELECT * FROM pg_temp.workshop_capacity_plan WHERE changed AND booking_id IN(ready,late_job) ORDER BY apply_order LOOP
  UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
   version=version+1,updated_by=a WHERE id=item.booking_id;
 END LOOP;
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=floor_at+interval '2 hours' FROM public.workshop_bookings WHERE id=ready),
   'Reordered ready job passes real booking guards on apply');
 p:=public.workshop_capacity_plan('TYRE',NULL,NULL,floor_at);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan WHERE changed AND booking_id IN(ready,late_job,waiting,fixed)),
   'Repeated gap fill is stable',p);
END $gap_tests$;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o FULL JOIN public.workshop_bookings b ON b.id=o.id
 WHERE o.id IS NOT NULL AND (b.id IS NULL OR to_jsonb(b) IS DISTINCT FROM o.row_data)),'Existing bookings untouched');
SELECT jsonb_build_object('count',count(*),'results',jsonb_agg(to_jsonb(r)-'evidence')) result FROM ou_results r;
ROLLBACK;
