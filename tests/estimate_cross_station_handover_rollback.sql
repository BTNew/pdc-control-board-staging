-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the operation-approval migration.
BEGIN;
DO $local$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'Owned loopback database only'; END IF; END $local$;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';
UPDATE public.workshop_settings SET value='"07:00"' WHERE key='day_start_time';
UPDATE public.workshop_settings SET value='"17:00"' WHERE key='day_end_time';
UPDATE public.workshop_settings SET value='[]' WHERE key IN('closures','break_windows','overtime_windows');
UPDATE public.workshop_settings SET value='["monday","tuesday","wednesday","thursday","friday","saturday"]' WHERE key='working_week';

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



CREATE FUNCTION pg_temp.estimate_test() RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $test$
DECLARE v uuid; op uuid; op2 uuid; h uuid; e uuid; b1 uuid; b2 uuid; f date; r jsonb; actor_id uuid; source_before jsonb; ver bigint;
BEGIN
 SELECT friday,actor INTO f,actor_id FROM ou_context;
 UPDATE public.pdc_user_roles SET role='administrator' WHERE auth_user_id=actor_id;
 INSERT INTO public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment,active)
 SELECT actor,email,'14450','staging',true FROM ou_context;
 v:=pg_temp.ou_vehicle('estimate-cross-station');
 INSERT INTO public.navision_backend_records(source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status,is_current,canonical_vehicle_id)
 SELECT 'ESTIMATE-ROLLBACK-'||v,repeat('e',64),jsonb_build_object('batch',(SELECT stock_number FROM public.vehicles WHERE id=v),'rego','QA','client','Synthetic fixture','vehicle','Rollback vehicle'),'{}',id,id,'microsoft_navision','14450','current',true,v
 FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='14450' AND status='applied' AND rolled_back_at IS NULL ORDER BY applied_at DESC LIMIT 1;
 op:=pg_temp.ou_operation(v,'HOIST',1,1);
 op2:=pg_temp.ou_operation(v,'ELECTRICAL',1,2);
 h:=pg_temp.ou_bay('estimate-hoist','HOIST');e:=pg_temp.ou_bay('estimate-electrical','ELECTRICAL');
 b1:=pg_temp.ou_booking('estimate-hoist',v,'HOIST',h,(f+time '08:00') AT TIME ZONE 'Australia/Perth');
 b2:=pg_temp.ou_booking('estimate-electrical',v,'ELECTRICAL',e,(f+time '10:00') AT TIME ZONE 'Australia/Perth');
 SELECT to_jsonb(o) INTO source_before FROM public.pdc_pilbara_service_operations o WHERE operation_id=op;
 SELECT version INTO ver FROM public.vehicles WHERE id=v;
 r:=public.save_vehicle_workshop_line_hours_batch_768(v,(SELECT stock_number FROM public.vehicles WHERE id=v),(SELECT job_card_number FROM public.vehicles WHERE id=v),ver,
 jsonb_build_array(jsonb_build_object('operation_line_id',op,'adjustment_id',NULL,'expected_line_version',0,'line_key','source:'||op,'stage_code','HOIST','work_key','hoist','estimated_hours',6),jsonb_build_object('operation_line_id',op2,'adjustment_id',NULL,'expected_line_version',0,'line_key','source:'||op2,'stage_code','ELECTRICAL','work_key','electrical','estimated_hours',2)),gen_random_uuid());
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Normal hours batch saves across later vehicle bookings',r);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=360 FROM public.workshop_bookings WHERE id=b1),'Hoist reserves full revised hours');
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=120 FROM public.workshop_bookings WHERE id=b2),'Electrical reserves its revised hours in the same batch');
 PERFORM pg_temp.ou_assert((SELECT b.scheduled_start_at>=a.scheduled_end_at+interval '1 hour' FROM public.workshop_bookings a CROSS JOIN public.workshop_bookings b WHERE a.id=b1 AND b.id=b2),'Electrical moves after full one-hour handover');
 PERFORM pg_temp.ou_assert(source_before=(SELECT to_jsonb(o) FROM public.pdc_pilbara_service_operations o WHERE operation_id=op),'Original source hours remain unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE vehicle_id=v AND scheduled_end_at<>public.workshop_add_operational_minutes(scheduled_start_at,default_duration_minutes)),'Calendar duration stays canonical');
END $test$;
GRANT EXECUTE ON FUNCTION pg_temp.estimate_test() TO authenticator;
SET LOCAL SESSION AUTHORIZATION authenticator;
SELECT pg_temp.estimate_test();
RESET SESSION AUTHORIZATION;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'Copied operational bookings unchanged');
SELECT name,status,evidence FROM ou_results ORDER BY name;
ROLLBACK;
