DO $repair$
DECLARE d text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 SELECT replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),chr(13),'') INTO d;
 IF md5(d)<>'59429597586a5d24fb391d1c9f3e728b' THEN RAISE EXCEPTION 'reviewed_clock_changed'; END IF;
 IF position('floor_at:=pdc_bus_private.clock_next_minute(p_now,item.calendar_bay_id);' IN d)=0 THEN RAISE EXCEPTION 'clock_floor_missing'; END IF;
 d:=replace(d,'rows jsonb; blocks jsonb; plan jsonb;', 'calendar_floors jsonb; rows jsonb; blocks jsonb; plan jsonb;');
 d:=replace(d,'CREATE INDEX ON clock_linked_plan(component_id);',
 $cache$CREATE INDEX ON clock_linked_plan(component_id);
 -- p_now and the calendar configuration are stable during this locked plan.
 -- Cache only the repeated opening-time lookup; all movement/guard logic stays.
 SELECT coalesce(jsonb_object_agg(coalesce(c.calendar_bay_id::text,'default'),
   pdc_bus_private.clock_next_minute(p_now,c.calendar_bay_id)),'{}') INTO calendar_floors
 FROM (SELECT DISTINCT calendar_bay_id FROM pg_temp.clock_linked_plan) c;$cache$);
 d:=replace(d,'floor_at:=pdc_bus_private.clock_next_minute(p_now,item.calendar_bay_id);',
 $cache$floor_at:=(calendar_floors->>coalesce(item.calendar_bay_id::text,'default'))::timestamptz;$cache$);
 EXECUTE d;
END $repair$;
