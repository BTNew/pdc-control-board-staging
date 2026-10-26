-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection. Every fixture, authorization, audit
-- and optional candidate migration is reverted by the final ROLLBACK.
BEGIN;
DO $local$ BEGIN IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'Owned loopback database only'; END IF; END $local$;
SET LOCAL statement_timeout = '240s';
SET LOCAL lock_timeout = '20s';
SELECT pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
SET LOCAL TIME ZONE 'Australia/Perth';

-- APPLY CANDIDATE MIGRATION HERE.
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
 VALUES(v,'operation-update-rollback-'||v,stock,'OU-JC-'||substr(v::text,1,8),'ROLLBACK FIXTURE '||tag,'Toyota HiAce Commuter','PMB',true,
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
 UPDATE public.workshop_bays SET bay_number=(SELECT coalesce(max(bay_number),0)+1 FROM public.workshop_bays WHERE stage_id=sid) WHERE id=b; INSERT INTO ou_refs VALUES('bay-'||tag,b);
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1, dept text DEFAULT '139')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department',dept,'operation_description',CASE WHEN dept='138' AND stage='BUS_4X4' THEN 'Coaster Bus 4x4 Conversion - 6 Speed 2.8' ELSE 'Fixture work '||stage||' line '||line_no END,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
 'proposed_station',stage,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
 semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(ev,batch_id,'pilbara_service_open_jobcards_v1',source_order_no,v.stock_number,v.job_card_number,line_no,repeat('c',64),p,'{}','insert','rollback_original',vid);
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
 mins:=CASE WHEN state IN('queued','planned') THEN public.workshop_capacity_duration_minutes(public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid),bay) ELSE public.workshop_vehicle_stage_estimated_duration_minutes(vid,sid) END;
 INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
 actual_start_at,source,created_by,updated_by,metadata)
 VALUES(bid,vid,sid,bay,state,start_at,public.workshop_add_operational_minutes(start_at,mins),mins,
 CASE WHEN state='started' THEN start_at END,'planner',actor_id,actor_id,jsonb_build_object('rollback_fixture',true,'bus_clock_fixture',current_setting('qa.bus_clock_case',true)));
 INSERT INTO ou_refs VALUES('booking-'||tag,bid);
 RETURN bid;
END $fn$;








DO $checks$
DECLARE v uuid; follower uuid; unallocated uuid; bay uuid; b uuid; nextb uuid; qb uuid; op uuid;
 at_time timestamptz; result jsonb; before_row jsonb; next_before jsonb; queue_before jsonb;
 ver integer; bv integer; request uuid:=gen_random_uuid(); saved integer; oldclaims text;
