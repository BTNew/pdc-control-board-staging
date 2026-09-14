-- STAGING ONLY: configured bay RPC audit using synthetic vehicles/operations.
-- Existing records are retained; revision, audit and fixture effects roll back.
-- Completion uses a separate synthetic stopped booking after current work.
-- Run the complete transaction in one connection; it always ends in ROLLBACK.
BEGIN;
SET LOCAL statement_timeout = '180s';
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




-- Only bays belonging to enabled physical workshop planners are audited.
-- PIT and Sublet retain their intentional configuration.
CREATE TEMP TABLE bay_audit_targets AS
SELECT b.id,b.code,b.bay_number,b.stage_id,b.is_active,b.efficiency_percent,s.code stage,s.work_key
FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
WHERE s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet
AND (nullif(current_setting('pdc.audit.bay_code',true),'') IS NULL OR b.code=current_setting('pdc.audit.bay_code',true));
CREATE TEMP TABLE bay_audit_original_bays AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bays b;
CREATE TEMP TABLE bay_audit_original_assignments AS SELECT id,to_jsonb(a) row_data FROM public.workshop_booking_assignments a;
CREATE TEMP TABLE bay_audit_original_work AS SELECT vehicle_id,work_key,to_jsonb(w) row_data FROM public.vehicle_work_items w;
CREATE TEMP TABLE bay_audit_original_operations AS SELECT operation_id,to_jsonb(o) row_data FROM public.pdc_pilbara_service_operations o;
CREATE TEMP TABLE bay_audit_actions(bay_code text,stage text,action text,status text,elapsed_ms numeric,evidence jsonb);
CREATE TEMP TABLE bay_audit_stats(started timestamptz);
INSERT INTO bay_audit_stats VALUES(clock_timestamp());
-- Serialize the synthetic calls against the same mutation gate as the website.
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

DO $configuration$
DECLARE item record; expected integer:=CASE WHEN nullif(current_setting('pdc.audit.bay_code',true),'') IS NULL THEN 43 ELSE 1 END;
BEGIN
 PERFORM pg_temp.ou_assert((SELECT count(*) FROM bay_audit_targets)=expected,'Expected configured physical workshop bay count',jsonb_build_object('expected',expected,'actual',(SELECT count(*) FROM bay_audit_targets)));
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bay_audit_targets WHERE NOT is_active),'All selected configured workshop bays are active');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT stage,bay_number FROM bay_audit_targets GROUP BY stage,bay_number HAVING count(*)>1),'Bay numbers resolve uniquely within each station');
 FOR item IN SELECT p.oid,p.oid::regprocedure::text signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('schedule_vehicle_work','move_workshop_booking','resize_workshop_booking','complete_workshop_work','list_workshop_bays') LOOP
  PERFORM pg_temp.ou_assert(has_function_privilege('authenticated',item.oid,'EXECUTE') AND NOT has_function_privilege('anon',item.oid,'EXECUTE'),'RPC permission '||item.signature);
 END LOOP;
END $configuration$;

DO $bay_checks$
DECLARE item record; vid uuid; booking_id uuid; r jsonb; starts timestamptz; moved_start timestamptz;
 mins integer; resized integer; ver integer; action_started timestamptz; previous_action text; errcode text; errmessage text; saved_claims text;
