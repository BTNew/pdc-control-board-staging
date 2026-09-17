-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the operation-approval migration.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '5s';
SET LOCAL TIME ZONE 'Australia/Perth';

-- APPLY CANDIDATE MIGRATIONS HERE FOR ROLLBACK REVIEW.
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
 'department','139','operation_description',CASE WHEN stage='BUS_4X4' THEN 'Bus 4x4 Conversion SLWB & Commuter' ELSE 'Fixture work '||stage||' line '||line_no END,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
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
 mins:=CASE WHEN state IN('queued','planned') THEN public.workshop_capacity_duration_minutes(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid),bay) ELSE public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid) END;
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;






DO $checks$
DECLARE v uuid; bay uuid; b uuid; tech uuid:=gen_random_uuid(); othertech uuid:=gen_random_uuid(); op uuid; d jsonb; l jsonb; r jsonb; rid uuid; request jsonb; s jsonb; before_ops jsonb; caught boolean;
BEGIN
 PERFORM pg_temp.ou_assert(pdc_fitter_private.conversion_model('Bus 4x4 Conversion SLWB & Commuter','HiAce Commuter Bus')='hiace_commuter','HiAce Commuter template matches');
 PERFORM pg_temp.ou_assert(pdc_fitter_private.conversion_model('Bus 4x4 Conversion SLWB & Commuter','HiAce SLWB Van')='hiace_commuter','Owner standard matches the named Commuter conversion on a HiAce');
 PERFORM pg_temp.ou_assert(pdc_fitter_private.conversion_model('Coaster Bus 4x4 Conversion Bull bar & Snorkel','Coaster') IS NULL,'Accessories do not receive the parent checklist');
 PERFORM pg_temp.ou_assert(pdc_fitter_private.conversion_model('Bus 4x4 Conversion SLWB & Commuter','TOYHIA')='hiace_commuter','Short HiAce range plus named Commuter conversion matches automatically');
 PERFORM pg_temp.ou_assert((SELECT sum((x->>'planned_minutes')::int)=3765 FROM jsonb_array_elements(pdc_fitter_private.conversion_catalog()#>'{coaster,sections}') x),'Coaster exact 62h45m');
 PERFORM pg_temp.ou_assert((SELECT sum((x->>'planned_minutes')::int)=2280 FROM jsonb_array_elements(pdc_fitter_private.conversion_catalog()#>'{hiace_commuter,sections}') x),'HiAce exact 38h');
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Conversion rollback','technician',true),(othertech,'Other conversion rollback','technician',true);
 v:=pg_temp.ou_vehicle('conversion'); UPDATE public.vehicles SET vehicle_description='Toyota HiAce Commuter' WHERE id=v;
 bay:=pg_temp.ou_bay('conversion','BUS_4X4'); UPDATE public.workshop_bays SET default_technician_id=tech WHERE id=bay;
 op:=pg_temp.ou_operation(v,'BUS_4X4',40,1);
 b:=pg_temp.ou_booking('conversion',v,'BUS_4X4',bay,date_trunc('minute',now())-interval '1 minute','started');
 before_ops:=public.pdc_qc_operation_lines_379(v);
 d:=public.get_fitter_job(tech,b); l:=d->'lines'->0;
 PERFORM pg_temp.ou_assert(l#>>'{conversion,id}'='hiace_commuter','Live fitter line has child template',l);
 PERFORM pg_temp.ou_assert((l#>>'{conversion,remaining_minutes}')::numeric=2280 AND l#>>'{conversion,risk}'='Progress update required','Initial remaining includes pre-assembly; progress unknown',l);
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'line','source:'||op,true,'skip children');
 PERFORM pg_temp.ou_assert(r->>'error'='conversion_sections_required','Parent checkbox cannot bypass sections');
 caught:=false;
 BEGIN UPDATE public.workshop_bookings SET status='completed' WHERE id=b; EXCEPTION WHEN check_violation THEN caught:=true; END;
 PERFORM pg_temp.ou_assert(caught,'Direct booking completion cannot bypass sections');
 caught:=false;
 BEGIN UPDATE public.vehicle_work_items SET completed=true WHERE vehicle_id=v AND work_key='bus4x4'; EXCEPTION WHEN check_violation THEN caught:=true; END;
 PERFORM pg_temp.ou_assert(caught,'Controller / import work completion cannot bypass sections');
 rid:=gen_random_uuid();request:='{"mode":"section","section":"PA","status":"complete","actual_minutes":60,"note":"Workshop confirms pre-assembly already complete"}';
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',rid,'conversion','source:'||op,NULL,request::text);
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Pre-assembly confirmed',r);
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',rid,'conversion','source:'||op,NULL,request::text);
 PERFORM pg_temp.ou_assert((r->>'replayed')::boolean,'Conversion update replay-safe');
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
 PERFORM pg_temp.ou_assert(r->>'error'='version_conflict','Stale conversion update rejected');
 d:=public.get_fitter_job(tech,b);l:=d->'lines'->0;
 PERFORM pg_temp.ou_assert((l#>>'{conversion,remaining_minutes}')::numeric=2220 AND (l#>>'{conversion,actual_minutes}')::numeric=60,'Completed pre-assembly removed from remaining');
 PERFORM pg_temp.ou_assert((d#>>'{progress,percent}')::numeric>0 AND (d#>>'{progress,total_hours}')::numeric=40,'Partial progress visible without double-counting source hours');
 request:='{"mode":"section","section":"1","status":"complete","actual_minutes":120,"deferred":"Final tightening"}';
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
 PERFORM pg_temp.ou_assert(r->>'error'='conversion_deferred','Deferred work prevents section completion');
 request:='{"mode":"section","section":"12","status":"complete","actual_minutes":180}';
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
 PERFORM pg_temp.ou_assert(r->>'error'='conversion_checklist_required','Section12 manufacturer scope required');
 request:=jsonb_build_object('mode','planning','helper_minutes',90,'parts_delay_minutes',120,'waiting_minutes',60,'repair_minutes',30,'rework_minutes',45,'available_minutes',100,'delay_remaining_minutes',60,'promised_at',now()+interval '30 days','comparable',true);
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
 d:=public.get_fitter_job(tech,b);l:=d->'lines'->0;
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND l#>>'{conversion,risk}'='At risk','Known remaining work and delay beyond available hours flag risk',l);
 PERFORM pg_temp.ou_assert((l#>>'{conversion,remaining_minutes}')::numeric=2220 AND (l#>>'{conversion,metadata,helper_minutes}')::numeric=90,'Extra work and helper labour remain separate');
 r:=public.fitter_job_command(othertech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
 PERFORM pg_temp.ou_assert(r->>'error'='assignment_changed','Unassigned technician blocked');
 UPDATE public.pdc_user_roles SET role='fitter' WHERE auth_user_id=auth.uid();
 PERFORM set_config('request.path','rpc/fitter_job_command',true);PERFORM set_config('request.method','POST',true);
 request:='{"mode":"checklist","reference":"Manufacturer test reference","scope":"Synthetic scope confirmation for rollback test only"}';
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
 PERFORM pg_temp.ou_assert(r->>'error'='conversion_controller_required','Fitter cannot certify manufacturer scope');
 UPDATE public.pdc_user_roles SET role='operator' WHERE auth_user_id=auth.uid();
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Controller records checklist reference and scope');
 FOR s IN SELECT value FROM jsonb_array_elements(pdc_fitter_private.conversion_catalog()#>'{hiace_commuter,sections}') LOOP
  d:=public.get_fitter_job(tech,b);
  request:=jsonb_build_object('mode','section','section',s->>'id','status','complete','actual_minutes',s->'planned_minutes','note','Workshop confirms complete');
  r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
  PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Section saved '||(s->>'id'),r);
 END LOOP;
 d:=public.get_fitter_job(tech,b);l:=d->'lines'->0;
 PERFORM pg_temp.ou_assert((l->>'completed')::boolean AND (d#>>'{progress,can_complete}')::boolean,'All sections automatically tick parent');
 PERFORM pg_temp.ou_assert((l#>>'{conversion,remaining_minutes}')::numeric=0 AND (l#>>'{conversion,actual_minutes}')::numeric=2280,'Completed actual and remaining totals correct');
 PERFORM pg_temp.ou_assert(public.pdc_qc_operation_lines_379(v)=before_ops,'Original Tune hours / operations and QC checks unchanged');
 -- Three separate completed comparable fixture builds, not multiple bookings of one job.
 FOR rid IN SELECT gen_random_uuid() FROM generate_series(1,2) LOOP
  INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,vehicle_description,current_location,visible_on_board,created_by,updated_by)
  VALUES(rid,'conversion-review-'||rid,'ROLLBACK-'||rid,'HiAce Commuter','PMB',false,auth.uid(),auth.uid());
  INSERT INTO pdc_fitter_private.conversion_state SELECT rid,line_identity,scope_hash,template_id,template_version,sections,metadata,updated_at,updated_by FROM pdc_fitter_private.conversion_state WHERE vehicle_id=v;
 END LOOP;
 d:=public.get_fitter_job(tech,b);l:=d->'lines'->0;
 PERFORM pg_temp.ou_assert((l#>>'{conversion,allowance_review_due}')::boolean AND (l#>>'{conversion,first_three_average_minutes}')::numeric=2280,'Review triggered after first three comparable timed builds');
 request:='{"mode":"section","section":"12","status":"in_progress","actual_minutes":180,"remaining_minutes":30,"deferred":"Final connection check"}';
 r:=public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion','source:'||op,NULL,request::text);
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert(NOT(d#>>'{progress,can_complete}')::boolean,'Reopened section revokes parent completion');
 UPDATE public.vehicles SET vehicle_description='Unknown model' WHERE id=v;
 d:=public.get_fitter_job(tech,b);
 PERFORM pg_temp.ou_assert((d#>>'{lines,0,conversion,needs_review}')::boolean AND NOT(d#>>'{progress,can_complete}')::boolean,'Model change cannot reuse completed checklist');
 PERFORM pg_temp.ou_assert(NOT has_schema_privilege('authenticated','pdc_fitter_private','USAGE') AND NOT has_table_privilege('authenticated','pdc_fitter_private.conversion_state','UPDATE'),'Conversion data cannot be edited directly');
END $checks$;
SELECT pg_temp.ou_assert(NOT EXISTS(
 SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data<>to_jsonb(b)
),'Existing operational bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(
 SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data<>to_jsonb(v)
),'Existing vehicles unchanged');
SELECT jsonb_agg(to_jsonb(r) ORDER BY name) results FROM ou_results r;
ROLLBACK;