BEGIN
 v:=pg_temp.ou_vehicle('running-estimate');follower:=pg_temp.ou_vehicle('following-estimate');
 bay:=pg_temp.ou_bay('running-estimate','HOIST');
 op:=pg_temp.ou_operation(v,'HOIST',1);
 PERFORM pg_temp.ou_operation(follower,'HOIST',1);
 PERFORM pg_temp.ou_operation(v,'FITTING',1,2);
 at_time:=public.workshop_admin_next_operational_minute(date_trunc('week',clock_timestamp()+interval '90 days')+interval '7 days 7 hours');
 b:=pg_temp.ou_booking('running-estimate',v,'HOIST',bay,at_time,'started');
 nextb:=pg_temp.ou_booking('following-estimate',follower,'HOIST',bay,public.workshop_add_operational_minutes(at_time,120),'planned');
 qb:=pg_temp.ou_booking('unallocated-other-station',v,'FITTING',NULL,public.workshop_add_operational_minutes(at_time,180),'queued');
 SELECT to_jsonb(x) INTO before_row FROM public.workshop_bookings x WHERE id=b;
 SELECT to_jsonb(x) INTO next_before FROM public.workshop_bookings x WHERE id=nextb;
 SELECT to_jsonb(x) INTO queue_before FROM public.workshop_bookings x WHERE id=qb;
 SELECT version INTO ver FROM public.vehicles WHERE id=v;SELECT version INTO bv FROM public.workshop_bookings WHERE id=b;
 result:=public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',360,request);
 PERFORM pg_temp.ou_assert(result->>'ok'='true','running estimate saves',result);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=360 AND status='started'
  AND scheduled_start_at=(before_row->>'scheduled_start_at')::timestamptz
  AND actual_start_at=(before_row->>'actual_start_at')::timestamptz FROM public.workshop_bookings WHERE id=b),'running start progress status retained and allocation extended');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at>=(SELECT scheduled_end_at FROM public.workshop_bookings WHERE id=b) FROM public.workshop_bookings WHERE id=nextb),'follower cascades forward');
 PERFORM pg_temp.ou_assert(queue_before=(SELECT to_jsonb(x) FROM public.workshop_bookings x WHERE id=qb),'Unallocated remains untouched and cannot block cascade');
 PERFORM pg_temp.ou_assert(public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',360,request)->>'replay'='true','retry is idempotent');
 SELECT version INTO ver FROM public.vehicles WHERE id=v;
 result:=public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',420,gen_random_uuid());
 PERFORM pg_temp.ou_assert(result->>'code'='version_conflict','stale booking version rejected',result);
 -- Ordinary line editing must grow a running booking with a warm projection.
 -- This reproduces the installed AFTER-trigger ordering, not only a cold read.
 INSERT INTO pdc_work_categories_private.qc_operation_lines_cache(vehicle_id,lines,computed_at)
 VALUES(v,public.pdc_qc_operation_lines_379_uncached(v),clock_timestamp())
 ON CONFLICT(vehicle_id) DO UPDATE SET lines=excluded.lines,computed_at=excluded.computed_at;
 PERFORM pg_temp.ou_assert(EXISTS(SELECT 1 FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id=v),
  'automatic growth fixture has a warm QC projection');
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,created_by,updated_by)
 VALUES(v,'source:'||op,'source','HOIST','Fixture longer operation',3,'manual_operator',true,auth.uid(),auth.uid());
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=480 AND scheduled_start_at=(before_row->>'scheduled_start_at')::timestamptz
  AND status='started' FROM public.workshop_bookings WHERE id=b),'line edit automatically extends running allocation');
 PERFORM pg_temp.ou_assert((SELECT scheduled_end_at=public.workshop_add_operational_minutes(scheduled_start_at,480)
  AND actual_start_at=(before_row->>'actual_start_at')::timestamptz FROM public.workshop_bookings WHERE id=b),
  'automatic growth persists the canonical finish without changing actual start');
 PERFORM pg_temp.ou_assert(public.pdc_qc_operation_lines_379(v)=public.pdc_qc_operation_lines_379_uncached(v)
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l
    WHERE l->>'line_identity'='source:'||op AND (l->>'estimated_hours')::numeric=3),
  'post-edit cached projection matches fresh operation hours');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at>=(SELECT scheduled_end_at FROM public.workshop_bookings WHERE id=b) FROM public.workshop_bookings WHERE id=nextb),
  'warm-cache automatic growth cascades the planned follower');
 PERFORM pg_temp.ou_assert(queue_before=(SELECT to_jsonb(x) FROM public.workshop_bookings x WHERE id=qb),
  'warm-cache automatic growth leaves bayless queued history unchanged');
 SELECT version INTO ver FROM public.vehicles WHERE id=v;SELECT version INTO bv FROM public.workshop_bookings WHERE id=b;
 result:=public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',60,gen_random_uuid());
 PERFORM pg_temp.ou_assert(result->>'code'='estimated_minutes_below_authenticated_work','source work minimum retained',result);
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o FULL JOIN (SELECT id,to_jsonb(x) row_data FROM public.workshop_bookings x WHERE id IN(SELECT id FROM ou_original_bookings))n USING(id) WHERE o.row_data IS DISTINCT FROM n.row_data),'existing bookings unchanged');
END $checks$;

-- The deferred owner must still reject a real in-bay running/stopped conflict.
-- Each rejected save is caught in a subtransaction, then all persisted state is
-- compared with its pre-request value, including the adjustment and receipt.
DO $protected_checks$
DECLARE
 protected_state text; v uuid; other_vehicle uuid; bay uuid; other_bay uuid; b uuid; other_booking uuid;
 at_time timestamptz; ver integer; bv integer; request uuid; result jsonb;
 before_bookings jsonb; before_adjustments jsonb; before_vehicle jsonb;
 failure_detail text; failure_state text; rejected boolean;
