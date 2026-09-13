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

CREATE FUNCTION pg_temp.ou_change(vid uuid, source_id uuid, hrs numeric, description text, new_line_no integer DEFAULT 1)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE ev uuid:=gen_random_uuid(); batch_id uuid:=gen_random_uuid(); cid uuid; a uuid; e text; v public.vehicles%rowtype; p jsonb; line_no integer;
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT actor,email INTO a,e FROM ou_context;
 IF source_id IS NOT NULL THEN SELECT original_line_number INTO STRICT line_no FROM public.pdc_pilbara_service_operations WHERE operation_id=source_id;
 ELSE line_no:=new_line_no; END IF;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department','139','operation_description',description,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station','REVIEW','hours_provenance','source_explicit','semantic_hash',encode(extensions.digest(description||hrs::text||ev::text,'sha256'),'hex'),
 'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
 source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(batch_id,'pilbara_service_open_jobcards_v1',encode(extensions.digest(batch_id::text,'sha256'),'hex'),repeat('e',64),'rollback-change-'||batch_id,'apply',1,1,0,1,0,0,'{}',a,e);
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',line_no,v.stock_number,v.job_card_number,line_no,p->>'semantic_hash',p,'{}','unchanged','operation_update_review',vid);
 PERFORM public.pdc_capture_tune_operation_changes_20260912(batch_id,batch_id);
 SELECT change_id INTO STRICT cid FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=vid AND original_line_number=line_no AND status='pending';
 -- An unchanged repeat import must keep the same pending review/version.
 PERFORM public.pdc_capture_tune_operation_changes_20260912(batch_id,batch_id);
 IF (SELECT count(*) FROM public.pdc_tune_operation_change_reviews WHERE vehicle_id=vid AND original_line_number=line_no AND status='pending')<>1
 OR (SELECT version FROM public.pdc_tune_operation_change_reviews WHERE change_id=cid)<>1 THEN RAISE EXCEPTION 'Repeated import duplicated or changed pending review'; END IF;
 RETURN cid;
END $fn$;


