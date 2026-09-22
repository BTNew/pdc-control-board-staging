-- Explicit rollback only. No real booking/timer history is changed.
BEGIN;
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
DO $test$
DECLARE actor uuid; email text; v uuid:=gen_random_uuid(); tech uuid:=gen_random_uuid(); source uuid; sid uuid;
 bay4 uuid; bay8 uuid; b uuid; vv integer; r jsonb; a jsonb; z jsonb; starts timestamptz; origin bigint;
 untouched text; real_id uuid; count_before bigint; dept text;
BEGIN
 SELECT auth_user_id,p.email INTO STRICT actor,email FROM public.pdc_user_roles p
 WHERE active AND account_status='approved' AND role='administrator' AND p.email!~* '(monitor|auditor|bot|service|import|hermes)' ORDER BY created_at LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',email,'role','authenticated')::text,true);
 SELECT id INTO sid FROM public.workshop_stages WHERE code='BUS_4X4';
 SELECT id INTO bay4 FROM public.workshop_bays WHERE stage_id=sid AND bay_number=4;
 SELECT id INTO bay8 FROM public.workshop_bays WHERE stage_id=sid AND bay_number=8;
 SELECT raw_evidence_id INTO source FROM public.pdc_pilbara_service_operations WHERE department='138' LIMIT 1;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]')::text) INTO untouched FROM public.workshop_bookings x;
 INSERT INTO public.workshop_technicians(id,code,name,role_type,active,created_by,updated_by)
 VALUES(tech,'TIMER-'||tech,'Bus timer rollback technician','technician',true,actor,actor);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,current_location,source_system,source_record_id,source_payload,visible_on_board,created_by,updated_by,model)
 VALUES(v,v::text,'TIMER-'||v,'Bus timer rollback fixture','PMB','department138_timer_rollback',v::text,jsonb_build_object('fixture',v),true,actor,actor,'Toyota Coaster');
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind) VALUES(v,'existing','department138_timer_rollback');
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(gen_random_uuid(),'pilbara_service_open_jobcards_v1','TIMER-'||v,'TIMER-'||v,1,1,v,'Mechanical fitment',2,2,'source_explicit','review','Review',
 md5(v::text)||md5(v::text),source,'138','BUS_4X4');
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v]);
 PERFORM public.save_pdc_bus_workflow(v,0,gen_random_uuid(),'{"parts_readiness":{"mechanical":{"ready":true,"note":"Rollback physical check"}}}');
 starts:=date_trunc('day',now() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth'+interval '350 days 6 hours';
 WHILE NOT pdc_bus_private.minute_available(starts,bay4) LOOP starts:=starts+interval '1 day'; END LOOP;
 r:=public.workshop_create_booking(v,'BUS_4X4',4,starts,120,tech,'{"source":"dept138_timer_rollback"}');
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Timer fixture create failed %',r; END IF;
 SELECT id INTO b FROM public.workshop_bookings WHERE vehicle_id=v;
 r:=pdc_fitter_private.timing(b,clock_timestamp());
 IF r#>>'{timer,elapsed_seconds}'<>'0' OR r#>>'{timer,history_complete}'<>'true' OR r#>>'{timer,running}'<>'false'
 THEN RAISE EXCEPTION 'Not-started zero is not trustworthy %',r; END IF;
 UPDATE public.workshop_bookings SET status='started',actual_start_at='2026-09-21 06:00+08',version=version+1 WHERE id=b;
 SELECT id INTO STRICT origin FROM pdc_bus_private.activity_events WHERE booking_id=b;
 IF NOT (SELECT is_origin FROM pdc_bus_private.activity_events WHERE id=origin) THEN RAISE EXCEPTION 'Start event not captured'; END IF;
 -- Synthetic past evidence tests deterministic hours; fixture-only rows roll back.
 INSERT INTO pdc_bus_private.activity_events(booking_id,effective_at,from_status,to_status,bay_id,is_origin,recorded_by)
 VALUES(b,'2026-09-21 09:00+08','started','queued',NULL,false,actor),
 (b,'2026-09-22 06:00+08','queued','started',bay8,false,actor),
 (b,'2026-09-22 08:00+08','started','stoppage',bay8,false,actor),
 (b,'2026-09-22 09:00+08','stoppage','started',bay4,false,actor);
 r:=pdc_fitter_private.timing(b,'2026-09-22 10:00+08');
 IF r#>>'{timer,elapsed_seconds}'<>'21600' OR r#>>'{timer,history_complete}'<>'true'
 THEN RAISE EXCEPTION 'Work/pause/queue/bay timeline incorrect %',r; END IF;
 IF pdc_bus_private.operational_seconds('2026-09-22 12:00+08','2026-09-22 16:30+08',bay8)<>7200
 OR pdc_bus_private.operational_seconds('2026-09-22 12:00+08','2026-09-22 16:30+08',bay4)<>10800
 OR pdc_bus_private.operational_seconds('2026-09-28 06:00+08','2026-09-28 16:30+08',bay4)<>0
 THEN RAISE EXCEPTION 'Timer counted after shift or public holiday'; END IF;
 -- Mixed and unknown active BUS lines keep legacy timing; subtransactions discard append-only fixture evidence.
 FOREACH dept IN ARRAY ARRAY['139',NULL::text] LOOP BEGIN
 INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
 operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
 VALUES(gen_random_uuid(),'pilbara_service_open_jobcards_v1','TIMER-'||v,'TIMER-'||v,2,2,v,'Mixed scope fixture',1,1,'source_explicit','review','Review',
 md5(tech::text)||md5(tech::text),source,dept,'BUS_4X4');
 IF pdc_bus_private.pure_department138_bus(v) THEN RAISE EXCEPTION 'Mixed BUS scope accepted'; END IF;
 IF pdc_fitter_private.timing(b,'2026-09-22 10:00+08') IS DISTINCT FROM pdc_fitter_private.timing_pre_dept138_20260923(b,'2026-09-22 10:00+08')
 THEN RAISE EXCEPTION 'Mixed department timer changed'; END IF;
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=b;
 IF public.set_pdc_bus_booking_team(b,vv,tech,'{}'::uuid[],gen_random_uuid(),'Mixed scope')->>'error'<>'active_department138_booking_required'
 THEN RAISE EXCEPTION 'Mixed department crew accepted'; END IF;
 RAISE EXCEPTION 'Rollback temporary mixed source line' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END; END LOOP;
 -- Directly rewriting a running start boundary cannot silently fabricate trusted elapsed time.
 SELECT max(id) INTO count_before FROM pdc_bus_private.activity_events WHERE booking_id=b;
 UPDATE public.workshop_bookings SET actual_start_at='2026-09-21 07:00+08',version=version+1 WHERE id=b;
 IF pdc_fitter_private.timing(b,clock_timestamp())#>>'{timer,history_complete}'<>'false' THEN RAISE EXCEPTION 'Edited running start stayed trustworthy'; END IF;
 UPDATE public.workshop_bookings SET actual_start_at='2026-09-21 06:00+08',version=version+1 WHERE id=b;
 -- Restore only synthetic evidence to exercise the next independent transition test.
 DELETE FROM pdc_bus_private.activity_events WHERE booking_id=b AND id>count_before;
 -- Real return-to-queue RPC emits an event and elapsed remains fixed while waiting.
 SELECT version INTO vv FROM public.workshop_bookings WHERE id=b;
 r:=public.return_work_to_queue(b,vv,NULL,'{"source":"dept138_timer_rollback"}');
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Real return-to-queue failed %',r; END IF;
 IF (SELECT to_status FROM pdc_bus_private.activity_events WHERE booking_id=b ORDER BY id DESC LIMIT 1)<>'queued'
 THEN RAISE EXCEPTION 'Queue transition missing'; END IF;
 a:=pdc_fitter_private.timing(b,clock_timestamp()+interval '1 second');
 z:=pdc_fitter_private.timing(b,clock_timestamp()+interval '3 days');
 IF a#>>'{timer,history_complete}'<>'true' OR a#>'{timer,elapsed_seconds}' IS DISTINCT FROM z#>'{timer,elapsed_seconds}'
 OR z#>>'{timer,running}'<>'false' THEN RAISE EXCEPTION 'Queued time kept growing % / %',a,z; END IF;
 -- A clock/estimate refresh has no status transition and cannot add an event or restart work.
 SELECT count(*) INTO count_before FROM pdc_bus_private.activity_events WHERE booking_id=b;
 UPDATE public.workshop_bookings SET version=version+1 WHERE id=b;
 IF count_before<>(SELECT count(*) FROM pdc_bus_private.activity_events WHERE booking_id=b) THEN RAISE EXCEPTION 'Refresh added activity'; END IF;
 -- Soft deletion and restoration leave explicit boundaries even if status/bay are unchanged.
 UPDATE public.workshop_bookings SET deleted_at=clock_timestamp(),deleted_reason='Rollback timer boundary',version=version+1 WHERE id=b;
 IF (SELECT to_status FROM pdc_bus_private.activity_events WHERE booking_id=b ORDER BY id DESC LIMIT 1)<>'deleted'
 THEN RAISE EXCEPTION 'Soft deletion not captured'; END IF;
 UPDATE public.workshop_bookings SET deleted_at=NULL,deleted_reason=NULL,version=version+1 WHERE id=b;
 IF (SELECT from_status FROM pdc_bus_private.activity_events WHERE booking_id=b ORDER BY id DESC LIMIT 1)<>'deleted'
 THEN RAISE EXCEPTION 'Restoration boundary incorrect'; END IF;
 IF pdc_fitter_private.timing(b,clock_timestamp())#>>'{timer,history_complete}'<>'true'
 THEN RAISE EXCEPTION 'Queued restore reused an obsolete timestamp'; END IF;
 -- Missing origin must stay explicitly unknown, not fabricated zero or global elapsed.
 DELETE FROM pdc_bus_private.activity_events WHERE id=origin;
 r:=pdc_fitter_private.timing(b,clock_timestamp());
 IF r#>>'{timer,history_complete}'<>'false' OR r#>>'{timer,elapsed_seconds}' IS NOT NULL OR r#>>'{timer,review_required}'<>'true'
 THEN RAISE EXCEPTION 'Incomplete history invented hours %',r; END IF;
 IF has_table_privilege('authenticated','pdc_bus_private.activity_events','INSERT')
 OR has_function_privilege('authenticated','pdc_bus_private.activity_timer(uuid,timestamptz)','EXECUTE')
 THEN RAISE EXCEPTION 'Private activity evidence exposed'; END IF;
 FOR real_id IN SELECT id FROM public.workshop_bookings WHERE vehicle_id<>v AND NOT pdc_bus_private.active_vehicle(vehicle_id) LOOP
  IF pdc_fitter_private.timing(real_id,transaction_timestamp()) IS DISTINCT FROM pdc_fitter_private.timing_pre_dept138_20260923(real_id,transaction_timestamp())
  THEN RAISE EXCEPTION 'Other department timer changed'; END IF;
 END LOOP;
 IF untouched IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id),'[]')::text) FROM public.workshop_bookings x WHERE vehicle_id<>v)
 THEN RAISE EXCEPTION 'Existing bookings changed'; END IF;
END $test$;
SELECT 'PASS: shared Dept138 activity, queue/stoppage exclusion, bay shifts/holidays, actual return-to-queue capture, no fabricated legacy hours, private evidence and other departments preserved' result;
ROLLBACK;
