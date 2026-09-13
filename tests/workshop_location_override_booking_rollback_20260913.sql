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


CREATE FUNCTION pg_temp.ou_override(vid uuid,loc text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE r jsonb; BEGIN
 r:=public.set_pdc_vehicle_location_override(vid,(SELECT version FROM public.vehicles WHERE id=vid),loc,'Rollback override verification');
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Override failed: %',r; END IF;
END $fn$;
DO $overrides$
DECLARE v uuid; v2 uuid; v3 uuid; bay uuid; bay2 uuid; sid uuid; f date; start_at timestamptz; r jsonb; snap jsonb; booked uuid; old_book jsonb; bcount integer;
BEGIN
 SELECT friday INTO f FROM ou_context; start_at:=(f+time '07:00') AT TIME ZONE 'Australia/Perth';
 SELECT id INTO sid FROM public.workshop_stages WHERE code='FITTING';
 bay:=pg_temp.ou_bay('override-manual','FITTING'); UPDATE public.workshop_bays SET bay_number=991 WHERE id=bay;
 bay2:=pg_temp.ou_bay('override-moved','FITTING'); UPDATE public.workshop_bays SET bay_number=992 WHERE id=bay2;
 v:=pg_temp.ou_vehicle('override-other-to-yh'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 UPDATE public.vehicles SET current_location='Other',eta_to_kewdale=NULL WHERE id=v;
 PERFORM pg_temp.ou_override(v,'YH');
 PERFORM pg_temp.ou_assert((SELECT current_location='Other' AND location_override='YH' FROM public.vehicles WHERE id=v),'Override retains underlying source location');
 r:=public.workshop_candidate_schedule_gate(v,'FITTING',start_at);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Best slot eligibility honors Other to Yard Hold override',r);
 snap:=public.get_workshop_eligibility_snapshot();
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'candidates')x WHERE x->'vehicle'->>'id'=v::text AND x->'vehicle'->>'current_location'='YH' AND x->'vehicle'->>'automatic_location'='Other'),'Overview DTO shows effective and source locations separately');
 snap:=public.get_station_workshop_snapshot_pre_170('FITTING',f,f);
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'vehicles')x WHERE x->>'id'=v::text AND x->>'current_location'='YH' AND x->>'automatic_location'='Other'),'Station DTO shows effective and source locations separately');
 r:=public.schedule_vehicle_work(v,(SELECT version FROM public.vehicles WHERE id=v),'FITTING',991,start_at,60,NULL,NULL,'{"rollback_fixture":true}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Manual scheduling accepts Yard Hold override',r);
 SELECT id INTO STRICT booked FROM public.workshop_bookings WHERE vehicle_id=v AND deleted_at IS NULL;
 r:=public.move_workshop_booking(booked,(SELECT version FROM public.workshop_bookings WHERE id=booked),'FITTING',992,start_at+interval '2h',NULL,NULL,'{"rollback_fixture":true}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT bay_id=bay2 FROM public.workshop_bookings WHERE id=booked),'Manual bay move honors effective Yard Hold location',r);
 PERFORM pg_temp.ou_override(v,NULL);
 PERFORM pg_temp.ou_assert((SELECT current_location='Other' AND location_override IS NULL FROM public.vehicles WHERE id=v) AND NOT EXISTS(SELECT 1 FROM public.workshop_station_eligibility('FITTING') WHERE vehicle_id=v),'Clearing override restores automatic ineligibility');
 SELECT to_jsonb(b) INTO old_book FROM public.workshop_bookings b WHERE id=booked;
 BEGIN
  r:=public.move_workshop_booking(booked,(SELECT version FROM public.workshop_bookings WHERE id=booked),'FITTING',991,start_at+interval '3h',NULL,NULL,'{"rollback_fixture":true}');
 EXCEPTION WHEN OTHERS THEN r:=jsonb_build_object('ok',false,'message',SQLERRM); END;
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND old_book=(SELECT to_jsonb(b) FROM public.workshop_bookings b WHERE id=booked),'Ineligible move fails without moving the booking',r);
 v2:=pg_temp.ou_vehicle('override-it-no-eta-to-pmb'); PERFORM pg_temp.ou_operation(v2,'FITTING',1);
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=NULL WHERE id=v2; PERFORM pg_temp.ou_override(v2,'PMB');
 r:=public.schedule_vehicle_work(v2,(SELECT version FROM public.vehicles WHERE id=v2),'FITTING',991,start_at,60,NULL,NULL,'{"rollback_fixture":true}');
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (SELECT eta_at_booking IS NULL FROM public.workshop_bookings WHERE vehicle_id=v2 AND deleted_at IS NULL),'PMB override ignores source IT ETA when scheduling',r);
 v3:=pg_temp.ou_vehicle('override-it-eta'); PERFORM pg_temp.ou_operation(v3,'FITTING',1); PERFORM pg_temp.ou_operation(v3,'ELECTRICAL',1,2); PERFORM pg_temp.ou_operation(v3,'SUBLET',0,3);
 UPDATE public.vehicles SET eta_to_kewdale=f WHERE id=v3; PERFORM pg_temp.ou_override(v3,'IT');
 r:=public.workshop_candidate_schedule_gate(v3,'FITTING',start_at);
 PERFORM pg_temp.ou_assert(r->>'error'='it_before_eta_plus_seven','Override to IT enforces ETA plus seven',r);
 r:=public.workshop_candidate_schedule_gate(v3,'FITTING',start_at+interval '7 days');
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Override to IT allows ETA plus seven boundary',r);
 PERFORM pg_temp.ou_override(v3,'Other');
 r:=public.book_all_vehicle_stations(v3,(SELECT version FROM public.vehicles WHERE id=v3));
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v3),'Override to Other blocks Book all without creating bookings',r);
 PERFORM pg_temp.ou_override(v3,'YH');
 r:=public.book_all_vehicle_stations(v3,(SELECT version FROM public.vehicles WHERE id=v3));
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND jsonb_array_length(r->'bookings')=2,'Book all accepts Yard Hold override',r);
 PERFORM pg_temp.ou_assert((SELECT current_location='PMB' AND location_override='YH' FROM public.vehicles WHERE id=v3),'Book all preserves source and override');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.vehicle_id=v3 AND s.code='SUBLET')
 AND (SELECT max(scheduled_start_at)-min(scheduled_end_at)>=interval '5 hours' FROM public.workshop_bookings WHERE vehicle_id=v3),'Book all excludes Sublet and preserves five-hour vehicle handover');
 UPDATE public.vehicles SET eta_to_kewdale=f+30 WHERE id=v2;
 PERFORM pg_temp.ou_assert((SELECT eta_risk_status='none' FROM public.workshop_bookings WHERE vehicle_id=v2 AND deleted_at IS NULL),'PMB override ignores later source ETA risk');
 SELECT jsonb_build_object('start',scheduled_start_at,'end',scheduled_end_at,'minutes',default_duration_minutes)
 INTO old_book FROM public.workshop_bookings WHERE vehicle_id=v2 AND deleted_at IS NULL;
 PERFORM pg_temp.ou_override(v2,NULL);
 PERFORM pg_temp.ou_assert((SELECT eta_risk_status='at_risk' FROM public.workshop_bookings WHERE vehicle_id=v2 AND deleted_at IS NULL),
 'Clearing PMB override restores source IT ETA warning');
 PERFORM pg_temp.ou_assert(old_book=(SELECT jsonb_build_object('start',scheduled_start_at,'end',scheduled_end_at,'minutes',default_duration_minutes)
 FROM public.workshop_bookings WHERE vehicle_id=v2 AND deleted_at IS NULL),'Changing override updates ETA warning without moving bookings');
 PERFORM pg_temp.ou_override(v3,'IT');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v3 AND eta_risk_status<>'at_risk'),
 'Override to IT marks existing bookings before ETA as at risk');
 PERFORM pg_temp.ou_override(v3,'PMB');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=v3 AND eta_risk_status<>'none'),
 'PMB override clears ETA risk without moving bookings');
 PERFORM pg_temp.ou_override(v3,'IT');
 UPDATE public.vehicles SET eta_to_kewdale=NULL WHERE id=v3;
 r:=public.workshop_validate_booking(NULL,v3,sid,NULL,start_at,start_at+interval '1h',60,'queued',NULL);
 PERFORM pg_temp.ou_assert(r->>'error'='it_eta_missing','IT override with missing ETA cannot schedule',r);
 PERFORM pg_temp.ou_override(v,'YH');
 UPDATE public.workshop_bookings SET deleted_at=clock_timestamp(),deleted_reason='Rollback restore eligibility verification',version=version+1 WHERE id=booked;
 PERFORM public.workshop_require_booking_restore_eligibility(booked);
 PERFORM pg_temp.ou_assert(true,'Restore eligibility honors Yard Hold override');

END $overrides$;
SET CONSTRAINTS ALL IMMEDIATE;
DO $unchanged$ BEGIN
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'All pre-existing bookings unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'All pre-existing vehicles unchanged');
END $unchanged$;
SELECT name,status,evidence FROM ou_results ORDER BY name;
ROLLBACK;
