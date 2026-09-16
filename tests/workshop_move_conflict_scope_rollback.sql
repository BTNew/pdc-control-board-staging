-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection after the minimal move-cascade migration.
BEGIN;
SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout = '20s';
SET LOCAL TIME ZONE 'Australia/Perth';

-- APPLY CANDIDATE MIGRATIONS HERE FOR ROLLBACK REVIEW.
DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

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
 UPDATE public.workshop_bays SET bay_number=(SELECT coalesce(max(bay_number),0)+1 FROM public.workshop_bays WHERE stage_id=sid) WHERE id=b;
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

-- Only synthetic records are mutated. Snapshots include assignments and audit
-- history so a late rejection cannot leave an earlier descendant half-moved.
CREATE TEMP TABLE scope_original_assignments AS SELECT id,to_jsonb(a) row_data FROM public.workshop_booking_assignments a;
CREATE TEMP TABLE scope_original_blocks AS SELECT id,to_jsonb(a) row_data FROM public.workshop_admin_blocks a;
CREATE TEMP TABLE scope_original_receipts AS SELECT receipt_id,to_jsonb(a) row_data FROM public.workshop_booking_move_receipts a;

CREATE FUNCTION pg_temp.scope_state(ids uuid[]) RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT jsonb_build_object(
  'bookings',(SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') FROM public.workshop_bookings b WHERE b.id=any(ids)),
  'assignments',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.id),'[]') FROM public.workshop_booking_assignments a WHERE a.booking_id=any(ids)),
  'history',(SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.id),'[]') FROM public.workshop_booking_history h WHERE h.booking_id=any(ids)));
$fn$;

CREATE FUNCTION pg_temp.scope_move(bid uuid, destination uuid, at_time timestamptz, cascade boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE r jsonb; n integer; stage text; ver integer; mins integer;
BEGIN
 SELECT b.bay_number,s.code INTO STRICT n,stage FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=destination;
 SELECT version,default_duration_minutes INTO STRICT ver,mins FROM public.workshop_bookings WHERE id=bid;
 IF cascade THEN
  r:=public.cascade_workshop_booking_move(bid,ver,stage,n,at_time,mins,NULL,'{"source":"move_scope_rollback"}');
 ELSE
  r:=public.move_workshop_booking(bid,ver,stage,n,at_time,mins,NULL,'{"source":"move_scope_rollback"}');
 END IF;
 RETURN r;
EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '23514' THEN
 RETURN jsonb_build_object('ok',false,'error',SQLERRM,'sqlstate',SQLSTATE);
END $fn$;

CREATE FUNCTION pg_temp.scope_time(minutes integer DEFAULT 0) RETURNS timestamptz LANGUAGE sql AS $fn$
 SELECT public.workshop_add_operational_minutes(
  public.workshop_admin_next_operational_minute((friday+time '06:00') AT TIME ZONE 'Australia/Perth'),minutes) FROM ou_context;
$fn$;

DO $minimal_chain$
DECLARE src uuid; dest uuid; remote uuid; va uuid; vb uuid; vc uuid; vp uuid;
 a uuid; b uuid; c uuid; other uuid; parallel uuid; r jsonb; distant_before jsonb; t timestamptz:=pg_temp.scope_time();
BEGIN
 src:=pg_temp.ou_bay('scope-source','FITTING'); dest:=pg_temp.ou_bay('scope-destination','FITTING'); remote:=pg_temp.ou_bay('scope-other-stage','TINT');
 va:=pg_temp.ou_vehicle('scope-target'); vb:=pg_temp.ou_vehicle('scope-nearest'); vc:=pg_temp.ou_vehicle('scope-distant'); vp:=pg_temp.ou_vehicle('scope-parallel');
 PERFORM pg_temp.ou_operation(va,'FITTING',2); PERFORM pg_temp.ou_operation(vb,'FITTING',1);
 PERFORM pg_temp.ou_operation(vc,'FITTING',1); PERFORM pg_temp.ou_operation(vc,'TINT',1,2); PERFORM pg_temp.ou_operation(vp,'TINT',1);
 a:=pg_temp.ou_booking('scope-target',va,'FITTING',src,pg_temp.scope_time(480));
 b:=pg_temp.ou_booking('scope-nearest',vb,'FITTING',dest,t);
 c:=pg_temp.ou_booking('scope-distant',vc,'FITTING',dest,pg_temp.scope_time(240));
 other:=pg_temp.ou_booking('scope-distant-other',vc,'TINT',remote,pg_temp.scope_time(360));
 parallel:=pg_temp.ou_booking('scope-parallel',vp,'TINT',remote,t);
 distant_before:=pg_temp.scope_state(ARRAY[c,other,parallel]);
 r:=pg_temp.scope_move(a,dest,t);
 PERFORM pg_temp.ou_assert(r->>'ok'='true','Destination gap absorbs displacement without unrelated-vehicle veto',r);
 PERFORM pg_temp.ou_assert(r->>'shifted_count'='1' AND r->'shifted_booking_ids'=jsonb_build_array(b),'Response lists only the genuinely displaced follower',r);
 PERFORM pg_temp.ou_assert((SELECT bay_id=dest AND scheduled_start_at=t AND scheduled_end_at=pg_temp.scope_time(120) FROM public.workshop_bookings WHERE id=a),'Target keeps requested destination and authoritative two-hour range');
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=pg_temp.scope_time(120) AND scheduled_end_at=pg_temp.scope_time(180) FROM public.workshop_bookings WHERE id=b),'Nearest follower moves only to target end');
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[c,other,parallel])=distant_before,'Distant bookings and other-vehicle parallel work retain exact rows, versions and history');
 PERFORM pg_temp.ou_assert((SELECT y.scheduled_start_at-x.scheduled_end_at>=interval '1 hour' FROM public.workshop_bookings x,public.workshop_bookings y WHERE x.id=c AND y.id=other),'Unaffected vehicle keeps its existing one-hour handover');
 PERFORM pg_temp.ou_assert((SELECT count(*)=1 FROM public.workshop_booking_history WHERE booking_id=b AND event_type='cascade_move_shifted'),'Only displaced follower receives one cascade audit event');