BEGIN
 FOREACH protected_state IN ARRAY ARRAY['started','stoppage'] LOOP
  v:=pg_temp.ou_vehicle('protected-root-'||protected_state);
  bay:=pg_temp.ou_bay('protected-'||protected_state,'HOIST');
  PERFORM pg_temp.ou_operation(v,'HOIST',1);
  at_time:=public.workshop_admin_next_operational_minute(date_trunc('week',clock_timestamp()+interval '120 days')+interval '7 days 7 hours');
  IF protected_state='started' THEN
   -- A bay permits only one started job. Use the same vehicle in another
   -- physical station to exercise a genuine protected vehicle conflict.
   other_bay:=pg_temp.ou_bay('protected-started-other-station','FITTING');
   PERFORM pg_temp.ou_operation(v,'FITTING',1,2);
   other_booking:=pg_temp.ou_booking('protected-follower-started',v,'FITTING',other_bay,public.workshop_add_operational_minutes(at_time,120),'started');
  ELSE
   other_vehicle:=pg_temp.ou_vehicle('protected-follower-stoppage');
   PERFORM pg_temp.ou_operation(other_vehicle,'HOIST',1);
   other_booking:=pg_temp.ou_booking('protected-follower-stoppage',other_vehicle,'HOIST',bay,public.workshop_add_operational_minutes(at_time,120),'started');
   UPDATE public.workshop_bookings SET status='stoppage',stoppage_reason='Rollback fixture protected stop',
    stoppage_started_at=public.workshop_add_operational_minutes(at_time,120),version=version+1 WHERE id=other_booking;
  END IF;
  b:=pg_temp.ou_booking('protected-root-'||protected_state,v,'HOIST',bay,at_time,'started');
  SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) INTO before_bookings FROM public.workshop_bookings x WHERE id IN(b,other_booking);
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.adjustment_id),'[]') INTO before_adjustments FROM public.vehicle_workshop_line_adjustments x WHERE vehicle_id=v;
  SELECT to_jsonb(x),x.version INTO before_vehicle,ver FROM public.vehicles x WHERE id=v;
  SELECT version INTO bv FROM public.workshop_bookings WHERE id=b;
  request:=gen_random_uuid();rejected:=false;failure_detail:=NULL;failure_state:=NULL;
  BEGIN
   result:=public.set_workshop_stage_estimated_minutes_407(v,ver,b,bv,'HOIST',360,request);
  EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS failure_detail=PG_EXCEPTION_DETAIL,failure_state=RETURNED_SQLSTATE;
   rejected:=true;
  END;
  PERFORM pg_temp.ou_assert(rejected AND failure_detail='operation_schedule_protected_active_booking',
   protected_state||' follower collision rejected by cascade authority',jsonb_build_object('sqlstate',failure_state,'detail',failure_detail));
  PERFORM pg_temp.ou_assert(before_bookings=(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.workshop_bookings x WHERE id IN(b,other_booking)),
   protected_state||' collision preserves both bookings');
  PERFORM pg_temp.ou_assert(before_adjustments=(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.adjustment_id),'[]') FROM public.vehicle_workshop_line_adjustments x WHERE vehicle_id=v)
    AND before_vehicle=(SELECT to_jsonb(x) FROM public.vehicles x WHERE id=v)
    AND NOT EXISTS(SELECT 1 FROM public.pdc_workshop_stage_estimate_receipts_407 WHERE actor_id=auth.uid() AND idempotency_key=request),
   protected_state||' rejected save leaves hours vehicle and receipt unchanged');
  PERFORM pg_temp.ou_assert(coalesce(current_setting('pdc.defer_workshop_adjustment_reconcile',true),'')<>'407',
   protected_state||' rejected save does not leak deferral state');
 END LOOP;
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o FULL JOIN (SELECT id,to_jsonb(x) row_data FROM public.workshop_bookings x WHERE id IN(SELECT id FROM ou_original_bookings))n USING(id) WHERE o.row_data IS DISTINCT FROM n.row_data),
  'protected-case checks leave existing bookings unchanged');
END $protected_checks$;

-- Exercise the actual Vehicle Locations hours-save RPC, not only raw adjustment
-- writes. It uses the same duration trigger without the deferred-407 contract.
DO $batch_hours_checks$
DECLARE
 v uuid; follower uuid; bay uuid; b uuid; nextb uuid; op uuid; at_time timestamptz;
 ver bigint; stock text; jobcard text; request uuid:=gen_random_uuid(); rows jsonb; actor_id uuid;
 result jsonb; before_row jsonb; next_before jsonb;
