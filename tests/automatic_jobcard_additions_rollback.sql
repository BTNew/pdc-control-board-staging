BEGIN;
-- DISPOSABLE LOCAL DATABASE ONLY. Synthetic actor, vehicles, operations and bays.
-- Department retry also exercises the copied backlog. Everything rolls back.
-- Run this complete file in one connection after the operation-approval migration.

SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';

DO $guard$
BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN
  RAISE EXCEPTION 'Disposable loopback database required';
 END IF;
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

-- This regression graph deliberately covers a configured Saturday shift.
-- Keep its calendar fixture independent of the deployed Monday-Friday calendar.
-- Both this setting and every synthetic record are undone by the final ROLLBACK.
UPDATE public.workshop_settings
SET value='["monday","tuesday","wednesday","thursday","friday","saturday"]'::jsonb
WHERE key='working_week';
UPDATE public.workshop_settings
SET value='[{"scope":"saturday","start":"07:00","end":"08:00"},{"scope":"saturday","start":"12:00","end":"17:00"}]'::jsonb
WHERE key='break_windows';

CREATE TEMP TABLE ou_context(actor uuid, email text, friday date, batch uuid) ON COMMIT DROP;
CREATE TEMP SEQUENCE ou_source_order;
CREATE TEMP TABLE ou_refs(name text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE ou_results(name text PRIMARY KEY, status text, evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE ou_original_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
CREATE TEMP TABLE ou_original_vehicles AS SELECT id,to_jsonb(v) row_data FROM public.vehicles v;
CREATE TEMP TABLE ou_original_reviews AS SELECT change_id,status FROM public.pdc_tune_operation_change_reviews;

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

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1,dept text DEFAULT '139',descr text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',coalesce(descr,'Fixture work '||stage||' line '||line_no),'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{"Company":"01","Division":"1"}','insert','rollback_original',vid);
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
 mins:=public.workshop_capacity_duration_minutes(pdc_work_categories_private.minutes(bid,vid,sid),bay);
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;

CREATE FUNCTION pg_temp.ou_change(vid uuid, source_id uuid, hrs numeric, description text, new_line_no integer DEFAULT 1,dept text DEFAULT '139')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE ev uuid:=gen_random_uuid(); change_batch_id uuid:=gen_random_uuid(); cid uuid; a uuid; e text; v public.vehicles%rowtype; p jsonb; line_no integer;
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT actor,email INTO a,e FROM ou_context;
 IF source_id IS NOT NULL THEN SELECT original_line_number INTO STRICT line_no FROM public.pdc_pilbara_service_operations WHERE operation_id=source_id;
 ELSE line_no:=new_line_no; END IF;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',description,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station','REVIEW','hours_provenance','source_explicit','semantic_hash',encode(extensions.digest(description||hrs::text||ev::text,'sha256'),'hex'),
 'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(change_batch_id,'pilbara_service_open_jobcards_v1',encode(extensions.digest(change_batch_id::text,'sha256'),'hex'),repeat('e',64),'rollback-change-'||change_batch_id,'apply',1,1,0,1,0,0,'{}',a,e);
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,change_batch_id,'pilbara_service_open_jobcards_v1',line_no,v.stock_number,v.job_card_number,line_no,p->>'semantic_hash',p,'{"Company":"01","Division":"1"}','unchanged','operation_update_review',vid);
 PERFORM public.pdc_capture_tune_operation_changes_20260912(change_batch_id,change_batch_id);
 SELECT q.change_id INTO STRICT cid FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=vid AND q.original_line_number=line_no AND q.batch_id=change_batch_id;
 -- Replayed imports must not insert duplicate accepted source lines.
 PERFORM public.pdc_capture_tune_operation_changes_20260912(change_batch_id,change_batch_id);
 RETURN cid;
END $fn$;

DO $test$
DECLARE v uuid; v2 uuid; cid uuid; op uuid; bay uuid; bid uuid; d date; result jsonb; l jsonb; actor_claims text:=current_setting('request.jwt.claims',true);
BEGIN
 PERFORM set_config('request.jwt.claims','',true);
 PERFORM pdc_operation_updates_private.remember_ai_routing_20261019('138','WARRANTY','JOB_CARD_NOTES',0,0.99,'Administrative warranty heading, no physical labour');
 PERFORM pdc_operation_updates_private.remember_ai_routing_20261019('138','NEW ELECTRICAL FIXTURE','BUS_ELECTRICAL',1.5,0.95,'Synthetic electrical addition with temporary labour estimate');
 PERFORM pdc_operation_updates_private.remember_ai_routing_20261019('138','NEW QA FIXTURE','BUS_QA',0,0.95,'Synthetic explicit zero-hour QA task');
 PERFORM pdc_operation_updates_private.remember_ai_routing_20261019('139','NEW FITTING FIXTURE','FITTING',2,0.95,'Synthetic fitting addition with temporary labour estimate');
 PERFORM pdc_operation_updates_private.remember_ai_routing_20261019('139','DELIVERED UNREGISTERED FIXTURE','JOB_CARD_NOTES',0,0.95,'Synthetic delivery instruction with no labour');
 PERFORM set_config('request.jwt.claims',actor_claims,true);
 UPDATE public.pdc_user_roles SET role='administrator' WHERE auth_user_id=(SELECT actor FROM ou_context);
 INSERT INTO public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment,active)
 SELECT actor,email,'14450','staging',true FROM ou_context;
 v:=pg_temp.ou_vehicle('automatic-additions');
 INSERT INTO public.navision_backend_records(source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status,is_current,canonical_vehicle_id)
 SELECT 'AUTOMATIC-ROLLBACK-'||v,repeat('e',64),jsonb_build_object('batch',(SELECT stock_number FROM public.vehicles WHERE id=v),'client','Synthetic fixture','vehicle','Rollback vehicle'),'{}',id,id,'microsoft_navision','14450','current',true,v
 FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='14450' AND status='applied' AND rolled_back_at IS NULL ORDER BY applied_at DESC LIMIT 1;
 cid:=pg_temp.ou_change(v,NULL,0,'WARRANTY',1,'138');
 SELECT approval_receipt INTO result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(result->>'ok'='true','Note automatically accepted',coalesce(result,(select automation_result from public.pdc_tune_operation_change_reviews where change_id=cid)));
 SELECT x INTO l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) x WHERE x->>'description'='WARRANTY';
 PERFORM pg_temp.ou_assert(l->>'stage_code'='JOB_CARD_NOTES' AND (l->>'estimated_hours')::numeric=0,'Note on canonical card with zero hours',l);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v),'Note creates no workshop requirements');
 cid:=pg_temp.ou_change(v,NULL,0,'NEW ELECTRICAL FIXTURE',2,'138');
 SELECT approval_receipt INTO result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(result->>'ok'='true','Electrical automatically accepted',coalesce(result,(select automation_result from public.pdc_tune_operation_change_reviews where change_id=cid)));
 SELECT x INTO l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) x WHERE x->>'description'='NEW ELECTRICAL FIXTURE';
 PERFORM pg_temp.ou_assert(l->>'work_category'='BUS_ELECTRICAL' AND (l->>'estimated_hours')::numeric=1.5,'Electrical category and AI estimate readback',l);
 PERFORM pg_temp.ou_assert((SELECT source_estimated_hours=0 FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v AND original_line_number=2),'Source zero retained');
 cid:=pg_temp.ou_change(v,NULL,0,'NEW QA FIXTURE',3,'138');
 SELECT approval_receipt INTO result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(result->>'ok'='true','Zero-hour QA automatically accepted',coalesce(result,(select automation_result from public.pdc_tune_operation_change_reviews where change_id=cid)));
 cid:=pg_temp.ou_change(v,NULL,3.75,'NEW FITTING FIXTURE',4,'139');
 SELECT approval_receipt INTO result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(result->>'ok'='true','139 automatically accepted',coalesce(result,(select automation_result from public.pdc_tune_operation_change_reviews where change_id=cid)));
 SELECT x INTO l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) x WHERE x->>'description'='NEW FITTING FIXTURE';
 PERFORM pg_temp.ou_assert(l->>'stage_code'='FITTING' AND (l->>'estimated_hours')::numeric=3.75,'Source hours beat AI estimate',l);
 PERFORM pg_temp.ou_assert((SELECT count(*)=4 FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v),'Replay creates no duplicate lines');
 v2:=pg_temp.ou_vehicle('background additions');
 cid:=pg_temp.ou_change(v2,NULL,0,'DELIVERED UNREGISTERED FIXTURE',1,'139');
 SELECT approval_receipt INTO result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(result->>'ok'='true','139 note automatically accepted',result);
 SELECT x INTO l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v2)) x WHERE x->>'description'='DELIVERED UNREGISTERED FIXTURE';
 PERFORM pg_temp.ou_assert(l->>'stage_code'='JOB_CARD_NOTES','139 note retained as information',l);
 op:=pg_temp.ou_operation(v2,'FITTING',1,2,'139','Fixture fitting base work');
 bay:=pg_temp.ou_bay('background fitting','FITTING');
 SELECT friday+21 INTO d FROM ou_context;
 bid:=pg_temp.ou_booking('background fitting',v2,'FITTING',bay,(d+time '08:00') AT TIME ZONE 'Australia/Perth');
 PERFORM set_config('request.jwt.claims','',true);
 cid:=pg_temp.ou_change(v2,NULL,1,'NEW FITTING FIXTURE',3,'139');
 SELECT approval_receipt INTO result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(result->>'ok'='true','Management import adjusts existing booking with real batch actor',coalesce(result,(SELECT automation_result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)));
 PERFORM pg_temp.ou_assert(auth.uid() IS NULL AND coalesce(current_setting('request.jwt.claims',true),'')='','Management actor context restored');
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=120 FROM public.workshop_bookings WHERE id=bid),'New line extends reservation');
 UPDATE public.pdc_user_roles SET active=false,account_status='rejected',role=NULL WHERE auth_user_id=(SELECT actor FROM ou_context);
 cid:=pg_temp.ou_change(v2,NULL,1,'NEW FITTING FIXTURE',4,'139');
 SELECT approval_receipt INTO result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid;
 PERFORM pg_temp.ou_assert(result->>'ok'='true','Disabled importer retains source attribution without login',coalesce(result,(SELECT automation_result FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)));
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM public.workshop_booking_history WHERE booking_id=bid AND actor_user_id=(SELECT actor FROM ou_context) AND metadata->>'actor_basis'='authenticated_source_batch'),'Booking history names immutable batch actor');
 PERFORM pg_temp.ou_assert((SELECT NOT active AND account_status='rejected' AND role IS NULL FROM public.pdc_user_roles WHERE auth_user_id=(SELECT actor FROM ou_context)) AND auth.uid() IS NULL,'Importer stays disabled and no staff session borrowed');
 UPDATE public.pdc_user_roles SET active=true,account_status='approved',role='administrator' WHERE auth_user_id=(SELECT actor FROM ou_context);
 PERFORM set_config('request.jwt.claims',actor_claims,true);
 UPDATE public.vehicles SET current_location='QC' WHERE id=v;
 cid:=pg_temp.ou_change(v,NULL,2,'NEW ELECTRICAL FIXTURE',5,'138');
 PERFORM pg_temp.ou_assert((SELECT status='pending' AND automation_result->>'code'='vehicle_or_review_state_protected' FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid),'QC guard remains authoritative');
 result:=public.get_vehicle_workshop_detail_scoped(v,'14450');
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'imported_additions') x WHERE x->>'change_id'=cid::text AND x->>'description'='NEW ELECTRICAL FIXTURE'),'Protected addition visible on scoped owning card',result-'job_card_lines'-'line_adjustments');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'Existing bookings untouched');
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('anon','pdc_operation_updates_private.remember_ai_routing_20261019(text,text,text,numeric,numeric,text)','execute'),'Anonymous classification denied');
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('authenticated','pdc_operation_updates_private.remember_ai_routing_20261019(text,text,text,numeric,numeric,text)','execute'),'Staff cannot impersonate AI routing worker');
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT name,status FROM ou_results;
ROLLBACK;
