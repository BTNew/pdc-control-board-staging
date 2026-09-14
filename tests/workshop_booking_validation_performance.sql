-- STAGING ONLY. Run after the performance migration. All changes are temporary.
BEGIN;
SET LOCAL statement_timeout='90s';
DO $guard$ BEGIN IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'Staging required'; END IF; END $guard$;
CREATE TEMP TABLE performance_checks(label text, expected jsonb, actual jsonb) ON COMMIT DROP;

-- The old station-wide projection is the membership oracle, once per station.
CREATE TEMP TABLE original_membership ON COMMIT DROP AS
 SELECT s.id stage_id,e.vehicle_id FROM public.workshop_stages s
 CROSS JOIN LATERAL public.workshop_station_eligibility(s.code)e;
CREATE TEMP TABLE targeted_membership ON COMMIT DROP AS
 SELECT DISTINCT s.id stage_id,v.id vehicle_id FROM public.vehicles v
 JOIN public.vehicle_work_items wi ON wi.vehicle_id=v.id AND wi.required AND NOT wi.completed
 JOIN public.workshop_stages s ON public.workshop_stage_code_for_work_key(wi.work_key)=s.code
 WHERE s.active AND s.planner_enabled AND v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
 AND public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IN('PMB','YH','IT')
 AND (public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))<>'IT' OR v.eta_to_kewdale IS NOT NULL);
INSERT INTO performance_checks SELECT 'station membership',to_jsonb(0),
 to_jsonb((SELECT count(*) FROM (
 (SELECT * FROM original_membership EXCEPT SELECT * FROM targeted_membership)
 UNION ALL (SELECT * FROM targeted_membership EXCEPT SELECT * FROM original_membership)
 ) differences));

CREATE OR REPLACE FUNCTION pg_temp.original_duration(p_vehicle_id uuid, p_stage_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH exact_synthetic AS(
  SELECT e.estimated_minutes
  FROM public.pdc_overnight_synthetic_estimates_369 e
  JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.run_id=e.run_id AND r.vehicle_id=e.vehicle_id AND r.scenario_no=e.scenario_no
  JOIN public.vehicles v ON v.id=e.vehicle_id AND v.stock_number=r.stock_number
   AND v.customer_name=r.customer_name AND v.job_card_number=r.job_card_number AND v.vehicle_description=r.vehicle_description
   AND v.source_system='hermes_overnight_synthetic' AND v.source_batch_id=e.run_id AND v.source_record_id=r.stock_number
   AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
   AND v.source_payload->>'run_id'=e.run_id AND (v.source_payload->>'scenario_no')::integer=e.scenario_no
  JOIN public.workshop_stages s ON s.id=p_stage_id AND s.code=e.stage_code
  WHERE e.run_id='HERMES-TEST-RUN-20260824' AND e.vehicle_id=p_vehicle_id
    AND e.estimated_minutes BETWEEN 1 AND 59
    AND e.estimated_minutes=round(e.estimated_hours*60)::integer
    AND public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,s.code)=e.estimated_hours
  LIMIT 1
 ), established AS(
  SELECT h.hours
  FROM public.workshop_stages s
  CROSS JOIN LATERAL(SELECT public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,s.code) hours) h
  WHERE s.id=p_stage_id
 )
 SELECT CASE WHEN x.estimated_minutes IS NOT NULL THEN x.estimated_minutes
             WHEN h.hours IS NULL THEN NULL WHEN (public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>'active')::boolean THEN greatest(1,round(h.hours*60)::integer) ELSE greatest(1,round(h.hours*60)::integer) END
 FROM established h LEFT JOIN exact_synthetic x ON true
$function$
;
INSERT INTO performance_checks
 SELECT 'duration:'||v.id||':'||s.id,
 to_jsonb(pg_temp.original_duration(v.id,s.id)),
 to_jsonb(public.workshop_vehicle_stage_estimated_duration_minutes(v.id,s.id))
 FROM public.vehicles v CROSS JOIN public.workshop_stages s
 WHERE v.deleted_at IS NULL AND v.lifecycle_state='active'
 AND EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.required AND NOT wi.completed
   AND public.workshop_stage_code_for_work_key(wi.work_key)=s.code);

