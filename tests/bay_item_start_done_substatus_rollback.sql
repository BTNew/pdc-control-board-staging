-- STAGING ONLY (cdsmnqxtyyoeoznmbidd). Never production vjdtsswhroyguxyfjdkt.
-- r384 x Tune Sub Status 80 / 99 imports, PMB Email check (20 Oct 2026).
-- Same before-tick / after-tick / rollback set as #381, run through the real
-- capture_service_status path on Dept 139 synthetic vehicles only (no live job,
-- no Delete, no Complete button). Phase A runs before 384, phase B with 384.sql
-- applied in this transaction, phase C after 384.down.sql; every import outcome
-- must match across the three. Ends with TESTRESULT so everything rolls back.
BEGIN;
SET LOCAL statement_timeout = '170s';
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

CREATE FUNCTION pg_temp.ou_operation(vid uuid, stage text, hrs numeric, line_no integer DEFAULT 1, opdesc text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE op uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); p jsonb; v public.vehicles%rowtype; batch_id uuid; wk text; source_order_no integer:=nextval('pg_temp.ou_source_order');
BEGIN
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 SELECT batch INTO batch_id FROM ou_context;
 SELECT work_key INTO STRICT wk FROM public.workshop_stages WHERE code=stage;
 p:=jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',line_no,'source_order',line_no,
 'department','139','operation_description',CASE WHEN opdesc IS NOT NULL THEN opdesc WHEN stage='BUS_4X4' THEN 'Coaster Bus 4x4 Conversion - 6 Speed 2.8' ELSE 'Fixture work '||stage||' line '||line_no END,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
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


CREATE TEMP SEQUENCE ss_seq;
CREATE TEMP TABLE ss_results(phase text, scen text, step text, result text, sig jsonb, PRIMARY KEY(phase,scen,step)) ON COMMIT DROP;

-- One Tune status import for one vehicle through the real capture path
-- (capture_service_status -> 99 checkout / finish_tune_checkout -> apply_service_pmb_complete).
CREATE FUNCTION pg_temp.ss_import(vid uuid, sub text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE pre uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid(); a uuid; e text; h text; v public.vehicles%rowtype; n integer:=nextval('pg_temp.ss_seq');
BEGIN
 SELECT actor,email INTO a,e FROM ou_context;
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=vid;
 h:=encode(extensions.digest(pre::text,'sha256'),'hex');
 INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,contract_revision,
  source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
 VALUES(pre,'pilbara_service_open_jobcards_v1',h,repeat('b',64),'ss-preview-'||pre,'preview','pmg_stock_v5',1,1,0,1,0,0,'{}',a,e),
       (ap,'pilbara_service_open_jobcards_v1',h,repeat('b',64),'ss-apply-'||ap,'apply','pmg_stock_v5',1,1,0,1,0,0,'{}',a,e);
 INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
  semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
 VALUES(gen_random_uuid(),pre,'pilbara_service_open_jobcards_v1',1,v.stock_number,v.job_card_number,1,repeat('c',64),
  jsonb_build_object('stock_number',v.stock_number,'repair_order_number',v.job_card_number,'original_line_number',1,'department','139'),
  jsonb_build_object('Company','01','Division','1','Sub Status',sub,'Key Number','513',
   'source_snapshot_at',to_char((timestamptz '2026-10-20 00:00+00'+n*interval '1 minute') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')),
  'unchanged','substatus_rollback_r384',vid);
 BEGIN
  PERFORM pdc_codex_intake_private.capture_service_status(pre,ap);
 EXCEPTION WHEN check_violation THEN RETURN 'blocked:'||SQLERRM;
 END;
 RETURN 'ran';
END $fn$;

-- Import outcome without ids or times: what PMB Email sees.
CREATE FUNCTION pg_temp.ss_sig(vid uuid) RETURNS jsonb LANGUAGE sql AS $fn$
SELECT jsonb_build_object('loc',v.current_location,'ws',v.workshop_status,'life',v.lifecycle_state,'visible',v.visible_on_board,
 'r80',(SELECT count(*) FROM pdc_codex_intake_private.tune_pmb_complete_receipts r WHERE r.vehicle_id=v.id),
 'r99',(SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts r WHERE r.vehicle_id=v.id),
 'reviews',(SELECT coalesce(jsonb_agg(z.reason ORDER BY z.reason),'[]'::jsonb) FROM pdc_codex_intake_private.service_status_reviews z WHERE z.stock_number=v.stock_number),
 'bookings',(SELECT jsonb_agg(jsonb_build_object('stage',s.code,'status',b.status,'mins',b.default_duration_minutes,
   'actual_start',b.actual_start_at IS NOT NULL,'actual_end',b.actual_end_at IS NOT NULL) ORDER BY s.code)
   FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.vehicle_id=v.id),
 'work',(SELECT jsonb_object_agg(w.work_key,jsonb_build_object('done',w.completed,
   'n80',(length(w.notes)-length(replace(w.notes,'Sub Status 80','')))/13,'n99',(length(w.notes)-length(replace(w.notes,'Sub Status 99','')))/13))
   FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),
 'moves',(SELECT count(*) FROM public.vehicle_movements m WHERE m.vehicle_id=v.id))
FROM public.vehicles v WHERE v.id=vid
$fn$;

-- Fitter-side state the imports must never touch: ticks, item timing, sections and their audits.
CREATE FUNCTION pg_temp.ss_fstate(vid uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE t jsonb; ta bigint;
BEGIN
 IF to_regclass('pdc_fitter_private.operation_timing') IS NOT NULL THEN
  EXECUTE 'SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.line_identity),''[]''::jsonb) FROM pdc_fitter_private.operation_timing t JOIN public.workshop_bookings b ON b.id=t.booking_id WHERE b.vehicle_id=$1' INTO t USING vid;
  EXECUTE 'SELECT count(*) FROM pdc_fitter_private.operation_timing_audit a JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE b.vehicle_id=$1' INTO ta USING vid;
 END IF;
 RETURN jsonb_build_object('progress',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.line_identity),'[]'::jsonb) FROM pdc_fitter_private.operation_progress p JOIN public.workshop_bookings b ON b.id=p.booking_id WHERE b.vehicle_id=vid),
  'timing',t,'timing_audit',ta,
  'conv',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.line_identity),'[]'::jsonb) FROM pdc_fitter_private.conversion_state c WHERE c.vehicle_id=vid),
  'conv_audit',(SELECT count(*) FROM pdc_fitter_private.conversion_audit a WHERE a.vehicle_id=vid));
END $fn$;

