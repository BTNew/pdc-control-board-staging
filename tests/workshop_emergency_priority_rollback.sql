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


DO $tests$
DECLARE
 f date; fit uuid; hoist uuid; slow uuid; urgent uuid; other uuid; urgent_fit uuid; urgent_hoist uuid; other_fit uuid; other_hoist uuid;
 p jsonb; saved jsonb; again jsonb; key uuid:=gen_random_uuid(); stock text; before_state text; before_count integer; started timestamptz; original_version integer;
BEGIN
 SELECT friday INTO f FROM ou_context;
 fit:=pg_temp.ou_bay('emergency-fit','FITTING'); UPDATE public.workshop_bays SET bay_number=991 WHERE id=fit;
 hoist:=pg_temp.ou_bay('emergency-hoist','HOIST'); UPDATE public.workshop_bays SET bay_number=992 WHERE id=hoist;
 slow:=pg_temp.ou_bay('emergency-slow','FITTING'); UPDATE public.workshop_bays SET bay_number=993,efficiency_percent=50 WHERE id=slow;
 -- Limit the test's bay choices to synthetic bays; these flags roll back.
 UPDATE public.workshop_bays SET is_active=false WHERE stage_id IN(SELECT stage_id FROM public.workshop_bays WHERE id IN(fit,hoist)) AND id NOT IN(fit,hoist,slow);
 urgent:=pg_temp.ou_vehicle('emergency-target'); other:=pg_temp.ou_vehicle('emergency-follower');
 PERFORM pg_temp.ou_operation(urgent,'FITTING',1); PERFORM pg_temp.ou_operation(urgent,'HOIST',1,2);
 PERFORM pg_temp.ou_operation(other,'FITTING',2); PERFORM pg_temp.ou_operation(other,'HOIST',1,2);
 urgent_fit:=pg_temp.ou_booking('urgent-fit',urgent,'FITTING',fit,(f+time '09:00') AT TIME ZONE 'Australia/Perth');
 urgent_hoist:=pg_temp.ou_booking('urgent-hoist',urgent,'HOIST',hoist,(f+time '15:00') AT TIME ZONE 'Australia/Perth');
 other_fit:=pg_temp.ou_booking('other-fit',other,'FITTING',fit,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 other_hoist:=pg_temp.ou_booking('other-hoist',other,'HOIST',hoist,(f+time '10:00') AT TIME ZONE 'Australia/Perth');
 started:=clock_timestamp();
 p:=pdc_workshop_priority_private.reschedule(urgent,(f+time '07:00') AT TIME ZONE 'Australia/Perth');
 PERFORM pg_temp.ou_assert(p->>'ok'='true','Emergency schedule applies including a dependency cycle',p);
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=(f+time '07:00') AT TIME ZONE 'Australia/Perth' AND bay_id=fit FROM public.workshop_bookings WHERE id=urgent_fit),
  'Priority chooses faster available bay over slower technician bay',p);
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=(f+time '08:00') AT TIME ZONE 'Australia/Perth' FROM public.workshop_bookings WHERE id=other_fit),
  'Conflicting planned job moves behind priority vehicle',p);
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=(f+time '11:00') AT TIME ZONE 'Australia/Perth' FROM public.workshop_bookings WHERE id=other_hoist),
  'Other vehicle cross-station successor also moves and retains one hour',p);
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=(f+time '09:00') AT TIME ZONE 'Australia/Perth' FROM public.workshop_bookings WHERE id=urgent_hoist),
  'Priority vehicle retains one hour between its stations',p);
 PERFORM pg_temp.ou_assert((SELECT capacity_base_minutes=60 AND default_duration_minutes=60 FROM public.workshop_bookings WHERE id=urgent_fit),
  'Priority retains operation hours and capacity basis');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN ou_original_bookings o ON o.id=b.id WHERE to_jsonb(b) IS DISTINCT FROM o.row_data),
  'Synthetic priority does not alter existing customer bookings');
 PERFORM pg_temp.ou_assert(true,'Emergency graph elapsed time',jsonb_build_object('milliseconds',extract(epoch FROM clock_timestamp()-started)*1000));
 SELECT stock_number INTO stock FROM public.vehicles WHERE id=urgent;
 before_state:=pdc_workshop_priority_private.state_hash(stock,now());
 p:=public.prioritise_workshop_vehicle(stock);
 PERFORM pg_temp.ou_assert(p->>'ok'='true' AND p->>'applied'='false','Public emergency preview succeeds',p);
 PERFORM pg_temp.ou_assert(pdc_workshop_priority_private.state_hash(stock,now())=before_state,'Preview rolls back every booking and vehicle change');
 UPDATE public.workshop_bays SET version=version+1 WHERE id=slow;
 saved:=public.prioritise_workshop_vehicle(stock,true,p->>'plan_hash',key);
 PERFORM pg_temp.ou_assert(saved->>'error'='stale_preview','Concurrent configuration change invalidates preview',saved);
 p:=public.prioritise_workshop_vehicle(stock);
 saved:=public.prioritise_workshop_vehicle(stock,true,p->>'plan_hash',key);
 PERFORM pg_temp.ou_assert(saved->>'applied'='true','Reviewed public emergency apply succeeds',saved);
 SELECT version INTO original_version FROM public.workshop_bookings WHERE id=urgent_fit;
 again:=public.prioritise_workshop_vehicle(stock,true,p->>'plan_hash',key);
 PERFORM pg_temp.ou_assert(again->>'replay'='true' AND (SELECT version=original_version FROM public.workshop_bookings WHERE id=urgent_fit),
  'Retry returns the same receipt without shifting bookings again',again);
 saved:=public.prioritise_workshop_vehicle('UNKNOWN-STOCK-TEST');
 PERFORM pg_temp.ou_assert(saved->>'error'='vehicle_not_unique','Unknown stock is rejected',saved);
 UPDATE public.vehicles SET current_location='YH' WHERE id=urgent;
 saved:=public.prioritise_workshop_vehicle(stock);
 PERFORM pg_temp.ou_assert(saved->>'ok'='false','Vehicle not at PMB cannot be emergency prioritised',saved);
 UPDATE public.vehicles SET current_location='PMB' WHERE id=urgent;
 UPDATE public.pdc_user_roles SET role='viewer' WHERE auth_user_id=(SELECT actor FROM ou_context);
 saved:=public.prioritise_workshop_vehicle(stock);
 PERFORM pg_temp.ou_assert(saved->>'ok'='false','Viewer cannot reprioritise bookings',saved);
 PERFORM set_config('request.jwt.claims','{}',true);
 saved:=public.prioritise_workshop_vehicle(stock);
 PERFORM pg_temp.ou_assert(saved->>'ok'='false','Anonymous caller cannot reprioritise bookings',saved);
END $tests$;
SELECT * FROM ou_results;
ROLLBACK;
