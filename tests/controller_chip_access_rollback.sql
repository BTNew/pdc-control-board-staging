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
 mins:=CASE WHEN state IN('queued','planned') THEN public.workshop_capacity_duration_minutes(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid),bay) ELSE public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid) END;
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,'{"rollback_fixture":true}');
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;





-- Exercise exact installed definitions in this session's temporary schema.
-- MCP cannot impersonate PostgREST's session_user. Only that transport condition
-- is omitted in the temporary guard; live functions and guards are never replaced.
DO $copies$
DECLARE def text; fn record; rejected boolean:=false;
BEGIN
 BEGIN PERFORM pdc_planner_access_private.require_vehicle_planner();
 EXCEPTION WHEN insufficient_privilege THEN rejected:=SQLERRM='PDC_244_WEBSITE_AUTH_REQUIRED'; END;
 PERFORM pg_temp.ou_assert(rejected,'Installed guard rejects non-website SQL session');
 def:=pg_get_functiondef('pdc_planner_access_private.require_vehicle_planner()'::regprocedure);
 PERFORM pg_temp.ou_assert(position('session_user<>''authenticator''' in def)>0,'Installed website transport restriction preserved');
 def:=replace(def,'pdc_planner_access_private.require_vehicle_planner()','pg_temp.require_vehicle_planner()');
 def:=replace(def,' or session_user<>''authenticator''','');
 EXECUTE def;
 FOR fn IN SELECT oid,proname FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('administrator_schedule_workshop_vehicle','administrator_move_workshop_booking','undo_administrator_workshop_booking_move') LOOP
  def:=pg_get_functiondef(fn.oid);
  PERFORM pg_temp.ou_assert(position('pdc_planner_access_private.require_vehicle_planner()' in def)>0,fn.proname||' has scoped Controller guard');
  EXECUTE replace(replace(def,'FUNCTION public.'||fn.proname,'FUNCTION pg_temp.'||fn.proname),
   'pdc_planner_access_private.require_vehicle_planner()','pg_temp.require_vehicle_planner()');
 END LOOP;
END $copies$;

DO $checks$
DECLARE v uuid; bay1 uuid; bay2 uuid; bid uuid; r jsonb; replay jsonb; receipt uuid;
 rid uuid:=gen_random_uuid(); t timestamptz; vv integer; ver integer; role_name text; rejected boolean; num1 integer; num2 integer;
BEGIN
 v:=pg_temp.ou_vehicle('controller');
 bay1:=pg_temp.ou_bay('controller-a','FITTING'); bay2:=pg_temp.ou_bay('controller-b','FITTING');
 SELECT coalesce(max(bay_number),0)+1 INTO num1 FROM public.workshop_bays WHERE stage_id=(SELECT stage_id FROM public.workshop_bays WHERE id=bay1);
 num2:=num1+1;
 UPDATE public.workshop_bays SET bay_number=num1 WHERE id=bay1;
 UPDATE public.workshop_bays SET bay_number=num2 WHERE id=bay2;
 PERFORM pg_temp.ou_operation(v,'FITTING',1);
 SELECT (friday+time '08:00') AT TIME ZONE 'Australia/Perth' INTO t FROM ou_context;
 SELECT version INTO vv FROM public.vehicles WHERE id=v;
 PERFORM pg_temp.require_vehicle_planner();
 r:=pg_temp.administrator_schedule_workshop_vehicle(v,vv,'FITTING',num1,t,60,NULL,'{"source":"controller_rollback"}',rid,true);
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean,'Controller can schedule unallocated vehicle',r);
 bid:=(r->>'booking_id')::uuid; receipt:=(r->>'receipt_id')::uuid;
 replay:=pg_temp.administrator_schedule_workshop_vehicle(v,vv,'FITTING',num1,t,60,NULL,'{"source":"controller_rollback"}',rid,true);
 PERFORM pg_temp.ou_assert((replay->>'idempotent_replay')::boolean AND replay->>'receipt_id'=r->>'receipt_id','Repeated scheduling returns same receipt',replay);
 SELECT version INTO ver FROM public.workshop_bookings WHERE id=bid;
 r:=pg_temp.administrator_move_workshop_booking(bid,ver-1,'FITTING',num2,t,60,NULL,'{}',gen_random_uuid(),true);
 PERFORM pg_temp.ou_assert(r->>'error'='version_conflict','Stale Controller chip move rejected',r);
 r:=pg_temp.administrator_move_workshop_booking(bid,ver,'FITTING',num2,t,60,NULL,'{}',gen_random_uuid(),true);
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (SELECT bay_id=bay2 FROM public.workshop_bookings WHERE id=bid),'Controller moves chip into another bay',r);
 receipt:=(r->>'receipt_id')::uuid;
 r:=pg_temp.undo_administrator_workshop_booking_move(receipt,(r->>'booking_version')::int,gen_random_uuid());
 PERFORM pg_temp.ou_assert((r->>'ok')::boolean AND (SELECT bay_id=bay1 FROM public.workshop_bookings WHERE id=bid),'Controller can undo own move',r);
 FOREACH role_name IN ARRAY ARRAY['viewer','importer','fitter'] LOOP
  UPDATE public.pdc_user_roles SET role=role_name::public.pdc_role WHERE auth_user_id=auth.uid();
  rejected:=false;
  BEGIN PERFORM pg_temp.administrator_move_workshop_booking(bid,1,'FITTING',num2,t,60,NULL,'{}',gen_random_uuid(),false);
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
  PERFORM pg_temp.ou_assert(rejected,role_name||' cannot move vehicle chips');
 END LOOP;
 UPDATE public.pdc_user_roles SET role='operator',active=false,account_status='disabled',disabled_at=clock_timestamp() WHERE auth_user_id=auth.uid();
 rejected:=false;
 BEGIN PERFORM pg_temp.require_vehicle_planner(); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 PERFORM pg_temp.ou_assert(rejected,'Disabled Controller denied');
 UPDATE public.pdc_user_roles SET role='administrator',active=true,account_status='approved',disabled_at=NULL WHERE auth_user_id=auth.uid();
 PERFORM pg_temp.require_vehicle_planner();
 PERFORM pg_temp.ou_assert(true,'Administrator remains authorized');
 PERFORM pg_temp.ou_assert(NOT has_schema_privilege('authenticated','pdc_planner_access_private','USAGE'),'Authorization helper schema remains private');
 PERFORM pg_temp.ou_assert(position('v_role is distinct from ''administrator''' in pg_get_functiondef('public.workshop_require_website_administrator_238()'::regprocedure))>0,'General administrator-only guard unchanged');
END $checks$;
SELECT pg_temp.ou_assert(NOT EXISTS(
 SELECT 1 FROM ou_original_bookings o FULL JOIN public.workshop_bookings b ON b.id=o.id WHERE o.id IS NOT NULL AND (b.id IS NULL OR o.row_data<>to_jsonb(b))
),'Existing operational bookings unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(
 SELECT 1 FROM ou_original_vehicles o FULL JOIN public.vehicles v ON v.id=o.id WHERE o.id IS NOT NULL AND (v.id IS NULL OR o.row_data<>to_jsonb(v))
),'Existing operational vehicles unchanged');
ROLLBACK;
SELECT 'PASS: Controller scheduling, move, retry, undo, stale version, denied roles and unchanged operational data' result;
