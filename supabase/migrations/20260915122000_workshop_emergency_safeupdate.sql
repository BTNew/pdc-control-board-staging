-- Preserve API safe-update enforcement while initializing only changed temp-plan rows.
SET lock_timeout='5s';
DO $repair$
DECLARE definition text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
 SELECT pg_get_functiondef('pdc_workshop_priority_private.reschedule(uuid,timestamptz)'::regprocedure) INTO definition;
 IF position('UPDATE pg_temp.emergency_plan SET original_bay_id=bay_id;' IN definition)=0 THEN RAISE EXCEPTION 'Unexpected emergency function version'; END IF;
 EXECUTE replace(definition,'UPDATE pg_temp.emergency_plan SET original_bay_id=bay_id;',
 'UPDATE pg_temp.emergency_plan SET original_bay_id=bay_id WHERE original_bay_id IS DISTINCT FROM bay_id;');
END $repair$;