CREATE FUNCTION pg_temp.fcmd(tech uuid, b uuid, act text, li text, done boolean DEFAULT NULL, note text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE d jsonb; v integer;
BEGIN
 d:=public.get_fitter_job(tech,b);
 SELECT version INTO v FROM public.workshop_bookings WHERE id=b;
 RETURN public.fitter_job_command(tech,b,v,d->>'catalog_hash',gen_random_uuid(),act,li,done,note);
END $fn$;
CREATE FUNCTION pg_temp.cmd(tech uuid, b uuid, change jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE d jsonb; l jsonb;
BEGIN
 d:=public.get_fitter_job(tech,b);
 SELECT x INTO l FROM jsonb_array_elements(d->'lines') x WHERE x->'conversion' IS NOT NULL;
 RETURN public.fitter_job_command(tech,b,(d->>'version')::int,d->>'catalog_hash',gen_random_uuid(),'conversion',l->>'line_identity',NULL,change::text);
END $fn$;
CREATE FUNCTION pg_temp.conv_line(tech uuid, b uuid) RETURNS text LANGUAGE sql AS $fn$
 SELECT x->>'line_identity' FROM jsonb_array_elements(public.get_fitter_job(tech,b)->'lines') x WHERE x->'conversion' IS NOT NULL
$fn$;
CREATE FUNCTION pg_temp.ok(r jsonb, what text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF (r->>'ok')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'setup step % failed: %',what,r; END IF; END $fn$;
CREATE FUNCTION pg_temp.rec(ph text, sc text, st text, res text, vid uuid) RETURNS void LANGUAGE sql AS $fn$
 INSERT INTO ss_results VALUES(ph,sc,st,res,pg_temp.ss_sig(vid))
$fn$;

CREATE FUNCTION pg_temp.ss_tech(bay uuid, ph text) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE t uuid:=gen_random_uuid();
BEGIN
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(t,'SubStatus rollback '||ph||' '||left(t::text,4),'technician',true);
 UPDATE public.workshop_bays SET default_technician_id=t WHERE id=bay;
 RETURN t;
END $fn$;

-- The same scenarios in every phase. A = before 384, B = 384 applied, C = after 384.down.sql.
CREATE FUNCTION pg_temp.ss_phase(ph text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE tech uuid; v uuid; bay uuid; b uuid; l1 text; l2 text; l3 text; cl text; d jsonb; r jsonb; res text;
 f0 jsonb; s1 jsonb; p0 jsonb; p1 jsonb; sc text;
BEGIN
 -- F1 / F2: Fitting job, 80 -> 80 -> 99 -> 99 and 99 -> 99 -> 80.
 FOREACH sc IN ARRAY ARRAY['F1','F2'] LOOP
  v:=pg_temp.ou_vehicle(ph||sc); bay:=pg_temp.ou_bay(ph||sc,'FITTING'); tech:=pg_temp.ss_tech(bay,ph);
  PERFORM pg_temp.ou_operation(v,'FITTING',1,1); PERFORM pg_temp.ou_operation(v,'FITTING',2,2); PERFORM pg_temp.ou_operation(v,'FITTING',0.5,3);
  b:=pg_temp.ou_booking(ph||sc,v,'FITTING',bay,date_trunc('minute',now())-interval '3 hours','started');
  d:=public.get_fitter_job(tech,b);
  SELECT x->>'line_identity' INTO l1 FROM jsonb_array_elements(d->'lines') x WHERE (x->>'hours')::numeric=1;
  SELECT x->>'line_identity' INTO l2 FROM jsonb_array_elements(d->'lines') x WHERE (x->>'hours')::numeric=2;
  SELECT x->>'line_identity' INTO l3 FROM jsonb_array_elements(d->'lines') x WHERE (x->>'hours')::numeric=0.5;
  IF ph='B' THEN
   PERFORM pg_temp.ok(pg_temp.fcmd(tech,b,'item_start',l1),'start l1'); PERFORM pg_temp.ok(pg_temp.fcmd(tech,b,'line',l1,true,''),'done l1');
   PERFORM pg_temp.ok(pg_temp.fcmd(tech,b,'item_start',l2),'start l2');
   PERFORM pg_temp.ok(pg_temp.fcmd(tech,b,'item_start',l3),'start l3'); PERFORM pg_temp.ok(pg_temp.fcmd(tech,b,'item_reset',l3),'reset l3');
   PERFORM pg_temp.ou_assert((SELECT jsonb_agg(status ORDER BY line_identity) FROM pdc_fitter_private.operation_timing WHERE booking_id=b)
     =(SELECT jsonb_agg(CASE x WHEN l1 THEN 'done' WHEN l2 THEN 'running' ELSE 'reset' END ORDER BY x) FROM unnest(ARRAY[l1,l2,l3]) x),ph||sc||' 00 timing rows running / Done / reset before import');
  ELSE
   PERFORM pg_temp.ok(pg_temp.fcmd(tech,b,'line',l1,true,''),'done l1');
  END IF;
  f0:=pg_temp.ss_fstate(v); p0:=pdc_fitter_private.progress(b);
  FOREACH res IN ARRAY CASE sc WHEN 'F1' THEN ARRAY['80','80','99','99'] ELSE ARRAY['99','99','80'] END LOOP
   PERFORM pg_temp.rec(ph,sc,(SELECT count(*)+1 FROM ss_results WHERE phase=ph AND scen=sc)||':'||res,pg_temp.ss_import(v,res),v);
   PERFORM pg_temp.ou_assert(pg_temp.ss_fstate(v)=f0,ph||sc||' '||(SELECT count(*) FROM ss_results WHERE phase=ph AND scen=sc)||' import '||res||' leaves ticks, timing and audits untouched');
  END LOOP;
  s1:=(SELECT sig FROM ss_results WHERE phase=ph AND scen=sc ORDER BY step LIMIT 1);
  PERFORM pg_temp.ou_assert((SELECT bool_and(sig=s1) FROM ss_results WHERE phase=ph AND scen=sc),ph||sc||' replays change nothing (no double complete)',(SELECT jsonb_agg(sig ORDER BY step) FROM ss_results WHERE phase=ph AND scen=sc));
  PERFORM pg_temp.ou_assert((s1#>>'{work,fitting,done}')::boolean AND (s1#>>'{work,fitting,n80}')::int+(s1#>>'{work,fitting,n99}')::int=1
    AND (s1->>'r80')::int+(s1->>'r99')::int=1 AND s1#>>'{bookings,0,status}'='completed',ph||sc||' completed once by the first import',s1);
  r:=pg_temp.fcmd(tech,b,'line',l1,false,'');
  PERFORM pg_temp.ou_assert(r->>'error'='job_not_running',ph||sc||' Done item cannot be unticked after import (no reopen)',r);
  p1:=pdc_fitter_private.progress(b);
  PERFORM pg_temp.ou_assert(p1->'percent'=p0->'percent' AND p1->'completed_hours'=p0->'completed_hours',ph||sc||' Done % unchanged by import',jsonb_build_object('before',p0-'current','after',p1-'current'));
  IF ph='B' THEN
   r:=pg_temp.fcmd(tech,b,'item_start',l3);
   PERFORM pg_temp.ou_assert(r->>'error'='job_not_running',ph||sc||' reset item cannot be restarted after import',r);
   r:=public.reset_fitter_item_timing(b,l2,NULL,'cleanup after import');
   PERFORM pg_temp.ou_assert(r->>'error'='booking_not_active',ph||sc||' manager reset refused on an imported-complete job',r);
   PERFORM pg_temp.ou_assert((p1->>'running')::int=0 AND p1->'current'='[]'::jsonb AND (p0->>'running')::int=1,ph||sc||' running item no longer shown once the job is complete',jsonb_build_object('before',p0,'after',p1));
   PERFORM pg_temp.ou_assert(pg_temp.ss_fstate(v)=f0,ph||sc||' refused actions wrote nothing');
  END IF;
 END LOOP;

 -- B1: Coaster, conversion not ticked whole: 99 and 80 stay blocked (#381 guard).
 v:=pg_temp.ou_vehicle(ph||'B1'); UPDATE public.vehicles SET vehicle_description='Toyota Coaster',model='Coaster 2.8L Diesel 6AT Standard' WHERE id=v;
 bay:=pg_temp.ou_bay(ph||'B1','BUS_4X4'); tech:=pg_temp.ss_tech(bay,ph);
 PERFORM pg_temp.ou_operation(v,'BUS_4X4',60,1);
 b:=pg_temp.ou_booking(ph||'B1',v,'BUS_4X4',bay,date_trunc('minute',now())-interval '1 minute','started');
 PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"PA","step":"start"}'),'PA start');
 IF ph='B' THEN
  PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"PB","step":"start"}'),'PB start');
  PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"PB","step":"done"}'),'PB done');
  PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"1","step":"start"}'),'1 start');
  PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"1","step":"reset"}'),'1 reset');
 ELSE
  PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"PB","step":"done"}'),'PB done');
 END IF;
 f0:=pg_temp.ss_fstate(v);
 PERFORM pg_temp.rec(ph,'B1','1:99',pg_temp.ss_import(v,'99'),v);
 PERFORM pg_temp.rec(ph,'B1','2:80',pg_temp.ss_import(v,'80'),v);
 PERFORM pg_temp.ou_assert((SELECT bool_and(result LIKE 'blocked:%conversion_sections_required%' AND sig#>>'{bookings,0,status}'='started' AND (sig->>'r80')::int=0 AND (sig->>'r99')::int=0) FROM ss_results WHERE phase=ph AND scen='B1'),ph||'B1 unticked Coaster: 99 and 80 blocked, nothing completed');
 PERFORM pg_temp.ou_assert(pg_temp.ss_fstate(v)=f0,ph||'B1 blocked imports leave sections and ticks untouched');

 -- B2 / B3: HiAce / Coaster ticked whole while sections are running, Done and reset.
 FOREACH sc IN ARRAY ARRAY['B2','B3'] LOOP
  v:=pg_temp.ou_vehicle(ph||sc);
  IF sc='B2' THEN UPDATE public.vehicles SET vehicle_description='Toyota HiAce Commuter',model='HiAce Commuter' WHERE id=v;
  ELSE UPDATE public.vehicles SET vehicle_description='Toyota Coaster',model='Coaster 2.8L Diesel 6AT Standard' WHERE id=v; END IF;
  bay:=pg_temp.ou_bay(ph||sc,'BUS_4X4'); tech:=pg_temp.ss_tech(bay,ph);
  IF sc='B2' THEN PERFORM pg_temp.ou_operation(v,'BUS_4X4',40,1,'BUS 4X4 CONVERSION SLWB & COMMUTER -- 05E2A **BUMPER & STEPS 04X4B**');
  ELSE PERFORM pg_temp.ou_operation(v,'BUS_4X4',60,1); END IF;
  b:=pg_temp.ou_booking(ph||sc,v,'BUS_4X4',bay,date_trunc('minute',now())-interval '1 minute','started');
  cl:=pg_temp.conv_line(tech,b);
  IF sc='B2' THEN
   PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"1","step":"start"}'),'1 start');
   IF ph='B' THEN
    PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"2","step":"start"}'),'2 start');
    PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"3","step":"start"}'),'3 start');
    PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"3","step":"reset"}'),'3 reset');
   END IF;
   PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"2","step":"done"}'),'2 done');
  ELSE
   PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"PA","step":"start"}'),'PA start');
   IF ph='B' THEN PERFORM pg_temp.ok(pg_temp.cmd(tech,b,'{"mode":"tick","section":"PB","step":"start"}'),'PB start'); END IF;
  END IF;
  PERFORM pg_temp.ok(pg_temp.fcmd(tech,b,'line',cl,true,''),'whole tick');
  f0:=pg_temp.ss_fstate(v); p0:=pdc_fitter_private.progress(b);
  FOREACH res IN ARRAY CASE sc WHEN 'B2' THEN ARRAY['99','99','80'] ELSE ARRAY['80','99','80'] END LOOP
   PERFORM pg_temp.rec(ph,sc,(SELECT count(*)+1 FROM ss_results WHERE phase=ph AND scen=sc)||':'||res,pg_temp.ss_import(v,res),v);
   PERFORM pg_temp.ou_assert(pg_temp.ss_fstate(v)=f0,ph||sc||' '||(SELECT count(*) FROM ss_results WHERE phase=ph AND scen=sc)||' import '||res||' leaves sections, ticks and timing untouched');
  END LOOP;
  s1:=(SELECT sig FROM ss_results WHERE phase=ph AND scen=sc ORDER BY step LIMIT 1);
  PERFORM pg_temp.ou_assert((SELECT bool_and(sig=s1 AND result='ran') FROM ss_results WHERE phase=ph AND scen=sc)
    AND (s1#>>'{work,bus4x4,done}')::boolean AND (s1#>>'{work,bus4x4,n80}')::int+(s1#>>'{work,bus4x4,n99}')::int=1
    AND (s1->>'r80')::int+(s1->>'r99')::int=1 AND s1#>>'{bookings,0,status}'='completed',ph||sc||' ticked conversion completed once; replays change nothing',(SELECT jsonb_agg(sig ORDER BY step) FROM ss_results WHERE phase=ph AND scen=sc));
  r:=pg_temp.cmd(tech,b,'{"mode":"tick","section":"2","step":"reset"}');
  PERFORM pg_temp.ou_assert(r->>'error'='job_not_running',ph||sc||' Done section cannot be reset after import (no reopen)',r);
  IF ph='B' THEN
   r:=public.reset_fitter_item_timing(b,cl,CASE sc WHEN 'B2' THEN '1' ELSE 'PA' END,'cleanup after import');
   p1:=pdc_fitter_private.progress(b);
   PERFORM pg_temp.ou_assert(r->>'error'='booking_not_active' AND p1->'current'='[]'::jsonb AND pg_temp.ss_fstate(v)=f0,ph||sc||' running section not reset or shown once the job is complete',jsonb_build_object('r',r,'p',p1));
  END IF;
 END LOOP;
END $fn$;

DO $a$ BEGIN PERFORM pg_temp.ss_phase('A'); END $a$;

-- ===== PHASE B: 384.sql applied inside this transaction =====
-- Start / Done ticks on every bay item (Fitting, Electrical, Tint, Tyre,
-- Fabrication, Hoist, Pit, Bus non-conversion lines). Start records the booking
-- work timer in pdc_fitter_private.operation_timing (several items may run at
-- once); Done on the existing line tick stamps the actual time; Done without
-- Start still works. Bus Coaster/HiAce sections may now run several at once.
-- The job % counts Done work only; running items are listed separately in
-- progress().current with a stale flag (> 2x allowance or since an earlier
-- Perth day). Controllers reset a forgotten item with reset_fitter_item_timing.
-- Start / reset write no workshop_bookings row: no QC cache invalidation, no
-- booking version change, no clock interaction.
-- Not touched: start_workshop_work_pre_116, workshop_clock_tick, base_lines,
-- summary, timing, the QC cache, apply_service_pmb_complete, finish_tune_checkout.
--
-- Rollback: supabase/rollbacks/20261020160000_bay_item_start_done.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
     IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_bus_private' AND p.proname = 'add_minutes')
     IS DISTINCT FROM 'c43afa5c1312392aa5d3666a8aa7cf65' THEN
    RAISE EXCEPTION 'add_minutes_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_bus_private' AND p.proname = 'clock_add_minutes')
     IS DISTINCT FROM 'd0a395e6739423c1e4f5f2329fa5cd75' THEN
    RAISE EXCEPTION 'clock_add_minutes_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'workshop_clock_tick')
     IS DISTINCT FROM '84af7607bfd0ce9907c89bae8644d5b6' THEN
    RAISE EXCEPTION 'workshop_clock_tick_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_view')
     IS DISTINCT FROM '45b3b8f43a2a630cca14466c1a9e1567' THEN
    RAISE EXCEPTION 'conversion_view_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_catalog')
     IS DISTINCT FROM 'b7789961f5e49d09b854ce7582d34e83' THEN
    RAISE EXCEPTION 'conversion_catalog_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_completion_guard')
     IS DISTINCT FROM 'befe9ecce7ea624be54b9c637a8b15df' THEN
    RAISE EXCEPTION 'conversion_completion_guard_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'operational_seconds')
     IS DISTINCT FROM '650b7df281eb4526c6d99ee497313515' THEN
    RAISE EXCEPTION 'operational_seconds_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'timing')
     IS DISTINCT FROM 'ddb9eb4132cf8fdbb5efca444fda29d0' THEN
    RAISE EXCEPTION 'timing_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'summary')
     IS DISTINCT FROM 'c481664c82eb64487b1085edd67b9045' THEN
    RAISE EXCEPTION 'summary_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines')
     IS DISTINCT FROM '28c3949d357c203601bfbee42da6c879' THEN
    RAISE EXCEPTION 'lines_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'base_lines')
     IS DISTINCT FROM '47addc72c8aa19d1d66d2c3239f03b9c' THEN
    RAISE EXCEPTION 'base_lines_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'invalidate_qc_operation_lines_cache')
     IS DISTINCT FROM '00f532fdd214dcd242c267616f43bc7f' THEN
    RAISE EXCEPTION 'invalidate_qc_operation_lines_cache_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'pdc_qc_operation_lines_379')
     IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN
    RAISE EXCEPTION 'pdc_qc_operation_lines_379_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'pdc_qc_operation_lines_379_uncached')
     IS DISTINCT FROM 'b677d7bfdf67c046fd05922da249325c' THEN
    RAISE EXCEPTION 'pdc_qc_operation_lines_379_uncached_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'get_fitter_job')
     IS DISTINCT FROM '74d1a88dc9b440782904c02682c25ebc' THEN
    RAISE EXCEPTION 'get_fitter_job_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'apply_service_pmb_complete')
     IS DISTINCT FROM 'eea5bb523c2538742db52508665191d3' THEN
    RAISE EXCEPTION 'apply_service_pmb_complete_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'finish_tune_checkout')
     IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
    RAISE EXCEPTION 'finish_tune_checkout_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS DISTINCT FROM 'db9db4ca6a63161d873480edf8a078b6' THEN
    RAISE EXCEPTION 'fitter_job_command_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines_before_bus_workflow_20260921')
     IS DISTINCT FROM '6154aaf1490f5d49acfc3a5f3232edc2' THEN
    RAISE EXCEPTION 'lines_before_bus_workflow_20260921_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'progress')
     IS DISTINCT FROM 'b388403d94d1adbb5c01fd4cb979ebd2' THEN
    RAISE EXCEPTION 'progress_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS DISTINCT FROM '2f156fdc1cafc810d60637f50b346f12' THEN
    RAISE EXCEPTION 'conversion_enrich_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS DISTINCT FROM 'fb4d6cd82f40ee27476186e0ac5b05f4' THEN
    RAISE EXCEPTION 'conversion_save_changed';
  END IF;
