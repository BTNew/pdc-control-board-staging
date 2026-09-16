-- STAGING ONLY. Verifies installed priority Start through a fitter-only account.
-- Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the priority Start migration.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '20s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
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






CREATE TEMP TABLE priority_original_assignments AS SELECT id,to_jsonb(a) row_data FROM public.workshop_booking_assignments a;
CREATE TEMP TABLE priority_original_blocks AS SELECT id,to_jsonb(a) row_data FROM public.workshop_admin_blocks a;
DO $checks$
DECLARE t timestamptz:=date_trunc('minute',statement_timestamp()); first_at timestamptz;
 v uuid; fitbay uuid; tintbay uuid; fabbay uuid; target uuid; tint uuid; fab uuid; tech uuid:=gen_random_uuid(); tinttech uuid:=gen_random_uuid();
 d jsonb; r jsonb; planner jsonb; old_tint jsonb; old_target jsonb; old_fab jsonb; assignment_id uuid; oldver integer; final_end timestamptz; denied boolean:=false;
BEGIN
 PERFORM pg_temp.ou_assert(public.workshop_calendar_minute_available(t),'Priority start runs during real opening hours');
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Priority fitter rollback','technician',true),(tinttech,'Priority tint rollback','technician',true);
 v:=pg_temp.ou_vehicle('priority-long');fitbay:=pg_temp.ou_bay('priority-long','FITTING');
 tintbay:=pg_temp.ou_bay('priority-tint','TINT');fabbay:=pg_temp.ou_bay('priority-fab','FABRICATION');
 UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=fitbay;
 PERFORM pg_temp.ou_operation(v,'FITTING',10,1);PERFORM pg_temp.ou_operation(v,'TINT',1,2);PERFORM pg_temp.ou_operation(v,'FABRICATION',1,3);
 first_at:=public.workshop_admin_next_operational_minute(t+interval '1 minute');
 tint:=pg_temp.ou_booking('priority-tint',v,'TINT',tintbay,first_at);
 target:=pg_temp.ou_booking('priority-long',v,'FITTING',fitbay,public.workshop_admin_next_operational_minute(public.workshop_add_operational_minutes(first_at,60)+interval '1 hour'));
 SELECT scheduled_end_at INTO final_end FROM public.workshop_bookings WHERE id=target;
 fab:=pg_temp.ou_booking('priority-fab',v,'FABRICATION',fabbay,public.workshop_admin_next_operational_minute(final_end+interval '1 hour'));
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,tinttech,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=tint RETURNING id INTO assignment_id;
 SELECT to_jsonb(b) INTO old_tint FROM public.workshop_bookings b WHERE id=tint;
 SELECT to_jsonb(b) INTO old_target FROM public.workshop_bookings b WHERE id=target;
 SELECT to_jsonb(b) INTO old_fab FROM public.workshop_bookings b WHERE id=fab;
 UPDATE public.pdc_user_roles SET role='fitter' WHERE auth_user_id=auth.uid();
 PERFORM set_config('request.method','POST',true);
 PERFORM set_config('request.path','/rpc/get_fitter_job',true);
 PERFORM public.pdc_check_fitter_request();
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=auth.uid() AND role::text='fitter'),'Account is fitter-only at the authorized detail and Start boundary');
 d:=public.get_fitter_job(tech,target);
 PERFORM set_config('request.path','/rpc/fitter_job_command',true);
 PERFORM public.pdc_check_fitter_request();
 r:=public.fitter_job_command(tech,target,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'start');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (r->>'start_priority')::boolean AND (r->>'shifted_count')::int>=1,'Fitter Start gives long Fitting priority over unstarted Tint',r);
 PERFORM pg_temp.ou_assert((SELECT status='started' AND actual_start_at=t AND scheduled_start_at=t FROM public.workshop_bookings WHERE id=target),'Selected job starts now rather than a future suggestion');
 PERFORM pg_temp.ou_assert((SELECT b.status='planned' AND b.actual_start_at IS NULL AND b.scheduled_start_at>=a.scheduled_end_at+interval '1 hour' FROM public.workshop_bookings a,public.workshop_bookings b WHERE a.id=target AND b.id=tint),'Earlier Tint remains unstarted after Fitting with one-hour handover');
 PERFORM pg_temp.ou_assert((SELECT c.scheduled_start_at>=b.scheduled_end_at+interval '1 hour' FROM public.workshop_bookings b,public.workshop_bookings c WHERE b.id=tint AND c.id=fab),'Other unstarted vehicle bookings keep their relative order');
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM pg_temp.workshop_start_writes WHERE NOT is_final AND id=tint) AND NOT EXISTS(SELECT 1 FROM pg_temp.workshop_start_writes WHERE NOT is_final AND id=target),'Long-job old-range swap uses safe reservation and never parks target');
 PERFORM pg_temp.ou_assert((SELECT b.version=(old_tint->>'version')::int+2 AND b.scheduled_start_at=public.workshop_admin_next_operational_minute(a.scheduled_end_at+interval '1 hour') FROM public.workshop_bookings a,public.workshop_bookings b WHERE a.id=target AND b.id=tint),'Temporary reservation leaves no extra final gap or incorrect version');
 PERFORM pg_temp.ou_assert((SELECT count(*)=1 AND bool_and((h.before_data->>'scheduled_start_at')::timestamptz=(old_tint->>'scheduled_start_at')::timestamptz) FROM public.workshop_booking_history h WHERE h.booking_id=tint AND h.event_type='start_cascade_shifted'),'Audit records original-to-final movement once without temporary slot history');
 PERFORM pg_temp.ou_assert((SELECT a.released_at IS NULL AND a.scheduled_start_at=b.scheduled_start_at AND a.scheduled_end_at=b.scheduled_end_at FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE a.id=assignment_id),'Assigned technician and assignment identity survive reservation and final move');
 -- Direct planner endpoints remain disallowed to this fitter-only account.
 PERFORM set_config('request.path','/rpc/start_workshop_work',true);
 BEGIN PERFORM public.pdc_check_fitter_request(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM pg_temp.ou_assert(denied,'Fitter request guard still rejects direct planner mutation');
 -- Operator authority is restored only for the independent planner readback.
 UPDATE public.pdc_user_roles SET role='operator' WHERE auth_user_id=auth.uid();
 PERFORM set_config('request.path','/rpc/get_station_workshop_snapshot',true);
 PERFORM public.pdc_check_fitter_request();
 SELECT j INTO planner FROM jsonb_array_elements(public.get_station_workshop_snapshot('FITTING',(t AT TIME ZONE 'Australia/Perth')::date,((t+interval '2 days') AT TIME ZONE 'Australia/Perth')::date)->'bookings')j WHERE j->>'booking_id'=target::text;
 PERFORM pg_temp.ou_assert(planner->>'status'='started' AND (planner->>'actual_start_at')::timestamptz=t,'Planner reads the fitter priority start');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings a JOIN public.workshop_bookings b ON a.vehicle_id=b.vehicle_id AND a.id<b.id
  WHERE a.vehicle_id=v AND a.deleted_at IS NULL AND b.deleted_at IS NULL AND a.status IN('planned','queued','started','stoppage') AND b.status IN('planned','queued','started','stoppage')
  AND a.scheduled_start_at<b.scheduled_end_at+interval '1 hour' AND a.scheduled_end_at+interval '1 hour'>b.scheduled_start_at),'Final same-vehicle schedule has no overlap and all one-hour buffers');
END $checks$;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'Existing operational bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o LEFT JOIN public.vehicles v ON v.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'Existing vehicles unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM priority_original_assignments o LEFT JOIN public.workshop_booking_assignments a ON a.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'Existing assignments unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM priority_original_blocks o LEFT JOIN public.workshop_admin_blocks a ON a.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'Existing downtime unchanged');
SELECT jsonb_agg(to_jsonb(r) ORDER BY name) results FROM ou_results r;
ROLLBACK;

