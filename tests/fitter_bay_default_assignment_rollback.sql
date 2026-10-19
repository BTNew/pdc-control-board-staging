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

CREATE FUNCTION pg_temp.ou_bay(tag text, stage text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE b uuid:=gen_random_uuid(); sid uuid;
BEGIN
 SELECT id INTO STRICT sid FROM public.workshop_stages WHERE code=stage AND active;
 INSERT INTO public.workshop_bays(id,stage_id,code,display_name,is_active)
 VALUES(b,sid,'OU-'||b,'Rollback fixture '||tag,true);
 UPDATE public.workshop_bays SET bay_number=(SELECT coalesce(max(bay_number),0)+1 FROM public.workshop_bays WHERE stage_id=sid) WHERE id=b;
 INSERT INTO ou_refs VALUES('bay-'||tag,b);
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
 'department',dept,'operation_description',CASE WHEN dept='138' AND stage='BUS_4X4' THEN 'Battery Compartment & Relay Box Protection' ELSE 'Fixture work '||stage||' line '||line_no END,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
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
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;

-- Only synthetic records are mutated. Snapshots include assignments and audit
-- history so a late rejection cannot leave an earlier descendant half-moved.
CREATE TEMP TABLE scope_original_assignments AS SELECT id,to_jsonb(a) row_data FROM public.workshop_booking_assignments a;
CREATE TEMP TABLE scope_original_blocks AS SELECT id,to_jsonb(a) row_data FROM public.workshop_admin_blocks a;
CREATE TEMP TABLE scope_original_receipts AS SELECT receipt_id,to_jsonb(a) row_data FROM public.workshop_booking_move_receipts a;

CREATE FUNCTION pg_temp.scope_state(ids uuid[]) RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT jsonb_build_object(
  'bookings',(SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') FROM public.workshop_bookings b WHERE b.id=any(ids)),
  'assignments',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.id),'[]') FROM public.workshop_booking_assignments a WHERE a.booking_id=any(ids)),
  'history',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.id),'[]') FROM public.workshop_booking_history h WHERE h.booking_id=any(ids)));
$fn$;

