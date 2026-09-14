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
-- Run after the one-hour handover migration. All fixture changes roll back.
DO $handover$
DECLARE v uuid; compact_v uuid; f date; h uuid; fit uuid; e uuid; first_id uuid; second_id uuid; third_id uuid;
 p jsonb; a timestamptz; b timestamptz; stock text; compact_id uuid; minute_count integer;
BEGIN
 SELECT friday INTO f FROM ou_context;
 h:=pg_temp.ou_bay('one-hour-hoist','HOIST');
 fit:=pg_temp.ou_bay('one-hour-fitting','FITTING');
 e:=pg_temp.ou_bay('one-hour-electrical','ELECTRICAL');
 v:=pg_temp.ou_vehicle('one-hour-boundary');
 SELECT stock_number INTO stock FROM public.vehicles WHERE id=v;
 PERFORM pg_temp.ou_operation(v,'HOIST',1,1);
 PERFORM pg_temp.ou_operation(v,'FITTING',1,2);
 PERFORM pg_temp.ou_operation(v,'ELECTRICAL',1,3);
 first_id:=pg_temp.ou_booking('one-hour-first',v,'HOIST',h,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 second_id:=pg_temp.ou_booking('one-hour-second',v,'FITTING',fit,(f+time '09:00') AT TIME ZONE 'Australia/Perth');
 third_id:=pg_temp.ou_booking('one-hour-third',v,'ELECTRICAL',e,(f+time '10:59') AT TIME ZONE 'Australia/Perth');
 p:=public.get_pdc_vehicle_planning_windows(NULL,clock_timestamp()-interval '1 minute');
 PERFORM pg_temp.ou_assert(p->>'buffer_minutes'='60','Planning-window DTO advertises sixty-minute spacing',p-'windows'-'warnings');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'warnings') w
   WHERE w->>'stock'=stock AND w->>'first_stage'='HOIST' AND w->>'next_stage'='FITTING'),
   'Exactly sixty minutes between vehicle bookings has no warning');
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(p->'warnings') w
   WHERE w->>'stock'=stock AND w->>'first_stage'='FITTING' AND w->>'next_stage'='ELECTRICAL' AND w->>'overlap'='false'),
   'Fifty-nine minutes still reports a short handover');
 UPDATE public.workshop_bookings SET scheduled_start_at=(f+time '11:00') AT TIME ZONE 'Australia/Perth',
   scheduled_end_at=(f+time '12:00') AT TIME ZONE 'Australia/Perth',version=version+1 WHERE id=third_id;
 p:=public.get_pdc_vehicle_planning_windows(NULL,clock_timestamp()-interval '1 minute');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'warnings') w WHERE w->>'stock'=stock),
   'Moving the fifty-nine-minute gap to sixty clears the warning');
 -- Compaction stays in this station and stops exactly one hour after the
 -- same vehicle finishes its earlier station.
 compact_v:=pg_temp.ou_vehicle('one-hour-compaction');
 PERFORM pg_temp.ou_operation(compact_v,'HOIST',1,1);
 PERFORM pg_temp.ou_operation(compact_v,'FITTING',1,2);
 h:=pg_temp.ou_bay('one-hour-compact-hoist','HOIST');
 fit:=pg_temp.ou_bay('one-hour-compact-fitting','FITTING');
 PERFORM pg_temp.ou_booking('one-hour-compact-first',compact_v,'HOIST',h,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 compact_id:=pg_temp.ou_booking('one-hour-compact-second',compact_v,'FITTING',fit,(f+time '13:00') AT TIME ZONE 'Australia/Perth');
 p:=public.workshop_capacity_plan('FITTING',NULL,NULL,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 PERFORM pg_temp.ou_assert(p->>'can_apply'='true' AND (SELECT final_start=(f+time '09:00') AT TIME ZONE 'Australia/Perth'
  AND final_end=(f+time '10:00') AT TIME ZONE 'Australia/Perth' AND changed
  FROM pg_temp.workshop_capacity_plan WHERE booking_id=compact_id),
  'Close gaps pulls thirteen-hundred booking forward to the exact one-hour boundary',p-'changes'-'warnings');
 -- The shortened handover changes elapsed spacing, never opening hours.
 a:=(f+1+time '11:00') AT TIME ZONE 'Australia/Perth';
 b:=public.workshop_admin_next_operational_minute(a+interval '1 hour');
 PERFORM pg_temp.ou_assert(b=(f+3+time '07:00') AT TIME ZONE 'Australia/Perth',
  'One-hour spacing finishing at Saturday noon still waits until Monday opening');
 a:=(f+time '16:30') AT TIME ZONE 'Australia/Perth';
 b:=public.workshop_add_operational_minutes(a,120);
 PERFORM pg_temp.ou_assert(b=(f+1+time '09:30') AT TIME ZONE 'Australia/Perth',
  'Multi-day duration still uses Friday and Saturday working minutes only');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings x
   JOIN public.workshop_bookings y ON x.vehicle_id=y.vehicle_id AND x.id<>y.id AND x.scheduled_start_at<y.scheduled_start_at
   WHERE x.vehicle_id IN(v,compact_v) AND x.scheduled_end_at>y.scheduled_start_at),
  'One-hour handovers retain true vehicle non-overlap');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=(f+time '13:00') AT TIME ZONE 'Australia/Perth' AND version=1
    FROM public.workshop_bookings WHERE id=compact_id),'Close gaps preview does not write the proposed earlier time');
