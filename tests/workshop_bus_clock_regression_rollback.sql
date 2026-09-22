-- STAGING ONLY. Synthetic actor, vehicles, operations and bays; no existing
-- operational records are written. Revision/audit effects and fixtures roll back.
-- Run this complete file in one connection. Every change, including test-only clock
-- snapshot isolation and optional candidate migration, is reverted by ROLLBACK.
BEGIN;
SET LOCAL statement_timeout = '240s';
SET LOCAL lock_timeout = '20s';
SELECT pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
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
 INSERT INTO ou_refs VALUES('bay-'||tag,b);
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
 'department',dept,'operation_description','Fixture work '||stage||' line '||line_no,'source_estimated_hours',hrs,'effective_estimated_hours',hrs,
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







-- Isolate the scheduler input, not its algorithm or its mutation guards. The
-- original function is restored automatically with the enclosing rollback.
DO $isolate$ DECLARE d text; needle text:='WHERE b.deleted_at IS NULL AND b.status IN(''planned'',''queued'',''started'',''stoppage'');';
BEGIN
 d:=pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure);
 IF (length(d)-length(replace(d,needle,'')))/length(needle)<>1 THEN RAISE EXCEPTION 'Clock snapshot changed; review test isolation'; END IF;
 EXECUTE replace(d,needle,replace(needle,';',E'\n AND b.metadata->>''bus_clock_fixture''=current_setting(''qa.bus_clock_case'',true);'));
END $isolate$;

-- Calendar fixtures are restored by rollback. This makes edge expectations
-- independent of production holidays or future settings changes.
UPDATE public.workshop_settings SET value=CASE key
 WHEN 'day_start_time' THEN '"06:00"'::jsonb WHEN 'day_end_time' THEN '"16:30"'::jsonb
 WHEN 'working_week' THEN '["monday","tuesday","wednesday","thursday","friday"]'::jsonb
 WHEN 'future_only_schedule_enforcement' THEN 'true'::jsonb ELSE '[]'::jsonb END
WHERE key IN('day_start_time','day_end_time','working_week','future_only_schedule_enforcement','break_windows','closures','overtime_windows','technician_leave');
-- Use a holiday-free synthetic window for clock/shift mechanics; exact official holidays are tested in dept138_team_planning_rollback.sql.
CREATE TEMP TABLE bc_context AS SELECT greatest(date '2028-02-07',(date_trunc('week',greatest(clock_timestamp()+interval '30 days',
 coalesce((SELECT max(scheduled_end_at) FROM public.workshop_bookings),clock_timestamp())+interval '30 days') AT TIME ZONE 'Australia/Perth')::date+7)) base_day;
CREATE TEMP TABLE bc_original_assignments AS SELECT id,to_jsonb(a) row_data FROM public.workshop_booking_assignments a;
CREATE TEMP TABLE bc_original_blocks AS SELECT id,to_jsonb(a) row_data FROM public.workshop_admin_blocks a;
CREATE TEMP TABLE bc_original_operations AS SELECT operation_id,to_jsonb(o) row_data FROM public.pdc_pilbara_service_operations o;

CREATE FUNCTION pg_temp.bc_at(day date,t time) RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $fn$
 SELECT (day+t) AT TIME ZONE 'Australia/Perth'
$fn$;
CREATE FUNCTION pg_temp.bc_bay(n integer) RETURNS uuid LANGUAGE sql STABLE AS $fn$
 SELECT b.id FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE s.code='BUS_4X4' AND b.bay_number=n AND b.is_active
$fn$;
CREATE FUNCTION pg_temp.bc_activate(vid uuid) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE old_op record;
BEGIN
 -- Legacy calendar fixture: add authenticated Department138 evidence and
 -- supersede only the synthetic provisional line through its normal adjustment.
 -- Source import evidence remains append-only throughout the test.
 FOR old_op IN SELECT * FROM public.pdc_pilbara_service_operations WHERE vehicle_id=vid AND department='139' LOOP
  PERFORM pg_temp.ou_operation(vid,old_op.proposed_station,old_op.effective_estimated_hours,old_op.original_line_number+100,'138');
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,description,stage_code,estimated_hours,active,created_by,updated_by)
  VALUES(vid,'source:'||old_op.operation_id,'source',old_op.operation_description,old_op.proposed_station,old_op.effective_estimated_hours,false,auth.uid(),auth.uid());
 END LOOP;
 PERFORM pg_temp.ou_assert(pdc_bus_private.active_vehicle(vid),'Department138 fixture active '||vid);
