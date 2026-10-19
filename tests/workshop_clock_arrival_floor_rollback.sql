-- Disposable-copy regression: the synthetic fixture and all changes roll back.
BEGIN;
-- APPLY CANDIDATE MIGRATIONS HERE FOR ROLLBACK REVIEW.
-- DISPOSABLE LOCAL DATABASE ONLY. Synthetic actor, vehicles, operations and bays.
-- The separate full-backlog test exercises the copied schedule. Everything rolls back.
-- Run this complete file in one connection after the forward-clock migration.

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
 mins:=public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid);
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




DO $isolate$
DECLARE d text; needle text:='WHERE b.deleted_at IS NULL AND b.status IN(''planned'',''queued'',''started'',''stoppage'');';
BEGIN
 d:=pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure);
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Clock fixture scope changed'; END IF;
 d:=replace(d,needle,replace(needle,';',E'\n AND b.vehicle_id IN(SELECT id FROM pg_temp.ou_refs WHERE name LIKE ''vehicle-clock-%'');'));
 EXECUTE d;
END $isolate$;
DO $exercise$
DECLARE v uuid; follower uuid; bay uuid; other_bay uuid; b uuid; b2 uuid; linked uuid;
 day date; at_time timestamptz; tick_at timestamptz; r jsonb; preview jsonb; before_rows jsonb;
BEGIN
 SELECT friday+350 INTO day FROM ou_context;
 at_time:=public.workshop_clock_next_minute((day+time '06:00') AT TIME ZONE 'Australia/Perth');
 v:=pg_temp.ou_vehicle('clock-arrival');
 follower:=pg_temp.ou_vehicle('clock-follower');
 PERFORM pg_temp.ou_operation(v,'FITTING',1,1,'139');
 PERFORM pg_temp.ou_operation(v,'ELECTRICAL',1,2,'139');
 PERFORM pg_temp.ou_operation(follower,'FITTING',1,1,'139');
 bay:=pg_temp.ou_bay('clock-fitting','FITTING');
 other_bay:=pg_temp.ou_bay('clock-electrical','ELECTRICAL');
 b:=pg_temp.ou_booking('clock-arrival',v,'FITTING',bay,at_time);
 b2:=pg_temp.ou_booking('clock-follower',follower,'FITTING',bay,public.workshop_add_operational_minutes(at_time,60));
 linked:=pg_temp.ou_booking('clock-linked',v,'ELECTRICAL',other_bay,public.workshop_clock_next_minute(at_time+interval '2 days'));
 SELECT jsonb_agg(to_jsonb(x)-ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent']) INTO before_rows FROM public.workshop_bookings x WHERE id IN(b,b2,linked);
 -- A normal arrival update can invalidate an already-planned start.
 UPDATE public.vehicles SET current_location='IT',location_override=NULL,eta_to_kewdale=day+7 WHERE id=v;
 -- Append a new immutable operation after booking, as a source import can.
 PERFORM pg_temp.ou_operation(follower,'FITTING',1,2,'139');
 tick_at:=at_time+interval '30 minutes';
 preview:=public.workshop_clock_tick(false,tick_at);
 r:=public.workshop_clock_tick(true,tick_at);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Arrival change does not freeze cascade',r);
 PERFORM pg_temp.ou_assert((r->>'moved_count')::int=3,'Both bay and cross-station followers cascade',r);
 PERFORM pg_temp.ou_assert(r->'plans'=preview->'plans','Persisted movement matches preview');
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=60 FROM public.workshop_bookings WHERE id=b),'Previously allocated hours are never cut');
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=120 FROM public.workshop_bookings WHERE id=b2),'Added work gets sufficient bay capacity');
 PERFORM pg_temp.ou_assert(current_setting('pdc.workshop_capacity_manual',true)='','Temporary capacity context restored');
 PERFORM pg_temp.ou_assert(to_regclass('pg_temp.pdc_clock_effective_ends') IS NULL,'Clock conflict cache removed before return');
 PERFORM pg_temp.ou_assert((SELECT (scheduled_start_at AT TIME ZONE 'Australia/Perth')::date>=day+14 FROM public.workshop_bookings WHERE id=b),'Arrival plus seven days respected');
 PERFORM pg_temp.ou_assert((SELECT y.scheduled_start_at>=x.scheduled_end_at FROM public.workshop_bookings x,public.workshop_bookings y WHERE x.id=b AND y.id=b2),'Later bay job follows without overlap');
 PERFORM pg_temp.ou_assert((SELECT y.scheduled_start_at>=x.scheduled_end_at+interval '1 hour' FROM public.workshop_bookings x,public.workshop_bookings y WHERE x.id=b AND y.id=linked),'Vehicle handover between stations respected');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE id IN(b,b2,linked) AND (scheduled_start_at<tick_at OR NOT public.workshop_calendar_minute_available(scheduled_start_at) OR public.workshop_operational_minutes_between(scheduled_start_at,scheduled_end_at)<>default_duration_minutes)),'All planned work uses future operating minutes');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE id IN(b,b2,linked) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(before_rows) old WHERE old=to_jsonb(x)-ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent'])),'Durations identity and protected fields retained');
 r:=public.workshop_clock_tick(true,tick_at);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND (r->>'moved_count')::int=0,'Same clock does not drift again',r);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_bookings x JOIN ou_original_bookings old USING(id) WHERE old.row_data IS DISTINCT FROM to_jsonb(x)),'Existing copied bookings untouched by synthetic scenario');
END $exercise$;
-- A caller-owned temp table must never spoof the privileged conflict lookup.
SET LOCAL ROLE authenticated;
CREATE TEMP TABLE pdc_clock_effective_ends(id uuid,version integer,scheduled_start_at timestamptz,scheduled_end_at timestamptz,default_duration_minutes integer,effective_end timestamptz);
RESET ROLE;
INSERT INTO pg_temp.pdc_clock_effective_ends
 SELECT b.id,b.version,b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,b.scheduled_start_at-interval '1 year'
 FROM public.workshop_bookings b JOIN ou_refs r ON r.id=b.id WHERE r.name='booking-clock-arrival';
SELECT pg_temp.ou_assert(public.workshop_booking_effective_end_at(c.id)=c.scheduled_end_at,'Caller-owned fake clock cache is ignored') FROM pg_temp.pdc_clock_effective_ends c;
DROP TABLE pg_temp.pdc_clock_effective_ends;
SELECT name,status,evidence FROM ou_results ORDER BY name;
ROLLBACK;