END $handover$;

DO $clock_handover$
DECLARE v uuid; f date; h uuid; fit uuid; live_id uuid; planned_id uuid; p jsonb; clock_at timestamptz;
BEGIN
 SELECT friday INTO f FROM ou_context;
 v:=pg_temp.ou_vehicle('one-hour-clock');
 PERFORM pg_temp.ou_operation(v,'HOIST',1,1); PERFORM pg_temp.ou_operation(v,'FITTING',1,2);
 h:=pg_temp.ou_bay('one-hour-clock-hoist','HOIST'); fit:=pg_temp.ou_bay('one-hour-clock-fitting','FITTING');
 live_id:=pg_temp.ou_booking('one-hour-clock-live',v,'HOIST',h,(f+time '07:00') AT TIME ZONE 'Australia/Perth','started');
 planned_id:=pg_temp.ou_booking('one-hour-clock-planned',v,'FITTING',fit,(f+time '09:00') AT TIME ZONE 'Australia/Perth');
 clock_at:=(f+time '09:00') AT TIME ZONE 'Australia/Perth';
 p:=public.workshop_clock_tick(false,clock_at);
 PERFORM pg_temp.ou_assert((SELECT final_start=public.workshop_clock_next_minute(clock_at)+interval '1 hour'
    AND final_end=public.workshop_clock_next_minute(clock_at)+interval '2 hours'
    FROM pg_temp.clock_linked_plan WHERE id=planned_id),
  'Clock overrun moves the next station to one hour after the live job forecast',p-'plans'-'issues');
 PERFORM pg_temp.ou_assert((SELECT scheduled_end_at=(f+time '08:00') AT TIME ZONE 'Australia/Perth' AND version=1
    FROM public.workshop_bookings WHERE id=live_id)
  AND (SELECT scheduled_start_at=clock_at AND version=1 FROM public.workshop_bookings WHERE id=planned_id),
  'Clock preview changes no actual live or planned booking');
END $clock_handover$;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id
 WHERE to_jsonb(b) IS DISTINCT FROM o.row_data),'All pre-existing bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id
 WHERE to_jsonb(v) IS DISTINCT FROM o.row_data),'All pre-existing vehicles unchanged');
SELECT jsonb_build_object('count',count(*),'checks',jsonb_agg(jsonb_build_object('name',name,'status',status) ORDER BY name)) result FROM ou_results;
ROLLBACK;
