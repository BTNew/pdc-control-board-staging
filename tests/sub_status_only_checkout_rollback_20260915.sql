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
 VALUES(v,'operation-update-rollback-'||v,stock,'OU-JC-'||substr(v::text,1,8),'ROLLBACK FIXTURE '||tag,'Synthetic vehicle',coalesce(nullif(current_setting('pdc.qc_test_location',true),''),'PMB'),true,
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
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,jsonb_build_object('Company','01','Division','1','Sub Status','99','Key Number','513','Parts Location','05C1A','source_snapshot_at','2026-09-15T04:00:00Z')||coalesce(nullif(current_setting('pdc.substatus_test_raw',true),''),'{}')::jsonb,'insert','rollback_original',vid);
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
DECLARE v uuid; k uuid; a uuid; b uuid; pre uuid:=gen_random_uuid(); provider uuid:=gen_random_uuid(); op uuid; wb uuid; f date; key0 uuid; snap timestamptz:=clock_timestamp(); prior jsonb; line jsonb; response jsonb; source_before jsonb; newer_pre uuid:=gen_random_uuid(); newer_apply uuid:=gen_random_uuid();
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
 PERFORM pg_temp.ou_assert((SELECT current_location='QC' AND location_override IS NULL AND workshop_status='completed' AND qc_completed_at IS NULL FROM public.vehicles WHERE id=v),'Any 99 queues QC and completes work without QC signoff');
 PERFORM pg_temp.ou_assert((SELECT count(*)=2 AND bool_and(NOT (value->>'completed')::boolean) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v))),'Both original QC lines remain unchecked');
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
 PERFORM pg_temp.ou_assert((SELECT current_location='QC' FROM public.vehicles WHERE id=v),'Checkout wins over key arrival');

 -- Verify the authenticated snapshot includes both original operation lines.
 SELECT value INTO source_before FROM jsonb_array_elements(public.get_pdc_email_vehicle_location_snapshot()#>'{data,vehicles}')
 WHERE value->>'id'=v::text;
 PERFORM pg_temp.ou_assert(source_before->>'current_location'='QC'
   AND jsonb_array_length(source_before->'operation_lines')=2
   AND source_before#>>'{tune_checkout,confirmed}'='true','Authenticated snapshot retains QC operations and checkout evidence');
 PERFORM pg_temp.ou_assert((SELECT lifecycle_state='active' AND rft_transferred_at IS NULL AND date_to_rft IS NULL FROM public.vehicles WHERE id=v),'Checkout invents no RFT milestones');
 PERFORM pg_temp.ou_assert(cardinality(public.pdc_qc_gate_issues(v))=0,'QC gate opens after work completion');
 -- Exercise the actual phone checklist RPC, including Sublet.
 FOR line IN SELECT value FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) LOOP
  SELECT public.set_pdc_qc_operation_completion_379(v,version,line->>'line_identity',(line->>'line_version')::integer,gen_random_uuid(),true)
   INTO response FROM public.vehicles WHERE id=v;
  PERFORM pg_temp.ou_assert((response->>'ok')::boolean,'Phone can tick '||(line->>'stage_code'));
 END LOOP;
 SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=v;
 PERFORM pdc_codex_intake_private.capture_service_status(pre,b);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=prior FROM public.vehicles x WHERE id=v)
   AND (SELECT count(*)=2 AND bool_and((value->>'completed')::boolean) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v))),
   'Replay preserves both human QC checks and vehicle version');
 BEGIN
  UPDATE public.vehicles SET current_location='RFT',lifecycle_state='rft' WHERE id=v;
  RAISE EXCEPTION 'FAIL Tune checkout bypassed QC';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
 END;
 PERFORM pg_temp.ou_assert((SELECT current_location='QC' AND qc_completed_at IS NULL FROM public.vehicles WHERE id=v),'RFT rejects Tune checkout without final QC');
 SELECT public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(v,stock_number,version,'Rollback inspection failed',gen_random_uuid(),
  (SELECT jsonb_agg(jsonb_build_object('line_identity',value->>'line_identity','line_version',(value->>'line_version')::integer)) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v))))
 INTO response FROM public.vehicles WHERE id=v;
 PERFORM pg_temp.ou_assert((response->>'ok')::boolean,'Inspector can reject checked-out vehicle');
 SELECT to_jsonb(x) INTO prior FROM public.vehicles x WHERE id=v;
 INSERT INTO public.pdc_pilbara_service_import_batches
 SELECT (jsonb_populate_record(NULL::public.pdc_pilbara_service_import_batches,to_jsonb(original)||
  jsonb_build_object('source_hash',encode(extensions.digest(newer_apply::text,'sha256'),'hex'),'batch_id',newer_apply,'idempotency_key','newer-apply-'||newer_apply))).*
 FROM public.pdc_pilbara_service_import_batches original WHERE batch_id=b;
 INSERT INTO public.pdc_pilbara_service_import_batches
 SELECT (jsonb_populate_record(NULL::public.pdc_pilbara_service_import_batches,to_jsonb(original)||
  jsonb_build_object('source_hash',encode(extensions.digest(newer_apply::text,'sha256'),'hex'),'batch_id',newer_pre,'idempotency_key','newer-preview-'||newer_pre))).*
 FROM public.pdc_pilbara_service_import_batches original WHERE batch_id=pre;
 INSERT INTO public.pdc_pilbara_service_import_rows
 SELECT (jsonb_populate_record(NULL::public.pdc_pilbara_service_import_rows,to_jsonb(original)||
  jsonb_build_object('evidence_id',gen_random_uuid(),'batch_id',newer_pre,'raw_row',
   jsonb_set(raw_row,'{source_snapshot_at}',to_jsonb((clock_timestamp()+interval '1 hour')::text))))).*
 FROM public.pdc_pilbara_service_import_rows original WHERE batch_id=pre AND vehicle_id=v;
 PERFORM pdc_codex_intake_private.capture_service_status(newer_pre,newer_apply);
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=prior FROM public.vehicles x WHERE id=v)
  AND EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v AND required AND NOT completed),
  'Newer 99 replay does not finish rejected QC rework or move it back to QC');

