-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the operation-approval migration.
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






DO $checks$
DECLARE v uuid; bay uuid; b uuid; tech uuid:=gen_random_uuid(); othertech uuid:=gen_random_uuid();
 d jsonb; r jsonb; replay jsonb; planner jsonb; board jsonb; queue jsonb; rid uuid:=gen_random_uuid();
 initial_version integer; rev bigint; station_rev bigint; actual timestamptz; history_count integer; request_count integer;
BEGIN
 INSERT INTO public.workshop_technicians(id,name,role_type,active)
 VALUES(tech,'Fitter confirmation rollback','technician',true),(othertech,'Other fitter rollback','technician',true);
 v:=pg_temp.ou_vehicle('confirmation');bay:=pg_temp.ou_bay('confirmation','FITTING');
 UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
 PERFORM pg_temp.ou_operation(v,'FITTING',1,1);
 b:=pg_temp.ou_booking('confirmation',v,'FITTING',bay,((SELECT friday FROM ou_context)::text||' 06:00+08')::timestamptz);
 d:=public.get_fitter_job(tech,b);initial_version:=(d->>'version')::int;
 rev:=public.workshop_current_revision();SELECT revision INTO station_rev FROM public.workshop_station_revision WHERE stage_code='FITTING';
 r:=public.fitter_job_command(tech,b,initial_version-1,d->>'catalog_hash',gen_random_uuid(),'start');
 PERFORM pg_temp.ou_assert(r->>'error'='version_conflict' AND (SELECT status='planned' FROM public.workshop_bookings WHERE id=b),'Stale planned start rejected without mutation',r);
 r:=public.fitter_job_command(othertech,b,initial_version,d->>'catalog_hash',gen_random_uuid(),'start');
 PERFORM pg_temp.ou_assert(r->>'error'='assignment_changed','Unassigned mechanic cannot start booking',r);
 r:=public.fitter_job_command(tech,b,initial_version,d->>'catalog_hash',rid,'start');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND r->>'status'='started' AND (r->>'actual_start_at') IS NOT NULL AND (r->>'version')::int>initial_version,'Fitter Start confirms saved canonical status and timing',r);
 SELECT actual_start_at INTO actual FROM public.workshop_bookings WHERE id=b;
 PERFORM pg_temp.ou_assert((r->>'actual_start_at')::timestamptz=actual AND (r#>>'{timer,elapsed_seconds}')::numeric>=0 AND r#>>'{timer,as_of}' IS NOT NULL,'Confirmation timer comes from canonical actual start',r->'timer');
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert(d->>'status'='started' AND (d->>'actual_start_at')::timestamptz=actual AND d#>>'{timer,basis}'='workshop_opening_hours','Fresh fitter detail confirms live state',d->'timer');
 SELECT j INTO queue FROM jsonb_array_elements(public.get_fitter_jobs(tech)->'jobs')j WHERE j->>'id'=b::text;
 PERFORM pg_temp.ou_assert(queue->>'status'='started' AND (queue->>'actual_start_at')::timestamptz=actual AND NOT(queue?'timer'),'Queue confirms state without computing every row timer',queue);
 SELECT j INTO planner FROM jsonb_array_elements(public.get_station_workshop_snapshot('FITTING',(actual AT TIME ZONE 'Australia/Perth')::date,((actual+interval '2 days') AT TIME ZONE 'Australia/Perth')::date)->'bookings')j WHERE j->>'booking_id'=b::text;
 PERFORM pg_temp.ou_assert(planner->>'status'='started' AND (planner->>'actual_start_at')::timestamptz=actual AND (planner->>'version')::int=(d->>'version')::int,'Station planner reads the fitter started booking',jsonb_build_object('status',planner->>'status','actual_start_at',planner->>'actual_start_at','version',planner->>'version'));
 SELECT j INTO board FROM jsonb_array_elements(public.get_workshop_snapshot((actual AT TIME ZONE 'Australia/Perth')::date,((actual+interval '2 days') AT TIME ZONE 'Australia/Perth')::date)->'bookings')j WHERE j->>'booking_id'=b::text;
 PERFORM pg_temp.ou_assert(board->>'status'='started' AND (board->>'actual_start_at')::timestamptz=actual,'All-bays control board reads the fitter started booking',jsonb_build_object('status',board->>'status','actual_start_at',board->>'actual_start_at'));
 PERFORM pg_temp.ou_assert(public.workshop_current_revision()>rev AND (SELECT revision>station_rev FROM public.workshop_station_revision WHERE stage_code='FITTING'),'Fitter start increments global and station revisions');
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='workshop_station_revision') AND has_table_privilege('authenticated','public.workshop_station_revision','SELECT'),'Station revisions published and readable to logged-in planners');
 SELECT count(*) INTO history_count FROM public.workshop_booking_history WHERE booking_id=b AND event_type='started';
 replay:=public.fitter_job_command(tech,b,initial_version,d->>'catalog_hash',rid,'start');
 PERFORM pg_temp.ou_assert((replay->>'replayed')::boolean AND replay-'replayed'=r,'Repeated request replays confirmation exactly',replay);
 r:=public.fitter_job_command(tech,b,initial_version,NULL,gen_random_uuid(),'start');
 PERFORM pg_temp.ou_assert((r->>'already_started')::boolean AND r->>'status'='started' AND (r->>'actual_start_at')::timestamptz=actual AND (SELECT count(*)=history_count FROM public.workshop_booking_history WHERE booking_id=b AND event_type='started'),'Controller or second fitter Start is idempotent without resetting timer',r);
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('authenticated','pdc_fitter_private.timing(uuid,timestamptz)','EXECUTE') AND NOT has_schema_privilege('authenticated','pdc_fitter_private','USAGE'),'Timing helper stays private behind authorized reads');
END $checks$;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data<>to_jsonb(b)),'Existing operational bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data<>to_jsonb(v)),'Existing vehicles unchanged');
SELECT jsonb_agg(to_jsonb(r) ORDER BY name) results FROM ou_results r;
ROLLBACK;