END $minimal_chain$;

DO $zero_displacement$
DECLARE src uuid; dest uuid; va uuid; vb uuid; a uuid; b uuid; r jsonb; saved jsonb; n integer;
BEGIN
 -- Both a positive gap and an exact end/start boundary must leave the next row alone.
 FOR n IN 0..1 LOOP
  src:=pg_temp.ou_bay('zero-source-'||n,'FITTING'); dest:=pg_temp.ou_bay('zero-dest-'||n,'FITTING');
  va:=pg_temp.ou_vehicle('zero-target-'||n); vb:=pg_temp.ou_vehicle('zero-next-'||n);
  PERFORM pg_temp.ou_operation(va,'FITTING',1); PERFORM pg_temp.ou_operation(vb,'FITTING',1);
  a:=pg_temp.ou_booking('zero-target-'||n,va,'FITTING',src,pg_temp.scope_time(300));
  b:=pg_temp.ou_booking('zero-next-'||n,vb,'FITTING',dest,pg_temp.scope_time(60+n*60)); saved:=pg_temp.scope_state(ARRAY[b]);
  r:=pg_temp.scope_move(a,dest,pg_temp.scope_time());
  PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r->>'shifted_count'='0' AND r->'shifted_booking_ids'='[]'::jsonb,'No follower moves at free-space boundary '||n,r);
  PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[b])=saved,'Unshifted boundary booking receives no version or audit churn '||n);
 END LOOP;
END $zero_displacement$;

