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
 'department',dept,'operation_description','Fixture work '||stage||' line '||line_no,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
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







CREATE FUNCTION pg_temp.bc_at(day date,t time) RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $fn$
 SELECT (day+t) AT TIME ZONE 'Australia/Perth'
$fn$;
CREATE FUNCTION pg_temp.bc_bay(n integer) RETURNS uuid LANGUAGE sql STABLE AS $fn$
 SELECT b.id FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE s.code='BUS_4X4' AND b.bay_number=n AND b.is_active
$fn$;
CREATE FUNCTION pg_temp.bc_activate(vid uuid) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE old_op record;
BEGIN
 -- Legacy calendar fixture: add authenticated Department138 evidence and
 -- supersede only the synthetic provisional line through its normal adjustment.
 -- Source import evidence remains append-only throughout the test.
 FOR old_op IN SELECT * FROM public.pdc_pilbara_service_operations WHERE vehicle_id=vid AND department='139' LOOP
  PERFORM pg_temp.ou_operation(vid,old_op.proposed_station,old_op.effective_estimated_hours,old_op.original_line_number+100,'138');
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,description,stage_code,estimated_hours,active,created_by,updated_by)
  VALUES(vid,'source:'||old_op.operation_id,'source',old_op.operation_description,old_op.proposed_station,old_op.effective_estimated_hours,false,auth.uid(),auth.uid());
 END LOOP;
 PERFORM pg_temp.ou_assert(pdc_bus_private.active_vehicle(vid),'Department138 fixture active '||vid);
END $fn$;
CREATE FUNCTION pg_temp.bc_booking(tag text,stage text,bay uuid,at_time timestamptz,minutes integer,
 bus_variant text DEFAULT 'legacy',state public.workshop_booking_status DEFAULT 'planned',model_name text DEFAULT 'Toyota HiAce Commuter')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid; b uuid; tech uuid:=gen_random_uuid(); parts jsonb;
BEGIN
 v:=pg_temp.ou_vehicle(tag);
 UPDATE public.vehicles SET vehicle_description=model_name,model=model_name WHERE id=v;
 PERFORM pg_temp.ou_operation(v,stage,minutes::numeric/60,1);
 IF bus_variant='current' THEN
  PERFORM pg_temp.bc_activate(v);
  parts:=jsonb_build_object('ready',true,'scope_hash',pdc_bus_private.catalog_hash(v),'note','Synthetic physical parts evidence');
  INSERT INTO pdc_bus_private.workflow(vehicle_id,version,plan,updated_by)
  VALUES(v,1,jsonb_build_object('parts_readiness',jsonb_build_object('mechanical',parts,'electrical',parts,'accessory',parts)),auth.uid());
 END IF;
 b:=pg_temp.ou_booking(tag,v,stage,bay,at_time,state);
 IF bus_variant='legacy' THEN PERFORM pg_temp.bc_activate(v); END IF;
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Bus clock rollback '||tag||' '||tech,'technician',true);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,tech,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=b;
 RETURN b;
END $fn$;


CREATE TEMP TABLE uq_original_assignments AS SELECT id,to_jsonb(a) row_data FROM public.workshop_booking_assignments a;
CREATE TEMP TABLE uq_original_history AS SELECT id,to_jsonb(h) row_data FROM public.workshop_booking_history h;
CREATE TEMP TABLE uq_original_operations AS SELECT operation_id,to_jsonb(o) row_data FROM public.pdc_pilbara_service_operations o;
DO $checks$
DECLARE day date; scenario text; b uuid; v uuid; bay uuid; stage text; state public.workshop_booking_status;
 ver integer; denied boolean; result jsonb; before_row jsonb; after_row jsonb; vehicle_before jsonb;
 assignments_before jsonb; history_before jsonb; history_after jsonb; source_before jsonb; work_before jsonb; workflow_before jsonb;
