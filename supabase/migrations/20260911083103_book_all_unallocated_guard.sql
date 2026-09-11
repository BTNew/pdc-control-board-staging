DO $migration$
DECLARE definition text; marker text:=$marker$  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.stage_id=st.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')) THEN$marker$;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 definition:=pg_get_functiondef('public.book_all_vehicle_stations(uuid,integer)'::regprocedure);
 IF position(marker in definition)=0 THEN RAISE EXCEPTION 'Expected booking preflight absent'; END IF;
 definition:=replace(definition,marker,$guard$  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.stage_id=st.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.bay_id IS NULL) THEN
   RAISE EXCEPTION '% has an existing booking without a bay. Allocate or cancel that booking first.',st.display_name USING DETAIL='existing_booking_without_bay';
  END IF;
$guard$||marker);
 EXECUTE definition;
END $migration$;
