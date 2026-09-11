-- STAGING regression. All real-table booking fixtures roll back.
BEGIN;
DO $test$
DECLARE v public.vehicles%rowtype; s public.workshop_stages%rowtype;
  bay uuid; booking uuid; start_at timestamptz; end_at timestamptz;
  result jsonb; rejected boolean; n integer; before_vehicle jsonb; before_work jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  SELECT * INTO STRICT v FROM public.vehicles WHERE stock_number='12667943' AND deleted_at IS NULL FOR UPDATE;
  SELECT * INTO STRICT s FROM public.workshop_stages WHERE code='FABRICATION';
  IF public.workshop_vehicle_stage_estimated_hours(v.id,s.code)<>0.5
    OR public.workshop_vehicle_stage_estimated_duration_minutes(v.id,s.id)<>30
  THEN RAISE EXCEPTION 'fixture_or_duration_changed'; END IF;
  SELECT id INTO STRICT bay FROM public.workshop_bays WHERE stage_id=s.id AND is_active ORDER BY bay_number LIMIT 1;
  before_vehicle:=to_jsonb(v);
  SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) INTO before_work FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id;
  FOR n IN 1..21 LOOP
    start_at:=(((current_timestamp AT TIME ZONE 'Australia/Perth')::date+n)+time '08:00') AT TIME ZONE 'Australia/Perth';
    end_at:=public.workshop_add_operational_minutes(start_at,30);
    result:=public.workshop_validate_booking(null,v.id,s.id,bay,start_at,end_at,30,'planned',null,false);
    EXIT WHEN result->>'ok'='true';
  END LOOP;
  IF result->>'ok'<>'true' THEN RAISE EXCEPTION 'no_available_test_slot: %',result; END IF;
  INSERT INTO public.workshop_bookings(vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,created_by,updated_by,metadata)
  VALUES(v.id,s.id,bay,'planned',start_at,end_at,30,v.created_by,v.created_by,jsonb_build_object('test','short-duration-rollback')) RETURNING id INTO booking;
  -- Same duration on update must pass the actual table guard again.
  UPDATE public.workshop_bookings SET default_duration_minutes=30 WHERE id=booking;
  IF (SELECT default_duration_minutes FROM public.workshop_bookings WHERE id=booking)<>30 THEN RAISE EXCEPTION 'wrong_persisted_duration'; END IF;
  rejected:=false;
  BEGIN
    UPDATE public.workshop_bookings SET default_duration_minutes=15,scheduled_end_at=public.workshop_add_operational_minutes(start_at,15) WHERE id=booking;
  EXCEPTION WHEN check_violation THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'arbitrary_shortening_was_allowed'; END IF;
  rejected:=false;
  BEGIN
    UPDATE public.workshop_bookings SET default_duration_minutes=0 WHERE id=booking;
  EXCEPTION WHEN check_violation THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'zero_duration_was_allowed'; END IF;
  result:=public.workshop_validate_booking(booking,v.id,s.id,bay,start_at,public.workshop_add_operational_minutes(start_at,60),60,'planned',null,false);
  IF result->>'error'<>'operation_estimate_duration_mismatch' THEN RAISE EXCEPTION 'inflated_duration_was_allowed: %',result; END IF;
  IF before_vehicle IS DISTINCT FROM (SELECT to_jsonb(x) FROM public.vehicles x WHERE id=v.id)
    OR before_work IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id)
  THEN RAISE EXCEPTION 'booking_changed_vehicle_or_required_work'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: 30-minute real booking insert/update; reject 15, 0 and inflated 60; vehicle/work unchanged; all fixtures rolled back' AS result;