END $test$;

DO $extra$
DECLARE c jsonb; v uuid; a uuid; b uuid; base_b uuid; pre uuid; before_vehicle jsonb;
BEGIN
 SELECT actor,batch INTO a,base_b FROM ou_context;
 FOR c IN SELECT value FROM jsonb_array_elements('[
  {"name":"blank substatus","raw":{"Sub Status":""},"checkout":false,"invalid":false},
  {"name":"legacy Status99 is ignored","raw":{"Status":"99","Sub Status":"22"},"checkout":false,"invalid":false},
  {"name":"legacy invalid Status is ignored","raw":{"Status":"All","Sub Status":"99"},"checkout":true,"invalid":false},
  {"name":"invalid substatus","raw":{"Sub Status":"All"},"checkout":false,"invalid":true},
  {"name":"ordinary22 without Status","raw":{"Sub Status":"22"},"checkout":false,"invalid":false},
  {"name":"manual QC remains untouched","raw":{"Sub Status":"99"},"checkout":false,"invalid":false,"existing_qc":true},
  {"name":"first99 after inspector rejection stays rework","raw":{"Sub Status":"99"},"checkout":false,"invalid":true,"rejected":true},
  {"name":"unknown arrival stays unknown","raw":{"Sub Status":"99"},"checkout":true,"invalid":false,"unknown_arrival":true}
 ]'::jsonb) LOOP
  pre:=gen_random_uuid(); b:=gen_random_uuid();
  INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,contract_revision,source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
  SELECT b,importer_version,encode(extensions.digest(b::text,'sha256'),'hex'),request_hash,'substatus-apply-'||b,'apply','pmg_stock_v5',1,1,0,1,0,0,'{}',created_by,created_actor FROM public.pdc_pilbara_service_import_batches WHERE batch_id=base_b;
  INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,contract_revision,source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
  SELECT pre,importer_version,source_hash,request_hash,'substatus-preview-'||pre,'preview','pmg_stock_v5',1,1,0,1,0,0,'{}',created_by,created_actor FROM public.pdc_pilbara_service_import_batches WHERE batch_id=b;
  PERFORM set_config('pdc.qc_test_location',CASE WHEN coalesce((c->>'unknown_arrival')::boolean,false) THEN 'Other' ELSE 'PMB' END,true);
  v:=pg_temp.ou_vehicle(c->>'name');
  PERFORM set_config('pdc.qc_test_location','',true);
  PERFORM set_config('pdc.substatus_test_raw',(c->'raw')::text,true);
  UPDATE ou_context SET batch=pre;
  PERFORM pg_temp.ou_operation(v,'FITTING',1,1);
  UPDATE ou_context SET batch=b;
  IF coalesce((c->>'existing_qc')::boolean,false) OR coalesce((c->>'rejected')::boolean,false) THEN
   UPDATE public.vehicle_work_items SET completed=true,completed_by=a,completed_at=clock_timestamp() WHERE vehicle_id=v;
   UPDATE public.vehicles SET current_location='QC' WHERE id=v;
   IF coalesce((c->>'rejected')::boolean,false) THEN
    PERFORM public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(v,stock_number,version,'Rollback first checkout rework',gen_random_uuid())
     FROM public.vehicles WHERE id=v;
   END IF;
  END IF;
  SELECT to_jsonb(x) INTO before_vehicle FROM public.vehicles x WHERE id=v;
  PERFORM pdc_codex_intake_private.capture_service_status(pre,b);
  PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM pdc_codex_intake_private.tune_checkout_receipts WHERE vehicle_id=v)=(c->>'checkout')::boolean,c->>'name');
  IF coalesce((c->>'existing_qc')::boolean,false) OR coalesce((c->>'rejected')::boolean,false) THEN
   PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=before_vehicle FROM public.vehicles x WHERE id=v),(c->>'name')||' preserves vehicle');
  END IF;
  IF coalesce((c->>'unknown_arrival')::boolean,false) THEN
   PERFORM pg_temp.ou_assert((SELECT current_location='QC' AND date_to_pmb IS NULL AND date_to_rft IS NULL FROM public.vehicles WHERE id=v),'Status99 does not invent PMB arrival');
   UPDATE public.vehicles SET version=version+1 WHERE id=v;
   PERFORM pg_temp.ou_assert((SELECT date_to_pmb IS NULL FROM public.vehicles WHERE id=v),'Later QC edit keeps unknown PMB arrival');
  END IF;
  PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM pdc_codex_intake_private.service_status_reviews WHERE batch_id=b AND stock_number=(SELECT stock_number FROM public.vehicles WHERE id=v))=(c->>'invalid')::boolean,(c->>'name')||' validation');
 END LOOP;
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o LEFT JOIN public.vehicles current_row USING(id) WHERE to_jsonb(current_row) IS DISTINCT FROM o.row_data),'Existing vehicles unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o LEFT JOIN public.workshop_bookings current_row USING(id) WHERE to_jsonb(current_row) IS DISTINCT FROM o.row_data),'Existing bookings unchanged');
END $extra$;
SELECT * FROM ou_results;
ROLLBACK;