DO $different_shift_amounts$
DECLARE src uuid; dest uuid; va uuid; vb uuid; vc uuid; vd uuid; a uuid; b uuid; c uuid; d uuid; saved jsonb; r jsonb;
BEGIN
 src:=pg_temp.ou_bay('vary-source','FITTING'); dest:=pg_temp.ou_bay('vary-dest','FITTING');
 va:=pg_temp.ou_vehicle('vary-target'); vb:=pg_temp.ou_vehicle('vary-first'); vc:=pg_temp.ou_vehicle('vary-second'); vd:=pg_temp.ou_vehicle('vary-distant');
 PERFORM pg_temp.ou_operation(va,'FITTING',2); PERFORM pg_temp.ou_operation(vb,'FITTING',1); PERFORM pg_temp.ou_operation(vc,'FITTING',1); PERFORM pg_temp.ou_operation(vd,'FITTING',1);
 a:=pg_temp.ou_booking('vary-target',va,'FITTING',src,pg_temp.scope_time(480)); b:=pg_temp.ou_booking('vary-first',vb,'FITTING',dest,pg_temp.scope_time());
 c:=pg_temp.ou_booking('vary-second',vc,'FITTING',dest,pg_temp.scope_time(150)); d:=pg_temp.ou_booking('vary-distant',vd,'FITTING',dest,pg_temp.scope_time(300));
 saved:=pg_temp.scope_state(ARRAY[d]); r:=pg_temp.scope_move(a,dest,pg_temp.scope_time());
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r->>'shifted_count'='2','Displacement traverses only the overlapping chain',r);
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=pg_temp.scope_time(120) FROM public.workshop_bookings WHERE id=b) AND (SELECT scheduled_start_at=pg_temp.scope_time(180) FROM public.workshop_bookings WHERE id=c),'Follower gaps reduce later displacement instead of applying one constant shift');
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[d])=saved,'First sufficient gap ends cascade before distant queue');
END $different_shift_amounts$;

DO $capacity$
DECLARE src uuid; dest uuid; va uuid; vb uuid; vc uuid; a uuid; b uuid; c uuid; saved jsonb; r jsonb;
BEGIN
 src:=pg_temp.ou_bay('capacity-source','FITTING'); dest:=pg_temp.ou_bay('capacity-dest','FITTING');
 va:=pg_temp.ou_vehicle('capacity-target'); vb:=pg_temp.ou_vehicle('capacity-follower'); vc:=pg_temp.ou_vehicle('capacity-distant');
 PERFORM pg_temp.ou_operation(va,'FITTING',1); PERFORM pg_temp.ou_operation(vb,'FITTING',1); PERFORM pg_temp.ou_operation(vc,'FITTING',1);
 a:=pg_temp.ou_booking('capacity-target',va,'FITTING',src,pg_temp.scope_time(480));
 b:=pg_temp.ou_booking('capacity-follower',vb,'FITTING',dest,pg_temp.scope_time()); c:=pg_temp.ou_booking('capacity-distant',vc,'FITTING',dest,pg_temp.scope_time(300));
 UPDATE public.workshop_bays SET efficiency_percent=50 WHERE id=dest;
 saved:=pg_temp.scope_state(ARRAY[c]); r:=pg_temp.scope_move(a,dest,pg_temp.scope_time());
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r->>'shifted_count'='1','Slower destination bay uses authoritative capacity when building the affected chain',r);
 PERFORM pg_temp.ou_assert((SELECT bool_and(default_duration_minutes=120 AND capacity_efficiency_percent=50) FROM public.workshop_bookings WHERE id IN(a,b)) AND (SELECT scheduled_start_at=pg_temp.scope_time(120) AND scheduled_end_at=pg_temp.scope_time(240) FROM public.workshop_bookings WHERE id=b),'Target and displaced follower both use current fifty-percent capacity');
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[c])=saved,'Slower bay does not silently replan untouched distant work');
END $capacity$;