END $fn$;
CREATE FUNCTION pg_temp.bc_booking(tag text,stage text,bay uuid,at_time timestamptz,minutes integer,
 bus_variant text DEFAULT 'legacy',state public.workshop_booking_status DEFAULT 'planned',model_name text DEFAULT 'Toyota HiAce Commuter')
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v uuid; b uuid; tech uuid:=gen_random_uuid(); parts jsonb;
BEGIN
 v:=pg_temp.ou_vehicle(tag);
 UPDATE public.vehicles SET vehicle_description=model_name,model=model_name WHERE id=v;
 PERFORM pg_temp.ou_operation(v,stage,minutes::numeric/60,1);
 IF bus_variant='current' THEN
  PERFORM pg_temp.bc_activate(v);
  parts:=jsonb_build_object('ready',true,'scope_hash',pdc_bus_private.catalog_hash(v),'note','Synthetic physical parts evidence');
  INSERT INTO pdc_bus_private.workflow(vehicle_id,version,plan,updated_by)
  VALUES(v,1,jsonb_build_object('parts_readiness',jsonb_build_object('mechanical',parts,'electrical',parts,'accessory',parts)),auth.uid());
 END IF;
 b:=pg_temp.ou_booking(tag,v,stage,bay,at_time,state);
 IF bus_variant='legacy' THEN PERFORM pg_temp.bc_activate(v); END IF;
 INSERT INTO public.workshop_technicians(id,name,role_type,active) VALUES(tech,'Bus clock rollback '||tag||' '||tech,'technician',true);
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at)
 SELECT id,tech,'primary',auth.uid(),scheduled_start_at,scheduled_end_at FROM public.workshop_bookings WHERE id=b;
 RETURN b;
END $fn$;

CREATE FUNCTION pg_temp.bc_tick(label text,at_time timestamptz) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE before_rows jsonb; preview jsonb; applied jsonb; again jsonb; audit_count bigint; expected_count integer;
BEGIN
 SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) INTO before_rows FROM public.workshop_bookings b
 WHERE metadata->>'bus_clock_fixture'=current_setting('qa.bus_clock_case',true);
 preview:=public.workshop_clock_tick(false,at_time);
 PERFORM pg_temp.ou_assert(preview->>'ok'='true',label||' preview succeeds',preview);
 PERFORM pg_temp.ou_assert(before_rows IS NOT DISTINCT FROM (SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bookings b
  WHERE metadata->>'bus_clock_fixture'=current_setting('qa.bus_clock_case',true)),label||' preview is read only');
 DROP TABLE IF EXISTS pg_temp.bc_expected;
 CREATE TEMP TABLE bc_expected ON COMMIT DROP AS SELECT id,original_start,original_end,final_start,final_end,duration,changed,before_row FROM pg_temp.clock_linked_plan;
 SELECT count(*) FILTER(WHERE changed) INTO expected_count FROM bc_expected;
 applied:=public.workshop_clock_tick(true,at_time);
 PERFORM pg_temp.ou_assert(applied->>'ok'='true',label||' apply succeeds',applied);
 PERFORM pg_temp.ou_assert(preview->'plans'=applied->'plans' AND preview->'issues'=applied->'issues'
  AND (applied->>'moved_count')::int=expected_count,label||' preview/apply parity',applied-'plans');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bc_expected x JOIN public.workshop_bookings b ON b.id=x.id
  WHERE x.changed AND (b.scheduled_start_at IS DISTINCT FROM x.final_start OR b.scheduled_end_at IS DISTINCT FROM x.final_end)),label||' persisted times match proposal');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id
  JOIN bc_expected x ON x.id=b.id WHERE x.changed AND a.released_at IS NULL
  AND (a.scheduled_start_at IS DISTINCT FROM b.scheduled_start_at OR a.scheduled_end_at IS DISTINCT FROM b.scheduled_end_at)),label||' assignment times match persisted booking');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bc_expected x JOIN public.workshop_bookings b ON b.id=x.id WHERE NOT x.changed
  AND x.before_row IS DISTINCT FROM to_jsonb(b)),label||' untouched and fixed bookings are byte-for-byte preserved');
 PERFORM pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bc_expected x JOIN public.workshop_bookings b ON b.id=x.id WHERE x.changed
  AND (x.before_row-array['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version'])
  IS DISTINCT FROM (to_jsonb(b)-array['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version'])),label||' source work/status/actual fields are preserved');
 SELECT count(*) INTO audit_count FROM public.workshop_clock_history h JOIN bc_expected x ON x.id=h.booking_id;
 again:=public.workshop_clock_tick(true,at_time);
 PERFORM pg_temp.ou_assert(again->>'ok'='true' AND again->>'moved_count'='0' AND audit_count=(SELECT count(*) FROM public.workshop_clock_history h JOIN bc_expected x ON x.id=h.booking_id),
  label||' identical repeat tick creates no movement or history',again-'plans');
 SET CONSTRAINTS ALL IMMEDIATE;
 SET CONSTRAINTS ALL DEFERRED;
 RETURN applied;
