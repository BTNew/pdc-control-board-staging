-- Keep deletion/restoration timestamps independent of earlier queue or stop times.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging required'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION pdc_bus_private.capture_activity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE origin boolean:=false; at_time timestamptz; previous_status text; in_scope boolean;
BEGIN
 IF NEW.actual_start_at IS NULL OR NOT pdc_bus_private.pure_department138_bus(NEW.vehicle_id) THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status AND NEW.bay_id IS NOT DISTINCT FROM OLD.bay_id
 AND NEW.actual_start_at IS NOT DISTINCT FROM OLD.actual_start_at AND NEW.actual_end_at IS NOT DISTINCT FROM OLD.actual_end_at
 AND NEW.deleted_at IS NOT DISTINCT FROM OLD.deleted_at
 THEN RETURN NEW; END IF;
 in_scope:=EXISTS(SELECT 1 FROM pdc_bus_private.activity_events e WHERE e.booking_id=NEW.id);
 IF NOT in_scope AND NOT (pdc_bus_private.active_vehicle(NEW.vehicle_id) AND EXISTS(
 SELECT 1 FROM public.workshop_stages s WHERE s.id=NEW.stage_id AND s.code='BUS_4X4')) THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' THEN
  previous_status:=CASE WHEN OLD.deleted_at IS NOT NULL THEN 'deleted' ELSE OLD.status::text END;
  -- An edited start boundary while already running is not a confirmed resume.
  IF OLD.status='started' AND NEW.status='started' AND OLD.actual_start_at IS DISTINCT FROM NEW.actual_start_at
  THEN previous_status:='unknown_start_boundary'; END IF;
 END IF;
 origin:=NOT in_scope AND NEW.status='started' AND (TG_OP='INSERT' OR OLD.actual_start_at IS NULL)
 AND NEW.actual_start_at<=clock_timestamp() AND NEW.bay_id IS NOT NULL;
 at_time:=CASE WHEN NEW.deleted_at IS NOT NULL THEN NEW.deleted_at
 WHEN TG_OP='UPDATE' AND OLD.deleted_at IS NOT NULL THEN clock_timestamp()
 WHEN origin THEN NEW.actual_start_at
 WHEN NEW.status='completed' THEN coalesce(NEW.actual_end_at,clock_timestamp())
 WHEN NEW.status='stoppage' THEN coalesce(NEW.stoppage_started_at,clock_timestamp())
 WHEN NEW.status='queued' THEN coalesce(NEW.returned_to_queue_at,clock_timestamp())
 ELSE clock_timestamp() END;
 INSERT INTO pdc_bus_private.activity_events(booking_id,effective_at,from_status,to_status,bay_id,is_origin,recorded_by)
 VALUES(NEW.id,at_time,previous_status,CASE WHEN NEW.deleted_at IS NOT NULL THEN 'deleted' ELSE NEW.status::text END,NEW.bay_id,origin,auth.uid());
 RETURN NEW;
END $fn$;