CREATE FUNCTION pg_temp.scope_move(bid uuid, destination uuid, at_time timestamptz, cascade boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE r jsonb; n integer; stage text; ver integer; mins integer;
BEGIN
 SELECT b.bay_number,s.code INTO STRICT n,stage FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=destination;
 SELECT version,default_duration_minutes INTO STRICT ver,mins FROM public.workshop_bookings WHERE id=bid;
 IF cascade THEN
  r:=public.cascade_workshop_booking_move(bid,ver,stage,n,at_time,mins,NULL,'{"source":"move_scope_rollback"}');
 ELSE
  r:=public.move_workshop_booking(bid,ver,stage,n,at_time,mins,NULL,'{"source":"move_scope_rollback"}');
 END IF;
 RETURN r;
EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '23514' THEN
 RETURN jsonb_build_object('ok',false,'error',SQLERRM,'sqlstate',SQLSTATE);
END $fn$;

CREATE FUNCTION pg_temp.scope_time(minutes integer DEFAULT 0) RETURNS timestamptz LANGUAGE sql AS $fn$
 SELECT public.workshop_add_operational_minutes(
  public.workshop_admin_next_operational_minute((friday+time '06:00') AT TIME ZONE 'Australia/Perth'),minutes) FROM ou_context;
$fn$;


DO $fitter_move$
DECLARE src uuid; dest uuid; spare uuid; v uuid; b uuid; conflict uuid; other uuid;
 oldtech uuid:=gen_random_uuid(); newtech uuid:=gen_random_uuid(); manualtech uuid:=gen_random_uuid();
 r jsonb; before_state jsonb; t timestamptz:=pg_temp.scope_time(120); ver integer;
BEGIN
 INSERT INTO public.workshop_technicians(id,name,role_type,active)
 VALUES(oldtech,'TEST OLD BAY FITTER','technician',true),(newtech,'TEST NEW BAY FITTER','technician',true),
 (manualtech,'TEST EXPLICIT FITTER','technician',true);
 src:=pg_temp.ou_bay('fitter-source','FITTING');dest:=pg_temp.ou_bay('fitter-destination','FITTING');
 spare:=pg_temp.ou_bay('fitter-other','FITTING');
 UPDATE public.workshop_bays SET default_technician_id=oldtech WHERE id=src;
 UPDATE public.workshop_bays SET default_technician_id=newtech WHERE id=dest;
 v:=pg_temp.ou_vehicle('fitter-follow-bay');PERFORM pg_temp.ou_operation(v,'FITTING',1);
 b:=pg_temp.ou_booking('fitter-follow-bay',v,'FITTING',src,t);
 PERFORM public.workshop_upsert_primary_assignment(b,oldtech,t,t+interval '1 hour','created');
 r:=pg_temp.scope_move(b,dest,t,true);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Cascade move succeeds with destination fitter',r);
 PERFORM pg_temp.ou_assert(pdc_fitter_private.assigned(b,newtech) AND NOT pdc_fitter_private.assigned(b,oldtech),'Moved bay job belongs to destination fitter');
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.workshop_booking_assignments WHERE booking_id=b AND technician_id=oldtech AND released_at IS NOT NULL),'Old assignment remains in history');
 UPDATE public.pdc_user_roles SET role='fitter' WHERE auth_user_id=auth.uid();
 PERFORM set_config('request.method','POST',true);PERFORM set_config('request.path','/rpc/get_fitter_refresh',true);
 PERFORM public.pdc_check_fitter_request();
 r:=public.get_fitter_refresh(newtech,NULL,NULL);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r->>'booking_id'=b::text AND r#>>'{detail,booking_id}'=b::text,'Selecting destination fitter loads moved job and checklist',r-'jobs'-'detail');
 PERFORM pg_temp.ou_assert(jsonb_array_length(public.get_fitter_jobs(oldtech)->'jobs')=0,'Previous fitter queue no longer shows reassigned work');
 UPDATE public.pdc_user_roles SET role='operator' WHERE auth_user_id=auth.uid();
 r:=pg_temp.scope_move(b,dest,pg_temp.scope_time(240),false);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND pdc_fitter_private.assigned(b,newtech),'Same-bay time move retains fitter',r);
 -- An explicit different mechanic stays assigned across a bay move.
 PERFORM public.workshop_upsert_primary_assignment(b,manualtech,x.scheduled_start_at,x.scheduled_end_at,'Explicit controller choice') FROM public.workshop_bookings x WHERE x.id=b;
 r:=pg_temp.scope_move(b,src,pg_temp.scope_time(360),false);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND pdc_fitter_private.assigned(b,manualtech),'Explicit fitter override remains assigned',r);
 -- Even a deliberately chosen fitter matching the old default is protected.
 PERFORM public.workshop_upsert_primary_assignment(b,oldtech,x.scheduled_start_at,x.scheduled_end_at,'Team choice') FROM public.workshop_bookings x WHERE x.id=b;
 PERFORM public.workshop_write_history(b,'team_changed',NULL,NULL,'{}');
 r:=pg_temp.scope_move(b,dest,pg_temp.scope_time(480),false);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND pdc_fitter_private.assigned(b,oldtech),'Explicit team history prevents automatic reassignment',r);
 -- Destination fitter conflict must reject before any booking/history changes.
 v:=pg_temp.ou_vehicle('fitter-conflict');PERFORM pg_temp.ou_operation(v,'FITTING',1);
 conflict:=pg_temp.ou_booking('fitter-conflict',v,'FITTING',spare,pg_temp.scope_time(600));
 PERFORM public.workshop_upsert_primary_assignment(conflict,newtech,pg_temp.scope_time(600),pg_temp.scope_time(660),'created');
 v:=pg_temp.ou_vehicle('fitter-conflict-target');PERFORM pg_temp.ou_operation(v,'FITTING',1);
 other:=pg_temp.ou_booking('fitter-conflict-target',v,'FITTING',src,pg_temp.scope_time(720));
 PERFORM public.workshop_upsert_primary_assignment(other,oldtech,pg_temp.scope_time(720),pg_temp.scope_time(780),'created');
 before_state:=pg_temp.scope_state(ARRAY[other,conflict]);
 r:=pg_temp.scope_move(other,dest,pg_temp.scope_time(600),true);
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND r::text LIKE '%technician_overlap%','Destination fitter conflict rejects move',r);
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[other,conflict])=before_state,'Rejected move leaves assignment and booking unchanged');
 -- Vehicle-removal paths can retain an unreleased assignment for history.
 -- Its soft-deleted parent must not reserve the fitter's time.
 UPDATE public.workshop_bookings SET deleted_at=clock_timestamp() WHERE id=conflict;
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.workshop_booking_assignments WHERE booking_id=conflict AND released_at IS NOT NULL),'Soft-deleting a booking releases its fitter reservation');
 r:=pg_temp.scope_move(other,dest,pg_temp.scope_time(600),true);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND pdc_fitter_private.assigned(other,newtech),'Deleted booking cannot block destination fitter assignment',r);
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.workshop_booking_assignments WHERE booking_id=conflict AND technician_id=newtech),'Historical deleted assignment is preserved');
END $fitter_move$;
DO $bus_move$
DECLARE src uuid; dest uuid; v uuid; b uuid; oldtech uuid:=gen_random_uuid(); newtech uuid:=gen_random_uuid(); r jsonb;
BEGIN
 INSERT INTO public.workshop_technicians(id,name,role_type,active)
 VALUES(oldtech,'TEST BUS SOURCE FITTER','technician',true),(newtech,'TEST BUS DESTINATION FITTER','technician',true);
 src:=pg_temp.ou_bay('bus-fitter-source','BUS_4X4');dest:=pg_temp.ou_bay('bus-fitter-destination','BUS_4X4');
 UPDATE public.workshop_bays SET default_technician_id=oldtech WHERE id=src;
 UPDATE public.workshop_bays SET default_technician_id=newtech WHERE id=dest;
 v:=pg_temp.ou_vehicle('bus-fitter-follow-bay');PERFORM pg_temp.ou_operation(v,'BUS_4X4',1,1,'138');
 PERFORM pg_temp.ou_assert(pdc_bus_private.active_vehicle(v),'Bus move fixture uses department 138 calendar and team rules');
 b:=pg_temp.ou_booking('bus-fitter-follow-bay',v,'BUS_4X4',src,pg_temp.scope_time(0));
 PERFORM public.workshop_upsert_primary_assignment(b,oldtech,x.scheduled_start_at,x.scheduled_end_at,'created') FROM public.workshop_bookings x WHERE x.id=b;
 r:=pg_temp.scope_move(b,dest,pg_temp.scope_time(60),true);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND pdc_fitter_private.assigned(b,newtech) AND NOT pdc_fitter_private.assigned(b,oldtech),'Bus cascade follows destination fitter through team interval trigger',r);
 UPDATE public.pdc_user_roles SET role='fitter' WHERE auth_user_id=auth.uid();
 PERFORM set_config('request.method','POST',true);PERFORM set_config('request.path','/rpc/get_fitter_refresh',true);
 PERFORM public.pdc_check_fitter_request();
 r:=public.get_fitter_refresh(newtech,NULL,NULL);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r->>'booking_id'=b::text AND r#>>'{detail,booking_id}'=b::text,'Bus destination fitter can load the moved job checklist',r-'jobs'-'detail');
 UPDATE public.pdc_user_roles SET role='operator' WHERE auth_user_id=auth.uid();
END $bus_move$;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE to_jsonb(b) IS DISTINCT FROM o.row_data),'Existing operational bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM scope_original_assignments o LEFT JOIN public.workshop_booking_assignments a ON a.id=o.id WHERE to_jsonb(a) IS DISTINCT FROM o.row_data),'Existing operational assignments unchanged');
SELECT name,status FROM ou_results ORDER BY name;
ROLLBACK;