DO $resources$
DECLARE v uuid; other uuid; away uuid; bay uuid; second uuid; sid uuid; f date; start_at timestamptz; sat timestamptz; r jsonb; bid uuid; actor_id uuid; tech uuid:=gen_random_uuid(); provider uuid:=gen_random_uuid(); snap jsonb;
BEGIN
 SELECT friday,actor INTO f,actor_id FROM ou_context; start_at:=(f+time '07:00') AT TIME ZONE 'Australia/Perth'; sat:=(f+1+time '08:00') AT TIME ZONE 'Australia/Perth';
 SELECT id INTO sid FROM public.workshop_stages WHERE code='FITTING';
 bay:=pg_temp.ou_bay('resource-a','FITTING'); UPDATE public.workshop_bays SET bay_number=993 WHERE id=bay;
 second:=pg_temp.ou_bay('resource-b','FITTING'); UPDATE public.workshop_bays SET bay_number=994 WHERE id=second;
 v:=pg_temp.ou_vehicle('resource-a'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 other:=pg_temp.ou_vehicle('resource-b'); PERFORM pg_temp.ou_operation(other,'FITTING',1);
 r:=public.workshop_validate_booking(NULL,v,sid,bay,sat-interval '1h',sat,60,'planned',NULL);
 PERFORM pg_temp.ou_assert(r->>'error'='calendar_unavailable','Saturday before eight cannot be scheduled',r);
 r:=public.workshop_validate_booking(NULL,v,sid,bay,sat,sat+interval '1h',60,'planned',NULL);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Saturday eight accepts a one-hour booking',r);
 r:=public.workshop_validate_booking(NULL,v,sid,bay,sat+interval '4h',sat+interval '5h',60,'planned',NULL);
 PERFORM pg_temp.ou_assert(r->>'error'='calendar_unavailable','Saturday noon cannot start a booking',r);
 r:=public.workshop_validate_booking(NULL,v,sid,bay,sat+interval '1 day',sat+interval '1 day 1h',60,'planned',NULL);
 PERFORM pg_temp.ou_assert(r->>'error'='calendar_unavailable','Sunday cannot be scheduled',r);
 PERFORM pg_temp.ou_assert(public.workshop_add_operational_minutes(sat+interval '3h 30min',90)=(f+3+time '08:00') AT TIME ZONE 'Australia/Perth',
 'Saturday work continues Monday with exact minutes');
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 VALUES(sid,bay,'admin','Rollback Admin conflict',start_at,start_at+interval '1h',60,actor_id,actor_id);
 BEGIN
  r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'FITTING',993,start_at,60,NULL,NULL,'{}');
 EXCEPTION WHEN OTHERS THEN r:=jsonb_build_object('ok',false,'message',SQLERRM); END;
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v),'Manual booking cannot overlap Admin block',r);
 r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'FITTING',993,start_at+interval '1h',60,NULL,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Manual booking can start at Admin end boundary',r);
 SELECT id INTO STRICT bid FROM public.workshop_bookings WHERE vehicle_id=v AND deleted_at IS NULL;
 r:=public.workshop_validate_booking(NULL,other,sid,bay,start_at+interval '1h',start_at+interval '2h',60,'planned',NULL);
 PERFORM pg_temp.ou_assert(r->>'error'='bay_overlap','Another vehicle cannot overlap the bay booking',r);
 r:=public.workshop_validate_booking(NULL,v,sid,second,start_at+interval '1h',start_at+interval '2h',60,'planned',NULL);
 PERFORM pg_temp.ou_assert(r->>'error'='vehicle_overlap','Same vehicle cannot overlap in a different bay',r);
 SELECT to_jsonb(b) INTO snap FROM public.workshop_bookings b WHERE id=bid;
 r:=public.move_workshop_booking(bid,0,'FITTING',994,start_at+interval '2h',NULL,NULL,'{}');
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND snap=(SELECT to_jsonb(b) FROM public.workshop_bookings b WHERE id=bid),'Stale move cannot change the booking',r);
 INSERT INTO public.workshop_technicians(id,name,role_type,can_fit_stages,created_by,updated_by)
 VALUES(tech,'Rollback leave technician '||tech,'technician',ARRAY['FITTING'],actor_id,actor_id);
 INSERT INTO public.workshop_settings(key,value) VALUES('technician_leave',jsonb_build_array(jsonb_build_object('technician_id',tech,'date',f)))
 ON CONFLICT(key) DO UPDATE SET value=public.workshop_settings.value||excluded.value;
 r:=public.workshop_validate_booking(NULL,other,sid,second,start_at,start_at+interval '1h',60,'planned',tech);
 PERFORM pg_temp.ou_assert(r->>'error'='technician_leave_conflict','Technician leave prevents assignment',r);
 r:=public.workshop_validate_booking(NULL,other,sid,second,sat,sat+interval '1h',60,'planned',tech);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Technician is available after configured leave day',r);
 away:=pg_temp.ou_vehicle('resource-away'); PERFORM pg_temp.ou_operation(away,'FITTING',1);
 INSERT INTO public.sublet_providers(id,name,created_by,updated_by) VALUES(provider,'Rollback provider '||provider,actor_id,actor_id);
 INSERT INTO public.pdc_sublet_booking_instances(vehicle_id,vehicle_version,provider_id,provider_name,out_date,expected_return_date,created_by,updated_by)
 VALUES(away,(SELECT version FROM public.vehicles WHERE id=away),provider,'Rollback provider '||provider,f,f+1,actor_id,actor_id);
 r:=public.workshop_candidate_schedule_gate(away,'FITTING',start_at);
 PERFORM pg_temp.ou_assert(r->>'error'='sublet_away','Sublet absence prevents workshop scheduling',r);
 r:=public.workshop_candidate_schedule_gate(away,'FITTING',(f+3+time '07:00') AT TIME ZONE 'Australia/Perth');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Vehicle can schedule after Sublet expected return',r);
END $resources$;
SET CONSTRAINTS ALL IMMEDIATE;
DO $unchanged$ BEGIN
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'All pre-existing bookings unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'All pre-existing vehicles unchanged');
END $unchanged$;
SELECT name,status,evidence FROM ou_results ORDER BY name;
ROLLBACK;

