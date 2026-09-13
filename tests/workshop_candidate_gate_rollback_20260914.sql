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



-- The original deployed gate is retained only in this connection for comparison.
CREATE OR REPLACE FUNCTION pg_temp.gate_before(p_vehicle_id uuid, p_stage_code text, p_scheduled_start_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_stage_code text;
  v_candidate record;
  v_schedule_date date;
BEGIN
  v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);
  SELECT e.* INTO v_candidate
  FROM public.workshop_station_eligibility(v_stage_code)e
  WHERE e.vehicle_id=p_vehicle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station');
  END IF;
  IF coalesce(v_candidate.existing_booking,false) THEN
    RETURN jsonb_build_object('ok',false,'error','active_booking_exists');
  END IF;
  v_schedule_date:=(p_scheduled_start_at AT TIME ZONE 'Australia/Perth')::date;
  IF public.pdc_sublet_away_on_date(p_vehicle_id,v_schedule_date) THEN
    RETURN jsonb_build_object('ok',false,'error','sublet_away','sublet_date',v_schedule_date);
  END IF;
  IF v_candidate.current_location='IT' AND v_candidate.eta_to_kewdale IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','it_eta_missing');
  END IF;
  IF v_candidate.current_location='IT'
     AND v_schedule_date<v_candidate.eta_to_kewdale+7 THEN
    RETURN jsonb_build_object(
      'ok',false,
      'error','it_before_eta_plus_seven',
      'earliest_permitted_date',v_candidate.eta_to_kewdale+7
    );
  END IF;
  RETURN jsonb_build_object(
    'ok',true,
    'earliest_permitted_date',CASE WHEN v_candidate.current_location='IT' THEN v_candidate.eta_to_kewdale+7 ELSE NULL END
  );
END;
$function$
;
-- APPLY CANDIDATE MIGRATION HERE FOR ROLLBACK REVIEW.