END $guard$;

-- ITEM TICKS APPLY
-- ===== TABLES =====
CREATE TABLE IF NOT EXISTS pdc_fitter_private.operation_timing (
  booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id) ON DELETE CASCADE,
  line_identity text NOT NULL,
  scope_hash text NOT NULL,
  technician_id uuid NOT NULL REFERENCES public.workshop_technicians(id),
  status text NOT NULL CHECK (status IN ('running','done','reset')),
  started_at timestamptz NOT NULL,
  start_elapsed_seconds numeric NOT NULL CHECK (start_elapsed_seconds >= 0),
  completed_at timestamptz,
  actual_seconds numeric CHECK (actual_seconds IS NULL OR actual_seconds >= 0),
  reset_reason text CHECK (reset_reason IS NULL OR length(reset_reason) <= 500),
  updated_by uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (booking_id, line_identity)
);
-- Several items may run at once for one technician (Craig, 20 Oct 2026).
CREATE INDEX IF NOT EXISTS operation_timing_running_idx
  ON pdc_fitter_private.operation_timing (booking_id) WHERE status = 'running';
ALTER TABLE pdc_fitter_private.operation_timing ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_fitter_private.operation_timing FROM PUBLIC;

CREATE TABLE IF NOT EXISTS pdc_fitter_private.operation_timing_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id uuid NOT NULL,
  line_identity text NOT NULL,
  section_id text,
  technician_id uuid,
  actor_id uuid NOT NULL,
  action text NOT NULL,
  before_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  after_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_fitter_private.operation_timing_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_fitter_private.operation_timing_audit FROM PUBLIC;

