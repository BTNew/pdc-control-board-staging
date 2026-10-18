-- Calendar availability is called repeatedly by scheduling and the background
-- clock. Read its six settings together; preserve every availability predicate.
DO $repair$
DECLARE d text; old_reads text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 SELECT replace(pg_get_functiondef('public.workshop_calendar_minute_available(timestamptz)'::regprocedure),chr(13),'') INTO d;
 IF md5(d)<>'1135597e0c937a301ebb10fbbbdc9fe2' THEN RAISE EXCEPTION 'reviewed_calendar_changed'; END IF;
 old_reads:=$reads$  select (value #>> '{}')::time into v_start from public.workshop_settings where key='day_start_time';
  select (value #>> '{}')::time into v_end from public.workshop_settings where key='day_end_time';
  select value into v_working_week from public.workshop_settings where key='working_week';
  select value into v_closures from public.workshop_settings where key='closures';
  select value into v_breaks from public.workshop_settings where key='break_windows';
  select value into v_overtime from public.workshop_settings where key='overtime_windows';$reads$;
 old_reads:=replace(old_reads,chr(13),'');
 IF position(old_reads IN d)=0 THEN RAISE EXCEPTION 'calendar_reads_changed'; END IF;
 d:=replace(d,'  v_start time;','  v_settings jsonb;'||chr(10)||'  v_start time;');
 d:=replace(d,old_reads,$reads$  select jsonb_object_agg(key,value) into v_settings from public.workshop_settings
  where key in('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');
  v_start:=(v_settings->>'day_start_time')::time;
  v_end:=(v_settings->>'day_end_time')::time;
  v_working_week:=v_settings->'working_week';
  v_closures:=v_settings->'closures';
  v_breaks:=v_settings->'break_windows';
  v_overtime:=v_settings->'overtime_windows';$reads$);
 EXECUTE replace(d,chr(13),'');
END $repair$;
