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


DO $eligibility$
DECLARE v uuid; sid uuid; snap jsonb; rowj jsonb; stagej jsonb; f date; r jsonb;
BEGIN
 SELECT friday INTO f FROM ou_context;
 SELECT id INTO sid FROM public.workshop_stages WHERE code='FITTING';
 v:=pg_temp.ou_vehicle('pmb-no-eta'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 v:=pg_temp.ou_vehicle('yh-no-eta'); PERFORM pg_temp.ou_operation(v,'FITTING',1); UPDATE public.vehicles SET current_location='Yard Hold',eta_to_kewdale=NULL WHERE id=v;
 v:=pg_temp.ou_vehicle('yh-alias'); PERFORM pg_temp.ou_operation(v,'FITTING',1); UPDATE public.vehicles SET current_location='YH',eta_to_kewdale=NULL WHERE id=v;
 v:=pg_temp.ou_vehicle('it-with-eta'); PERFORM pg_temp.ou_operation(v,'FITTING',1); UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=f WHERE id=v;
 r:=public.workshop_validate_booking(NULL,v,sid,NULL,(f+6+time '07:00') AT TIME ZONE 'Australia/Perth',(f+6+time '08:00') AT TIME ZONE 'Australia/Perth',60,'queued',NULL);
 PERFORM pg_temp.ou_assert(r->>'error'='it_before_eta_plus_seven','IT cannot book before ETA plus seven days',r);
 r:=public.workshop_validate_booking(NULL,v,sid,NULL,(f+7+time '07:00') AT TIME ZONE 'Australia/Perth',(f+7+time '08:00') AT TIME ZONE 'Australia/Perth',60,'queued',NULL);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','IT can book at ETA plus seven days',r);
 v:=pg_temp.ou_vehicle('it-no-eta'); PERFORM pg_temp.ou_operation(v,'FITTING',1); UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=NULL WHERE id=v;
 v:=pg_temp.ou_vehicle('other'); PERFORM pg_temp.ou_operation(v,'FITTING',1); UPDATE public.vehicles SET current_location='Other' WHERE id=v;
 v:=pg_temp.ou_vehicle('hidden'); PERFORM pg_temp.ou_operation(v,'FITTING',1); UPDATE public.vehicles SET visible_on_board=false WHERE id=v;
 v:=pg_temp.ou_vehicle('completed'); PERFORM pg_temp.ou_operation(v,'FITTING',1); UPDATE public.vehicle_work_items SET completed=true WHERE vehicle_id=v;
 v:=pg_temp.ou_vehicle('missing-hours'); PERFORM pg_temp.ou_operation(v,'FITTING',0);
 snap:=public.get_workshop_eligibility_snapshot();
 FOR rowj IN SELECT jsonb_build_object('name',ref.name,'present',EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'candidates') x WHERE x->'vehicle'->>'id'=ref.id::text AND x->>'stage_code'='FITTING')) FROM ou_refs ref LOOP
 PERFORM pg_temp.ou_assert((rowj->>'present')::boolean=(rowj->>'name' IN('vehicle-pmb-no-eta','vehicle-yh-no-eta','vehicle-yh-alias','vehicle-it-with-eta','vehicle-missing-hours')),
 'Eligibility visibility: '||(rowj->>'name'),rowj);
 END LOOP;
 SELECT x INTO rowj FROM jsonb_array_elements(snap->'candidates') x WHERE x->'vehicle'->>'id'=(SELECT id::text FROM ou_refs WHERE name='vehicle-missing-hours');
 PERFORM pg_temp.ou_assert(rowj->>'schedule_enabled'='false' AND rowj->>'disabled_reason'='estimated_duration_missing','Missing hours remain visible but cannot be scheduled',rowj-'vehicle'-'work_items');
 SELECT x INTO stagej FROM jsonb_array_elements(snap->'pipeline')x WHERE x->>'stage_code'='FITTING';
 PERFORM pg_temp.ou_assert((stagej->>'yard_hold_waiting')::integer>=2,'Yard Hold pipeline includes both location aliases');
 PERFORM set_config('request.jwt.claims','{}',true);
 BEGIN
  PERFORM public.get_workshop_eligibility_snapshot();
  RAISE EXCEPTION 'FAIL anonymous could read snapshot';
 EXCEPTION WHEN insufficient_privilege THEN
  PERFORM pg_temp.ou_assert(true,'Anonymous cannot read eligibility snapshot');
 END;
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('anon','public.get_workshop_eligibility_snapshot()','execute') AND has_function_privilege('authenticated','public.get_workshop_eligibility_snapshot()','execute'),'Existing snapshot execution grants unchanged');
END $eligibility$;
SELECT name,status,evidence FROM ou_results ORDER BY name;
ROLLBACK;

