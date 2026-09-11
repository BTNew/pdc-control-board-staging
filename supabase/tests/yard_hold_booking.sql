-- STAGING ONLY. Synthetic vehicles/bookings and every mutation roll back.
-- Yard Hold is an arrived location; Navision details and ETA are not prerequisites.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
DO $test$
DECLARE
 actor uuid; actor_email text; fixture uuid; result jsonb; version_number integer;
 yard_bulk uuid:=gen_random_uuid(); yh_bulk uuid:=gen_random_uuid();
 yard_single uuid:=gen_random_uuid(); missing_eta uuid:=gen_random_uuid();
 eta_boundary uuid:=gen_random_uuid(); qc_override uuid:=gen_random_uuid();
 fixtures uuid[]; before_bookings jsonb; before_source jsonb;
 target_stage_id uuid; target_bay_id uuid; target_bay_number integer; target_start timestamptz;
 target_end timestamptz; previous_start timestamptz; previous_end timestamptz;
 scan_day integer; fixture_index integer:=0; found_slot boolean;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'wrong_environment'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT r.auth_user_id,r.email INTO STRICT actor,actor_email
 FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND r.role::text IN('administrator','operator')
  AND r.email NOT ILIKE '%hermes%' ORDER BY r.role LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);
 PERFORM public.workshop_require_planner_operator();
 SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') INTO before_bookings FROM public.workshop_bookings b;
 fixtures:=ARRAY[yard_bulk,yh_bulk,yard_single,missing_eta,eta_boundary,qc_override];
 FOREACH fixture IN ARRAY fixtures LOOP
  INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,current_location,
    eta_to_kewdale,vehicle_description,model,source_system,source_record_id,source_payload,location_override,
    visible_on_board,created_by,updated_by)
  VALUES(fixture,fixture,'YH-BOOK-'||left(fixture::text,8),'BUSSELTON TOYOTA',
    CASE WHEN fixture=yh_bulk THEN 'YH' WHEN fixture IN(missing_eta,eta_boundary) THEN 'IT'
      WHEN fixture=qc_override THEN 'QC' ELSE 'Yard Hold' END,
    NULL,NULL,NULL,'yard_hold_booking_rollback_fixture',fixture::text,jsonb_build_object('fixture',fixture),
    CASE WHEN fixture=qc_override THEN 'YH' ELSE NULL END,true,actor,actor);
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
  VALUES(fixture,'manual:'||gen_random_uuid()::text,'manual','HOIST','Rollback Yard Hold booking fixture',1.00,actor,actor);
 END LOOP;
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed)
 SELECT a.vehicle_id,s.work_key,true,false FROM public.vehicle_workshop_line_adjustments a
 JOIN public.workshop_stages s ON s.code=a.stage_code WHERE a.vehicle_id=ANY(fixtures)
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,completed=false;
 SELECT jsonb_agg(jsonb_build_object('id',id,'location',current_location,'eta',eta_to_kewdale,
   'description',vehicle_description,'model',model,'source_system',source_system,'source_payload',source_payload)
   ORDER BY id) INTO before_source FROM public.vehicles WHERE id IN(yard_bulk,yh_bulk,yard_single);
 IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE canonical_vehicle_id=ANY(fixtures)) THEN RAISE EXCEPTION 'fixture_unexpectedly_has_navision_record'; END IF;
 IF public.workshop_location_code('  yard hold  ') IS DISTINCT FROM 'YH'
  OR public.workshop_location_code('YH') IS DISTINCT FROM 'YH'
  OR public.workshop_location_code('QC') IS DISTINCT FROM 'QC'
  OR public.workshop_location_code('Yard Hold extra')='YH'
 THEN RAISE EXCEPTION 'location_normalization_not_exact'; END IF;
 FOREACH fixture IN ARRAY ARRAY[yard_bulk,yh_bulk,yard_single] LOOP
  IF NOT EXISTS(SELECT 1 FROM public.workshop_station_eligibility('HOIST') e WHERE e.vehicle_id=fixture AND e.schedule_enabled) THEN
   RAISE EXCEPTION 'yard_hold_without_eta_not_eligible: %',fixture;
  END IF;
 END LOOP;
 FOREACH fixture IN ARRAY ARRAY[yard_bulk,yh_bulk] LOOP
  SELECT version INTO version_number FROM public.vehicles WHERE id=fixture;
  result:=public.book_all_vehicle_stations(fixture,version_number);
  IF result->>'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(result->'bookings')<>1
   OR (SELECT count(*) FROM public.workshop_bookings WHERE vehicle_id=fixture)<>1
  THEN RAISE EXCEPTION 'yard_hold_bulk_booking_failed: %',result; END IF;
 END LOOP;
 -- Closed or not-yet-arrived vehicles stay blocked despite a display override.
 FOREACH fixture IN ARRAY ARRAY[missing_eta,qc_override] LOOP
  IF EXISTS(SELECT 1 FROM public.workshop_station_eligibility('HOIST') e WHERE e.vehicle_id=fixture AND e.schedule_enabled) THEN
   RAISE EXCEPTION 'ineligible_location_or_missing_eta_enabled: %',fixture;
  END IF;
  SELECT version INTO version_number FROM public.vehicles WHERE id=fixture;
  result:=public.book_all_vehicle_stations(fixture,version_number);
  IF result->>'ok' IS DISTINCT FROM 'false' OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=fixture) THEN
   RAISE EXCEPTION 'ineligible_bulk_booking_not_rejected: %',result;
  END IF;
 END LOOP;
 SELECT s.id INTO STRICT target_stage_id FROM public.workshop_stages s WHERE s.code='HOIST';
 SELECT b.id,b.bay_number INTO STRICT target_bay_id,target_bay_number FROM public.workshop_bays b
 WHERE b.stage_id=target_stage_id AND b.is_active ORDER BY b.bay_number LIMIT 1;
 FOREACH fixture IN ARRAY ARRAY[yard_single,missing_eta,qc_override,eta_boundary] LOOP
  fixture_index:=fixture_index+1; found_slot:=false;
  -- Select a genuinely vacant future morning. Requiring Tuesday-Friday also
  -- leaves an operational previous day for the exact ETA+7 boundary rejection.
  FOR scan_day IN (60+fixture_index*14)..(120+fixture_index*14) LOOP
   target_start:=public.workshop_admin_next_operational_minute((((clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+scan_day)::timestamp AT TIME ZONE 'Australia/Perth'));
   IF extract(isodow FROM target_start AT TIME ZONE 'Australia/Perth') NOT IN(2,3,4,5) THEN CONTINUE; END IF;
   previous_start:=target_start-interval '1 day';
   IF public.workshop_admin_next_operational_minute(previous_start)<>previous_start THEN CONTINUE; END IF;
   target_end:=public.workshop_add_operational_minutes(target_start,60);
   previous_end:=public.workshop_add_operational_minutes(previous_start,60);
   IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.bay_id=target_bay_id AND b.deleted_at IS NULL
     AND b.status IN('queued','planned','started','stoppage')
     AND (tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(target_start,target_end,'[)')
       OR tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(previous_start,previous_end,'[)')))
    OR EXISTS(SELECT 1 FROM public.workshop_admin_blocks b WHERE b.bay_id=target_bay_id AND b.deleted_at IS NULL
     AND (tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(target_start,target_end,'[)')
       OR tstzrange(b.scheduled_start_at,b.scheduled_end_at,'[)')&&tstzrange(previous_start,previous_end,'[)')))
   THEN CONTINUE; END IF;
   found_slot:=true; EXIT;
  END LOOP;
  IF NOT found_slot THEN RAISE EXCEPTION 'no_available_future_fixture_slot'; END IF;
  IF fixture=eta_boundary THEN
   UPDATE public.vehicles SET eta_to_kewdale=(target_start AT TIME ZONE 'Australia/Perth')::date-7 WHERE id=fixture;
   SELECT version INTO version_number FROM public.vehicles WHERE id=fixture;
   result:=public.schedule_vehicle_work(fixture,version_number,'HOIST',target_bay_number,previous_start,60,NULL,NULL,'{"source":"yard_hold_rollback_test"}');
   IF result->>'ok' IS DISTINCT FROM 'false' OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=fixture) THEN
    RAISE EXCEPTION 'it_before_eta_plus_seven_not_rejected: %',result;
   END IF;
  END IF;
  SELECT version INTO version_number FROM public.vehicles WHERE id=fixture;
  result:=public.schedule_vehicle_work(fixture,version_number,'HOIST',target_bay_number,target_start,60,NULL,NULL,'{"source":"yard_hold_rollback_test"}');
  IF fixture IN(missing_eta,qc_override) THEN
   IF result->>'ok' IS DISTINCT FROM 'false' OR EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=fixture) THEN
    RAISE EXCEPTION 'ineligible_single_booking_not_rejected: %',result;
   END IF;
  ELSIF result->>'ok' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM public.workshop_bookings
    WHERE vehicle_id=fixture AND scheduled_start_at=target_start AND scheduled_end_at=target_end) THEN
   RAISE EXCEPTION 'yard_hold_or_eta_boundary_single_booking_failed: %',result;
  END IF;
 END LOOP;
 IF before_source IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_object('id',id,'location',current_location,'eta',eta_to_kewdale,
   'description',vehicle_description,'model',model,'source_system',source_system,'source_payload',source_payload)
   ORDER BY id) FROM public.vehicles WHERE id IN(yard_bulk,yh_bulk,yard_single)) THEN
  RAISE EXCEPTION 'booking_rewrote_original_location_source_or_missing_details';
 END IF;
 IF before_bookings IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') FROM public.workshop_bookings b WHERE NOT(b.vehicle_id=ANY(fixtures))) THEN
  RAISE EXCEPTION 'preexisting_bookings_changed';
 END IF;
END $test$;
SELECT 'PASS: Yard Hold and YH without ETA/Navision details, bulk and single-station booking, IT missing ETA and ETA+7 boundary, canonical QC with YH display override rejected, source/location preserved; all fixtures roll back' AS result;
ROLLBACK;