-- ===== HELPERS =====
-- Item timing as line keys. Elapsed = booking work timer since Start, so
-- breaks, closures and stoppages are excluded exactly like the job clock.
-- Stale = running more than twice its allowance, or since an earlier Perth day.
CREATE OR REPLACE FUNCTION pdc_fitter_private.item_timing(t pdc_fitter_private.operation_timing, p_scope text, p_hours jsonb, p_job_seconds numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 SELECT CASE WHEN (t).booking_id IS NULL OR (t).status NOT IN ('running','done') OR (t).scope_hash IS DISTINCT FROM p_scope THEN '{}'::jsonb
 ELSE jsonb_build_object('item_status',(t).status,'item_started_at',(t).started_at,'item_completed_at',(t).completed_at,
  'item_start_seconds',(t).start_elapsed_seconds,
  'item_elapsed_minutes',x.el,
  'item_actual_minutes',CASE WHEN (t).status='done' AND (t).actual_seconds IS NOT NULL THEN round((t).actual_seconds/60.0,2) END,
  'item_technician_id',(t).technician_id,
  'item_technician',(SELECT w.name FROM public.workshop_technicians w WHERE w.id=(t).technician_id),
  'item_stale',(t).status='running' AND (
    (jsonb_typeof(p_hours)='number' AND (p_hours::text)::numeric>0 AND x.el>2*(p_hours::text)::numeric*60)
    OR ((t).started_at AT TIME ZONE 'Australia/Perth')::date<(statement_timestamp() AT TIME ZONE 'Australia/Perth')::date))
 END
 FROM (SELECT round(CASE WHEN (t).status='done' THEN coalesce((t).actual_seconds,0)
   ELSE greatest(0,coalesce(p_job_seconds,(t).start_elapsed_seconds)-(t).start_elapsed_seconds) END/60.0,2) el) x
$function$;

-- Start / reset one bay item (not supplier or conversion lines). Writes only
-- operation_timing and its audit; never workshop_bookings, so neither the QC
-- cache nor the booking version changes. Station + board revisions advance.
CREATE OR REPLACE FUNCTION pdc_fitter_private.item_timing_save(p_tech uuid, p_booking uuid, p_line jsonb, p_step text, p_reason text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE t pdc_fitter_private.operation_timing; after_t pdc_fitter_private.operation_timing; secs numeric; code text; li text:=p_line->>'line_identity';
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 IF li IS NULL OR p_step NOT IN ('start','reset') THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
 SELECT * INTO t FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking AND line_identity=li FOR UPDATE;
 IF p_step='start' THEN
  IF p_line->>'external_work'='true' OR p_line->'conversion' IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','item_start_unavailable'); END IF;
  IF coalesce((p_line->>'completed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'error','item_already_done'); END IF;
  IF t.status='running' AND t.scope_hash=p_line->>'scope_hash' THEN RETURN jsonb_build_object('ok',true,'already_running',true); END IF;
  secs:=coalesce((pdc_fitter_private.timing(p_booking,clock_timestamp())#>>'{timer,elapsed_seconds}')::numeric,0);
  INSERT INTO pdc_fitter_private.operation_timing(booking_id,line_identity,scope_hash,technician_id,status,started_at,start_elapsed_seconds,updated_by)
  VALUES(p_booking,li,p_line->>'scope_hash',p_tech,'running',clock_timestamp(),secs,auth.uid())
  ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,technician_id=excluded.technician_id,
   status='running',started_at=excluded.started_at,start_elapsed_seconds=excluded.start_elapsed_seconds,completed_at=NULL,
   actual_seconds=NULL,reset_reason=NULL,updated_by=excluded.updated_by,updated_at=clock_timestamp()
   WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
 ELSE
  IF t.booking_id IS NULL OR t.status<>'running' THEN RETURN jsonb_build_object('ok',true,'already_reset',true); END IF;
  UPDATE pdc_fitter_private.operation_timing SET status='reset',reset_reason=nullif(btrim(coalesce(p_reason,'')),''),
   updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE booking_id=p_booking AND line_identity=li AND status='running';
 END IF;
 SELECT * INTO after_t FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking AND line_identity=li;
 INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
 VALUES(p_booking,li,p_tech,auth.uid(),'item_'||p_step,coalesce(to_jsonb(t),'{}'::jsonb),coalesce(to_jsonb(after_t),'{}'::jsonb));
 SELECT s.code INTO code FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_booking;
 PERFORM public.workshop_bump_station_revision(code);
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true);
END $function$;

-- Done / untick on the existing line path: stamp the actual time on a running
-- item, or clear a done item when it is unticked. Done without Start is fine.
CREATE OR REPLACE FUNCTION pdc_fitter_private.item_timing_tick(p_booking uuid, p_line text, p_scope text, p_completed boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE t pdc_fitter_private.operation_timing; after_t pdc_fitter_private.operation_timing; secs numeric;
BEGIN
 SELECT * INTO t FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking AND line_identity=p_line FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF p_completed AND t.status='running' AND t.scope_hash=p_scope THEN
  secs:=coalesce((pdc_fitter_private.timing(p_booking,clock_timestamp())#>>'{timer,elapsed_seconds}')::numeric,t.start_elapsed_seconds);
  UPDATE pdc_fitter_private.operation_timing SET status='done',completed_at=clock_timestamp(),
   actual_seconds=greatest(0,secs-t.start_elapsed_seconds),updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE booking_id=p_booking AND line_identity=p_line AND status='running';
 ELSIF NOT p_completed AND t.status='done' THEN
  UPDATE pdc_fitter_private.operation_timing SET status='reset',updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE booking_id=p_booking AND line_identity=p_line AND status='done';
 ELSE RETURN;
 END IF;
 SELECT * INTO after_t FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking AND line_identity=p_line;
 INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
 VALUES(p_booking,p_line,t.technician_id,auth.uid(),CASE WHEN p_completed THEN 'item_done' ELSE 'item_untick' END,to_jsonb(t),to_jsonb(after_t));
END $function$;

REVOKE ALL ON FUNCTION pdc_fitter_private.item_timing(pdc_fitter_private.operation_timing,text,jsonb,numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION pdc_fitter_private.item_timing_save(uuid,uuid,jsonb,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION pdc_fitter_private.item_timing_tick(uuid,text,text,boolean) FROM PUBLIC;

-- ===== LINES (adds item timing keys; % stays Done-only) =====
CREATE OR REPLACE FUNCTION pdc_fitter_private.lines_before_bus_workflow_20260921(p_vehicle_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH source AS (
  SELECT l,md5(jsonb_build_array(l->>'line_identity',l->>'description',
    l->>'stage_code',l->'estimated_hours',l->>'job_card_number')::text) scope_hash
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true)
 ), clock AS (
  -- Booking work timer, read once and only while an item is running here.
  SELECT CASE WHEN EXISTS(SELECT 1 FROM pdc_fitter_private.operation_timing t
    WHERE t.booking_id=p_booking_id AND t.status='running')
   THEN (pdc_fitter_private.timing(p_booking_id,statement_timestamp())#>>'{timer,elapsed_seconds}')::numeric END job_seconds
 )
 SELECT coalesce(jsonb_agg(pdc_fitter_private.conversion_enrich(p_vehicle_id,jsonb_build_object(
  'line_identity',s.l->>'line_identity','description',s.l->>'description',
  'stage_code',s.l->>'stage_code','hours',s.l->'estimated_hours',
  'operation_no',s.l->'operation_no','source_note',s.l->>'review_note',
  'scope_hash',s.scope_hash,'completed',coalesce(p.completed AND p.scope_hash=s.scope_hash,false),
  'note',coalesce(p.note,''),'scope_changed',p.scope_hash IS NOT NULL AND p.scope_hash<>s.scope_hash,
  'updated_at',p.updated_at,'technician_id',p.technician_id
 )||pdc_fitter_private.item_timing(t,s.scope_hash,s.l->'estimated_hours',(SELECT job_seconds FROM clock))
 ) ORDER BY s.l->>'stage_code',s.l->>'operation_no',s.l->>'line_identity'),'[]'::jsonb)
 FROM source s LEFT JOIN pdc_fitter_private.operation_progress p
   ON p.booking_id=p_booking_id AND p.line_identity=s.l->>'line_identity'
 LEFT JOIN pdc_fitter_private.operation_timing t
   ON t.booking_id=p_booking_id AND t.line_identity=s.l->>'line_identity'
$function$;

-- ===== PROGRESS (board feed: Done-only %, plus running / stale lists) =====
CREATE OR REPLACE FUNCTION pdc_fitter_private.progress(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; ls jsonb; cur jsonb;
BEGIN
 -- Avoid rebuilding operation catalogues for the many bookings with no fitter work.
 IF NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=p_booking_id)
  AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_timing WHERE booking_id=p_booking_id AND status='running')
  AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.conversion_state cs JOIN public.workshop_bookings cb ON cb.vehicle_id=cs.vehicle_id WHERE cb.id=p_booking_id) THEN RETURN NULL; END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 ls:=pdc_fitter_private.lines(b.vehicle_id,b.id);
 cur:='[]'::jsonb;
 -- Running items are listed separately; they never add to the Done %. A job
 -- completed by Sub Status 80/99 (or deleted) shows no running items.
 IF b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage') THEN
 SELECT coalesce(jsonb_agg(x ORDER BY x->>'started_at',x->>'line_identity',x->>'section'),'[]'::jsonb) INTO cur FROM (
  SELECT jsonb_build_object('booking_id',b.id,'line_identity',l->>'line_identity','section',NULL,
   'description',l->>'description','technician',l->>'item_technician','started_at',l->'item_started_at',
   'elapsed_minutes',l->'item_elapsed_minutes',
   'allowance_minutes',CASE WHEN jsonb_typeof(l->'hours')='number' THEN round((l->>'hours')::numeric*60) END,
   'stale',coalesce((l->>'item_stale')::boolean,false)) x
  FROM jsonb_array_elements(ls) l
  WHERE l->>'stage_code'=code AND l->>'item_status'='running' AND NOT coalesce((l->>'completed')::boolean,false)
  UNION ALL
  SELECT jsonb_build_object('booking_id',b.id,'line_identity',l->>'line_identity','section',s->>'id',
   'description',concat_ws(' — ',s->>'label',s->>'description'),'technician',s->>'technician','started_at',s->'started_at',
   'elapsed_minutes',s->'elapsed_minutes','allowance_minutes',s->'planned_minutes',
   'stale',coalesce((s->>'stale')::boolean,false))
  FROM jsonb_array_elements(ls) l, jsonb_array_elements(coalesce(l#>'{conversion,sections}','[]'::jsonb)) s
  WHERE l->>'stage_code'=code AND s->>'status'='in_progress' AND s->>'started_at' IS NOT NULL
   AND NOT coalesce((l->>'completed')::boolean,false)
 ) q;
 END IF;
 RETURN pdc_fitter_private.summary(ls,code)||jsonb_build_object('running',jsonb_array_length(cur),
  'stale',(SELECT count(*) FROM jsonb_array_elements(cur) x WHERE (x->>'stale')::boolean),'current',cur);
END $function$;

-- ===== CONVERSION ENRICH (Done-only %, several sections may run) =====
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE c jsonb; ticked boolean; rows jsonb:='[]'; s jsonb; el numeric; planned numeric; total numeric:=0; credit numeric:=0; done integer:=0; running integer:=0; n integer:=0;
BEGIN
 c := pdc_fitter_private.conversion_view(p_vehicle, p_line);
 IF c IS NULL THEN RETURN p_line; END IF;
 -- Matched Coaster and HiAce templates: each section is its own tick. The
 -- source scope hash stays on the line so the item tick matches
 -- operation_progress. Progress = Done sections' allowances only; running
 -- sections are counted separately (Bhavesh, 20 Oct 2026) and flagged stale
 -- after twice their allowance or from an earlier Perth day.
 -- Review / conflicting conversions keep the section-and-checklist gate.
 IF c->>'id' IN ('coaster', 'hiace_commuter') AND coalesce((c->>'needs_review')::boolean, false) = false THEN
  ticked := coalesce((p_line->>'completed')::boolean, false);
  FOR s IN SELECT value FROM jsonb_array_elements(c->'sections') LOOP
   n := n + 1; planned := coalesce((s->>'planned_minutes')::numeric, 0); total := total + planned;
   IF s->>'status' = 'complete' THEN
    done := done + 1; credit := credit + planned;
   ELSIF s->>'status' = 'in_progress' AND s->>'started_at' IS NOT NULL THEN
    running := running + 1;
    el := round(pdc_fitter_private.operational_seconds((s->>'started_at')::timestamptz, statement_timestamp()) / 60.0, 2);
    s := s || jsonb_build_object('elapsed_minutes', el, 'stale',
     (planned > 0 AND el > 2 * planned)
     OR ((s->>'started_at')::timestamptz AT TIME ZONE 'Australia/Perth')::date < (statement_timestamp() AT TIME ZONE 'Australia/Perth')::date);
   END IF;
   rows := rows || jsonb_build_array(s);
  END LOOP;
  c := c || jsonb_build_object('sections', rows, 'sections_done', done, 'sections_total', n, 'sections_running', running);
  RETURN p_line || jsonb_build_object('conversion', c, 'completed', ticked,
   'completed_fraction', CASE WHEN ticked THEN 1 WHEN total > 0 THEN least(0.99, round(credit / total, 4)) ELSE 0 END);
 END IF;
 RETURN p_line || jsonb_build_object('conversion', c,
  'scope_hash', coalesce(c->>'scope_hash', md5((p_line->>'scope_hash') || ':model-review')),
  'completed', coalesce((c->>'complete')::boolean, false),
  'completed_fraction', CASE WHEN (c->>'total_minutes')::numeric > 0
   THEN least(0.99, (c->>'completed_planned_minutes')::numeric / (c->>'total_minutes')::numeric)
   ELSE 0 END);
END
$function$;

-- ===== CONVERSION SAVE (several sections may run at once) =====
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_save(p_tech uuid, p_booking uuid, p_line text, p_change jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; l jsonb; c jsonb; sec jsonb; oldstate pdc_fitter_private.conversion_state;
 beforej jsonb; sections jsonb; meta jsonb; valuej jsonb; mode text:=p_change->>'mode'; k text; v numeric;
 sk text; all_done boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 PERFORM public.workshop_require_planner_operator();
 IF NOT pdc_fitter_private.assigned(p_booking,p_tech) THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking FOR UPDATE;
 IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(pdc_fitter_private.lines(b.vehicle_id,b.id)) x WHERE x->>'line_identity'=p_line AND x->>'stage_code'='BUS_4X4';
 IF l IS NULL OR l->'conversion' IS NULL OR coalesce((l#>>'{conversion,needs_review}')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'error','conversion_model_review'); END IF;
 c:=l->'conversion';
 -- Section state lives under the conversion's own scope hash (the one
 -- conversion_view reads). #381 left the line on its source hash.
 sk:=coalesce(c->>'scope_hash',l->>'scope_hash');
 SELECT * INTO oldstate FROM pdc_fitter_private.conversion_state WHERE vehicle_id=b.vehicle_id AND line_identity=p_line AND scope_hash=sk FOR UPDATE;
 beforej:=coalesce(to_jsonb(oldstate),'{}'); sections:=coalesce(oldstate.sections,'{}'); meta:=coalesce(oldstate.metadata,'{}');
 IF mode='section' THEN
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'status','') NOT IN ('not_started','in_progress','complete') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  FOR k IN SELECT unnest(ARRAY['actual_minutes','remaining_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>60000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
  END LOOP;
  IF p_change->>'status'='complete' AND (nullif(btrim(p_change->>'deferred'),'') IS NOT NULL OR nullif(btrim(p_change->>'blocker'),'') IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','conversion_deferred'); END IF;
  IF p_change->>'status'='complete' AND sec->>'id'='12' AND nullif(meta->>'checklist_reference','') IS NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF length(coalesce(p_change->>'note',''))>500 OR length(coalesce(p_change->>'deferred',''))>500 OR length(coalesce(p_change->>'blocker',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=jsonb_build_object('status',p_change->>'status','actual_minutes',p_change->'actual_minutes',
    'remaining_minutes',CASE WHEN p_change->>'status'='complete' THEN '0'::jsonb WHEN p_change->>'status'='not_started' THEN sec->'planned_minutes' ELSE coalesce(p_change->'remaining_minutes','null'::jsonb) END,
    'deferred',btrim(coalesce(p_change->>'deferred','')),'blocker',btrim(coalesce(p_change->>'blocker','')),'note',coalesce(p_change->>'note',''),
    'technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);

 ELSIF mode='tick' THEN
  -- Coaster / HiAce: each section is its own simple item. step 'start' begins
  -- it (several sections may run at once), 'done' records the actual
  -- workshop time since start, 'reset' unticks it, 'note' saves a note only.
  IF coalesce(c->>'id','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'step','') NOT IN ('start','done','reset','note') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  IF p_change ? 'note' AND (jsonb_typeof(p_change->'note')<>'string' OR length(p_change->>'note')>500) THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=coalesce(sections->(sec->>'id'),'{}');
  IF p_change->>'step'='start' THEN
   IF coalesce(valuej->>'status','')='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   IF coalesce(valuej->>'status','')<>'in_progress' THEN
    valuej:=valuej||jsonb_build_object('status','in_progress','started_at',clock_timestamp(),'completed_at',NULL,'remaining_minutes',sec->'planned_minutes');
   END IF;
  ELSIF p_change->>'step'='note' THEN
   NULL; -- note only, status and times unchanged
  ELSIF p_change->>'step'='done' THEN
   IF coalesce(valuej->>'status','')<>'complete' THEN
   valuej:=valuej||jsonb_build_object('status','complete','completed_at',clock_timestamp(),'remaining_minutes',0,
    'actual_minutes',CASE WHEN valuej->>'status'='in_progress' AND valuej->>'started_at' IS NOT NULL
     THEN to_jsonb(round(pdc_fitter_private.operational_seconds((valuej->>'started_at')::timestamptz,clock_timestamp())/60.0,2))
     ELSE coalesce(valuej->'actual_minutes','null'::jsonb) END);
   END IF;
  ELSE
   valuej:=valuej||jsonb_build_object('status','not_started','started_at',NULL,'completed_at',NULL,'actual_minutes',NULL,'remaining_minutes',sec->'planned_minutes');
  END IF;
  valuej:=valuej||jsonb_build_object('technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  IF p_change ? 'note' THEN valuej:=valuej||jsonb_build_object('note',p_change->>'note'); END IF;
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);
 ELSIF mode='planning' THEN
  -- Cumulative additional time is separate from conversion labour. Delay remaining is prospective, not elapsed waiting.
  FOR k IN SELECT unnest(ARRAY['helper_minutes','parts_delay_minutes','waiting_minutes','repair_minutes','rework_minutes','delay_remaining_minutes','available_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>600000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
   meta:=jsonb_set(meta,ARRAY[k],coalesce(p_change->k,'null'::jsonb));
  END LOOP;
  IF p_change->>'promised_at' IS NOT NULL THEN PERFORM (p_change->>'promised_at')::timestamptz; END IF;
  IF length(coalesce(p_change->>'note',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  meta:=meta||jsonb_build_object('promised_at',p_change->>'promised_at','capacity_as_of',clock_timestamp(),'planning_note',coalesce(p_change->>'note',''),
   'comparable',coalesce((p_change->>'comparable')::boolean,true),'planning_updated_by',auth.uid(),'planning_technician_id',p_tech);
 ELSIF mode='checklist' THEN
  IF coalesce(public.current_pdc_user_role()::text,'') NOT IN ('operator','administrator') THEN RETURN jsonb_build_object('ok',false,'error','conversion_controller_required'); END IF;
  IF length(btrim(coalesce(p_change->>'reference','')))<5 OR length(btrim(coalesce(p_change->>'scope','')))<10 OR length(p_change->>'reference')>500 OR length(p_change->>'scope')>1000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF sections#>>'{12,status}'='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_reopen_section'); END IF;
  meta:=meta||jsonb_build_object('checklist_reference',btrim(p_change->>'reference'),'checklist_scope',btrim(p_change->>'scope'),'checklist_confirmed_by',auth.uid(),'checklist_confirmed_at',clock_timestamp());
 ELSE RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
 INSERT INTO pdc_fitter_private.conversion_state(vehicle_id,line_identity,scope_hash,template_id,template_version,sections,metadata,updated_by)
 VALUES(b.vehicle_id,p_line,sk,c->>'id',c->>'version',sections,meta,auth.uid())
 ON CONFLICT(vehicle_id,line_identity,scope_hash) DO UPDATE SET sections=excluded.sections,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=clock_timestamp()
  WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
 INSERT INTO pdc_fitter_private.conversion_audit(vehicle_id,line_identity,scope_hash,booking_id,technician_id,actor_id,action,before_state,after_state)
 VALUES(b.vehicle_id,p_line,sk,b.id,p_tech,auth.uid(),mode,beforej,jsonb_build_object('sections',sections,'metadata',meta));
 IF mode='tick' THEN
  -- The bay item is complete when every section is ticked. Ticking a section
  -- never clears an existing whole-item tick; resetting one reopens the item.
  all_done:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c->'sections') x
   WHERE coalesce(sections#>>ARRAY[x->>'id','status'],'')<>'complete');
  IF all_done THEN
   INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
   VALUES(b.id,p_line,l->>'scope_hash',true,coalesce(l->>'note',''),p_tech,auth.uid())
   ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,completed=true,
    technician_id=excluded.technician_id,updated_by=excluded.updated_by,updated_at=clock_timestamp()
    WHERE true;
  ELSIF p_change->>'step'='reset' THEN
   UPDATE pdc_fitter_private.operation_progress SET completed=false,technician_id=p_tech,updated_by=auth.uid(),updated_at=clock_timestamp()
   WHERE booking_id=b.id AND line_identity=p_line AND completed;
  END IF;
 END IF;
 UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true);
END $function$;

-- ===== FITTER JOB COMMAND (item_start / item_reset; Done stamps actual) =====
CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion','item_start','item_reset')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action IN('item_start','item_reset') THEN
     -- Start / reset an item: timing only; booking row and version unchanged.
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     r:=pdc_fitter_private.item_timing_save(p_technician_id,b.id,l,substr(p_action,6),p_note);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp()
      WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
     -- Done stamps the actual time on a started item; untick clears it.
     PERFORM pdc_fitter_private.item_timing_tick(b.id,p_line_identity,l->>'scope_hash',p_completed);
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$;

-- ===== MANAGER RESET (board / planner) =====
-- A controller resets a forgotten running item or conversion section. It goes
-- back to not started; the reason and before/after are audited. Never touches
-- workshop_bookings, operation_progress or a Done tick.
CREATE OR REPLACE FUNCTION public.reset_fitter_item_timing(p_booking_id uuid, p_line_identity text, p_section text DEFAULT NULL, p_reason text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; t pdc_fitter_private.operation_timing; cs pdc_fitter_private.conversion_state; sec jsonb; nsec jsonb;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_booking_id IS NULL OR nullif(btrim(coalesce(p_line_identity,'')),'') IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
 IF length(btrim(coalesce(p_reason,'')))<3 OR length(p_reason)>500 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND deleted_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','booking_unavailable'); END IF;
 -- A completed job (fitter, Sub Status 80 or 99) is never reopened from here.
 IF b.status NOT IN ('queued','planned','started','stoppage') THEN RETURN jsonb_build_object('ok',false,'error','booking_not_active'); END IF;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 IF p_section IS NULL THEN
  SELECT * INTO t FROM pdc_fitter_private.operation_timing
  WHERE booking_id=b.id AND line_identity=p_line_identity AND status='running' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','item_not_running'); END IF;
  UPDATE pdc_fitter_private.operation_timing SET status='reset',reset_reason=btrim(p_reason),updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE booking_id=b.id AND line_identity=p_line_identity AND status='running';
  INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,technician_id,actor_id,action,before_state,after_state)
  SELECT b.id,p_line_identity,t.technician_id,auth.uid(),'manager_reset',to_jsonb(t),to_jsonb(x)
  FROM pdc_fitter_private.operation_timing x WHERE x.booking_id=b.id AND x.line_identity=p_line_identity;
 ELSE
  SELECT * INTO cs FROM pdc_fitter_private.conversion_state
  WHERE vehicle_id=b.vehicle_id AND line_identity=p_line_identity AND sections#>>ARRAY[p_section,'status']='in_progress'
  ORDER BY updated_at DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','item_not_running'); END IF;
  sec:=cs.sections->p_section;
  nsec:=sec||jsonb_build_object('status','not_started','started_at',NULL,'completed_at',NULL,'actual_minutes',NULL,
   'reset_by',auth.uid(),'reset_reason',btrim(p_reason),'updated_at',clock_timestamp());
  UPDATE pdc_fitter_private.conversion_state SET sections=jsonb_set(sections,ARRAY[p_section],nsec),updated_by=auth.uid(),updated_at=clock_timestamp()
  WHERE vehicle_id=cs.vehicle_id AND line_identity=cs.line_identity AND scope_hash=cs.scope_hash;
  INSERT INTO pdc_fitter_private.conversion_audit(vehicle_id,line_identity,scope_hash,booking_id,technician_id,actor_id,action,before_state,after_state)
  VALUES(cs.vehicle_id,cs.line_identity,cs.scope_hash,b.id,coalesce((sec->>'technician_id')::uuid,auth.uid()),auth.uid(),'manager_reset',
   jsonb_build_object('section',p_section,'state',sec),jsonb_build_object('section',p_section,'state',nsec,'reason',btrim(p_reason)));
  INSERT INTO pdc_fitter_private.operation_timing_audit(booking_id,line_identity,section_id,technician_id,actor_id,action,before_state,after_state)
  VALUES(b.id,p_line_identity,p_section,(sec->>'technician_id')::uuid,auth.uid(),'manager_reset',sec,nsec);
 END IF;
 PERFORM public.workshop_bump_station_revision(code);
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'line_identity',p_line_identity,'section',p_section,
  'revision',public.workshop_bump_revision());
END $function$;
REVOKE ALL ON FUNCTION public.reset_fitter_item_timing(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reset_fitter_item_timing(uuid,text,text,text) TO authenticated, service_role;
-- END ITEM TICKS APPLY

DO $post$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'start_workshop_work_pre_116')
     IS DISTINCT FROM '40ab1b0a75d347b56c69e54c65ddd193' THEN
    RAISE EXCEPTION 'start_workshop_work_pre_116_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_bus_private' AND p.proname = 'add_minutes')
     IS DISTINCT FROM 'c43afa5c1312392aa5d3666a8aa7cf65' THEN
    RAISE EXCEPTION 'add_minutes_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_bus_private' AND p.proname = 'clock_add_minutes')
     IS DISTINCT FROM 'd0a395e6739423c1e4f5f2329fa5cd75' THEN
    RAISE EXCEPTION 'clock_add_minutes_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'workshop_clock_tick')
     IS DISTINCT FROM '84af7607bfd0ce9907c89bae8644d5b6' THEN
    RAISE EXCEPTION 'workshop_clock_tick_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_view')
     IS DISTINCT FROM '45b3b8f43a2a630cca14466c1a9e1567' THEN
    RAISE EXCEPTION 'conversion_view_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_catalog')
     IS DISTINCT FROM 'b7789961f5e49d09b854ce7582d34e83' THEN
    RAISE EXCEPTION 'conversion_catalog_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_completion_guard')
     IS DISTINCT FROM 'befe9ecce7ea624be54b9c637a8b15df' THEN
    RAISE EXCEPTION 'conversion_completion_guard_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'operational_seconds')
     IS DISTINCT FROM '650b7df281eb4526c6d99ee497313515' THEN
    RAISE EXCEPTION 'operational_seconds_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'timing')
     IS DISTINCT FROM 'ddb9eb4132cf8fdbb5efca444fda29d0' THEN
    RAISE EXCEPTION 'timing_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'summary')
     IS DISTINCT FROM 'c481664c82eb64487b1085edd67b9045' THEN
    RAISE EXCEPTION 'summary_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines')
     IS DISTINCT FROM '28c3949d357c203601bfbee42da6c879' THEN
    RAISE EXCEPTION 'lines_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'base_lines')
     IS DISTINCT FROM '47addc72c8aa19d1d66d2c3239f03b9c' THEN
    RAISE EXCEPTION 'base_lines_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_work_categories_private' AND p.proname = 'invalidate_qc_operation_lines_cache')
     IS DISTINCT FROM '00f532fdd214dcd242c267616f43bc7f' THEN
    RAISE EXCEPTION 'invalidate_qc_operation_lines_cache_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'pdc_qc_operation_lines_379')
     IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN
    RAISE EXCEPTION 'pdc_qc_operation_lines_379_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'pdc_qc_operation_lines_379_uncached')
     IS DISTINCT FROM 'b677d7bfdf67c046fd05922da249325c' THEN
    RAISE EXCEPTION 'pdc_qc_operation_lines_379_uncached_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'get_fitter_job')
     IS DISTINCT FROM '74d1a88dc9b440782904c02682c25ebc' THEN
    RAISE EXCEPTION 'get_fitter_job_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'apply_service_pmb_complete')
     IS DISTINCT FROM 'eea5bb523c2538742db52508665191d3' THEN
    RAISE EXCEPTION 'apply_service_pmb_complete_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'finish_tune_checkout')
     IS DISTINCT FROM '3e5c6b28e7c025a6ebbae61879ff3a82' THEN
    RAISE EXCEPTION 'finish_tune_checkout_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS NOT DISTINCT FROM 'db9db4ca6a63161d873480edf8a078b6' THEN
    RAISE EXCEPTION 'fitter_job_command_not_applied';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines_before_bus_workflow_20260921')
     IS NOT DISTINCT FROM '6154aaf1490f5d49acfc3a5f3232edc2' THEN
    RAISE EXCEPTION 'lines_before_bus_workflow_20260921_not_applied';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'progress')
     IS NOT DISTINCT FROM 'b388403d94d1adbb5c01fd4cb979ebd2' THEN
    RAISE EXCEPTION 'progress_not_applied';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS NOT DISTINCT FROM '2f156fdc1cafc810d60637f50b346f12' THEN
    RAISE EXCEPTION 'conversion_enrich_not_applied';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS NOT DISTINCT FROM 'fb4d6cd82f40ee27476186e0ac5b05f4' THEN
    RAISE EXCEPTION 'conversion_save_not_applied';
  END IF;
  IF position('item_timing_tick' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')) = 0
   OR position('conversion_section_in_progress' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')) > 0 THEN
    RAISE EXCEPTION 'item_ticks_not_applied';
  END IF;
END $post$;

DO $b$ BEGIN PERFORM pg_temp.ss_phase('B'); END $b$;

-- ===== PHASE C: 384.down.sql applied inside this transaction =====
-- Undo 20261020160000_bay_item_start_done: restore fitter_job_command,
-- lines_before_bus_workflow_20260921, progress, conversion_enrich and
-- conversion_save byte-exact (md5 db9db4ca / 6154aaf1 / b388403d / 2f156fdc /
-- fb4d6cd8) and drop the reset RPC and item helpers. operation_timing and its
-- audit stay stored (nothing is deleted). Bus sections go back to one running
-- section per conversion and the in-progress share returns to the job %.
-- Staging cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF position('item_timing_tick' IN (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')) = 0 THEN
    RAISE EXCEPTION 'item_ticks_not_applied';
  END IF;
END $guard$;

-- public.fitter_job_command (md5 db9db4ca)
CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL AND coalesce(l#>>'{conversion,id}','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp();
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$;

-- pdc_fitter_private.conversion_save (md5 fb4d6cd8)
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_save(p_tech uuid, p_booking uuid, p_line text, p_change jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; l jsonb; c jsonb; sec jsonb; oldstate pdc_fitter_private.conversion_state;
 beforej jsonb; sections jsonb; meta jsonb; valuej jsonb; mode text:=p_change->>'mode'; k text; v numeric;
 sk text; all_done boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 PERFORM public.workshop_require_planner_operator();
 IF NOT pdc_fitter_private.assigned(p_booking,p_tech) THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking FOR UPDATE;
 IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(pdc_fitter_private.lines(b.vehicle_id,b.id)) x WHERE x->>'line_identity'=p_line AND x->>'stage_code'='BUS_4X4';
 IF l IS NULL OR l->'conversion' IS NULL OR coalesce((l#>>'{conversion,needs_review}')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'error','conversion_model_review'); END IF;
 c:=l->'conversion';
 -- Section state lives under the conversion's own scope hash (the one
 -- conversion_view reads). #381 left the line on its source hash.
 sk:=coalesce(c->>'scope_hash',l->>'scope_hash');
 SELECT * INTO oldstate FROM pdc_fitter_private.conversion_state WHERE vehicle_id=b.vehicle_id AND line_identity=p_line AND scope_hash=sk FOR UPDATE;
 beforej:=coalesce(to_jsonb(oldstate),'{}'); sections:=coalesce(oldstate.sections,'{}'); meta:=coalesce(oldstate.metadata,'{}');
 IF mode='section' THEN
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'status','') NOT IN ('not_started','in_progress','complete') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  FOR k IN SELECT unnest(ARRAY['actual_minutes','remaining_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>60000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
  END LOOP;
  IF p_change->>'status'='complete' AND (nullif(btrim(p_change->>'deferred'),'') IS NOT NULL OR nullif(btrim(p_change->>'blocker'),'') IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','conversion_deferred'); END IF;
  IF p_change->>'status'='complete' AND sec->>'id'='12' AND nullif(meta->>'checklist_reference','') IS NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF length(coalesce(p_change->>'note',''))>500 OR length(coalesce(p_change->>'deferred',''))>500 OR length(coalesce(p_change->>'blocker',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=jsonb_build_object('status',p_change->>'status','actual_minutes',p_change->'actual_minutes',
    'remaining_minutes',CASE WHEN p_change->>'status'='complete' THEN '0'::jsonb WHEN p_change->>'status'='not_started' THEN sec->'planned_minutes' ELSE coalesce(p_change->'remaining_minutes','null'::jsonb) END,
    'deferred',btrim(coalesce(p_change->>'deferred','')),'blocker',btrim(coalesce(p_change->>'blocker','')),'note',coalesce(p_change->>'note',''),
    'technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);

 ELSIF mode='tick' THEN
  -- Coaster / HiAce: each section is its own simple item. step 'start' begins
  -- it (one section in progress per conversion), 'done' records the actual
  -- workshop time since start, 'reset' unticks it, 'note' saves a note only.
  IF coalesce(c->>'id','') NOT IN ('coaster','hiace_commuter') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'step','') NOT IN ('start','done','reset','note') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  IF p_change ? 'note' AND (jsonb_typeof(p_change->'note')<>'string' OR length(p_change->>'note')>500) THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=coalesce(sections->(sec->>'id'),'{}');
  IF p_change->>'step'='start' THEN
   IF coalesce(valuej->>'status','')='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   IF EXISTS(SELECT 1 FROM jsonb_each(sections) x WHERE x.key<>sec->>'id' AND x.value->>'status'='in_progress') THEN
    RETURN jsonb_build_object('ok',false,'error','conversion_section_in_progress'); END IF;
   IF coalesce(valuej->>'status','')<>'in_progress' THEN
    valuej:=valuej||jsonb_build_object('status','in_progress','started_at',clock_timestamp(),'completed_at',NULL,'remaining_minutes',sec->'planned_minutes');
   END IF;
  ELSIF p_change->>'step'='note' THEN
   NULL; -- note only, status and times unchanged
  ELSIF p_change->>'step'='done' THEN
   IF coalesce(valuej->>'status','')<>'complete' THEN
   valuej:=valuej||jsonb_build_object('status','complete','completed_at',clock_timestamp(),'remaining_minutes',0,
    'actual_minutes',CASE WHEN valuej->>'status'='in_progress' AND valuej->>'started_at' IS NOT NULL
     THEN to_jsonb(round(pdc_fitter_private.operational_seconds((valuej->>'started_at')::timestamptz,clock_timestamp())/60.0,2))
     ELSE coalesce(valuej->'actual_minutes','null'::jsonb) END);
   END IF;
  ELSE
   valuej:=valuej||jsonb_build_object('status','not_started','started_at',NULL,'completed_at',NULL,'actual_minutes',NULL,'remaining_minutes',sec->'planned_minutes');
  END IF;
  valuej:=valuej||jsonb_build_object('technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  IF p_change ? 'note' THEN valuej:=valuej||jsonb_build_object('note',p_change->>'note'); END IF;
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);
 ELSIF mode='planning' THEN
  -- Cumulative additional time is separate from conversion labour. Delay remaining is prospective, not elapsed waiting.
  FOR k IN SELECT unnest(ARRAY['helper_minutes','parts_delay_minutes','waiting_minutes','repair_minutes','rework_minutes','delay_remaining_minutes','available_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>600000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
   meta:=jsonb_set(meta,ARRAY[k],coalesce(p_change->k,'null'::jsonb));
  END LOOP;
  IF p_change->>'promised_at' IS NOT NULL THEN PERFORM (p_change->>'promised_at')::timestamptz; END IF;
  IF length(coalesce(p_change->>'note',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  meta:=meta||jsonb_build_object('promised_at',p_change->>'promised_at','capacity_as_of',clock_timestamp(),'planning_note',coalesce(p_change->>'note',''),
   'comparable',coalesce((p_change->>'comparable')::boolean,true),'planning_updated_by',auth.uid(),'planning_technician_id',p_tech);
 ELSIF mode='checklist' THEN
  IF coalesce(public.current_pdc_user_role()::text,'') NOT IN ('operator','administrator') THEN RETURN jsonb_build_object('ok',false,'error','conversion_controller_required'); END IF;
  IF length(btrim(coalesce(p_change->>'reference','')))<5 OR length(btrim(coalesce(p_change->>'scope','')))<10 OR length(p_change->>'reference')>500 OR length(p_change->>'scope')>1000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF sections#>>'{12,status}'='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_reopen_section'); END IF;
  meta:=meta||jsonb_build_object('checklist_reference',btrim(p_change->>'reference'),'checklist_scope',btrim(p_change->>'scope'),'checklist_confirmed_by',auth.uid(),'checklist_confirmed_at',clock_timestamp());
 ELSE RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
 INSERT INTO pdc_fitter_private.conversion_state(vehicle_id,line_identity,scope_hash,template_id,template_version,sections,metadata,updated_by)
 VALUES(b.vehicle_id,p_line,sk,c->>'id',c->>'version',sections,meta,auth.uid())
 ON CONFLICT(vehicle_id,line_identity,scope_hash) DO UPDATE SET sections=excluded.sections,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=clock_timestamp()
  WHERE true; -- explicit WHERE for the CI safeupdate lint (#379)
 INSERT INTO pdc_fitter_private.conversion_audit(vehicle_id,line_identity,scope_hash,booking_id,technician_id,actor_id,action,before_state,after_state)
 VALUES(b.vehicle_id,p_line,sk,b.id,p_tech,auth.uid(),mode,beforej,jsonb_build_object('sections',sections,'metadata',meta));
 IF mode='tick' THEN
  -- The bay item is complete when every section is ticked. Ticking a section
  -- never clears an existing whole-item tick; resetting one reopens the item.
  all_done:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c->'sections') x
   WHERE coalesce(sections#>>ARRAY[x->>'id','status'],'')<>'complete');
  IF all_done THEN
   INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
   VALUES(b.id,p_line,l->>'scope_hash',true,coalesce(l->>'note',''),p_tech,auth.uid())
   ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,completed=true,
    technician_id=excluded.technician_id,updated_by=excluded.updated_by,updated_at=clock_timestamp()
    WHERE true;
  ELSIF p_change->>'step'='reset' THEN
   UPDATE pdc_fitter_private.operation_progress SET completed=false,technician_id=p_tech,updated_by=auth.uid(),updated_at=clock_timestamp()
   WHERE booking_id=b.id AND line_identity=p_line AND completed;
  END IF;
 END IF;
 UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true);
END $function$;

-- pdc_fitter_private.conversion_enrich (md5 2f156fdc)
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid, p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE c jsonb; ticked boolean; rows jsonb:='[]'; s jsonb; el numeric; total numeric:=0; credit numeric:=0; done integer:=0; n integer:=0;
BEGIN
 c := pdc_fitter_private.conversion_view(p_vehicle, p_line);
 IF c IS NULL THEN RETURN p_line; END IF;
 -- Matched Coaster and HiAce templates: each section is its own tick. The
 -- source scope hash stays on the line so the item tick matches
 -- operation_progress. Progress = ticked sections' allowances plus the
 -- in-progress section's elapsed workshop time (capped at its allowance).
 -- Review / conflicting conversions keep the section-and-checklist gate.
 IF c->>'id' IN ('coaster', 'hiace_commuter') AND coalesce((c->>'needs_review')::boolean, false) = false THEN
  ticked := coalesce((p_line->>'completed')::boolean, false);
  FOR s IN SELECT value FROM jsonb_array_elements(c->'sections') LOOP
   n := n + 1; total := total + coalesce((s->>'planned_minutes')::numeric, 0);
   IF s->>'status' = 'complete' THEN
    done := done + 1; credit := credit + coalesce((s->>'planned_minutes')::numeric, 0);
   ELSIF s->>'status' = 'in_progress' AND s->>'started_at' IS NOT NULL THEN
    el := round(pdc_fitter_private.operational_seconds((s->>'started_at')::timestamptz, statement_timestamp()) / 60.0, 2);
    s := s || jsonb_build_object('elapsed_minutes', el);
    credit := credit + least(el, coalesce((s->>'planned_minutes')::numeric, 0));
   END IF;
   rows := rows || jsonb_build_array(s);
  END LOOP;
  c := c || jsonb_build_object('sections', rows, 'sections_done', done, 'sections_total', n);
  RETURN p_line || jsonb_build_object('conversion', c, 'completed', ticked,
   'completed_fraction', CASE WHEN ticked THEN 1 WHEN total > 0 THEN least(0.99, round(credit / total, 4)) ELSE 0 END);
 END IF;
 RETURN p_line || jsonb_build_object('conversion', c,
  'scope_hash', coalesce(c->>'scope_hash', md5((p_line->>'scope_hash') || ':model-review')),
  'completed', coalesce((c->>'complete')::boolean, false),
  'completed_fraction', CASE WHEN (c->>'total_minutes')::numeric > 0
   THEN least(0.99, (c->>'completed_planned_minutes')::numeric / (c->>'total_minutes')::numeric)
   ELSE 0 END);
END
$function$;

-- pdc_fitter_private.lines_before_bus_workflow_20260921 (CRLF body, md5 6154aaf1)
DO $restore$
BEGIN
 EXECUTE replace($def$
CREATE OR REPLACE FUNCTION pdc_fitter_private.lines_before_bus_workflow_20260921(p_vehicle_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH source AS (
  SELECT l,md5(jsonb_build_array(l->>'line_identity',l->>'description',
    l->>'stage_code',l->'estimated_hours',l->>'job_card_number')::text) scope_hash
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true)
 )
 SELECT coalesce(jsonb_agg(pdc_fitter_private.conversion_enrich(p_vehicle_id,jsonb_build_object(
  'line_identity',s.l->>'line_identity','description',s.l->>'description',
  'stage_code',s.l->>'stage_code','hours',s.l->'estimated_hours',
  'operation_no',s.l->'operation_no','source_note',s.l->>'review_note',
  'scope_hash',s.scope_hash,'completed',coalesce(p.completed AND p.scope_hash=s.scope_hash,false),
  'note',coalesce(p.note,''),'scope_changed',p.scope_hash IS NOT NULL AND p.scope_hash<>s.scope_hash,
  'updated_at',p.updated_at,'technician_id',p.technician_id
 )) ORDER BY s.l->>'stage_code',s.l->>'operation_no',s.l->>'line_identity'),'[]'::jsonb)
 FROM source s LEFT JOIN pdc_fitter_private.operation_progress p
   ON p.booking_id=p_booking_id AND p.line_identity=s.l->>'line_identity'
$function$
$def$, E'\n', E'\r\n');
END $restore$;

-- pdc_fitter_private.progress (CRLF body, md5 b388403d)
DO $restore$
BEGIN
 EXECUTE replace($def$
CREATE OR REPLACE FUNCTION pdc_fitter_private.progress(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text;
BEGIN
 -- Avoid rebuilding operation catalogues for the many bookings with no fitter work.
 IF NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=p_booking_id) AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.conversion_state cs JOIN public.workshop_bookings cb ON cb.vehicle_id=cs.vehicle_id WHERE cb.id=p_booking_id) THEN RETURN NULL; END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 RETURN pdc_fitter_private.summary(pdc_fitter_private.lines(b.vehicle_id,b.id),code);
END $function$
$def$, E'\n', E'\r\n');
END $restore$;

DROP FUNCTION IF EXISTS public.reset_fitter_item_timing(uuid,text,text,text);
DROP FUNCTION IF EXISTS pdc_fitter_private.item_timing_save(uuid,uuid,jsonb,text,text);
DROP FUNCTION IF EXISTS pdc_fitter_private.item_timing_tick(uuid,text,text,boolean);
DROP FUNCTION IF EXISTS pdc_fitter_private.item_timing(pdc_fitter_private.operation_timing,text,jsonb,numeric);

DO $post$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fitter_job_command')
     IS DISTINCT FROM 'db9db4ca6a63161d873480edf8a078b6' THEN
    RAISE EXCEPTION 'fitter_job_command_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_save')
     IS DISTINCT FROM 'fb4d6cd82f40ee27476186e0ac5b05f4' THEN
    RAISE EXCEPTION 'conversion_save_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'conversion_enrich')
     IS DISTINCT FROM '2f156fdc1cafc810d60637f50b346f12' THEN
    RAISE EXCEPTION 'conversion_enrich_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'lines_before_bus_workflow_20260921')
     IS DISTINCT FROM '6154aaf1490f5d49acfc3a5f3232edc2' THEN
    RAISE EXCEPTION 'lines_before_bus_workflow_20260921_not_restored';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_fitter_private' AND p.proname = 'progress')
     IS DISTINCT FROM 'b388403d94d1adbb5c01fd4cb979ebd2' THEN
    RAISE EXCEPTION 'progress_not_restored';
  END IF;
END $post$;

DO $c$
DECLARE n integer;
BEGIN
 PERFORM pg_temp.ss_phase('C');
 PERFORM pg_temp.ou_assert(NOT EXISTS(
   SELECT 1 FROM ss_results a JOIN ss_results x ON x.scen=a.scen AND x.step=a.step AND x.phase<>'A'
   WHERE a.phase='A' AND (x.result IS DISTINCT FROM a.result OR x.sig IS DISTINCT FROM a.sig))
  AND (SELECT count(*) FROM ss_results WHERE phase='A')=(SELECT count(*) FROM ss_results WHERE phase='B')
  AND (SELECT count(*) FROM ss_results WHERE phase='A')=(SELECT count(*) FROM ss_results WHERE phase='C'),
  'Z1 every import outcome identical before 384, with 384 and after 384.down.sql',
  (SELECT jsonb_object_agg(phase||' '||scen||' '||step,jsonb_build_object('result',result,'sig',sig)) FROM ss_results));
 SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE (ns.nspname,p.proname,left(md5(p.prosrc),8)) IN (
  ('public','start_workshop_work_pre_116','40ab1b0a'),('pdc_bus_private','add_minutes','c43afa5c'),
  ('public','workshop_clock_tick','84af7607'),('pdc_codex_intake_private','apply_service_pmb_complete','eea5bb52'),
  ('pdc_codex_intake_private','finish_tune_checkout','3e5c6b28'),('pdc_codex_intake_private','capture_service_status','3cc871d8'),
  ('pdc_fitter_private','conversion_completion_guard','befe9ecc'),
  ('public','fitter_job_command','db9db4ca'),('pdc_fitter_private','conversion_save','fb4d6cd8'),
  ('pdc_fitter_private','conversion_enrich','2f156fdc'),('pdc_fitter_private','progress','b388403d'),
  ('pdc_fitter_private','lines_before_bus_workflow_20260921','6154aaf1'));
 PERFORM pg_temp.ou_assert(n=12,'Z2 after 384.down.sql all import, guard and restored fitter md5s match the pre-384 baseline',jsonb_build_object('n',n));
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles old FULL JOIN public.vehicles veh ON veh.id=old.id WHERE old.id IS NOT NULL AND to_jsonb(veh) IS DISTINCT FROM old.row_data),'Z3 all real vehicles unchanged');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings old FULL JOIN public.workshop_bookings w ON w.id=old.id WHERE old.id IS NOT NULL AND to_jsonb(w) IS DISTINCT FROM old.row_data),'Z4 all real bookings unchanged');
 RAISE EXCEPTION 'TESTRESULT % %', (SELECT count(*) FROM ou_results),
  (SELECT jsonb_build_object('checks',jsonb_agg(name ORDER BY name),'imports',(SELECT jsonb_agg(jsonb_build_object('k',phase||' '||scen||' '||step,'result',result,'loc',sig->'loc','r80',sig->'r80','r99',sig->'r99','booking',sig#>'{bookings,0,status}') ORDER BY scen,step,phase) FROM ss_results)) FROM ou_results);
END $c$;
ROLLBACK;
