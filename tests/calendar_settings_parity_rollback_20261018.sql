-- Run only in the owned disposable loopback copy; every settings change rolls back.
BEGIN;
SET LOCAL statement_timeout='120s';
DO $guard$ BEGIN
 IF inet_server_addr() IS NOT NULL AND NOT (inet_server_addr() <<= '127.0.0.0/8'::inet OR inet_server_addr()='::1'::inet) THEN RAISE EXCEPTION 'loopback_only'; END IF;
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION pg_temp.calendar_original(p_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_local timestamp := p_at at time zone 'Australia/Perth';
  v_date date := v_local::date;
  v_clock time := v_local::time;
  v_day text := lower(to_char(v_local,'FMDay'));
  v_start time;
  v_end time;
  v_working_week jsonb;
  v_closures jsonb;
  v_breaks jsonb;
  v_overtime jsonb;
  v_workday boolean;
  v_regular boolean;
  v_overtime_ok boolean;
  v_break boolean;
begin
  select (value #>> '{}')::time into v_start from public.workshop_settings where key='day_start_time';
  select (value #>> '{}')::time into v_end from public.workshop_settings where key='day_end_time';
  select value into v_working_week from public.workshop_settings where key='working_week';
  select value into v_closures from public.workshop_settings where key='closures';
  select value into v_breaks from public.workshop_settings where key='break_windows';
  select value into v_overtime from public.workshop_settings where key='overtime_windows';
  if v_start is null or v_end is null or v_start>=v_end
     or jsonb_typeof(v_working_week)<>'array' or jsonb_typeof(v_closures)<>'array'
     or jsonb_typeof(v_breaks)<>'array' or jsonb_typeof(v_overtime)<>'array' then
    return false;
  end if;
  select exists(select 1 from jsonb_array_elements_text(v_working_week) d where lower(d)=v_day) into v_workday;
  if not v_workday or exists(
    select 1 from jsonb_array_elements(v_closures) c where c->>'date'=v_date::text
  ) then return false; end if;
  v_regular := v_clock>=v_start and v_clock<v_end;
  select exists(
    select 1 from jsonb_array_elements(v_overtime) w
    where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
      and ((w ? 'date' and w->>'date'=v_date::text)
        or (not (w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in ('global','working_day',v_day)))
  ) into v_overtime_ok;
  select exists(
    select 1 from jsonb_array_elements(v_breaks) w
    where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
      and ((w ? 'date' and w->>'date'=v_date::text)
        or (not (w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in ('global','working_day',v_day)))
  ) into v_break;
  return (v_regular or v_overtime_ok) and not v_break;
exception when others then
  return false;
end $function$;

CREATE TEMP TABLE original_settings AS SELECT * FROM public.workshop_settings;
DO $test$ DECLARE scenario integer; mismatches integer; BEGIN
 FOR scenario IN 0..7 LOOP
  UPDATE public.workshop_settings s SET value=o.value FROM original_settings o WHERE o.key=s.key;
  CASE scenario
   WHEN 0 THEN NULL;
   WHEN 1 THEN UPDATE public.workshop_settings SET value='[{"date":"2026-10-19"}]' WHERE key='closures';
   WHEN 2 THEN UPDATE public.workshop_settings SET value='[{"scope":"global","start":"08:15:31","end":"08:33:42"},{"date":"2026-10-20","start":"11:30","end":"13:00"}]' WHERE key='break_windows';
   WHEN 3 THEN UPDATE public.workshop_settings SET value='[{"scope":"global","start":"04:00","end":"05:45"},{"day":"tuesday","start":"17:00","end":"19:30"}]' WHERE key='overtime_windows';
   WHEN 4 THEN UPDATE public.workshop_settings SET value='[]' WHERE key='working_week';
   WHEN 5 THEN UPDATE public.workshop_settings SET value='"invalid"' WHERE key='day_start_time';
   WHEN 6 THEN UPDATE public.workshop_settings SET value='null' WHERE key='closures';
   WHEN 7 THEN UPDATE public.workshop_settings SET value='[{"scope":"global","start":"invalid","end":"10:00"}]' WHERE key='break_windows';
  END CASE;
  SELECT count(*) INTO mismatches FROM generate_series('2026-10-19 00:00+08'::timestamptz,'2026-10-25 23:59+08'::timestamptz,interval '1 minute') t
   WHERE pg_temp.calendar_original(t) IS DISTINCT FROM public.workshop_calendar_minute_available(t);
  IF mismatches>0 THEN RAISE EXCEPTION 'calendar_case_%_changed',scenario; END IF;
 END LOOP;
 IF public.workshop_calendar_minute_available(NULL) IS DISTINCT FROM pg_temp.calendar_original(NULL) THEN RAISE EXCEPTION 'null_changed'; END IF;
END $test$;
SELECT 'PASS: original calendar parity across eight full weeks of minute samples' result;
ROLLBACK;

