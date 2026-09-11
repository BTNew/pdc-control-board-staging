-- STAGING ONLY. Random vehicle fixtures and every booking are rolled back.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
DO $test$
DECLARE
 actor uuid; actor_email text; fixture uuid; st text; r record; result jsonb;
 main_vehicle uuid:=gen_random_uuid(); it_vehicle uuid:=gen_random_uuid();
 missing_hours_vehicle uuid:=gen_random_uuid(); missing_eta_vehicle uuid:=gen_random_uuid();
 sublet_vehicle uuid:=gen_random_uuid(); blocked_vehicle uuid:=gen_random_uuid();
 mid_save_vehicle uuid:=gen_random_uuid(); no_bay_vehicle uuid:=gen_random_uuid();
 fixtures uuid[]; version_number integer; before_bookings jsonb; booked_once jsonb;
 before_location jsonb; before_work jsonb; target_start timestamptz; target_end timestamptz;
 block_until timestamptz; blocker_booking uuid; blocker_stage uuid; blocker_bay uuid;
 booking_total integer; found_slot boolean; scan_day integer;
 rpc_started timestamptz; rpc_seconds numeric; before_bays jsonb;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'wrong_environment'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT actor_role.auth_user_id,actor_role.email INTO STRICT actor,actor_email
 FROM public.pdc_user_roles actor_role JOIN auth.users u ON u.id=actor_role.auth_user_id
 WHERE actor_role.active AND actor_role.account_status='approved' AND actor_role.role::text IN('administrator','operator')
  AND actor_role.email NOT ILIKE '%hermes%' ORDER BY actor_role.role LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);
 PERFORM public.workshop_require_planner_operator();
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') INTO before_bookings FROM public.workshop_bookings b;
 fixtures:=ARRAY[main_vehicle,it_vehicle,missing_hours_vehicle,missing_eta_vehicle,sublet_vehicle,blocked_vehicle,mid_save_vehicle,no_bay_vehicle];
 FOREACH fixture IN ARRAY fixtures LOOP
  INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,current_location,visible_on_board,created_by,updated_by)
  VALUES(fixture,fixture,'BOOKALL-'||left(fixture::text,8),CASE WHEN fixture=missing_hours_vehicle THEN 'YH' ELSE 'PMB' END,true,actor,actor);
 END LOOP;
 -- Positive canonical manual estimates, including a genuine multi-day job.
 FOR r IN SELECT * FROM (VALUES
  (main_vehicle,'HOIST',40.10::numeric),(main_vehicle,'FITTING',2.00::numeric),(main_vehicle,'ELECTRICAL',0.50::numeric),
  (main_vehicle,'SUBLET',NULL::numeric),(it_vehicle,'HOIST',0.50::numeric),
  (missing_hours_vehicle,'HOIST',1.00::numeric),(missing_hours_vehicle,'ELECTRICAL',NULL::numeric),
  (missing_eta_vehicle,'HOIST',1.00::numeric),(sublet_vehicle,'SUBLET',NULL::numeric),
  (blocked_vehicle,'HOIST',1.00::numeric),
  (mid_save_vehicle,'HOIST',1.00::numeric),(mid_save_vehicle,'FITTING',1.00::numeric),
  (no_bay_vehicle,'HOIST',1.00::numeric),(no_bay_vehicle,'FITTING',1.00::numeric)
 ) x(vehicle_id,stage_code,hours) LOOP
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
  VALUES(r.vehicle_id,'manual:'||gen_random_uuid()::text,'manual',r.stage_code,'Rollback booking fixture '||r.stage_code,r.hours,actor,actor);
 END LOOP;
 -- Populate requirements after all adjustment reconciliation has run.
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed)
 SELECT a.vehicle_id,s.work_key,true,false FROM public.vehicle_workshop_line_adjustments a
 JOIN public.workshop_stages s ON s.code=a.stage_code WHERE a.vehicle_id=ANY(fixtures)
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,completed=false;
 SELECT jsonb_build_object('location',current_location,'stage',pmb_stage,'bay_stage',pmb_bay_stage,'bay',pmb_bay_number,'lifecycle',lifecycle_state)
 INTO before_location FROM public.vehicles WHERE id=main_vehicle;
 SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) INTO before_work FROM public.vehicle_work_items w WHERE vehicle_id=main_vehicle;
 SELECT version INTO version_number FROM public.vehicles WHERE id=main_vehicle;
 result:=public.book_all_vehicle_stations(main_vehicle,version_number+1);
 IF result->>'ok' IS DISTINCT FROM 'false' OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=main_vehicle) THEN
  RAISE EXCEPTION 'stale_version_not_rejected: %',result;
 END IF;
 rpc_started:=clock_timestamp();
 result:=public.book_all_vehicle_stations(main_vehicle,version_number);
 rpc_seconds:=extract(epoch FROM clock_timestamp()-rpc_started);
 PERFORM set_config('pdc.test_book_all_seconds',rpc_seconds::text,true);
 IF rpc_seconds>=30 THEN RAISE EXCEPTION 'three_station_rpc_exceeded_30_seconds: %',rpc_seconds; END IF;
 IF result->>'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(result->'bookings')<>3 THEN RAISE EXCEPTION 'three_stations_not_booked: %',result; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.vehicle_id=main_vehicle AND s.code IN('SUBLET','PIT_INSPECTION')) THEN RAISE EXCEPTION 'excluded_station_booked'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=main_vehicle
  AND (public.workshop_operational_minutes_between(b.scheduled_start_at,b.scheduled_end_at)<>b.default_duration_minutes
   OR b.default_duration_minutes<>public.workshop_vehicle_stage_estimated_duration_minutes(b.vehicle_id,b.stage_id))) THEN RAISE EXCEPTION 'duration_or_calendar_mismatch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=main_vehicle AND b.default_duration_minutes=2406
  AND (b.scheduled_end_at AT TIME ZONE 'Australia/Perth')::date>(b.scheduled_start_at AT TIME ZONE 'Australia/Perth')::date) THEN RAISE EXCEPTION 'long_booking_not_continued'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings a JOIN public.workshop_bookings b ON a.vehicle_id=b.vehicle_id AND (b.scheduled_start_at,b.id)>(a.scheduled_start_at,a.id)
  WHERE a.vehicle_id=main_vehicle AND a.scheduled_end_at+interval '5 hours'>b.scheduled_start_at) THEN RAISE EXCEPTION 'five_hour_buffer_missing'; END IF;
 IF before_location IS DISTINCT FROM (SELECT jsonb_build_object('location',current_location,'stage',pmb_stage,'bay_stage',pmb_bay_stage,'bay',pmb_bay_number,'lifecycle',lifecycle_state) FROM public.vehicles WHERE id=main_vehicle)
  OR before_work IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE vehicle_id=main_vehicle) THEN RAISE EXCEPTION 'booking_changed_location_or_required_work'; END IF;
 SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) INTO booked_once FROM public.workshop_bookings b WHERE b.vehicle_id=main_vehicle;
 SELECT version INTO version_number FROM public.vehicles WHERE id=main_vehicle;
 result:=public.book_all_vehicle_stations(main_vehicle,version_number);
 IF result->>'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(result->'bookings')<>0 OR jsonb_array_length(result->'skipped')<>3
  OR booked_once IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bookings b WHERE b.vehicle_id=main_vehicle)
 THEN RAISE EXCEPTION 'repeat_created_duplicate_or_moved_existing: %',result; END IF;
 -- Add one newly required station; the three existing bookings must stay fixed.
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
 VALUES(main_vehicle,'manual:'||gen_random_uuid()::text,'manual','TINT','Rollback later requirement',0.50,actor,actor);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed)
 SELECT main_vehicle,s.work_key,true,false FROM public.workshop_stages s WHERE s.code IN('HOIST','FITTING','ELECTRICAL','SUBLET','TINT')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,completed=false;
 SELECT version INTO version_number FROM public.vehicles WHERE id=main_vehicle;
 result:=public.book_all_vehicle_stations(main_vehicle,version_number);
 IF result->>'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(result->'bookings')<>1 OR jsonb_array_length(result->'skipped')<>3 THEN RAISE EXCEPTION 'existing_bookings_not_skipped: %',result; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(booked_once) old_row WHERE old_row IS DISTINCT FROM (SELECT to_jsonb(b) FROM public.workshop_bookings b WHERE b.id=(old_row->>'id')::uuid)) THEN RAISE EXCEPTION 'old_booking_changed'; END IF;
 -- Missing hours must fail before any of the otherwise valid stations save.
 SELECT version INTO version_number FROM public.vehicles WHERE id=missing_hours_vehicle;
 result:=public.book_all_vehicle_stations(missing_hours_vehicle,version_number);
 IF result->>'ok' IS DISTINCT FROM 'false' OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=missing_hours_vehicle) THEN RAISE EXCEPTION 'missing_hours_not_atomic: %',result; END IF;
 -- An IT vehicle without ETA is unavailable; Sublet alone creates no bay booking.
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=NULL WHERE id=missing_eta_vehicle;
 SELECT version INTO version_number FROM public.vehicles WHERE id=missing_eta_vehicle;
 result:=public.book_all_vehicle_stations(missing_eta_vehicle,version_number);
 IF result->>'ok' IS DISTINCT FROM 'false' OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=missing_eta_vehicle) THEN RAISE EXCEPTION 'missing_eta_not_rejected: %',result; END IF;
 SELECT version INTO version_number FROM public.vehicles WHERE id=sublet_vehicle;
 result:=public.book_all_vehicle_stations(sublet_vehicle,version_number);
 IF result->>'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(result->'bookings')<>0 OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=sublet_vehicle) THEN RAISE EXCEPTION 'sublet_only_created_booking: %',result; END IF;
 -- Use an operational morning after a future ETA+7, with every Hoist bay blocked.
 target_start:=public.workshop_admin_next_operational_minute((((clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+21)::timestamp AT TIME ZONE 'Australia/Perth'));
 target_end:=public.workshop_add_operational_minutes(target_start,60);
 UPDATE public.vehicles SET current_location='IT',eta_to_kewdale=(target_start AT TIME ZONE 'Australia/Perth')::date-7 WHERE id IN(it_vehicle,blocked_vehicle);
 SELECT s.id INTO STRICT blocker_stage FROM public.workshop_stages s WHERE s.code='HOIST';
 SELECT b.id INTO STRICT blocker_bay FROM public.workshop_bays b WHERE b.stage_id=blocker_stage AND b.is_active ORDER BY b.bay_number LIMIT 1;
 -- One actual competing vehicle occupies the first bay. This is a future, random fixture.
 result:=public.schedule_vehicle_work(blocked_vehicle,(SELECT version FROM public.vehicles WHERE id=blocked_vehicle),'HOIST',(SELECT bay_number FROM public.workshop_bays WHERE id=blocker_bay),target_start,60,NULL,NULL,'{"source":"book_all_rollback_test"}');
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'blocker_booking_setup_failed: %',result; END IF;
 SELECT id INTO STRICT blocker_booking FROM public.workshop_bookings WHERE vehicle_id=blocked_vehicle;
 -- Other bays have admin time, so a free alternate bay cannot hide either overlap bug.
 FOR r IN SELECT * FROM public.workshop_bays WHERE stage_id=blocker_stage AND is_active AND id<>blocker_bay LOOP
  INSERT INTO public.workshop_admin_blocks(stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
  VALUES(blocker_stage,r.id,'admin','Rollback bulk scheduling collision',target_start,target_end,60,actor,actor);
 END LOOP;
 SELECT version INTO version_number FROM public.vehicles WHERE id=it_vehicle;
 result:=public.book_all_vehicle_stations(it_vehicle,version_number);
 IF result->>'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(result->'bookings')<>1 THEN RAISE EXCEPTION 'it_booking_failed: %',result; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=it_vehicle AND scheduled_start_at<target_end) THEN RAISE EXCEPTION 'eta_or_bay_or_admin_overlap'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings a JOIN public.workshop_admin_blocks b ON b.bay_id=a.bay_id
  WHERE a.vehicle_id=it_vehicle AND b.deleted_at IS NULL AND tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)')&&tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')) THEN RAISE EXCEPTION 'admin_block_overlap'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings a JOIN public.workshop_bookings b ON b.bay_id=a.bay_id AND b.id<>a.id
  WHERE a.vehicle_id=it_vehicle AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND tstzrange(a.scheduled_start_at,a.scheduled_end_at,'[)')&&tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')) THEN RAISE EXCEPTION 'bay_booking_overlap'; END IF;
 IF (SELECT scheduled_start_at FROM public.workshop_bookings WHERE id=blocker_booking)<>target_start THEN RAISE EXCEPTION 'competing_booking_was_moved'; END IF;
 -- An existing unallocated booking must not be reported as safely booked.
 INSERT INTO public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by)
 VALUES(no_bay_vehicle,blocker_stage,NULL,'queued',target_start,target_end,60,actor,actor);
 SELECT version INTO version_number FROM public.vehicles WHERE id=no_bay_vehicle;
 result:=public.book_all_vehicle_stations(no_bay_vehicle,version_number);
 IF result->>'ok' IS DISTINCT FROM 'false' OR result->>'error' IS DISTINCT FROM 'existing_booking_without_bay'
  OR (SELECT count(*) FROM public.workshop_bookings WHERE vehicle_id=no_bay_vehicle)<>1
  OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=no_bay_vehicle AND bay_id IS NOT NULL)
 THEN RAISE EXCEPTION 'unallocated_booking_not_rejected_atomically: %',result; END IF;
 -- Deliberately make the later station's target invalid after preflight can pass.
 -- Its active bays allow preflight; nullable bay_number is legal in the schema,
 -- but the actual booking write rejects the missing bay number. The RPC has
 -- already attempted the preceding Hoist stage, which must also roll back.
 SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) INTO before_bays FROM public.workshop_bays b WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='FITTING');
 BEGIN
  UPDATE public.workshop_bays SET bay_number=NULL WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='FITTING') AND is_active;
  SELECT version INTO version_number FROM public.vehicles WHERE id=mid_save_vehicle;
  result:=public.book_all_vehicle_stations(mid_save_vehicle,version_number);
  IF result->>'ok' IS DISTINCT FROM 'false' OR result->>'message' NOT ILIKE '%bay%'
   OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=mid_save_vehicle)
  THEN RAISE EXCEPTION 'mid_save_failure_not_rolled_back: %',result; END IF;
  RAISE EXCEPTION 'Restore temporary bay configuration after verified rollback' USING ERRCODE='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 IF before_bays IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bays b WHERE stage_id=(SELECT id FROM public.workshop_stages WHERE code='FITTING')) THEN RAISE EXCEPTION 'temporary_bay_configuration_not_restored'; END IF;
 IF before_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') FROM public.workshop_bookings b WHERE NOT(b.vehicle_id=ANY(fixtures))) THEN RAISE EXCEPTION 'preexisting_bookings_changed'; END IF;
END $test$;
SELECT 'PASS: three stations, full multi-day duration, 5-hour gaps, existing/repeated booking preservation, IT ETA+7, bay/admin collisions, missing-hours and mid-save atomicity, unallocated booking guard, stale version, missing ETA and Sublet exclusion; all fixtures roll back' AS result,
 current_setting('pdc.test_book_all_seconds')::numeric AS three_station_rpc_seconds;
ROLLBACK;