-- Use isolated copies of settings and the unchanged canonical predicate so
-- closed days, breaks, overtime and malformed legacy inputs can be varied
-- without taking any shared settings locks or changing the workshop calendar.
CREATE TEMP TABLE calendar_settings ON COMMIT DROP AS SELECT key,value FROM public.workshop_settings;
CREATE TEMP TABLE original_calendar_settings ON COMMIT DROP AS SELECT * FROM calendar_settings;
CREATE OR REPLACE FUNCTION pg_temp.test_minute_available(p_at timestamp with time zone)
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
  select (value #>> '{}')::time into v_start from pg_temp.calendar_settings where key='day_start_time';
  select (value #>> '{}')::time into v_end from pg_temp.calendar_settings where key='day_end_time';
  select value into v_working_week from pg_temp.calendar_settings where key='working_week';
  select value into v_closures from pg_temp.calendar_settings where key='closures';
  select value into v_breaks from pg_temp.calendar_settings where key='break_windows';
  select value into v_overtime from pg_temp.calendar_settings where key='overtime_windows';
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
end $function$
;
CREATE OR REPLACE FUNCTION pg_temp.candidate_count(p_start timestamptz,p_end timestamptz)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE settings jsonb; start_time time; end_time time; windows jsonb;
 cursor_at timestamptz:=date_trunc('minute',p_start); stop_at timestamptz:=date_trunc('minute',p_end);
 day_start_at timestamptz; day_end timestamptz; local_day date; day_name text; boundaries integer[]; boundary integer;
 next_at timestamptz; day_minutes integer; total_minutes integer:=0;
BEGIN
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start OR stop_at<=cursor_at THEN RETURN 0; END IF;
 SELECT jsonb_object_agg(key,value) INTO settings FROM pg_temp.calendar_settings
 WHERE key IN('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');
 BEGIN
  start_time:=(settings->>'day_start_time')::time; end_time:=(settings->>'day_end_time')::time;
 EXCEPTION WHEN OTHERS THEN RETURN 0; END;
 IF start_time IS NULL OR end_time IS NULL OR start_time>=end_time
 OR jsonb_typeof(settings->'working_week')<>'array'
 OR jsonb_typeof(settings->'closures')<>'array'
 OR jsonb_typeof(settings->'break_windows')<>'array'
 OR jsonb_typeof(settings->'overtime_windows')<>'array' THEN RETURN 0; END IF;
 windows:=coalesce(settings->'break_windows','[]'::jsonb)||coalesce(settings->'overtime_windows','[]'::jsonb);
 WHILE cursor_at<stop_at LOOP
  local_day:=(cursor_at AT TIME ZONE 'Australia/Perth')::date;
  day_name:=lower(to_char(local_day,'FMDay'));
  day_end:=least((local_day+1)::timestamp AT TIME ZONE 'Australia/Perth',stop_at);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(settings->'working_week') d WHERE lower(d)=day_name)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(settings->'closures') c WHERE c->>'date'=local_day::text)
  THEN cursor_at:=day_end; CONTINUE; END IF;
  day_start_at:=cursor_at; day_minutes:=0;
  BEGIN
   -- Integer-minute sampling changes only at the first minute on/after a boundary.
   SELECT array_agg(DISTINCT n ORDER BY n) INTO boundaries FROM (
    SELECT ceil(extract(epoch FROM start_time)/60)::integer n
    UNION ALL SELECT ceil(extract(epoch FROM end_time)/60)::integer
    UNION ALL SELECT 1440
    UNION ALL SELECT ceil(extract(epoch FROM b.t)/60)::integer
    FROM jsonb_array_elements(windows) w
    CROSS JOIN LATERAL(VALUES((w->>'start')::time),((w->>'end')::time)) b(t)
    WHERE (w ? 'date' AND w->>'date'=local_day::text)
       OR (NOT(w ? 'date') AND lower(coalesce(w->>'scope',w->>'day','global')) IN('global','working_day',day_name))
   ) points WHERE n IS NOT NULL;
   FOREACH boundary IN ARRAY boundaries LOOP
    next_at:=least((local_day::timestamp+make_interval(mins=>boundary)) AT TIME ZONE 'Australia/Perth',day_end);
    IF next_at<=cursor_at THEN CONTINUE; END IF;
    IF pg_temp.test_minute_available(cursor_at) THEN
     day_minutes:=day_minutes+floor(extract(epoch FROM next_at-cursor_at)/60)::integer;
    END IF;
    cursor_at:=next_at;
    EXIT WHEN cursor_at>=day_end;
   END LOOP;
  EXCEPTION WHEN OTHERS THEN
   -- Unusual legacy windows use the original minute oracle for this day.
   SELECT count(*)::integer INTO day_minutes
   FROM generate_series(day_start_at,day_end-interval '1 minute',interval '1 minute') m
   WHERE pg_temp.test_minute_available(m);
  END;
  total_minutes:=total_minutes+day_minutes;
  cursor_at:=day_end;
 END LOOP;
 RETURN total_minutes;
END $function$;
-- CREATE OR REPLACE retains the existing owner and execution grants.

;
CREATE FUNCTION pg_temp.oracle_count(s timestamptz,e timestamptz) RETURNS integer LANGUAGE sql STABLE AS $oracle$
 SELECT CASE WHEN s IS NULL OR e IS NULL OR e<=s THEN 0 ELSE count(*)::integer END
 FROM generate_series(date_trunc('minute',s),date_trunc('minute',e)-interval '1 minute',interval '1 minute') m
 WHERE pg_temp.test_minute_available(m)