BEGIN
 -- The audit stays after all current reservations and uses a valid workshop day.
 SELECT public.workshop_clock_next_minute(
   (date_trunc('week',greatest(clock_timestamp(),
      coalesce((SELECT max(scheduled_end_at) FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('queued','planned','started','stoppage')),clock_timestamp()),
      coalesce((SELECT max(scheduled_end_at) FROM public.workshop_admin_blocks WHERE deleted_at IS NULL),clock_timestamp())) AT TIME ZONE 'Australia/Perth')::date+14+time '08:00') AT TIME ZONE 'Australia/Perth')
 INTO starts;
 FOR item IN SELECT * FROM bay_audit_targets ORDER BY stage,bay_number LOOP
  BEGIN
   previous_action:='prepare'; action_started:=clock_timestamp();
   vid:=pg_temp.ou_vehicle('configured-'||item.code); PERFORM pg_temp.ou_operation(vid,item.stage,0.5);
   mins:=public.workshop_capacity_duration_minutes(30,item.id);
   PERFORM pg_temp.ou_assert(public.workshop_resolve_bay_id(item.stage,item.bay_number)=item.id,'Resolve '||item.code);
   previous_action:='book'; action_started:=clock_timestamp();
   r:=public.schedule_vehicle_work(vid,(SELECT version FROM public.vehicles WHERE id=vid),item.stage,item.bay_number,starts,mins,NULL,NULL,'{"source":"configured_bay_rollback_audit"}');
   booking_id:=coalesce(r#>>'{booking,booking_id}',r#>>'{booking,id}')::uuid;
   PERFORM pg_temp.ou_assert(r->>'ok'='true' AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=booking_id AND b.bay_id=item.id AND b.status='planned' AND b.default_duration_minutes=mins AND b.scheduled_start_at=starts),'Book '||item.code,r);
   INSERT INTO bay_audit_actions VALUES(item.code,item.stage,'book','PASS',extract(epoch FROM clock_timestamp()-action_started)*1000,jsonb_build_object('booking_id',booking_id,'minutes',mins,'start',starts));
   previous_action:='resize'; action_started:=clock_timestamp();
   SELECT version INTO ver FROM public.workshop_bookings WHERE id=booking_id;
   resized:=mins+15;
   r:=public.resize_workshop_booking(booking_id,ver,resized,'{"source":"configured_bay_rollback_audit"}');
   PERFORM pg_temp.ou_assert(r->>'ok'='true' AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=booking_id AND b.default_duration_minutes=resized) AND public.workshop_vehicle_stage_estimated_duration_minutes(vid,item.stage_id)=30,'Resize '||item.code,r);
   INSERT INTO bay_audit_actions VALUES(item.code,item.stage,'resize','PASS',extract(epoch FROM clock_timestamp()-action_started)*1000,jsonb_build_object('minutes',resized,'quoted_minutes',30));
   previous_action:='stale_version'; action_started:=clock_timestamp();
   r:=public.resize_workshop_booking(booking_id,ver,resized+15,'{"source":"configured_bay_rollback_audit"}');
   PERFORM pg_temp.ou_assert(r->>'ok'='false' AND r->>'error'='version_conflict' AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=booking_id AND b.default_duration_minutes=resized),'Reject stale resize '||item.code,r);
   INSERT INTO bay_audit_actions VALUES(item.code,item.stage,'stale_version','PASS',extract(epoch FROM clock_timestamp()-action_started)*1000,jsonb_build_object('error',r->>'error'));
   previous_action:='move'; action_started:=clock_timestamp();
   SELECT version INTO ver FROM public.workshop_bookings WHERE id=booking_id;
   moved_start:=public.workshop_add_operational_minutes(starts,120);
   r:=public.move_workshop_booking(booking_id,ver,item.stage,item.bay_number,moved_start,NULL,NULL,'{"source":"configured_bay_rollback_audit"}');
   PERFORM pg_temp.ou_assert(r->>'ok'='true' AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=booking_id AND b.bay_id=item.id AND b.scheduled_start_at=moved_start AND b.default_duration_minutes=resized),'Move '||item.code,r);
   INSERT INTO bay_audit_actions VALUES(item.code,item.stage,'move','PASS',extract(epoch FROM clock_timestamp()-action_started)*1000,jsonb_build_object('start',moved_start,'minutes',resized));
   -- Test completion from STOPPAGE without occupying the bay's single live-job
   -- slot or invoking the Start button's deliberate snap to present time.
   previous_action:='prepare_completion';
