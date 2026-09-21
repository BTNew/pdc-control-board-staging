-- Run after the additive read projection migration, in a rollback transaction.
DO $test$
DECLARE actor uuid; actor_email text; result jsonb; row jsonb; matched integer:=0; b record; v uuid;
BEGIN
 SELECT auth_user_id,email INTO STRICT actor,actor_email FROM public.pdc_user_roles
 WHERE active AND account_status='approved' AND role='administrator'
 AND email!~* '(monitor|auditor|bot|service|import|hermes)' ORDER BY created_at LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);
 result:=public.get_station_workshop_snapshot('BUS_4X4',current_date,current_date+30);
 FOR row IN SELECT value FROM jsonb_array_elements(result->'vehicles') LOOP
  IF (row->>'bus_workflow_department138')::boolean IS DISTINCT FROM pdc_bus_private.active_vehicle((row->>'id')::uuid)
  THEN RAISE EXCEPTION 'Vehicle scope missing or incorrect'; END IF;
  matched:=matched+1;
 END LOOP;
 IF matched=0 THEN RAISE EXCEPTION 'No vehicle scope rows exercised'; END IF;
 FOR row IN SELECT value FROM jsonb_array_elements(result->'bookings') LOOP
  IF NOT row?'bus_calendar_version' OR row->>'bus_calendar_version' IS DISTINCT FROM
   (SELECT bus_calendar_version::text FROM public.workshop_bookings WHERE id=(row->>'booking_id')::uuid)
  THEN RAISE EXCEPTION 'Booking calendar projection incorrect'; END IF;
 END LOOP;
 FOR b IN SELECT id,vehicle_id,bus_calendar_version FROM public.workshop_bookings LOOP
  result:=public.workshop_booking_snapshot(b.id);
  IF NOT result?'bus_calendar_version' OR result->>'bus_calendar_version' IS DISTINCT FROM b.bus_calendar_version::text
   OR (result#>>'{vehicle,bus_workflow_department138}')::boolean IS DISTINCT FROM pdc_bus_private.active_vehicle(b.vehicle_id)
  THEN RAISE EXCEPTION 'Single booking projection incorrect'; END IF;
 END LOOP;
 IF pdc_parts_private.planner_search_identity_20260917(gen_random_uuid())<>'{}'::jsonb
 THEN RAISE EXCEPTION 'Missing vehicle exposed identity'; END IF;
 IF (SELECT count(*) FROM pg_indexes WHERE schemaname='pdc_bus_private'
  AND indexname IN('bus_audit_actor_idx','bus_audit_vehicle_idx','bus_supplier_booking_idx','bus_supplier_technician_idx','bus_supplier_actor_idx','bus_workflow_actor_idx'))<>6
 THEN RAISE EXCEPTION 'FK indexes missing'; END IF;
END $test$;
SELECT 'PASS: exact Dept138 snapshot scope, historic/new calendar marker, bounded identity and six private FK indexes' result;