DO $target_guards$
DECLARE src uuid; dest uuid; remote uuid; va uuid; vb uuid; a uuid; b uuid; other uuid; saved jsonb; r jsonb;
BEGIN
 src:=pg_temp.ou_bay('guard-source','FITTING'); dest:=pg_temp.ou_bay('guard-dest','FITTING'); remote:=pg_temp.ou_bay('guard-other','TINT');
 va:=pg_temp.ou_vehicle('guard-target'); vb:=pg_temp.ou_vehicle('guard-neighbour');
 PERFORM pg_temp.ou_operation(va,'FITTING',2); PERFORM pg_temp.ou_operation(va,'TINT',1,2); PERFORM pg_temp.ou_operation(vb,'FITTING',1);
 a:=pg_temp.ou_booking('guard-target',va,'FITTING',src,pg_temp.scope_time(360)); b:=pg_temp.ou_booking('guard-neighbour',vb,'FITTING',dest,pg_temp.scope_time());
 other:=pg_temp.ou_booking('guard-other',va,'TINT',remote,pg_temp.scope_time(60)); saved:=pg_temp.scope_state(ARRAY[a,b,other]);
 r:=pg_temp.scope_move(a,dest,pg_temp.scope_time(),false);
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND r::text LIKE '%bay_overlap%','Ordinary move still rejects actual occupied destination bay',r);
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[a,b,other])=saved,'Bay rejection retains all booking and audit rows');
 r:=pg_temp.scope_move(a,dest,pg_temp.scope_time());
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND r::text LIKE '%vehicle_overlap%','Target vehicle overlapping another station remains protected',r);
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[a,b,other])=saved,'Late target conflict rolls back already shifted follower and audit');
END $target_guards$;

DO $descendant_guards$
DECLARE src uuid; dest uuid; remote uuid; va uuid; vb uuid; vc uuid; a uuid; b uuid; c uuid; other uuid; saved jsonb; r jsonb;
BEGIN
 src:=pg_temp.ou_bay('desc-source','FITTING'); dest:=pg_temp.ou_bay('desc-dest','FITTING'); remote:=pg_temp.ou_bay('desc-other','TINT');
 va:=pg_temp.ou_vehicle('desc-target'); vb:=pg_temp.ou_vehicle('desc-first'); vc:=pg_temp.ou_vehicle('desc-second');
 PERFORM pg_temp.ou_operation(va,'FITTING',2); PERFORM pg_temp.ou_operation(vb,'FITTING',1); PERFORM pg_temp.ou_operation(vb,'TINT',1,2); PERFORM pg_temp.ou_operation(vc,'FITTING',1);
 a:=pg_temp.ou_booking('desc-target',va,'FITTING',src,pg_temp.scope_time(480)); b:=pg_temp.ou_booking('desc-first',vb,'FITTING',dest,pg_temp.scope_time());
 c:=pg_temp.ou_booking('desc-second',vc,'FITTING',dest,pg_temp.scope_time(60)); other:=pg_temp.ou_booking('desc-other',vb,'TINT',remote,pg_temp.scope_time(150));
 saved:=pg_temp.scope_state(ARRAY[a,b,c,other]); r:=pg_temp.scope_move(a,dest,pg_temp.scope_time());
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND r::text LIKE '%vehicle_overlap%','Actually shifted descendant cannot overlap its own other-station booking',r);
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[a,b,c,other])=saved,'Early descendant failure rolls back later-first descendant writes and history atomically');
END $descendant_guards$;

DO $technician_guard$
DECLARE src uuid; dest uuid; remote uuid; va uuid; vb uuid; vc uuid; a uuid; b uuid; other uuid; tech uuid:=gen_random_uuid(); saved jsonb; r jsonb;
BEGIN
 src:=pg_temp.ou_bay('tech-source','FITTING'); dest:=pg_temp.ou_bay('tech-dest','FITTING'); remote:=pg_temp.ou_bay('tech-other','FITTING');
 va:=pg_temp.ou_vehicle('tech-target'); vb:=pg_temp.ou_vehicle('tech-follower'); vc:=pg_temp.ou_vehicle('tech-other');
 PERFORM pg_temp.ou_operation(va,'FITTING',2); PERFORM pg_temp.ou_operation(vb,'FITTING',1); PERFORM pg_temp.ou_operation(vc,'FITTING',1);
 a:=pg_temp.ou_booking('tech-target',va,'FITTING',src,pg_temp.scope_time(480)); b:=pg_temp.ou_booking('tech-follower',vb,'FITTING',dest,pg_temp.scope_time());
 other:=pg_temp.ou_booking('tech-other',vc,'FITTING',remote,pg_temp.scope_time(120));
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Move scope rollback mechanic','technician',true);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,tech,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id IN(b,other);
 saved:=pg_temp.scope_state(ARRAY[a,b,other]); r:=pg_temp.scope_move(a,dest,pg_temp.scope_time());
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND r::text LIKE '%technician_overlap%','Actually shifted descendant still respects assigned technician in another bay',r);
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[a,b,other])=saved,'Technician rejection leaves bookings, assignments and history unchanged');
END $technician_guard$;