BEGIN
 v:=pg_temp.ou_vehicle('running-batch-hours');follower:=pg_temp.ou_vehicle('running-batch-follower');
 -- Match the real hours API's dealer-scoped authorization using only a newly
 -- created actor and a synthetic backend record in this disposable copy.
 SELECT actor INTO actor_id FROM ou_context;
 UPDATE public.pdc_user_roles SET role='administrator' WHERE auth_user_id=actor_id;
 INSERT INTO public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment,active)
 SELECT actor,email,'14450','staging',true FROM ou_context;
 INSERT INTO public.navision_backend_records(source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status,is_current,canonical_vehicle_id)
 SELECT 'RUNNING-HOURS-ROLLBACK-'||v,repeat('e',64),jsonb_build_object('batch',(SELECT stock_number FROM public.vehicles WHERE id=v),'rego','QA','client','Synthetic fixture','vehicle','Rollback vehicle'),
  '{}',id,id,'microsoft_navision','14450','current',true,v
 FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='14450' AND status='applied' AND rolled_back_at IS NULL ORDER BY applied_at DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Fixture capability missing: dealer14450 import-batch reference'; END IF;
 bay:=pg_temp.ou_bay('running-batch-hours','HOIST');
 op:=pg_temp.ou_operation(v,'HOIST',1);PERFORM pg_temp.ou_operation(follower,'HOIST',1);
 at_time:=public.workshop_admin_next_operational_minute(date_trunc('week',clock_timestamp()+interval '150 days')+interval '7 days 7 hours');
 b:=pg_temp.ou_booking('running-batch-hours',v,'HOIST',bay,at_time,'started');
 nextb:=pg_temp.ou_booking('running-batch-follower',follower,'HOIST',bay,public.workshop_add_operational_minutes(at_time,120),'planned');
 SELECT to_jsonb(x) INTO before_row FROM public.workshop_bookings x WHERE id=b;
 SELECT to_jsonb(x) INTO next_before FROM public.workshop_bookings x WHERE id=nextb;
 SELECT version,stock_number,job_card_number INTO ver,stock,jobcard FROM public.vehicles WHERE id=v;
 rows:=jsonb_build_array(jsonb_build_object('operation_line_id',op,'adjustment_id',NULL,'expected_line_version',0,
  'line_key','source:'||op,'work_key','hoist','stage_code','HOIST','estimated_hours',6));
 INSERT INTO pdc_work_categories_private.qc_operation_lines_cache(vehicle_id,lines,computed_at)
 VALUES(v,public.pdc_qc_operation_lines_379_uncached(v),clock_timestamp())
 ON CONFLICT(vehicle_id) DO UPDATE SET lines=excluded.lines,computed_at=excluded.computed_at;
 result:=public.save_vehicle_workshop_line_hours_batch_768(v,stock,jobcard,ver,rows,request);
 PERFORM pg_temp.ou_assert(result->>'ok'='true' AND (result->>'changed_count')::integer=1,
  'running batch768 hours save succeeds with warm cache',result);
 PERFORM pg_temp.ou_assert((SELECT default_duration_minutes=360 AND status='started'
  AND scheduled_start_at=(before_row->>'scheduled_start_at')::timestamptz
  AND actual_start_at=(before_row->>'actual_start_at')::timestamptz
  AND scheduled_end_at=public.workshop_add_operational_minutes(scheduled_start_at,360)
  FROM public.workshop_bookings WHERE id=b),'running batch768 persists duration finish and original start');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at>=(SELECT scheduled_end_at FROM public.workshop_bookings WHERE id=b)
  AND scheduled_start_at>(next_before->>'scheduled_start_at')::timestamptz FROM public.workshop_bookings WHERE id=nextb),
  'running batch768 cascades the planned follower');
 PERFORM pg_temp.ou_assert(public.pdc_qc_operation_lines_379(v)=public.pdc_qc_operation_lines_379_uncached(v)
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v)) l
    WHERE l->>'line_identity'='source:'||op AND (l->>'estimated_hours')::numeric=6)
  AND (SELECT source_estimated_hours=1 FROM public.pdc_pilbara_service_operations WHERE operation_id=op),
  'running batch768 fresh readback preserves original source hours');
 PERFORM pg_temp.ou_assert(public.save_vehicle_workshop_line_hours_batch_768(v,stock,jobcard,ver,rows,request)->>'replay'='true',
  'running batch768 exact retry is idempotent');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o FULL JOIN (SELECT id,to_jsonb(x) row_data FROM public.workshop_bookings x WHERE id IN(SELECT id FROM ou_original_bookings))n USING(id) WHERE o.row_data IS DISTINCT FROM n.row_data),
  'running batch768 checks leave existing bookings unchanged');
END $batch_hours_checks$;
SELECT jsonb_build_object('status','PASS','checks',(SELECT jsonb_agg(to_jsonb(r)) FROM ou_results r));
ROLLBACK;
