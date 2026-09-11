DO $migration$
DECLARE definition text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 definition:=pg_get_functiondef('public.get_station_workshop_snapshot_pre_170(text,date,date)'::regprocedure);
 IF position('b.effective_end>v_from' in definition)=0 THEN RAISE EXCEPTION 'Expected continuation filter absent'; END IF;
 definition:=replace(definition,'b.effective_end>v_from','b.scheduled_end_at>v_from');
 EXECUTE definition;
END $migration$;