DO $fixed_work$
DECLARE src uuid; dest uuid; va uuid; vb uuid; a uuid; b uuid; block_id uuid; saved jsonb; block_saved jsonb; r jsonb;
BEGIN
 src:=pg_temp.ou_bay('fixed-source','FITTING'); dest:=pg_temp.ou_bay('fixed-dest','FITTING');
 va:=pg_temp.ou_vehicle('fixed-target'); vb:=pg_temp.ou_vehicle('fixed-follower');
 PERFORM pg_temp.ou_operation(va,'FITTING',2); PERFORM pg_temp.ou_operation(vb,'FITTING',1);
 a:=pg_temp.ou_booking('fixed-target',va,'FITTING',src,pg_temp.scope_time(480)); b:=pg_temp.ou_booking('fixed-follower',vb,'FITTING',dest,pg_temp.scope_time());
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,dest,'admin','Move scope protected block',pg_temp.scope_time(120),pg_temp.scope_time(180),60,auth.uid(),auth.uid()
 FROM public.workshop_bays WHERE id=dest RETURNING id INTO block_id;
 saved:=pg_temp.scope_state(ARRAY[a,b]); SELECT to_jsonb(x) INTO block_saved FROM public.workshop_admin_blocks x WHERE id=block_id;
 r:=pg_temp.scope_move(a,dest,pg_temp.scope_time());
 PERFORM pg_temp.ou_assert(r->>'ok' IS DISTINCT FROM 'true' AND (r::text LIKE '%admin_block%' OR r::text LIKE '%fixed_booking%'),'Displaced follower cannot overwrite protected bay downtime',r);
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[a,b])=saved AND (SELECT to_jsonb(x)=block_saved FROM public.workshop_admin_blocks x WHERE id=block_id),'Fixed-work rejection is atomic and preserves admin block');
END $fixed_work$;

