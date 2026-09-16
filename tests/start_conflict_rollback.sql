-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the safe-start migration.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '20s';
SET LOCAL TIME ZONE 'Australia/Perth';
-- Match production lock order before synthetic setup bumps shared revisions.
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

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

-- Synthetic tests use real canonical guards and a real operating-minute clock.
-- This is deliberately not a scheduled future-time "start" simulation.

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



CREATE TEMP TABLE start_original_assignments AS SELECT id,to_jsonb(a) row_data FROM public.workshop_booking_assignments a;
CREATE TEMP TABLE start_original_blocks AS SELECT id,to_jsonb(a) row_data FROM public.workshop_admin_blocks a;

DO $checks$
DECLARE
 t timestamptz:=date_trunc('minute',statement_timestamp()); later timestamptz;
 bay uuid; bay2 uuid; target uuid; follower uuid; third uuid; successor uuid;
 v uuid; v2 uuid; v3 uuid; bid uuid; aid uuid; r jsonb; saved jsonb;
 tech uuid:=gen_random_uuid(); helper uuid:=gen_random_uuid(); ver integer; rejected boolean:=false;
 validator_definition text; validator_fixture_definition text;
 overdue_definition text; overdue_fixture_definition text;
BEGIN
 PERFORM pg_temp.ou_assert(public.workshop_calendar_minute_available(t),'Start test runs during real workshop hours');
 later:=public.workshop_admin_next_operational_minute(t+interval '2 days');

 -- Reproduction: an early start previously pulled future queued work into downtime.
 bay:=pg_temp.ou_bay('early','FITTING');
 v:=pg_temp.ou_vehicle('early'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 target:=pg_temp.ou_booking('early',v,'FITTING',bay,later);
 v2:=pg_temp.ou_vehicle('early-follower'); PERFORM pg_temp.ou_operation(v2,'FITTING',1);
 follower:=pg_temp.ou_booking('early-follower',v2,'FITTING',bay,public.workshop_add_operational_minutes(later,60));
 SELECT to_jsonb(b) INTO saved FROM public.workshop_bookings b WHERE id=follower;
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,bay_id,'admin','Rollback fixed downtime',public.workshop_add_operational_minutes(t,60),public.workshop_add_operational_minutes(t,120),60,auth.uid(),auth.uid() FROM public.workshop_bookings WHERE id=target;
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=target;
 r:=public.start_workshop_work(target,ver,t+interval '1 year','{"rollback_fixture":true}');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Early start succeeds without moving future jobs into downtime',r);
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=t AND actual_start_at=t AND status='started' FROM public.workshop_bookings WHERE id=target),'Actual start uses database now, ignoring client date');
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(b)=saved FROM public.workshop_bookings b WHERE id=follower),'Early start leaves unrelated future booking unchanged');
 r:=public.start_workshop_work(target,ver,t,'{}');
 PERFORM pg_temp.ou_assert(r->>'error'='version_conflict','Repeated stale start cannot move anything again',r);

 -- A late start pushes only intersecting rows, around downtime and across station handover.
 bay:=pg_temp.ou_bay('late','FITTING'); bay2:=pg_temp.ou_bay('late-next-station','FABRICATION');
 v:=pg_temp.ou_vehicle('late'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 -- Set up one historical synthetic planned row. The current API correctly
 -- disallows creating past work. This insertion-only exception names this fresh
 -- fixture UUID; restore and verify the exact validator before testing Start.
 validator_definition:=pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure);
 validator_fixture_definition:=replace(validator_definition,'if not p_allow_unchanged_past',
  'if p_vehicle_id <> '||quote_literal(v::text)||'::uuid and not p_allow_unchanged_past');
 IF validator_fixture_definition=validator_definition THEN RAISE EXCEPTION 'Historical fixture anchor changed'; END IF;
 EXECUTE validator_fixture_definition;
 overdue_definition:=pg_get_functiondef('public.workshop_reject_overdue_planned_booking()'::regprocedure);
 overdue_fixture_definition:=replace(overdue_definition,'IF public.workshop_future_only_schedule_enabled()',
  'IF new.vehicle_id <> '||quote_literal(v::text)||'::uuid AND public.workshop_future_only_schedule_enabled()');
 IF overdue_fixture_definition=overdue_definition THEN RAISE EXCEPTION 'Historical overdue fixture anchor changed'; END IF;
 EXECUTE overdue_fixture_definition;
 target:=pg_temp.ou_booking('late',v,'FITTING',bay,t-interval '30 minutes');
 EXECUTE validator_definition;
 EXECUTE overdue_definition;
 PERFORM pg_temp.ou_assert(pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure)=validator_definition,'Real booking validator restored before late-start test');
 PERFORM pg_temp.ou_assert(pg_get_functiondef('public.workshop_reject_overdue_planned_booking()'::regprocedure)=overdue_definition,'Overdue guard restored before late-start test');
 v2:=pg_temp.ou_vehicle('late-follower'); PERFORM pg_temp.ou_operation(v2,'FITTING',1); PERFORM pg_temp.ou_operation(v2,'FABRICATION',1,2);
 follower:=pg_temp.ou_booking('late-follower',v2,'FITTING',bay,public.workshop_add_operational_minutes(t,30));
 successor:=pg_temp.ou_booking('late-successor',v2,'FABRICATION',bay2,public.workshop_add_operational_minutes(t,90)+interval '1 hour');
 v3:=pg_temp.ou_vehicle('late-third'); PERFORM pg_temp.ou_operation(v3,'FITTING',1);
 third:=pg_temp.ou_booking('late-third',v3,'FITTING',bay,public.workshop_add_operational_minutes(t,90));
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,bay_id,'admin','Rollback fixed downtime',public.workshop_add_operational_minutes(t,150),public.workshop_add_operational_minutes(t,210),60,auth.uid(),auth.uid() FROM public.workshop_bookings WHERE id=target RETURNING id INTO aid;
 SELECT to_jsonb(a) INTO saved FROM public.workshop_admin_blocks a WHERE id=aid;
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=target;
 r:=public.start_workshop_work(target,ver,t,'{"rollback_fixture":true}');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Late start safely cascades planned dependents',r);
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=public.workshop_add_operational_minutes(t,60) FROM public.workshop_bookings WHERE id=follower),'Only intersecting next job moves behind current work');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at>=public.workshop_add_operational_minutes(t,210) FROM public.workshop_bookings WHERE id=third),'Following job skips fixed downtime');
 PERFORM pg_temp.ou_assert((SELECT s.scheduled_start_at>=f.scheduled_end_at+interval '1 hour' FROM public.workshop_bookings s,public.workshop_bookings f WHERE s.id=successor AND f.id=follower),'Dependent station preserves one-hour vehicle handover');
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(a)=saved FROM public.workshop_admin_blocks a WHERE id=aid),'Admin downtime remains exactly unchanged');

 -- A real current-time block is explained without partially changing the queue.
 bay:=pg_temp.ou_bay('blocked','FITTING');
 v:=pg_temp.ou_vehicle('blocked'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 target:=pg_temp.ou_booking('blocked',v,'FITTING',bay,later);
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,bay_id,'admin','Rollback blocked now',t,public.workshop_add_operational_minutes(t,60),60,auth.uid(),auth.uid() FROM public.workshop_bookings WHERE id=target;
 SELECT to_jsonb(b),version INTO saved,ver FROM public.workshop_bookings b WHERE id=target;
 r:=public.start_workshop_work(target,ver,t,'{}');
 PERFORM pg_temp.ou_assert(r->>'error'='admin_block_conflict','Real downtime gives specific reason instead of fixed booking error',r);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(b)=saved FROM public.workshop_bookings b WHERE id=target),'Rejected start leaves booking and version unchanged');

 -- Assignments are retained, including a secondary technician.
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Rollback primary','technician',true),(helper,'Rollback secondary','technician',true);
 bay:=pg_temp.ou_bay('assignments','FITTING');
 v:=pg_temp.ou_vehicle('assignments'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 target:=pg_temp.ou_booking('assignments',v,'FITTING',bay,later);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,tech,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=target;
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,helper,'secondary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=target;
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=target;
 r:=public.start_workshop_work(target,ver,t,'{}');
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Assigned job starts safely',r);
 PERFORM pg_temp.ou_assert((SELECT count(*)=2 AND bool_and(a.scheduled_start_at=t AND a.scheduled_end_at=b.scheduled_end_at) FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE b.id=target AND a.released_at IS NULL),'Primary and secondary assignments follow booking and remain assigned');

 -- Concurrent live work is retained as physical truth.
 v2:=pg_temp.ou_vehicle('other-live'); PERFORM pg_temp.ou_operation(v2,'FITTING',1);
 bid:=pg_temp.ou_booking('other-live',v2,'FITTING',bay,public.workshop_add_operational_minutes(later,60));
 SELECT to_jsonb(b),version INTO saved,ver FROM public.workshop_bookings b WHERE id=bid;
 r:=public.start_workshop_work(bid,ver,t,'{}');
 PERFORM pg_temp.ou_assert(r->>'error'='bay_already_started','A bay already running work cannot start a second job',r);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(b)=saved FROM public.workshop_bookings b WHERE id=bid),'Live bay rejection changes no booking');

 -- A stoppage still occupies its bay even after its old estimated end time.
 bay:=pg_temp.ou_bay('expired-stoppage','FITTING');
 v:=pg_temp.ou_vehicle('expired-stoppage'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 follower:=pg_temp.ou_booking('expired-stoppage',v,'FITTING',bay,t-interval '2 hours','started');
 UPDATE public.workshop_bookings SET status='stoppage',stoppage_reason='Rollback parts stoppage',stoppage_started_at=t WHERE id=follower;
 SELECT to_jsonb(b) INTO saved FROM public.workshop_bookings b WHERE id=follower;
 v2:=pg_temp.ou_vehicle('after-stoppage'); PERFORM pg_temp.ou_operation(v2,'FITTING',1);
 bid:=pg_temp.ou_booking('after-stoppage',v2,'FITTING',bay,later);
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=bid;
 r:=public.start_workshop_work(bid,ver,t,'{}');
 PERFORM pg_temp.ou_assert(r->>'error'='bay_already_started','Expired estimated end does not free an occupied stopped bay',r);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(b)=saved FROM public.workshop_bookings b WHERE id=follower),'Stopped work remains unchanged');

 -- A secondary mechanic's live work blocks overlapping work elsewhere.
 bay:=pg_temp.ou_bay('secondary-conflict','FITTING');
 v:=pg_temp.ou_vehicle('secondary-conflict'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 bid:=pg_temp.ou_booking('secondary-conflict',v,'FITTING',bay,public.workshop_add_operational_minutes(later,120));
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,helper,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=bid;
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=bid;
 r:=public.start_workshop_work(bid,ver,t,'{}');
 PERFORM pg_temp.ou_assert(r->>'error'='technician_overlap','Secondary mechanic cannot be double booked by another start',r);

 UPDATE public.pdc_user_roles SET role='viewer' WHERE auth_user_id=auth.uid();
 BEGIN PERFORM public.start_workshop_work(bid,ver,t,'{}'); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 PERFORM pg_temp.ou_assert(rejected,'Viewer cannot start workshop work');
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('anon','public.start_workshop_work(uuid,integer,timestamptz,jsonb)','EXECUTE'),'Anonymous users cannot start work');
END $checks$;

SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data<>to_jsonb(b)),'Existing operational bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data<>to_jsonb(v)),'Existing vehicles unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM start_original_assignments o JOIN public.workshop_booking_assignments a ON a.id=o.id WHERE o.row_data<>to_jsonb(a)),'Existing assignments unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM start_original_blocks o JOIN public.workshop_admin_blocks a ON a.id=o.id WHERE o.row_data<>to_jsonb(a)),'Existing downtime unchanged');
SELECT jsonb_agg(to_jsonb(r) ORDER BY name) results FROM ou_results r;
ROLLBACK;
