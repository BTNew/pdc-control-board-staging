-- Independent actual-write compatibility rehearsal. Apply candidate inside this transaction before fixtures.
BEGIN;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
CREATE TEMP TABLE deep_security_fixture(label text PRIMARY KEY,actor uuid,email text);
GRANT SELECT ON deep_security_fixture TO authenticated;
DO $fixtures$
DECLARE label text; actor uuid; email text; assigned_role public.pdc_role;
BEGIN
 FOREACH label IN ARRAY ARRAY['operator','importer','administrator','salesperson','viewer','fitter','pending','disabled','rejected','monitor'] LOOP
  actor:=gen_random_uuid();email:='deep-security-'||label||'-'||actor||'@example.invalid';
  INSERT INTO deep_security_fixture VALUES(label,actor,email);
  INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
   VALUES(actor,'authenticated','authenticated',email,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
  assigned_role:=CASE WHEN label='disabled' THEN 'operator'::public.pdc_role
   WHEN label IN('pending','rejected') THEN NULL WHEN label='monitor' THEN 'viewer'::public.pdc_role ELSE label::public.pdc_role END;
  UPDATE public.pdc_user_roles SET role=assigned_role,active=label NOT IN('pending','disabled','rejected'),
    account_status=(CASE WHEN label IN('pending','disabled','rejected') THEN label ELSE 'approved' END)::public.pdc_account_status WHERE auth_user_id=actor;
 END LOOP;
END $fixtures$;

DO $actual_monitor_setup$
DECLARE f record; approver uuid;
BEGIN
 SELECT * INTO f FROM deep_security_fixture WHERE label='monitor';
 SELECT actor INTO approver FROM deep_security_fixture WHERE label='administrator';
 INSERT INTO public.pdc_email_ai_successor_runtime_identities(auth_user_id,normalized_email,environment,identity_purpose,gateway_instance_id,transport_release_version,
 model_version,prompt_version,taxonomy_version,rule_version,action_contract_version,approved_by)
 VALUES(f.actor,f.email,'staging','pdc_email_ai_transaction_successor','deep-audit-rollback','audit','audit','audit','audit','audit','pdc-email-ai-actions-v1',approver);
 INSERT INTO public.pdc_monitor_stage_activation_writers(user_id,reason,granted_by) VALUES(f.actor,'Synthetic rollback security verification',approver);
END $actual_monitor_setup$;
-- Append this fragment AFTER $unchanged$ and BEFORE final ROLLBACK in security-hardening-rollback.sql.
-- Requires the synthetic deep_security_fixture from that suite and candidate applied/rehearsed.
-- All new operational rows, fixture calendars, auth accounts, grants and history roll back.
CREATE TEMP TABLE ou_context(actor uuid,email text,friday date,batch uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE ou_source_order;
CREATE TEMP TABLE ou_refs(name text PRIMARY KEY,id uuid NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ou_results(name text PRIMARY KEY,status text,evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE deep_original_vehicles AS SELECT id,to_jsonb(v) data FROM public.vehicles v;
CREATE TEMP TABLE deep_original_bookings AS SELECT id,to_jsonb(b) data FROM public.workshop_bookings b;
CREATE TEMP TABLE deep_actual_refs(label text PRIMARY KEY,vehicle uuid,bay uuid,bay_number integer,technician uuid,operation uuid,vehicle_version integer);
GRANT SELECT ON deep_actual_refs,ou_context TO authenticated;
GRANT SELECT,INSERT ON ou_results TO authenticated;
CREATE FUNCTION pg_temp.ou_assert(pass boolean,label text,evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO ou_results VALUES(label,'PASS',evidence);
END $fn$;
GRANT EXECUTE ON FUNCTION pg_temp.ou_assert(boolean,text,jsonb) TO authenticated;
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
 INSERT INTO public.workshop_bays(id,stage_id,bay_number,code,display_name,is_active)
 SELECT b,sid,coalesce(max(bay_number),0)+10000,'OU-'||b,'Rollback fixture '||tag,true FROM public.workshop_bays WHERE stage_id=sid;
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






DO $actual_setup$
DECLARE f record; a uuid; e text; batch_id uuid:=gen_random_uuid(); v uuid; bay uuid; tech uuid; op uuid;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 SELECT actor,email INTO a,e FROM deep_security_fixture WHERE label='operator';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 INSERT INTO ou_context VALUES(a,e,date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+18,batch_id);
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(batch_id,'pilbara_service_open_jobcards_v1',encode(extensions.digest(batch_id::text,'sha256'),'hex'),repeat('b',64),'deep-rollback-base-'||batch_id,'apply',1,1,0,1,0,0,'{}',a,e);
 -- The after-hours real clock must be available for fixture Start/Resume only.
 INSERT INTO public.workshop_settings(key,value,scope) VALUES
 ('day_start_time','"00:00"','global'),('day_end_time','"23:59"','global'),
 ('working_week','["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]','global'),
 ('closures','[]','global'),('break_windows','[]','global'),('overtime_windows','[]','global')
 ON CONFLICT(key) DO UPDATE SET value=excluded.value;
 FOR f IN SELECT * FROM deep_security_fixture WHERE label IN('operator','administrator','importer') LOOP
  v:=pg_temp.ou_vehicle('actual-'||f.label);bay:=pg_temp.ou_bay('actual-'||f.label,'FITTING');tech:=gen_random_uuid();
  INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Synthetic security rollback technician '||f.label||' '||substr(tech::text,1,8),'technician',true);
  UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
  op:=pg_temp.ou_operation(v,'FITTING',1,1);
  INSERT INTO deep_actual_refs SELECT f.label,v,bay,bay_number,tech,op,(SELECT version FROM public.vehicles WHERE id=v) FROM public.workshop_bays WHERE id=bay;
 END LOOP;
 -- Restore the synthetic writer fixture revoked by the preceding negative test.
 UPDATE public.pdc_monitor_stage_activation_writers SET active=true,revoked_at=NULL WHERE user_id=(SELECT actor FROM deep_security_fixture WHERE label='monitor');
END $actual_setup$;
SET LOCAL ROLE authenticated;
DO $actual_commands$
DECLARE f record; ref record; r jsonb; d jsonb; snap jsonb; bid uuid; vers integer; schedule_at timestamptz;
 event_row public.vehicle_timeline_events; eta_row public.vehicle_eta_history; denied boolean; observed text; operator_booking uuid;
BEGIN
 PERFORM set_config('request.method','POST',true);
 schedule_at:=((date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+14)::text||' 08:00+08')::timestamptz;
 FOR f IN SELECT * FROM deep_security_fixture WHERE label<>'monitor' ORDER BY label LOOP
  SELECT * INTO ref FROM deep_actual_refs WHERE label=CASE WHEN f.label IN('operator','administrator','importer') THEN f.label ELSE 'operator' END;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
  PERFORM set_config('pdc.monitor.v2_canonical_action_capability_20260902','',true);
  PERFORM set_config('request.path',CASE WHEN f.label='fitter' THEN '/rpc/fitter_job_command' ELSE '/rpc/append_vehicle_timeline_event' END,true);
  IF f.label='fitter' THEN PERFORM public.pdc_check_fitter_request(); END IF;
  denied:=false;
  BEGIN SELECT * INTO event_row FROM public.append_vehicle_timeline_event(ref.vehicle,'deep_security_actual_'||f.label);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF f.label IN('operator','administrator','importer','fitter') THEN
   PERFORM pg_temp.ou_assert(NOT denied AND event_row.vehicle_id=ref.vehicle,'Actual timeline insert and intelligence rebuild: '||f.label);
  ELSE PERFORM pg_temp.ou_assert(denied,'Actual timeline denies: '||f.label); END IF;
  PERFORM set_config('request.path','/rpc/record_vehicle_eta_history',true);
  denied:=false;
  BEGIN SELECT * INTO eta_row FROM public.record_vehicle_eta_history(ref.vehicle,'deep_security_actual_'||f.label,'2099-01-01');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF f.label IN('administrator','importer') THEN
   PERFORM pg_temp.ou_assert(NOT denied AND eta_row.vehicle_id=ref.vehicle AND eta_row.eta_value='2099-01-01','Actual ETA insert and intelligence rebuild: '||f.label);
  ELSE PERFORM pg_temp.ou_assert(denied,'Actual ETA denies: '||f.label); END IF;
  IF f.label IN('operator','administrator') THEN
   -- Full snapshots are checked in a separate transaction; these are actual writes.
   PERFORM set_config('request.path','/rpc/schedule_vehicle_work',true);
   r:=public.schedule_vehicle_work(ref.vehicle,ref.vehicle_version,'FITTING',ref.bay_number,schedule_at,60,ref.technician,NULL,'{"deep_rollback_fixture":true}');
   PERFORM pg_temp.ou_assert(r->>'ok'='true','Actual approved scheduling/assignment validation: '||f.label,r);
   bid:=(r#>>'{booking,booking_id}')::uuid;vers:=(r#>>'{booking,version}')::integer;
   PERFORM pg_temp.ou_assert(bid IS NOT NULL AND vers IS NOT NULL,'Scheduling receipt has canonical identity/version: '||f.label);
   PERFORM set_config('request.path','/rpc/move_workshop_booking',true);
   r:=public.move_workshop_booking(bid,vers,'FITTING',ref.bay_number,schedule_at+interval '1 hour',60,NULL,'{"deep_rollback_fixture":true}');
   PERFORM pg_temp.ou_assert(r->>'ok'='true','Actual approved move/internal eligibility: '||f.label,r);
   vers:=(r#>>'{booking,version}')::integer;
   PERFORM set_config('request.path','/rpc/resize_workshop_booking',true);
   r:=public.resize_workshop_booking(bid,vers,60,'{"deep_rollback_fixture":true}');
   PERFORM pg_temp.ou_assert(r->>'ok'='true','Actual approved resize/internal eligibility: '||f.label,r);
   IF f.label='operator' THEN operator_booking:=bid; END IF;
  END IF;
 END LOOP;
 -- Real scoped fitter role uses the existing approved command route, not helper calls.
 SELECT * INTO f FROM deep_security_fixture WHERE label='fitter';
 SELECT * INTO ref FROM deep_actual_refs WHERE label='operator';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
 PERFORM set_config('request.path','/rpc/get_fitter_job',true);PERFORM public.pdc_check_fitter_request();
 d:=public.get_fitter_job(ref.technician,operator_booking);
 PERFORM pg_temp.ou_assert(d->>'ok'='true' AND jsonb_array_length(d->'lines')>0,'Actual fitter scoped job/QC helper projection');
 PERFORM set_config('request.path','/rpc/fitter_job_command',true);PERFORM public.pdc_check_fitter_request();
 r:=public.fitter_job_command(ref.technician,operator_booking,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'start');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r->>'status'='started','Actual fitter Start/internal validation/timeline',r);
 PERFORM set_config('request.path','/rpc/get_fitter_job',true);PERFORM public.pdc_check_fitter_request();d:=public.get_fitter_job(ref.technician,operator_booking);
 PERFORM set_config('request.path','/rpc/fitter_job_command',true);PERFORM public.pdc_check_fitter_request();
 r:=public.fitter_job_command(ref.technician,operator_booking,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line','source:'||ref.operation,true,'Synthetic rollback check');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Actual fitter item completion',r);
 PERFORM set_config('request.path','/rpc/get_fitter_job',true);PERFORM public.pdc_check_fitter_request();d:=public.get_fitter_job(ref.technician,operator_booking);
 PERFORM set_config('request.path','/rpc/fitter_job_command',true);PERFORM public.pdc_check_fitter_request();
 r:=public.fitter_job_command(ref.technician,operator_booking,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'complete');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r->>'status'='completed','Actual fitter Complete/internal timeline',r);
 -- Trusted monitor has the sealed identity/writer binding established in the preceding suite.
 SELECT * INTO f FROM deep_security_fixture WHERE label='monitor';
 SELECT * INTO ref FROM deep_actual_refs WHERE label='importer';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
 PERFORM set_config('request.path','/rpc/append_vehicle_timeline_event',true);
 PERFORM set_config('pdc.monitor.v2_canonical_action_capability_20260902','pdc-email-ai-v2|synthetic-rollback-authority',true);
 SELECT * INTO event_row FROM public.append_vehicle_timeline_event(ref.vehicle,'deep_security_actual_monitor');
 PERFORM pg_temp.ou_assert(event_row.vehicle_id=ref.vehicle,'Actual trusted monitor timeline and intelligence rebuild');
 SELECT * INTO eta_row FROM public.record_vehicle_eta_history(ref.vehicle,'deep_security_actual_monitor','2099-01-02');
 PERFORM pg_temp.ou_assert(eta_row.vehicle_id=ref.vehicle,'Actual trusted monitor ETA and intelligence rebuild');
END $actual_commands$;
RESET ROLE;

-- Exercise QC's authorized public wrapper against the same synthetic source line.
CREATE TEMP TABLE deep_actual_qc(vehicle uuid,vehicle_version integer,line_identity text);
GRANT SELECT ON deep_actual_qc TO authenticated;
DO $qc_setup$
DECLARE f record; ref record;
BEGIN
 SELECT * INTO f FROM deep_security_fixture WHERE label='operator';
 SELECT * INTO ref FROM deep_actual_refs WHERE label='operator';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
 PERFORM set_config('pdc.monitor.v2_canonical_action_capability_20260902','',true);
 UPDATE public.vehicles SET current_location='QC',location_override=NULL WHERE id=ref.vehicle;
 INSERT INTO deep_actual_qc SELECT id,version,'source:'||ref.operation FROM public.vehicles WHERE id=ref.vehicle;
END $qc_setup$;
SET LOCAL ROLE authenticated;
DO $qc_actual$
DECLARE f record; ref record; r jsonb; key uuid:=gen_random_uuid(); denied boolean;
BEGIN
 SELECT * INTO f FROM deep_security_fixture WHERE label='operator';
 SELECT * INTO ref FROM deep_actual_qc;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
 PERFORM set_config('request.path','/rpc/set_pdc_qc_operation_completion_379',true);
 r:=public.set_pdc_qc_operation_completion_379(ref.vehicle,ref.vehicle_version,ref.line_identity,0,key,true);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r#>>'{line,line_identity}'=ref.line_identity AND r#>>'{line,completed}'='true','Actual approved QC completion/internal QC line helper');
 r:=public.set_pdc_qc_operation_completion_379(ref.vehicle,ref.vehicle_version,ref.line_identity,0,key,true);
 PERFORM pg_temp.ou_assert(r->>'replay'='true','Actual approved QC idempotent replay');
 SELECT * INTO f FROM deep_security_fixture WHERE label='salesperson';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
 denied:=false;
 BEGIN PERFORM public.set_pdc_qc_operation_completion_379(ref.vehicle,ref.vehicle_version,ref.line_identity,0,gen_random_uuid(),true);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 PERFORM pg_temp.ou_assert(denied,'Actual QC denies salesperson');
END $qc_actual$;
RESET ROLE;

SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM deep_original_vehicles o LEFT JOIN public.vehicles v ON v.id=o.id WHERE v.id IS NULL OR o.data<>to_jsonb(v)),'Every existing vehicle unchanged by actual fixture commands');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM deep_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE b.id IS NULL OR o.data<>to_jsonb(b)),'Every existing booking unchanged by actual fixture commands');
SELECT jsonb_agg(jsonb_build_object('name',name,'status',status) ORDER BY name) AS actual_operational_checks FROM ou_results;
-- The containing suite's final ROLLBACK removes all fixtures/calendar/snapshots.

ROLLBACK;
SELECT 'Actual isolated timeline/ETA/planner/fitter/QC compatibility checks passed; all fixtures rolled back' verification;
