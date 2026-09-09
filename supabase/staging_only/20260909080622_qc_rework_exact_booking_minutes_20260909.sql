-- Only a canonical QC-rework estimate may use a sub-hour repair booking.
DO $repair$
DECLARE d text; p text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'STAGING required'; END IF;
 SELECT pg_get_functiondef('public.workshop_booking_minimum_duration_guard_372()'::regprocedure) INTO d;
 IF md5(d)<>'0e013e0e5f2cc284632ef79823d448ab' THEN RAISE EXCEPTION 'Minimum duration guard changed'; END IF;
 p:=replace(d,' IF NEW.default_duration_minutes<60 AND NOT EXISTS(',
  ' IF NEW.default_duration_minutes<60 AND NOT (coalesce((public.pdc_qc_rework_scope_20260909(NEW.vehicle_id)->>''active'')::boolean,false) AND NEW.default_duration_minutes=public.workshop_vehicle_stage_estimated_duration_minutes(NEW.vehicle_id,NEW.stage_id)) AND NOT EXISTS(');
 IF p=d THEN RAISE EXCEPTION 'Scoped rework duration patch failed'; END IF;
 EXECUTE p;
END $repair$;