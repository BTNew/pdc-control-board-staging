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


DO $bookall$
DECLARE v uuid; v_missing uuid; v_late uuid; v_away uuid; v_conflict uuid; other uuid;
 f date; t timestamptz; r jsonb; repeat_result jsonb; n integer; bid uuid; provider uuid:=gen_random_uuid(); actor_id uuid;
 sid uuid; hbay uuid; fbay uuid; busy_until timestamptz; snapshot jsonb;
BEGIN
 SELECT friday,actor INTO f,actor_id FROM ou_context;
 v:=pg_temp.ou_vehicle('book-all-long');
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',57,1);
 PERFORM pg_temp.ou_operation(v,'FITTING',8.5,2);
 PERFORM pg_temp.ou_operation(v,'ELECTRICAL',3,3);
 PERFORM pg_temp.ou_operation(v,'SUBLET',0,4);
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=f-7 WHERE id=v;
 t:=clock_timestamp();
 r:=public.book_all_vehicle_stations(v,(SELECT version FROM public.vehicles WHERE id=v));
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND jsonb_array_length(r->'bookings')=3,'Long Book all succeeds across three stations',jsonb_build_object('elapsed_ms',extract(epoch FROM clock_timestamp()-t)*1000,'result',r));
 PERFORM pg_temp.ou_assert(NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=v AND (s.is_sublet OR s.code='SUBLET' OR b.scheduled_start_at<(f::timestamp AT TIME ZONE 'Australia/Perth'))
 ),'Book all excludes Sublet and respects IT ETA plus seven');
 PERFORM pg_temp.ou_assert(NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings a JOIN public.workshop_bookings b ON a.vehicle_id=b.vehicle_id AND a.id<>b.id AND a.scheduled_start_at<b.scheduled_start_at
  WHERE a.vehicle_id=v AND a.scheduled_end_at+interval '1 hour'>b.scheduled_start_at
 ),'Book all keeps one elapsed hour between stations');
 PERFORM pg_temp.ou_assert(NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v AND
   (NOT public.workshop_calendar_minute_available(b.scheduled_start_at)
    OR b.scheduled_end_at<>public.workshop_add_operational_minutes(b.scheduled_start_at,b.default_duration_minutes))
 ),'Book all preserves canonical duration and open start times');
 PERFORM pg_temp.ou_assert(NOT EXISTS(
  SELECT 1 FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE b.vehicle_id=v AND a.released_at IS NULL
 ),'Book all retains unassigned booking policy');
 SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) INTO snapshot FROM public.workshop_bookings b WHERE b.vehicle_id=v;
 repeat_result:=public.book_all_vehicle_stations(v,(SELECT version FROM public.vehicles WHERE id=v));
 PERFORM pg_temp.ou_assert(repeat_result->>'ok'='true' AND jsonb_array_length(repeat_result->'bookings')=0 AND jsonb_array_length(repeat_result->'skipped')=3
  AND snapshot=(SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bookings b WHERE b.vehicle_id=v),'Repeat Book all skips existing stations without duplicates');
 repeat_result:=public.book_all_vehicle_stations(v,0);
 PERFORM pg_temp.ou_assert(repeat_result->>'ok'='false' AND snapshot=(SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bookings b WHERE b.vehicle_id=v),'Stale Book all cannot alter existing bookings');

 v_missing:=pg_temp.ou_vehicle('book-all-missing-hours');
 PERFORM pg_temp.ou_operation(v_missing,'BUS_4X4',1,1);
 PERFORM pg_temp.ou_operation(v_missing,'FITTING',NULL,2);
 r:=public.book_all_vehicle_stations(v_missing,(SELECT version FROM public.vehicles WHERE id=v_missing));
 PERFORM pg_temp.ou_assert(r->>'ok'='false' AND r->>'error'='estimated_duration_missing'
  AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v_missing),'Missing later station hours makes no partial booking',r);

 v_late:=pg_temp.ou_vehicle('book-all-late-failure');
 PERFORM pg_temp.ou_operation(v_late,'BUS_4X4',1,1);
 PERFORM pg_temp.ou_operation(v_late,'FITTING',999,2);
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=f-7 WHERE id=v_late;
 r:=public.book_all_vehicle_stations(v_late,(SELECT version FROM public.vehicles WHERE id=v_late));
 PERFORM pg_temp.ou_assert(r->>'ok'='false' AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v_late),'Failure after first station rolls back every booking',r);

 v_away:=pg_temp.ou_vehicle('book-all-away');
 PERFORM pg_temp.ou_operation(v_away,'FITTING',1);
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=f-7 WHERE id=v_away;
 INSERT INTO public.sublet_providers(id,name,created_by,updated_by) VALUES(provider,'Rollback provider '||provider,actor_id,actor_id);
 INSERT INTO public.pdc_sublet_booking_instances(vehicle_id,vehicle_version,provider_id,provider_name,out_date,expected_return_date,created_by,updated_by)
 VALUES(v_away,(SELECT version FROM public.vehicles WHERE id=v_away),provider,'Rollback provider '||provider,f,f+1,actor_id,actor_id);
 r:=public.book_all_vehicle_stations(v_away,(SELECT version FROM public.vehicles WHERE id=v_away));
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b CROSS JOIN LATERAL generate_series((b.scheduled_start_at AT TIME ZONE 'Australia/Perth')::date::timestamp,
   ((b.scheduled_end_at-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day')d
  WHERE b.vehicle_id=v_away AND public.pdc_sublet_away_on_date(v_away,d::date)
 ),'Book all skips Sublet absence and closed Sunday',r);

 v_conflict:=pg_temp.ou_vehicle('book-all-vehicle-admin-bay');
 PERFORM pg_temp.ou_operation(v_conflict,'HOIST',1,1);
 PERFORM pg_temp.ou_operation(v_conflict,'FITTING',1,2);
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=f-7 WHERE id=v_conflict;
 hbay:=pg_temp.ou_bay('book-all-existing-hoist','HOIST');
 PERFORM pg_temp.ou_booking('book-all-existing-hoist',v_conflict,'HOIST',hbay,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 SELECT id INTO sid FROM public.workshop_stages WHERE code='FITTING';
 busy_until:=(f+time '10:00') AT TIME ZONE 'Australia/Perth';
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT sid,b.id,'admin','Rollback Book all fixture',busy_until-interval '1 hour',busy_until,60,actor_id,actor_id
 FROM public.workshop_bays b WHERE b.stage_id=sid AND b.is_active;
 SELECT id INTO fbay FROM public.workshop_bays WHERE stage_id=sid AND is_active ORDER BY bay_number LIMIT 1;
 other:=pg_temp.ou_vehicle('book-all-occupied-bay');
 PERFORM pg_temp.ou_operation(other,'FITTING',1);
 PERFORM pg_temp.ou_booking('book-all-occupied-bay',other,'FITTING',fbay,busy_until);
 r:=public.book_all_vehicle_stations(v_conflict,(SELECT version FROM public.vehicles WHERE id=v_conflict));
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND jsonb_array_length(r->'skipped')=1 AND EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v_conflict AND b.stage_id=sid AND b.scheduled_start_at=busy_until AND b.bay_id<>fbay
 ),'Book all combines existing vehicle handover, Admin block and occupied bay',r);
END $bookall$;
SET CONSTRAINTS ALL IMMEDIATE;
DO $unchanged$ BEGIN
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'All pre-existing bookings unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'All pre-existing vehicles unchanged');
END $unchanged$;
SELECT name,status,evidence FROM ou_results ORDER BY name;
ROLLBACK;