CREATE FUNCTION pg_temp.gate_compare(vid uuid, stage text, starts timestamptz, label text, expected_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE old_result jsonb; next_result jsonb; t timestamptz; old_ms numeric; next_ms numeric;
BEGIN
 t:=clock_timestamp(); old_result:=pg_temp.gate_before(vid,stage,starts); old_ms:=extract(epoch FROM clock_timestamp()-t)*1000;
 t:=clock_timestamp(); next_result:=public.workshop_candidate_schedule_gate(vid,stage,starts); next_ms:=extract(epoch FROM clock_timestamp()-t)*1000;
 PERFORM pg_temp.ou_assert(old_result=next_result
   AND CASE WHEN expected_error IS NULL THEN next_result->>'ok'='true' ELSE next_result->>'error'=expected_error END,
   label,jsonb_build_object('before_ms',old_ms,'after_ms',next_ms,'result',next_result));
END $fn$;

DO $gate_cases$
DECLARE v uuid; v2 uuid; bay uuid; bid uuid; f date; starts timestamptz; wk text; actor_id uuid; provider uuid; provider_label text;
BEGIN
 SELECT friday,actor INTO f,actor_id FROM ou_context; starts:=(f+time '07:00') AT TIME ZONE 'Australia/Perth';
 SELECT work_key INTO wk FROM public.workshop_stages WHERE code='FITTING';
 v:=pg_temp.ou_vehicle('gate-membership'); PERFORM pg_temp.ou_operation(v,'FITTING',1);
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'PMB point gate');
 PERFORM pg_temp.gate_compare(v,'fitting',starts,'Canonical stage alias');
 PERFORM pg_temp.gate_compare(v,'not-a-workshop-stage',starts,'Unknown stage', 'vehicle_not_eligible_for_station');
 PERFORM pg_temp.gate_compare(v,NULL,starts,'Null stage','vehicle_not_eligible_for_station');
 PERFORM pg_temp.gate_compare(NULL,'FITTING',starts,'Null vehicle identity','vehicle_not_eligible_for_station');
 PERFORM pg_temp.gate_compare(gen_random_uuid(),'FITTING',starts,'Missing vehicle identity','vehicle_not_eligible_for_station');
 PERFORM pg_temp.gate_compare(v,'ELECTRICAL',starts,'No outstanding requirement in another station','vehicle_not_eligible_for_station');
 PERFORM pg_temp.gate_compare(v,'SUBLET',starts,'Sublet excluded from planner membership','vehicle_not_eligible_for_station');
 PERFORM pg_temp.gate_compare(v,'FITTING',NULL,'Null start retains prior gate response');
 UPDATE public.vehicles SET current_location='Yard Hold',eta_to_kewdale=NULL WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Yard Hold without ETA');
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=f-7 WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'IT exact ETA plus seven');
 PERFORM pg_temp.gate_compare(v,'FITTING',starts-interval '1 day','IT before ETA plus seven','it_before_eta_plus_seven');
 UPDATE public.vehicles SET eta_to_kewdale=NULL WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'IT missing ETA preserves membership error','vehicle_not_eligible_for_station');
 UPDATE public.vehicles SET location_override='PMB' WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'PMB override bypasses underlying IT missing ETA');
 UPDATE public.vehicles SET location_override=NULL WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Cleared override restores IT missing ETA gate','vehicle_not_eligible_for_station');
 UPDATE public.vehicles SET current_location='QC',location_override='YH' WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Yard Hold override on QC source');
 UPDATE public.vehicles SET location_override=NULL WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'QC source without override','vehicle_not_eligible_for_station');
 UPDATE public.vehicles SET current_location='PMB',location_override='IT',eta_to_kewdale=f WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'IT override enforces ETA plus seven','it_before_eta_plus_seven');
 UPDATE public.vehicles SET location_override=NULL,visible_on_board=false WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Hidden vehicle','vehicle_not_eligible_for_station');
 UPDATE public.vehicles SET visible_on_board=true,deleted_at=clock_timestamp() WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Deleted vehicle','vehicle_not_eligible_for_station');
 UPDATE public.vehicles SET deleted_at=NULL,lifecycle_state='completed' WHERE id=v;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Completed lifecycle','vehicle_not_eligible_for_station');
 UPDATE public.vehicles SET lifecycle_state='active' WHERE id=v;
 UPDATE public.vehicle_work_items SET completed=true WHERE vehicle_id=v AND work_key=wk;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Completed required work','vehicle_not_eligible_for_station');
 UPDATE public.vehicle_work_items SET completed=false,required=false WHERE vehicle_id=v AND work_key=wk;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Work not required','vehicle_not_eligible_for_station');
 UPDATE public.vehicle_work_items SET required=true WHERE vehicle_id=v AND work_key=wk;

 v2:=pg_temp.ou_vehicle('gate-no-hours');
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed) VALUES(v2,wk,true,false);
 PERFORM pg_temp.gate_compare(v2,'FITTING',starts,'Gate retains prior missing-estimate behavior');

 SELECT id,name INTO provider,provider_label FROM public.sublet_providers ORDER BY id LIMIT 1;
 INSERT INTO public.pdc_sublet_booking_instances(vehicle_id,vehicle_version,provider_id,provider_name,out_date,expected_return_date,created_by,updated_by)
 VALUES(v,(SELECT version FROM public.vehicles WHERE id=v),provider,provider_label,f,f+1,actor_id,actor_id);
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Sublet away date','sublet_away');
 PERFORM pg_temp.gate_compare(v,'FITTING',starts+interval '2 days','After Sublet away dates');

 bay:=pg_temp.ou_bay('gate-existing','FITTING'); UPDATE public.workshop_bays SET bay_number=993 WHERE id=bay;
 bid:=pg_temp.ou_booking('gate-existing',v,'FITTING',bay,starts+interval '3 days');
 PERFORM pg_temp.gate_compare(v,'FITTING',starts,'Active booking takes precedence over Sublet away','active_booking_exists');
 UPDATE public.workshop_bookings SET deleted_at=clock_timestamp(),deleted_reason='Rollback gate comparison',version=version+1 WHERE id=bid;
 PERFORM pg_temp.gate_compare(v,'FITTING',starts+interval '3 days','Soft-deleted booking does not block');
END $gate_cases$;

SET CONSTRAINTS ALL IMMEDIATE;
DO $unchanged$
BEGIN
 PERFORM pg_temp.ou_assert(NOT has_function_privilege('authenticated','public.workshop_candidate_schedule_gate(uuid,text,timestamptz)','EXECUTE')
   AND NOT has_function_privilege('anon','public.workshop_candidate_schedule_gate(uuid,text,timestamptz)','EXECUTE'),'Internal gate remains unexposed to client roles');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'All pre-existing bookings unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o JOIN public.vehicles v ON v.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'All pre-existing vehicles unchanged');
END $unchanged$;
SELECT name,status,evidence FROM ou_results ORDER BY name;
ROLLBACK;