END $fn$;

DO $valid_cases$
DECLARE day date; b uuid; other uuid; v uuid; stage uuid; bay uuid; next_bay uuid; hold uuid; fixed uuid; fixed_saved jsonb; block_saved jsonb;
 at_time timestamptz; expected_start timestamptz; expected_end timestamptz; result jsonb; variant text; step integer:=0;
BEGIN
 SELECT base_day INTO day FROM bc_context;
 FOREACH variant IN ARRAY ARRAY['legacy','current'] LOOP
  PERFORM set_config('qa.bus_clock_case','bay3-'||variant,true);
  b:=pg_temp.bc_booking('bay3-'||variant,'BUS_4X4',pg_temp.bc_bay(3),pg_temp.bc_at(day+step*7,time '07:10'),600,variant);
  PERFORM pg_temp.ou_assert((SELECT (bus_calendar_version IS NULL)=(variant='legacy') FROM public.workshop_bookings WHERE id=b),'Fixture has requested '||variant||' calendar basis');
  at_time:=pg_temp.bc_at(day+step*7,time '09:01:15');expected_start:=pg_temp.bc_at(day+step*7,time '09:02');
  expected_end:=pdc_bus_private.add_minutes(expected_start,600,pg_temp.bc_bay(3));
  result:=pg_temp.bc_tick('Bay3 elapsed start '||variant,at_time);
  PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=expected_start AND scheduled_end_at=expected_end AND bus_calendar_version=1
   AND default_duration_minutes=600 AND status='planned' AND actual_start_at IS NULL FROM public.workshop_bookings WHERE id=b),
   'Bay3 '||variant||' advances to present without shortening work or starting it');
  step:=step+1;
 END LOOP;
 -- Mechanical and electrical shifts have different closing times, including Fridays.
 FOREACH variant IN ARRAY ARRAY['mechanical-close','electrical8-close','electrical9-friday'] LOOP
  PERFORM set_config('qa.bus_clock_case',variant,true);
  bay:=pg_temp.bc_bay(CASE variant WHEN 'mechanical-close' THEN 1 WHEN 'electrical8-close' THEN 8 ELSE 9 END);
  b:=pg_temp.bc_booking(variant,'BUS_4X4',bay,pg_temp.bc_at(day+step*7+CASE WHEN variant='electrical9-friday' THEN 4 ELSE 0 END,time '07:00'),60,'legacy');
  at_time:=pg_temp.bc_at(day+step*7+CASE WHEN variant='electrical9-friday' THEN 4 ELSE 0 END,
    CASE WHEN variant='mechanical-close' THEN time '15:01' ELSE time '14:01' END);
  expected_start:=pg_temp.bc_at(day+step*7+CASE WHEN variant='electrical9-friday' THEN 7 ELSE 1 END,time '06:00');
  -- Public holidays added to the Department138 calendar remain closed even when Monday is a weekday.
  WHILE extract(isodow FROM expected_start AT TIME ZONE 'Australia/Perth')>5
    OR pdc_bus_private.planning_calendar()->'closures' ? (expected_start AT TIME ZONE 'Australia/Perth')::date::text LOOP
   expected_start:=expected_start+interval '1 day';
  END LOOP;
  result:=pg_temp.bc_tick(variant,at_time);
  PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=expected_start AND scheduled_end_at=expected_start+interval '1 hour' FROM public.workshop_bookings WHERE id=b),variant||' resumes next open weekday at six');
  step:=step+1;
 END LOOP;
 -- Break and closure cannot become productive capacity during a long cascade.
 -- Keep this break-specific case away from public holidays; holiday exclusion has separate assertions.
 WHILE EXISTS(SELECT 1 FROM generate_series(0,3) offset_day WHERE
  pdc_bus_private.planning_calendar()->'closures' ? (day+step*7+offset_day)::text) LOOP day:=day+7; END LOOP;
 PERFORM set_config('qa.bus_clock_case','break-closure',true);
 UPDATE public.workshop_settings SET value='[{"scope":"global","start":"12:00","end":"12:30"}]'::jsonb WHERE key='break_windows';
 UPDATE public.workshop_settings SET value=jsonb_build_array(jsonb_build_object('date',(day+step*7+1)::text)) WHERE key='closures';
 b:=pg_temp.bc_booking('break-closure','BUS_4X4',pg_temp.bc_bay(8),pg_temp.bc_at(day+step*7,time '06:00'),600,'legacy');
 result:=pg_temp.bc_tick('Long electrical break/closure',pg_temp.bc_at(day+step*7,time '11:30'));
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=pg_temp.bc_at(day+step*7,time '11:30') AND scheduled_end_at=pg_temp.bc_at(day+step*7+3,time '06:30')
   FROM public.workshop_bookings WHERE id=b),'Ten hours skips lunch, electrical close and next-day closure');
 UPDATE public.workshop_settings SET value='[]'::jsonb WHERE key IN('break_windows','closures');step:=step+1;
 -- Existing live and stopped work retain physical timestamps; fixed queued work remains fixed.
 FOREACH variant IN ARRAY ARRAY['started','stoppage','queued'] LOOP
  PERFORM set_config('qa.bus_clock_case','fixed-'||variant,true);
  bay:=pg_temp.bc_bay(1);
  fixed:=pg_temp.bc_booking('fixed-'||variant,'BUS_4X4',bay,pg_temp.bc_at(day+step*7,time '06:00'),120,'current',variant::public.workshop_booking_status);
  SELECT to_jsonb(x) INTO fixed_saved FROM public.workshop_bookings x WHERE id=fixed;
  b:=pg_temp.bc_booking('after-'||variant,'BUS_4X4',bay,pg_temp.bc_at(day+step*7,time '08:00'),60,'current');
  result:=pg_temp.bc_tick('Fixed '||variant,pg_temp.bc_at(day+step*7,time '09:01'));
  PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=fixed_saved FROM public.workshop_bookings x WHERE id=fixed),'Fixed '||variant||' original schedule and actual evidence stay unchanged');
  PERFORM pg_temp.ou_assert((SELECT scheduled_start_at>=pg_temp.bc_at(day+step*7,time '09:01') FROM public.workshop_bookings WHERE id=b),'Successor moves after fixed '||variant);step:=step+1;
 END LOOP;
 -- Admin reservations and unrelated resource groups are preserved exactly.
 PERFORM set_config('qa.bus_clock_case','admin-unrelated',true);
 bay:=pg_temp.bc_bay(1);
 b:=pg_temp.bc_booking('admin-target','BUS_4X4',bay,pg_temp.bc_at(day+step*7,time '07:00'),60,'current');
 other:=pg_temp.bc_booking('unrelated-future','FITTING',pg_temp.ou_bay('unrelated-future','FITTING'),pg_temp.bc_at(day+step*7+2,time '07:00'),60,'none');
 INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
 SELECT stage_id,bay,'admin','Rollback fixed maintenance',pg_temp.bc_at(day+step*7,time '09:00'),pg_temp.bc_at(day+step*7,time '10:00'),60,auth.uid(),auth.uid()
 FROM public.workshop_bookings WHERE id=b RETURNING id,to_jsonb(workshop_admin_blocks) INTO hold,block_saved;
 result:=pg_temp.bc_tick('Admin block and unrelated future',pg_temp.bc_at(day+step*7,time '09:01'));
 PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=pg_temp.bc_at(day+step*7,time '10:00') FROM public.workshop_bookings WHERE id=b),'Overdue planned job skips maintenance');
 PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=block_saved FROM public.workshop_admin_blocks x WHERE id=hold),'Admin reservation unchanged byte-for-byte');step:=step+1;
 -- One vehicle across stages carries the elapsed one-hour handover forward.
 PERFORM set_config('qa.bus_clock_case','vehicle-handover',true);
 bay:=pg_temp.bc_bay(1);next_bay:=pg_temp.ou_bay('handover-tint','TINT');
 b:=pg_temp.bc_booking('handover-first','BUS_4X4',bay,pg_temp.bc_at(day+step*7,time '07:00'),60,'current');
 SELECT vehicle_id INTO v FROM public.workshop_bookings WHERE id=b;
 PERFORM pg_temp.ou_operation(v,'TINT',1,2);
 other:=pg_temp.ou_booking('handover-next',v,'TINT',next_bay,pg_temp.bc_at(day+step*7,time '09:00'));
 result:=pg_temp.bc_tick('Cross-station same-vehicle handover',pg_temp.bc_at(day+step*7,time '09:01'));
 PERFORM pg_temp.ou_assert((SELECT n.scheduled_start_at>=f.scheduled_end_at+interval '1 hour' FROM public.workshop_bookings f,public.workshop_bookings n WHERE f.id=b AND n.id=other),'Cross-stage same vehicle retains one-hour separation');
