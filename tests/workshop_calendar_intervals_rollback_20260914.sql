-- STAGING ONLY. Every setting/fixture change rolls back; compare the preserved
-- deployed minute-by-minute authority with the interval implementation.
BEGIN;
SET LOCAL statement_timeout='120s';
SET LOCAL lock_timeout='5s';
SET LOCAL TIME ZONE 'Australia/Perth';
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
END $guard$;
CREATE TEMP TABLE calendar_results(label text PRIMARY KEY,ok boolean,evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE calendar_original_settings AS SELECT * FROM public.workshop_settings;
CREATE OR REPLACE FUNCTION pg_temp.baseline_add_operational_minutes(p_start timestamp with time zone, p_duration_minutes integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_origin timestamptz:=date_trunc('minute',p_start);
  v_limit timestamptz:=date_trunc('minute',p_start)+interval '90 days';
  v_settings jsonb;
  v_start time;
  v_end time;
  v_working_week jsonb;
  v_closures jsonb;
  v_breaks jsonb;
  v_overtime jsonb;
  v_result timestamptz;
  v_cursor timestamptz:=date_trunc('minute',p_start);
  v_remaining integer:=p_duration_minutes;
  v_local timestamp;
  v_date date;
  v_clock time;
  v_day text;
  v_workday boolean;
  v_regular boolean;
  v_overtime_ok boolean;
  v_break boolean;
begin
  if p_start is null or p_duration_minutes is null or p_duration_minutes<0 then
    raise exception 'Operational minutes must be non-negative' using errcode='22023';
  end if;
  if p_duration_minutes=0 then return p_start; end if;

  select jsonb_object_agg(key,value)
  into v_settings
  from public.workshop_settings
  where key in('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');
  begin
    v_start:=(v_settings->>'day_start_time')::time;
    v_end:=(v_settings->>'day_end_time')::time;
  exception when others then
    v_start:=null; v_end:=null;
  end;
  v_working_week:=v_settings->'working_week';
  v_closures:=v_settings->'closures';
  v_breaks:=v_settings->'break_windows';
  v_overtime:=v_settings->'overtime_windows';

  if v_start is null or v_end is null or v_start>=v_end
     or jsonb_typeof(v_working_week)<>'array' or jsonb_typeof(v_closures)<>'array'
     or jsonb_typeof(v_breaks)<>'array' or jsonb_typeof(v_overtime)<>'array' then
    raise exception 'Operational duration exceeded canonical calendar guard' using errcode='22023';
  end if;

  while v_remaining>0 and v_cursor<v_limit loop
    v_local:=v_cursor at time zone 'Australia/Perth';
    v_date:=v_local::date;
    v_clock:=v_local::time;
    v_day:=lower(to_char(v_local,'FMDay'));
    select exists(select 1 from jsonb_array_elements_text(v_working_week) d where lower(d)=v_day)
      into v_workday;
    if v_workday and not exists(
      select 1 from jsonb_array_elements(v_closures) c where c->>'date'=v_date::text
    ) then
      v_regular:=v_clock>=v_start and v_clock<v_end;
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
      if (v_regular or v_overtime_ok) and not v_break then
        v_remaining:=v_remaining-1;
      end if;
    end if;
    v_cursor:=v_cursor+interval '1 minute';
  end loop;

  if v_remaining>0 then
    raise exception 'Operational duration exceeded canonical calendar guard' using errcode='22023';
  end if;
  v_result:=v_cursor;
  return v_result;
end $function$;

CREATE FUNCTION pg_temp.compare_calendar(start_at timestamptz,minutes integer,label text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE before_at timestamptz; after_at timestamptz; before_error text; after_error text;
BEGIN
 BEGIN before_at:=pg_temp.baseline_add_operational_minutes(start_at,minutes); EXCEPTION WHEN OTHERS THEN before_error:=SQLSTATE||':'||SQLERRM; END;
 BEGIN after_at:=public.workshop_add_operational_minutes(start_at,minutes); EXCEPTION WHEN OTHERS THEN after_error:=SQLSTATE||':'||SQLERRM; END;
 IF before_at IS DISTINCT FROM after_at OR before_error IS DISTINCT FROM after_error THEN
  RAISE EXCEPTION 'Calendar mismatch %: before % [%], after % [%]',label,before_at,before_error,after_at,after_error;
 END IF;
 INSERT INTO calendar_results VALUES(label,true,jsonb_build_object('finish',after_at,'error',after_error));
END $fn$;
DO $cases$
DECLARE variant text; start_at timestamptz; mins integer; original_breaks jsonb;
BEGIN
 SELECT value INTO original_breaks FROM calendar_original_settings WHERE key='break_windows';
 FOR variant IN SELECT unnest(ARRAY['configured','irregular breaks','overlapping overtime','closure','date scope','seconds boundaries']) LOOP
  UPDATE public.workshop_settings s SET value=o.value FROM calendar_original_settings o WHERE o.key=s.key;
  IF variant='irregular breaks' THEN
   UPDATE public.workshop_settings SET value=original_breaks||'[{"scope":"working_day","start":"09:10","end":"09:25"},{"scope":"global","start":"12:05","end":"12:50"}]'::jsonb WHERE key='break_windows';
  ELSIF variant='overlapping overtime' THEN
   UPDATE public.workshop_settings SET value='[{"day":"friday","start":"06:10","end":"07:30"},{"scope":"global","start":"16:45","end":"19:20"}]'::jsonb WHERE key='overtime_windows';
  ELSIF variant='closure' THEN
   UPDATE public.workshop_settings SET value='[{"date":"2026-09-18"},{"date":"2026-09-21"}]'::jsonb WHERE key='closures';
  ELSIF variant='date scope' THEN
   UPDATE public.workshop_settings SET value=original_breaks||'[{"date":"2026-09-18","day":"monday","start":"10:13","end":"11:47"}]'::jsonb WHERE key='break_windows';
   UPDATE public.workshop_settings SET value='[{"date":"2026-09-19","scope":"global","start":"12:00","end":"14:00"}]'::jsonb WHERE key='overtime_windows';
  ELSIF variant='seconds boundaries' THEN
   UPDATE public.workshop_settings SET value='"07:00:30"'::jsonb WHERE key='day_start_time';
   UPDATE public.workshop_settings SET value=original_breaks||'[{"scope":"global","start":"12:00:30","end":"12:01:30"}]'::jsonb WHERE key='break_windows';
  END IF;
  FOR start_at IN SELECT unnest(ARRAY['2026-09-18 06:59+08'::timestamptz,'2026-09-18 07:00+08','2026-09-18 09:10+08','2026-09-18 12:05+08','2026-09-18 16:59:45+08','2026-09-19 07:00+08','2026-09-19 11:59+08','2026-09-19 12:00+08','2026-09-20 10:00+08']) LOOP
   FOREACH mins IN ARRAY ARRAY[0,1,17,600,3420] LOOP
    PERFORM pg_temp.compare_calendar(start_at,mins,variant||' '||start_at::text||' '||mins);
   END LOOP;
  END LOOP;
 END LOOP;
 UPDATE public.workshop_settings s SET value=o.value FROM calendar_original_settings o WHERE o.key=s.key;
 PERFORM pg_temp.compare_calendar(NULL,1,'Null start is rejected');
 PERFORM pg_temp.compare_calendar(now(),NULL,'Null duration is rejected');
 PERFORM pg_temp.compare_calendar(now(),-1,'Negative duration is rejected');
 PERFORM pg_temp.compare_calendar('infinity',1,'Infinite start is guarded');
 UPDATE public.workshop_settings SET value='[]'::jsonb WHERE key='working_week';
 PERFORM pg_temp.compare_calendar('2026-09-18 07:00+08',1,'No working days reaches the 90-day guard');
 UPDATE public.workshop_settings SET value='"00:00"'::jsonb WHERE key='day_start_time';
 UPDATE public.workshop_settings SET value='"24:00"'::jsonb WHERE key='day_end_time';
 UPDATE public.workshop_settings SET value='["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]'::jsonb WHERE key='working_week';
 UPDATE public.workshop_settings SET value='[]'::jsonb WHERE key IN('closures','break_windows','overtime_windows');
 PERFORM pg_temp.compare_calendar('2026-09-18 07:00+08',129600,'Exact 90-day duration finishes at the guard');
 PERFORM pg_temp.compare_calendar('2026-09-18 07:00+08',129601,'Duration beyond 90 days retains guard');
 UPDATE public.workshop_settings SET value='"invalid"'::jsonb WHERE key='day_start_time';
 PERFORM pg_temp.compare_calendar(now(),1,'Invalid regular time retains canonical error');
END $cases$;
SELECT count(*) passed, bool_and(ok) all_passed,
 jsonb_agg(jsonb_build_object('label',label,'evidence',evidence) ORDER BY label) FILTER(WHERE evidence->>'error' IS NOT NULL) rejected_inputs
FROM calendar_results;
ROLLBACK;