$oracle$;
INSERT INTO performance_checks
 SELECT 'calendar-range-'||i,to_jsonb(pg_temp.oracle_count(s,e)),to_jsonb(pg_temp.candidate_count(s,e))
 FROM (SELECT i,'2026-09-11 06:59:31 Australia/Perth'::timestamptz+make_interval(hours=>i*3) s,
 '2026-09-11 06:59:31 Australia/Perth'::timestamptz+make_interval(hours=>i*3,mins=>i*91) e FROM generate_series(0,24)i) ranges;
INSERT INTO performance_checks VALUES
 ('null start','0',to_jsonb(pg_temp.candidate_count(NULL,now()))),
 ('null end','0',to_jsonb(pg_temp.candidate_count(now(),NULL))),
 ('reverse','0',to_jsonb(pg_temp.candidate_count(now(),now()-interval '1 hour'))),
 ('same partial minute','0',to_jsonb(pg_temp.candidate_count('2026-09-14 07:00:01 Australia/Perth','2026-09-14 07:00:59 Australia/Perth')));
INSERT INTO performance_checks SELECT 'long job',
 to_jsonb(pg_temp.oracle_count('2026-09-14 07:00 Australia/Perth','2026-09-23 08:00 Australia/Perth')),
 to_jsonb(pg_temp.candidate_count('2026-09-14 07:00 Australia/Perth','2026-09-23 08:00 Australia/Perth'));

DO $configs$ DECLARE c jsonb; label text; BEGIN
 FOR c IN SELECT x FROM jsonb_array_elements('[
 {"name":"closure","key":"closures","value":[{"date":"2026-09-14"}]},
 {"name":"break","key":"break_windows","value":[{"scope":"global","start":"12:00","end":"12:30"}]},
 {"name":"overtime","key":"overtime_windows","value":[{"scope":"monday","start":"17:00","end":"18:00"}]},
 {"name":"seconds boundary","key":"break_windows","value":[{"scope":"monday","start":"12:00:30","end":"12:15:30"}]},
 {"name":"malformed window","key":"break_windows","value":[{"scope":"monday","start":"bad","end":"12:15"}]},
 {"name":"unrelated malformed window","key":"break_windows","value":[{"date":"2026-12-01","start":"bad","end":"12:15"}]},
 {"name":"missing breaks","key":"break_windows","delete":true},
 {"name":"null breaks","key":"break_windows","value":null},
 {"name":"non-array breaks","key":"break_windows","value":{}},
 {"name":"missing closures","key":"closures","delete":true},
 {"name":"missing overtime","key":"overtime_windows","delete":true},
 {"name":"missing weekdays","key":"working_week","delete":true},
 {"name":"overlapping break and overtime","key":"break_windows","value":[{"scope":"global","start":"11:00","end":"12:30"},{"scope":"global","start":"12:00","end":"13:00"}],"overtime":[{"scope":"monday","start":"12:00","end":"18:00"}]}
 ]'::jsonb)x LOOP
  DELETE FROM pg_temp.calendar_settings;
  INSERT INTO pg_temp.calendar_settings SELECT * FROM pg_temp.original_calendar_settings;
  IF coalesce((c->>'delete')::boolean,false) THEN DELETE FROM pg_temp.calendar_settings WHERE key=c->>'key';
  ELSE UPDATE pg_temp.calendar_settings SET value=c->'value' WHERE key=c->>'key'; END IF;
  IF c ? 'overtime' THEN UPDATE pg_temp.calendar_settings SET value=c->'overtime' WHERE key='overtime_windows'; END IF;
  label:=c->>'name';
  INSERT INTO performance_checks SELECT 'config:'||label,
   to_jsonb(pg_temp.oracle_count('2026-09-11 16:00 Australia/Perth','2026-09-14 18:00 Australia/Perth')),
   to_jsonb(pg_temp.candidate_count('2026-09-11 16:00 Australia/Perth','2026-09-14 18:00 Australia/Perth'));
 END LOOP;
END $configs$;

SELECT count(*) checks,count(*) FILTER(WHERE actual IS DISTINCT FROM expected) failed,
 (SELECT count(*) FROM original_membership) eligible_vehicle_stations,
 jsonb_agg(to_jsonb(p)) FILTER(WHERE actual IS DISTINCT FROM expected) failures FROM performance_checks p;
DO $assert$ BEGIN IF EXISTS(SELECT 1 FROM performance_checks WHERE actual IS DISTINCT FROM expected) THEN
 RAISE EXCEPTION 'Workshop validation performance parity mismatch'; END IF; END $assert$;
ROLLBACK;
