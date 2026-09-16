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
DECLARE v uuid; bay uuid; b uuid; tech uuid:=gen_random_uuid(); othertech uuid:=gen_random_uuid();
 op uuid; d jsonb; r jsonb; ver integer; rid uuid; payload jsonb; qc_before jsonb; rejected boolean:=false;
BEGIN
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Fitter rollback','technician',true),(othertech,'Other rollback','technician',true);
 v:=pg_temp.ou_vehicle('fitter'); bay:=pg_temp.ou_bay('fitter','FITTING');
 UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
 op:=pg_temp.ou_operation(v,'FITTING',1,1);
 PERFORM pg_temp.ou_operation(v,'FITTING',2,2);
 PERFORM pg_temp.ou_operation(v,'FITTING',7,3);
 PERFORM pg_temp.ou_operation(v,'ELECTRICAL',3,4);
 b:=pg_temp.ou_booking('fitter',v,'FITTING',bay,date_trunc('minute',now())-interval '1 minute','started');
 qc_before:=public.pdc_qc_operation_lines_379(v);
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert((d#>>'{progress,total_hours}')::numeric=10 AND (d#>>'{progress,percent}')::numeric=0,'Progress starts at zero and uses this station only',d->'progress');
 PERFORM pg_temp.ou_assert(jsonb_array_length(public.get_fitter_jobs(tech)->'jobs')=1,'Default bay assignment finds the booking');
 PERFORM pg_temp.ou_assert(public.get_fitter_job(othertech,b)->>'error'='assignment_changed','Other mechanic cannot change this job');
 r:=public.fitter_job_command(tech,b,0,NULL,gen_random_uuid(),'start');
 PERFORM pg_temp.ou_assert((r->>'already_started')::boolean,'Already started by controller is idempotent');
 rid:=gen_random_uuid();
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',rid,'line','source:'||op,true,'Installed and checked fit');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'First line saved',r);
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',rid,'line','source:'||op,true,'Installed and checked fit');
 PERFORM pg_temp.ou_assert((r->>'replayed')::boolean,'Retry reuses receipt without a second write');
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line','source:'||op,false,'');
 PERFORM pg_temp.ou_assert(r->>'error'='version_conflict','Concurrent stale line write rejected');
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert((d#>>'{progress,percent}')::numeric=10,'One completed hour out of ten is ten percent',d->'progress');
 SELECT l INTO payload FROM jsonb_array_elements(d->'lines') l WHERE l->>'stage_code'='FITTING' AND (l->>'hours')::numeric=2;
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line',payload->>'line_identity',true,'Second item done');
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (d#>>'{progress,percent}')::numeric=30,'Two more hours adds twenty percent',d->'progress');
 PERFORM pg_temp.ou_assert((SELECT (j#>>'{fitter_progress,percent}')::numeric=30 FROM jsonb_array_elements(public.get_station_workshop_snapshot('FITTING',(now() at time zone 'Australia/Perth')::date,((now()+interval '4 days') at time zone 'Australia/Perth')::date)->'bookings') j WHERE j->>'booking_id'=b::text),'Station planner receives saved progress');
 PERFORM pg_temp.ou_assert((SELECT (j#>>'{fitter_progress,percent}')::numeric=30 FROM jsonb_array_elements(public.get_workshop_eligibility_snapshot()#>'{board,bookings}') j WHERE j->>'booking_id'=b::text),'Control board receives saved progress');
 PERFORM pg_temp.ou_assert(public.pdc_qc_operation_lines_379(v)=qc_before,'Fitter ticks leave QC inspection unchanged');
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'complete');
 PERFORM pg_temp.ou_assert(r->>'error'='items_incomplete','Cannot finish with incomplete items');
 SELECT l INTO payload FROM jsonb_array_elements(d->'lines') l WHERE l->>'stage_code'='ELECTRICAL';
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line',payload->>'line_identity',true,'');
 PERFORM pg_temp.ou_assert(r->>'error'='line_unavailable','Other station items are read only');
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'stop',NULL,NULL,'Parts: waiting for bracket');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Parts stoppage uses planner lifecycle',r);
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert(d->>'status'='stoppage' AND (d#>>'{progress,percent}')::numeric=30,'Stoppage preserves saved work');
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line','source:'||op,false,'');
 PERFORM pg_temp.ou_assert(r->>'error'='job_not_running','Work cannot be ticked during stoppage');
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'resume');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Resume shares planner state',r);
 d:=public.get_fitter_job(tech,b);
 -- Changed scope invalidates only that item, and stale clients cannot check it.
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by) VALUES(v,'source:'||op,'source','FITTING','Fixture work FITTING line 1',2,auth.uid(),auth.uid());
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line','source:'||op,true,'');
 PERFORM pg_temp.ou_assert(r->>'error'='scope_changed','Import changes reject stale catalogue');
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert((d#>>'{progress,completed_hours}')::numeric=2 AND (d#>>'{progress,total_hours}')::numeric=11,'Changed hours revoke previous item completion',d->'progress');
 FOR payload IN SELECT l FROM jsonb_array_elements(d->'lines') l WHERE l->>'stage_code'='FITTING' AND NOT (l->>'completed')::boolean LOOP
  d:=public.get_fitter_job(tech,b);
  r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line',payload->>'line_identity',true,'Final review');
  PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Complete remaining line '||(payload->>'line_identity'),r);
 END LOOP;
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert((d#>>'{progress,percent}')::numeric=100,'All hours completed is one hundred percent');
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'complete');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (SELECT status='completed' FROM public.workshop_bookings WHERE id=b),'Finish completes the canonical booking',r);
 PERFORM pg_temp.ou_assert((SELECT completed FROM public.vehicle_work_items WHERE vehicle_id=v AND work_key='fitting'),'Finish completes station work requirement');
 PERFORM pg_temp.ou_assert(NOT (pdc_fitter_private.summary('[{"stage_code":"FITTING","hours":null,"completed":true}]','FITTING')->>'can_complete')::boolean,'Unknown hours cannot falsely complete');

 -- An unstarted booking can be started from the fitter, then resumed by the controller.
 UPDATE public.workshop_bays SET default_technician_id=NULL WHERE default_technician_id=tech;
 v:=pg_temp.ou_vehicle('start'); bay:=pg_temp.ou_bay('start','FITTING');
 UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
 PERFORM pg_temp.ou_operation(v,'FITTING',1,1);
 b:=pg_temp.ou_booking('start',v,'FITTING',bay,((SELECT friday FROM ou_context)::text||' 07:00+08')::timestamptz);
 d:=public.get_fitter_job(tech,b);
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'start');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (SELECT status='started' FROM public.workshop_bookings WHERE id=b),'Fitter starts planned booking through canonical planner controls',r);
 PERFORM pg_temp.ou_assert((SELECT actual_start_at IS NOT NULL FROM public.workshop_bookings WHERE id=b),'Actual start recorded once');
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,othertech,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=b;
 PERFORM pg_temp.ou_assert(NOT pdc_fitter_private.assigned(b,tech) AND pdc_fitter_private.assigned(b,othertech),'Booking assignment overrides bay default');

 UPDATE public.pdc_user_roles SET role='viewer' WHERE auth_user_id=auth.uid();
 BEGIN
  PERFORM public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'start');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
 END;
 PERFORM pg_temp.ou_assert(rejected,'Viewer cannot write');
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('anon','public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)','EXECUTE'),'Anonymous command access denied');
 PERFORM pg_temp.ou_assert(NOT has_schema_privilege('authenticated','pdc_fitter_private','USAGE'),'Progress tables remain private');
END $checks$;
SELECT pg_temp.ou_assert(NOT EXISTS(
 SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data<>to_jsonb(b)
),'Existing operational bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(
 SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data<>to_jsonb(v)
),'Existing vehicles unchanged');
SELECT jsonb_agg(to_jsonb(r) ORDER BY name) results FROM ou_results r;
ROLLBACK;