END $valid_cases$;

-- Existing incompatible/unknown Bay3 work is never silently accepted or changed.
-- An independent eligible component must still advance in that same transaction.
DO $blocked_cases$
DECLARE day date; kind text; b uuid; free uuid; linked uuid; preview jsonb; result jsonb; saved jsonb; linked_saved jsonb; assignment_saved jsonb; step integer:=14;
BEGIN
 SELECT base_day INTO day FROM bc_context;
 FOREACH kind IN ARRAY ARRAY['Toyota Coaster','Unknown vehicle','HiAce Coaster conflict'] LOOP
  PERFORM set_config('qa.bus_clock_case','denied-'||step,true);
  linked:=pg_temp.bc_booking('linked-valid-'||step,'BUS_4X4',pg_temp.bc_bay(3),pg_temp.bc_at(day+step*7,time '07:00'),60,'current');
  b:=pg_temp.bc_booking('denied-'||step,'BUS_4X4',pg_temp.bc_bay(3),pg_temp.bc_at(day+step*7,time '13:00'),60,'legacy','planned',kind);
  SELECT to_jsonb(x) INTO linked_saved FROM public.workshop_bookings x WHERE id=linked;
  SELECT jsonb_agg(to_jsonb(a) ORDER BY id) INTO assignment_saved FROM public.workshop_booking_assignments a WHERE booking_id IN(linked,b);
  free:=pg_temp.bc_booking('independent-'||step,'FITTING',pg_temp.ou_bay('independent-'||step,'FITTING'),pg_temp.bc_at(day+step*7,time '07:00'),60,'none');
  SELECT to_jsonb(x) INTO saved FROM public.workshop_bookings x WHERE id=b;
  preview:=public.workshop_clock_tick(false,pg_temp.bc_at(day+step*7,time '09:01'));
  result:=public.workshop_clock_tick(true,pg_temp.bc_at(day+step*7,time '09:01'));
  PERFORM pg_temp.ou_assert(result->>'ok'='false' AND EXISTS(SELECT 1 FROM jsonb_array_elements(result->'issues') x WHERE x->>'detail' LIKE '%bus_bay_vehicle_incompatible%'),
   kind||' is rejected by physical bay compatibility',result-'plans');
  PERFORM pg_temp.ou_assert(preview->'issues'=result->'issues',kind||' fails consistently in preview and apply');
  PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=saved FROM public.workshop_bookings x WHERE id=b),kind||' failed component has no partial booking change');
  PERFORM pg_temp.ou_assert((SELECT to_jsonb(x)=linked_saved FROM public.workshop_bookings x WHERE id=linked),kind||' blocks the linked component atomically including earlier valid HiAce');
  PERFORM pg_temp.ou_assert(assignment_saved IS NOT DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM public.workshop_booking_assignments a WHERE booking_id IN(linked,b))
   AND NOT EXISTS(SELECT 1 FROM public.workshop_clock_history WHERE booking_id IN(linked,b)),kind||' failed component changes no assignment or history');
  PERFORM pg_temp.ou_assert((SELECT scheduled_start_at=pg_temp.bc_at(day+step*7,time '09:01') AND version=2 FROM public.workshop_bookings WHERE id=free),kind||' leaves independent valid component able to advance');
  step:=step+1;
 END LOOP;
END $blocked_cases$;

SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_bookings o LEFT JOIN public.workshop_bookings b ON b.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(b)),'All original customer bookings unchanged, including dates and versions');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM ou_original_vehicles o LEFT JOIN public.vehicles v ON v.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(v)),'All original vehicle identities and workflow states unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bc_original_assignments o LEFT JOIN public.workshop_booking_assignments a ON a.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'All original technician assignments unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bc_original_blocks o LEFT JOIN public.workshop_admin_blocks a ON a.id=o.id WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'All original admin reservations unchanged');
SELECT pg_temp.ou_assert(NOT EXISTS(SELECT 1 FROM bc_original_operations o LEFT JOIN public.pdc_pilbara_service_operations a ON a.operation_id=o.operation_id WHERE o.row_data IS DISTINCT FROM to_jsonb(a)),'All original imported operation hours and evidence unchanged');
SELECT jsonb_build_object('count',count(*),'checks',jsonb_agg(jsonb_build_object('name',name,'status',status) ORDER BY name)) result FROM ou_results;
ROLLBACK;