BEGIN
 day:=date_trunc('week',greatest(clock_timestamp()+interval '30 days',coalesce((SELECT max(scheduled_end_at) FROM public.workshop_bookings),clock_timestamp())+interval '30 days') AT TIME ZONE 'Australia/Perth')::date+7;
 FOREACH scenario IN ARRAY ARRAY['fitting-planned','coaster-planned','fitting-started','fitting-stoppage'] LOOP
  PERFORM set_config('qa.bus_clock_case','unallocate-'||scenario,true);
  stage:=CASE WHEN scenario='coaster-planned' THEN 'BUS_4X4' ELSE 'FITTING' END;
  state:=CASE scenario WHEN 'fitting-started' THEN 'started' WHEN 'fitting-stoppage' THEN 'stoppage' ELSE 'planned' END;
  bay:=CASE WHEN stage='BUS_4X4' THEN pg_temp.bc_bay(3) ELSE pg_temp.ou_bay('unallocate-'||scenario,'FITTING') END;
  b:=pg_temp.bc_booking('unallocate-'||scenario,stage,bay,pg_temp.bc_at(day,time '07:00'),60,CASE WHEN stage='BUS_4X4' THEN 'legacy' ELSE 'none' END,state,'Toyota Coaster');
  SELECT vehicle_id,version,to_jsonb(x) INTO v,ver,before_row FROM public.workshop_bookings x WHERE id=b;
  PERFORM public.workshop_write_history(b,'created',NULL,public.workshop_booking_snapshot(b),'{"rollback_fixture":"planned_unallocate"}');
  SELECT to_jsonb(x) INTO vehicle_before FROM public.vehicles x WHERE id=v;
  SELECT jsonb_agg(to_jsonb(a) ORDER BY id) INTO assignments_before FROM public.workshop_booking_assignments a WHERE booking_id=b;
  SELECT jsonb_agg(to_jsonb(h) ORDER BY id) INTO history_before FROM public.workshop_booking_history h WHERE booking_id=b;
  SELECT jsonb_agg(to_jsonb(o) ORDER BY operation_id) INTO source_before FROM public.pdc_pilbara_service_operations o WHERE vehicle_id=v;
  SELECT jsonb_agg(to_jsonb(w) ORDER BY work_key) INTO work_before FROM public.vehicle_work_items w WHERE vehicle_id=v;
  SELECT to_jsonb(w) INTO workflow_before FROM pdc_bus_private.workflow w WHERE vehicle_id=v;
  denied:=false;
  BEGIN
   UPDATE public.workshop_bookings SET status='queued',bay_id=NULL,returned_to_queue_at=clock_timestamp(),version=version+1 WHERE id=b;
  EXCEPTION WHEN SQLSTATE '22023' THEN denied:=true;
  END;
  PERFORM pg_temp.ou_assert(denied,scenario||' direct unapproved transition is rejected');
  PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=before_row FROM public.workshop_bookings x WHERE id=b),scenario||' rejected direct transition leaves booking unchanged');
  result:=public.return_work_to_queue(b,ver+1,NULL,'{"source":"wrong_version_before_return"}');
  PERFORM pg_temp.ou_assert(result->>'error'='version_conflict' AND (SELECT to_jsonb(x)=before_row FROM public.workshop_bookings x WHERE id=b),scenario||' wrong version cannot unallocate planned or active work');
  PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_transition_authorizations WHERE txid=txid_current() AND booking_id=b AND transition='return_to_queue'),scenario||' failed request leaves no authorization token');
  denied:=false;
  BEGIN
   UPDATE public.workshop_bookings SET status='queued',bay_id=NULL,returned_to_queue_at=clock_timestamp(),version=version+1 WHERE id=b;
  EXCEPTION WHEN SQLSTATE '22023' THEN denied:=true;
  END;
  PERFORM pg_temp.ou_assert(denied,scenario||' direct transition stays denied after version conflict');
  result:=public.return_work_to_queue(b,ver,NULL,'{"source":"planned_unallocate_rollback"}');
  PERFORM pg_temp.ou_assert(result->>'ok'='true',scenario||' authorized return to Unallocated succeeds',result);
  SELECT to_jsonb(x) INTO after_row FROM public.workshop_bookings x WHERE id=b;
  PERFORM pg_temp.ou_assert(after_row->>'status'='queued' AND after_row->>'bay_id' IS NULL
   AND after_row->>'returned_to_queue_at' IS NOT NULL AND (after_row->>'version')::int=ver+1,scenario||' becomes queued with no bay and one version increment');
  PERFORM pg_temp.ou_assert(before_row-array['status','bay_id','returned_to_queue_at','stoppage_reason','stoppage_started_at','updated_by','updated_at','version']
    IS NOT DISTINCT FROM after_row-array['status','bay_id','returned_to_queue_at','stoppage_reason','stoppage_started_at','updated_by','updated_at','version'],
   scenario||' duration scheduled times actual evidence and other protected fields remain intact');
  PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_booking_assignments WHERE booking_id=b AND released_at IS NULL)
   AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(assignments_before) old_row LEFT JOIN public.workshop_booking_assignments a ON a.id=(old_row->>'id')::uuid
    WHERE (old_row-array['released_at','updated_at']) IS DISTINCT FROM (to_jsonb(a)-array['released_at','updated_at'])),scenario||' assignment is released without rewriting its work interval');
  PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_transition_authorizations WHERE txid=txid_current() AND booking_id=b AND transition='return_to_queue'),scenario||' single-use transition authorization is consumed');
  PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(history_before) old_row LEFT JOIN public.workshop_booking_history h ON h.id=(old_row->>'id')::uuid
   WHERE old_row IS DISTINCT FROM to_jsonb(h)) AND EXISTS(SELECT 1 FROM public.workshop_booking_history WHERE id=(result->>'history_id')::uuid AND booking_id=b AND event_type='returned_to_queue'),scenario||' prior history is retained and return is audited');
  SELECT jsonb_agg(to_jsonb(h) ORDER BY id) INTO history_after FROM public.workshop_booking_history h WHERE booking_id=b;
  result:=public.return_work_to_queue(b,ver,NULL,'{"source":"repeat_stale_request"}');
  PERFORM pg_temp.ou_assert(result->>'error'='version_conflict' AND (SELECT to_jsonb(x)=after_row FROM public.workshop_bookings x WHERE id=b),scenario||' replay with stale version does not repeat the mutation',result-'conflict');
  PERFORM pg_temp.ou_assert(history_after IS NOT DISTINCT FROM (SELECT jsonb_agg(to_jsonb(h) ORDER BY id) FROM public.workshop_booking_history h WHERE booking_id=b),scenario||' stale retry adds no history');
  PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_transition_authorizations WHERE txid=txid_current() AND booking_id=b AND transition='return_to_queue'),scenario||' stale retry leaves no usable transition authorization');
  PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=vehicle_before FROM public.vehicles x WHERE id=v)
   AND source_before IS NOT DISTINCT FROM (SELECT jsonb_agg(to_jsonb(o) ORDER BY operation_id) FROM public.pdc_pilbara_service_operations o WHERE vehicle_id=v)
   AND work_before IS NOT DISTINCT FROM (SELECT jsonb_agg(to_jsonb(w) ORDER BY work_key) FROM public.vehicle_work_items w WHERE vehicle_id=v)
   AND workflow_before IS NOT DISTINCT FROM (SELECT to_jsonb(w) FROM pdc_bus_private.workflow w WHERE vehicle_id=v),scenario||' location parts readiness imported work and completed flags are untouched');
  day:=day+7;
 END LOOP;
END $checks$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'All original customer bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o LEFT JOIN public.vehicles v ON v.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'All original customer vehicle records unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM uq_original_assignments o LEFT JOIN public.workshop_booking_assignments a ON a.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'All original technician assignments unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM uq_original_history o LEFT JOIN public.workshop_booking_history h ON h.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(h)),'All original history unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM uq_original_operations o LEFT JOIN public.pdc_pilbara_service_operations a ON a.operation_id=o.operation_id WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'All original imported operation evidence unchanged');
SELECT jsonb_build_object('count',count(*),'checks',jsonb_agg(jsonb_build_object('name',name,'status',status) ORDER BY name)) result FROM ou_results;
ROLLBACK;