vid:=pg_temp.ou_vehicle('completion-'||item.code); PERFORM pg_temp.ou_operation(vid,item.stage,0.5);
   moved_start:=public.workshop_add_operational_minutes(moved_start,120);
   booking_id:=pg_temp.ou_booking('completion-'||item.code,vid,item.stage,item.id,moved_start,'stoppage');
   SELECT default_duration_minutes INTO resized FROM public.workshop_bookings WHERE id=booking_id;
   UPDATE public.workshop_bookings SET actual_start_at=moved_start,stoppage_reason='Synthetic completion audit',stoppage_started_at=moved_start+interval '15 minutes',version=version+1 WHERE id=booking_id;
   previous_action:='complete'; action_started:=clock_timestamp();
   SELECT version INTO ver FROM public.workshop_bookings WHERE id=booking_id;
   r:=public.complete_workshop_work(booking_id,ver,item.work_key,public.workshop_add_operational_minutes(moved_start,resized),'{"source":"configured_bay_rollback_audit"}');
   PERFORM pg_temp.ou_assert(r->>'ok'='true' AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=booking_id AND b.status='completed' AND b.bay_id=item.id AND b.default_duration_minutes=resized) AND EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=vid AND w.work_key=item.work_key AND w.completed),'Complete '||item.code,r);
   INSERT INTO bay_audit_actions VALUES(item.code,item.stage,'complete','PASS',extract(epoch FROM clock_timestamp()-action_started)*1000,jsonb_build_object('completed',true));
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS errcode=RETURNED_SQLSTATE,errmessage=MESSAGE_TEXT;
   INSERT INTO bay_audit_actions VALUES(item.code,item.stage,previous_action,'FAIL',extract(epoch FROM clock_timestamp()-action_started)*1000,jsonb_build_object('code',errcode,'message',errmessage,'response',r));
  END;
 END LOOP;
 -- Approved operator claims are checked by the actual RPC; an unsigned call fails.
 vid:=pg_temp.ou_vehicle('unsigned-denied'); SELECT * INTO item FROM bay_audit_targets ORDER BY stage,bay_number LIMIT 1;
 PERFORM pg_temp.ou_operation(vid,item.stage,0.5);
 saved_claims:=current_setting('request.jwt.claims',true); PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
 BEGIN
  r:=public.schedule_vehicle_work(vid,(SELECT version FROM public.vehicles WHERE id=vid),item.stage,item.bay_number,starts,30,NULL,NULL,'{}');
  PERFORM pg_temp.ou_assert(false,'Unsigned scheduling denied',r);
 EXCEPTION WHEN insufficient_privilege THEN
  PERFORM set_config('request.jwt.claims',saved_claims,true);
  PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=vid),'Unsigned scheduling denied without a booking');
 END;
 PERFORM set_config('request.jwt.claims',saved_claims,true);
END $bay_checks$;

DO $preservation$
BEGIN
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'Every existing booking is unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o LEFT JOIN public.vehicles v ON v.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'Every existing vehicle is unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bay_audit_original_bays o LEFT JOIN public.workshop_bays b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'Every configured bay is unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bay_audit_original_assignments o LEFT JOIN public.workshop_booking_assignments a ON a.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'Every existing mechanic assignment is unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bay_audit_original_work o LEFT JOIN public.vehicle_work_items w ON w.vehicle_id=o.vehicle_id AND w.work_key=o.work_key WHERE o.row_data IS DISTINCT FROM to_jsonb(w)),'Every existing vehicle work item is unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bay_audit_original_operations o LEFT JOIN public.pdc_pilbara_service_operations p ON p.operation_id=o.operation_id WHERE o.row_data IS DISTINCT FROM to_jsonb(p)),'Every existing imported operation is unchanged');
END $preservation$;
SELECT jsonb_build_object(
 'bay_count',(SELECT count(*) FROM bay_audit_targets),
 'passing_assertions',(SELECT count(*) FROM ou_results WHERE status='PASS'),
 'passing_actions',(SELECT count(*) FROM bay_audit_actions WHERE status='PASS'),
 'failed_actions',(SELECT count(*) FROM bay_audit_actions WHERE status='FAIL'),
 'elapsed_ms',(SELECT extract(epoch FROM clock_timestamp()-started)*1000 FROM bay_audit_stats),
 'stages',(SELECT jsonb_agg(x) FROM (SELECT stage,count(DISTINCT bay_code) bays,count(*) FILTER(WHERE status='PASS') passing_actions,count(*) FILTER(WHERE status='FAIL') failures FROM bay_audit_actions GROUP BY stage ORDER BY stage) x),
 'actions',(SELECT jsonb_agg(a ORDER BY stage,bay_code,action) FROM bay_audit_actions a),
 'preservation',(SELECT jsonb_agg(name ORDER BY name) FROM ou_results WHERE name LIKE 'Every existing%' OR name LIKE 'Every configured%')
) result;
ROLLBACK;
