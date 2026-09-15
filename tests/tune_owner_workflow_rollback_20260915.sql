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
 contract_revision,source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(b,'pilbara_service_open_jobcards_v1',encode(extensions.digest(b::text,'sha256'),'hex'),repeat('b',64),'rollback-base-'||b,'apply','pmg_stock_v5',1,1,0,1,0,0,'{}',a,e);
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
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,jsonb_build_object('Company','01','Division','1','Status','20','Sub Status','99','Key Number','513','Parts Location','05C1A','source_snapshot_at','2026-09-15T04:00:00Z'),'insert','rollback_original',vid);
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


DO $test$
DECLARE v uuid; k uuid; a uuid; b uuid; pre uuid:=gen_random_uuid(); provider uuid:=gen_random_uuid(); op uuid; wb uuid; f date; key0 uuid; snap timestamptz:=clock_timestamp(); prior jsonb;
BEGIN
 SELECT actor,batch,friday INTO a,b,f FROM ou_context;
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,contract_revision,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 SELECT pre,importer_version,source_hash,request_hash,'workflow-preview-'||pre,'preview','pmg_stock_v5',2,2,0,1,0,0,'{}',created_by,created_actor
 FROM public.pdc_pilbara_service_import_batches WHERE batch_id=b;
 v:=pg_temp.ou_vehicle('checkout-mixed');
 UPDATE ou_context SET batch=pre;
 PERFORM pg_temp.ou_operation(v,'FITTING',1,1);
 PERFORM pg_temp.ou_operation(v,'SUBLET',0,2);
 UPDATE ou_context SET batch=b;
 wb:=pg_temp.ou_booking('checkout-planned',v,'FITTING',pg_temp.ou_bay('checkout','FITTING'),(f::text||' 08:00 Australia/Perth')::timestamptz);
 SELECT to_jsonb(w) INTO prior FROM public.workshop_bookings w WHERE id=wb;
 INSERT INTO pdc_parts_private.jobs(vehicle_id,source_system,company,division,stock_number,ro_number,departments,service_seen_at)
 SELECT v,'tune_pmg','01','1',stock_number,job_card_number,ARRAY['139'],snap FROM public.vehicles WHERE id=v;
 INSERT INTO pdc_codex_intake_private.service_job_status(company,division,ro_number,vehicle_id,stock_number,status,sub_status,snapshot_at,batch_id)
 SELECT '01','1','OTHER-OPEN-JOB',v,stock_number,'20','20',snap,b FROM public.vehicles WHERE id=v;
 INSERT INTO pdc_parts_private.jobs(vehicle_id,source_system,company,division,stock_number,ro_number,departments,service_seen_at)
 SELECT v,'tune_pmg','01','1',stock_number,'OTHER-OPEN-JOB',ARRAY['139'],snap FROM public.vehicles WHERE id=v;
 INSERT INTO public.sublet_providers(id,name,created_by,updated_by) VALUES(provider,'Rollback provider '||provider,a,a);
 INSERT INTO public.pdc_sublet_booking_instances(vehicle_id,vehicle_version,provider_id,provider_name,out_date,expected_return_date,status,notes,source_kind,source_ref,source_evidence,created_by,updated_by)
 SELECT v,version,provider,'Rollback supplier',current_date-2,current_date-1,'active','','manual','rollback','{}',a,a FROM public.vehicles WHERE id=v;
 PERFORM pdc_codex_intake_private.capture_service_locations(pre,b);
 PERFORM pg_temp.ou_assert((SELECT vehicle_key_number='513' AND parts_location='05C1A' FROM pdc_codex_intake_private.service_location_fields WHERE vehicle_id=v),'Key Number header imports separately from parts location');
 UPDATE public.vehicles SET location_override='PMB',location_override_reason='Prior arrival' WHERE id=v;
 PERFORM pdc_codex_intake_private.capture_service_status(pre,b);
 PERFORM pg_temp.ou_assert((SELECT current_location='RFT' AND location_override IS NULL AND workshop_status='completed' AND qc_completed_at IS NULL FROM public.vehicles WHERE id=v),'Any 99 completes mixed vehicle without inventing QC');
 PERFORM pg_temp.ou_assert((SELECT bool_and((value->>'completed')::boolean) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v))),'All operation lines completed');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs WHERE vehicle_id=v AND closed_at IS NULL),'All vehicle parts jobs retired from active parts');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.pdc_sublet_booking_instances WHERE vehicle_id=v AND status='active'),'Sublet no longer active');
 PERFORM pg_temp.ou_assert((SELECT status='completed' AND (to_jsonb(w)-ARRAY['status','version','updated_by','updated_at'])=(prior-ARRAY['status','version','updated_by','updated_at']) FROM public.workshop_bookings w WHERE id=wb),'Booking cleared with dates and actual labour retained');
 SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=v;
 PERFORM pdc_codex_intake_private.capture_service_status(pre,b);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=prior FROM public.vehicles x WHERE id=v),'Repeat checkout preserves vehicle');
 k:=pg_temp.ou_vehicle('service-key'); UPDATE public.vehicles SET current_location='Other',date_to_pmb=NULL WHERE id=k;
 INSERT INTO pdc_codex_intake_private.service_location_fields(company,division,ro_number,vehicle_id,stock_number,parts_location,vehicle_key_number,snapshot_at,batch_id)
 SELECT '01','1',job_card_number,k,stock_number,'05C1A','513',snap,b FROM public.vehicles WHERE id=k;
 PERFORM pdc_codex_intake_private.apply_service_arrival(b);
 PERFORM pg_temp.ou_assert((SELECT current_location='PMB' AND key_number='513' FROM public.vehicles WHERE id=k),'Service key confirms PMB arrival');
 SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=k;
 PERFORM pdc_codex_intake_private.apply_service_arrival(b);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=prior FROM public.vehicles x WHERE id=k),'Repeat key import preserves PMB state');
 key0:=pg_temp.ou_vehicle('zero-key'); UPDATE public.vehicles SET current_location='Other',date_to_pmb=NULL WHERE id=key0;
 INSERT INTO pdc_codex_intake_private.service_location_fields(company,division,ro_number,vehicle_id,stock_number,parts_location,vehicle_key_number,snapshot_at,batch_id)
 SELECT '01','1',job_card_number,key0,stock_number,'05C1A','0',snap,b FROM public.vehicles WHERE id=key0;
 PERFORM pdc_codex_intake_private.apply_service_arrival(b);
 PERFORM pg_temp.ou_assert((SELECT current_location='Other' FROM public.vehicles WHERE id=key0),'Zero key does not confirm arrival');
 PERFORM pg_temp.ou_assert((SELECT current_location='RFT' FROM public.vehicles WHERE id=v),'Checkout wins over key arrival');
END $test$;
SELECT * FROM ou_results;
ROLLBACK;
