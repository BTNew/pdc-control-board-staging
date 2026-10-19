-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection. Every fixture, authorization, audit
-- and optional candidate migration is reverted by the final ROLLBACK.
BEGIN;
SET LOCAL statement_timeout = '240s';
SET LOCAL lock_timeout = '20s';
SELECT pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
SET LOCAL TIME ZONE 'Australia/Perth';

-- APPLY CANDIDATE MIGRATION HERE.
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
 VALUES(v,'operation-update-rollback-'||v,stock,'OU-JC-'||substr(v::text,1,8),'ROLLBACK FIXTURE '||tag,'Toyota HiAce Commuter','PMB',true,
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
 UPDATE public.workshop_bays SET bay_number=(SELECT coalesce(max(bay_number),0)+1 FROM public.workshop_bays WHERE stage_id=sid) WHERE id=b; INSERT INTO ou_refs VALUES('bay-'||tag,b);
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1, dept text DEFAULT '139')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',CASE WHEN dept='138' AND stage='BUS_4X4' THEN 'Coaster Bus 4x4 Conversion - 6 Speed 2.8' ELSE 'Fixture work '||stage||' line '||line_no END,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
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
 mins:=CASE WHEN state IN('queued','planned') THEN public.workshop_capacity_duration_minutes(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid),bay) ELSE public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid) END;
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,jsonb_build_object('rollback_fixture',true,'bus_clock_fixture',current_setting('qa.bus_clock_case',true)));
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;








DO $checks$
DECLARE v uuid; follower uuid; unallocated uuid; bay uuid; b uuid; nextb uuid; qb uuid; op uuid;
 at_time timestamptz; result jsonb; before_row jsonb; next_before jsonb; queue_before jsonb;
 ver integer; bv integer; request uuid:=gen_random_uuid(); saved integer; oldclaims text;
BEGIN
 v:=pg_temp.ou_vehicle('running-estimate');follower:=pg_temp.ou_vehicle('following-estimate');
 bay:=pg_temp.ou_bay('running-estimate','HOIST');
 op:=pg_temp.ou_operation(v,'HOIST',1);
 PERFORM pg_temp.ou_operation(follower,'HOIST',1);
 PERFORM pg_temp.ou_operation(v,'FITTING',1,2);
 at_time:=public.workshop_admin_next_operational_minute(date_trunc('week',clock_timestamp()+interval '90 days')+interval '7 days 7 hours');
 b:=pg_temp.ou_booking('running-estimate',v,'HOIST',bay,at_time,'started');
 nextb:=pg_temp.ou_booking('following-estimate',follower,'HOIST',bay,public.workshop_add_operational_minutes(at_time,120),'planned');
 qb:=pg_temp.ou_booking('unallocated-other-station',v,'FITTING',NULL,public.workshop_add_operational_minutes(at_time,180),'queued');
 SELECT to_jsonb(x) INTO before_row FROM public.workshop_bookings x WHERE id=b;
 SELECT to_jsonb(x) INTO next_before FROM public.workshop_bookings x WHERE id=nextb;
 SELECT to_jsonb(x) INTO queue_before FROM public.workshop_bookings x WHERE id=qb;
 SELECT version INTO ver FROM public.vehicles WHERE id=v;SELECT version INTO bv FROM public.workshop_bookings WHERE id=b;
 result:=public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',360,request);
 PERFORM pg_temp.ou_assert(result->>'ok'='true','running estimate saves',result);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=360 AND status='started'
  AND scheduled_start_at=(before_row->>'scheduled_start_at')::timestamptz
  AND actual_start_at=(before_row->>'actual_start_at')::timestamptz FROM public.workshop_bookings WHERE id=b),'running start progress status retained and allocation extended');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at>=(SELECT scheduled_end_at FROM public.workshop_bookings WHERE id=b) FROM public.workshop_bookings WHERE id=nextb),'follower cascades forward');
 PERFORM pg_temp.ou_assert(queue_before=(SELECT to_jsonb(x) FROM public.workshop_bookings x WHERE id=qb),'Unallocated remains untouched and cannot block cascade');
 PERFORM pg_temp.ou_assert(public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',360,request)->>'replay'='true','retry is idempotent');
 SELECT version INTO ver FROM public.vehicles WHERE id=v;
 result:=public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',420,gen_random_uuid());
 PERFORM pg_temp.ou_assert(result->>'code'='version_conflict','stale booking version rejected',result);
 -- Ordinary line editing must now grow a running booking automatically.
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,created_by,updated_by)
 VALUES(v,'source:'||op,'source','HOIST','Fixture longer operation',3,'manual_operator',true,auth.uid(),auth.uid());
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=480 AND scheduled_start_at=(before_row->>'scheduled_start_at')::timestamptz
  AND status='started' FROM public.workshop_bookings WHERE id=b),'line edit automatically extends running allocation');
 SELECT version INTO ver FROM public.vehicles WHERE id=v;SELECT version INTO bv FROM public.workshop_bookings WHERE id=b;
 result:=public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',60,gen_random_uuid());
 PERFORM pg_temp.ou_assert(result->>'code'='estimated_minutes_below_authenticated_work','source work minimum retained',result);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o FULL JOIN (SELECT id,to_jsonb(x) row_data FROM public.workshop_bookings x WHERE id IN(SELECT id FROM ou_original_bookings))n USING(id) WHERE o.row_data IS DISTINCT FROM n.row_data),'existing bookings unchanged');
END $checks$;
SELECT jsonb_build_object('status','PASS','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK;