-- The installed website-only entry point deliberately rejects SQL sessions.
-- A temporary copy preserves its role, version, idempotency, receipt and inner
-- cascade logic, removing only the transport check for this rollback connection.
DO $receipt_copy$
DECLARE def text; denied boolean:=false;
BEGIN
 BEGIN PERFORM pdc_planner_access_private.require_vehicle_planner();
 EXCEPTION WHEN insufficient_privilege THEN denied:=SQLERRM='PDC_244_WEBSITE_AUTH_REQUIRED'; END;
 PERFORM pg_temp.ou_assert(denied,'Installed Controller endpoint still rejects non-website SQL transport');
 def:=pg_get_functiondef('pdc_planner_access_private.require_vehicle_planner()'::regprocedure);
 PERFORM pg_temp.ou_assert(position('session_user<>''authenticator''' in def)>0,'Installed website session guard is unchanged');
 def:=replace(def,'pdc_planner_access_private.require_vehicle_planner()','pg_temp.require_vehicle_planner()');
 def:=replace(def,' or session_user<>''authenticator''','');
 EXECUTE def;
 def:=pg_get_functiondef('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure);
 PERFORM pg_temp.ou_assert(position('pdc_planner_access_private.require_vehicle_planner()' in def)>0,'Controller move retains approved-actor guard');
 EXECUTE replace(replace(def,'FUNCTION public.administrator_move_workshop_booking','FUNCTION pg_temp.administrator_move_workshop_booking'),
  'pdc_planner_access_private.require_vehicle_planner()','pg_temp.require_vehicle_planner()');
END $receipt_copy$;

DO $receipt_checks$
DECLARE src uuid; dest uuid; va uuid; vb uuid; vc uuid; a uuid; b uuid; c uuid; rid uuid:=gen_random_uuid();
 n integer; ver integer; r jsonb; replay jsonb; saved jsonb; after_saved jsonb; receipt_count integer;
BEGIN
 src:=pg_temp.ou_bay('receipt-source','FITTING'); dest:=pg_temp.ou_bay('receipt-dest','FITTING');
 va:=pg_temp.ou_vehicle('receipt-target'); vb:=pg_temp.ou_vehicle('receipt-follower'); vc:=pg_temp.ou_vehicle('receipt-distant');
 PERFORM pg_temp.ou_operation(va,'FITTING',2); PERFORM pg_temp.ou_operation(vb,'FITTING',1); PERFORM pg_temp.ou_operation(vc,'FITTING',1);
 a:=pg_temp.ou_booking('receipt-target',va,'FITTING',src,pg_temp.scope_time(480)); b:=pg_temp.ou_booking('receipt-follower',vb,'FITTING',dest,pg_temp.scope_time());
 c:=pg_temp.ou_booking('receipt-distant',vc,'FITTING',dest,pg_temp.scope_time(240));
 SELECT bay_number INTO n FROM public.workshop_bays WHERE id=dest; SELECT version INTO ver FROM public.workshop_bookings WHERE id=a;
 saved:=pg_temp.scope_state(ARRAY[a,b,c]); SELECT count(*) INTO receipt_count FROM public.workshop_booking_move_receipts WHERE booking_id=a;
 r:=pg_temp.administrator_move_workshop_booking(a,ver-1,'FITTING',n,pg_temp.scope_time(),120,NULL,'{"source":"move_scope_receipt_rollback"}',gen_random_uuid(),true);
 PERFORM pg_temp.ou_assert(r->>'error'='version_conflict' AND pg_temp.scope_state(ARRAY[a,b,c])=saved,'Controller stale version rejects without touching target or descendants',r);
 PERFORM pg_temp.ou_assert((SELECT count(*)=receipt_count FROM public.workshop_booking_move_receipts WHERE booking_id=a),'Rejected stale request does not create success receipt');
 r:=pg_temp.administrator_move_workshop_booking(a,ver,'FITTING',n,pg_temp.scope_time(),120,NULL,'{"source":"move_scope_receipt_rollback"}',rid,true);
 PERFORM pg_temp.ou_assert(r->>'ok'='true' AND r->>'shifted_count'='1' AND r->>'receipt_id' IS NOT NULL,'Controller receipt-backed entry point uses the minimal displacement chain',r);
 after_saved:=pg_temp.scope_state(ARRAY[a,b,c]);
 replay:=pg_temp.administrator_move_workshop_booking(a,ver,'FITTING',n,pg_temp.scope_time(),120,NULL,'{"source":"move_scope_receipt_rollback"}',rid,true);
 PERFORM pg_temp.ou_assert(replay->>'idempotent_replay'='true' AND replay->>'receipt_id'=r->>'receipt_id' AND replay->'shifted_booking_ids'=r->'shifted_booking_ids','Same request replay returns original successful move receipt',replay);
 PERFORM pg_temp.ou_assert(pg_temp.scope_state(ARRAY[a,b,c])=after_saved AND (SELECT count(*)=receipt_count+1 FROM public.workshop_booking_move_receipts WHERE booking_id=a),'Replay adds no move, version increment, assignment, audit or duplicate receipt');
END $receipt_checks$;

SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE to_jsonb(b) IS DISTINCT FROM o.row_data),'All pre-existing bookings byte-for-byte unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o LEFT JOIN public.vehicles v ON v.id=o.id WHERE to_jsonb(v) IS DISTINCT FROM o.row_data),'All pre-existing vehicles byte-for-byte unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM scope_original_assignments o LEFT JOIN public.workshop_booking_assignments a ON a.id=o.id WHERE to_jsonb(a) IS DISTINCT FROM o.row_data),'All pre-existing technician assignments unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM scope_original_blocks o LEFT JOIN public.workshop_admin_blocks a ON a.id=o.id WHERE to_jsonb(a) IS DISTINCT FROM o.row_data),'All pre-existing admin blocks unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM scope_original_receipts o LEFT JOIN public.workshop_booking_move_receipts a ON a.receipt_id=o.receipt_id WHERE to_jsonb(a) IS DISTINCT FROM o.row_data),'All pre-existing move receipts unchanged');
SELECT jsonb_agg(to_jsonb(r) ORDER BY name) results FROM ou_results r;
ROLLBACK;


