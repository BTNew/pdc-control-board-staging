-- Bus add_minutes: same result, walk shift/break segments instead of every minute.
-- Undo: clock_bus_add_minutes_segments.down.sql. Staging cdsmnqxtyyoeoznmbidd only.
DO $g$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.add_minutes(timestamptz,integer,uuid)'::regprocedure) IS DISTINCT FROM '2222e170c317f1a8361dcd4058d14c89' THEN RAISE EXCEPTION 'add_minutes_changed'; END IF;
END $g$;
CREATE OR REPLACE FUNCTION pdc_bus_private.add_minutes(p_start timestamp with time zone, p_minutes integer, p_bay_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE cursor_at timestamptz:=date_trunc('minute',p_start); remaining integer:=p_minutes; max_at timestamptz:=p_start+interval '366 days';
 end_minutes integer; breaks jsonb; local_day date; day_name text; day_end timestamptz; next_at timestamptz;
 boundaries integer[]; boundary integer; seg integer;
BEGIN
 IF p_start IS NULL OR p_minutes IS NULL OR p_minutes<0 OR p_minutes>59999 THEN RAISE EXCEPTION 'Invalid duration' USING errcode='22023'; END IF;
 SELECT CASE WHEN b.bay_number IN(8,9) THEN 840 ELSE 900 END INTO end_minutes
 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id AND s.code='BUS_4X4';
 IF NOT FOUND THEN RETURN public.workshop_add_operational_minutes(p_start,p_minutes); END IF;
 IF remaining=0 THEN RETURN cursor_at; END IF;
 SELECT coalesce(value,'[]'::jsonb) INTO breaks FROM public.workshop_settings WHERE key='break_windows';
 -- Same result as the minute-by-minute walk: availability only changes at the
 -- shift edges, configured break edges or midnight (holidays and closures are
 -- whole days), so each segment is tested once at its first minute.
 WHILE cursor_at<max_at LOOP
  local_day:=(cursor_at AT TIME ZONE 'Australia/Perth')::date;
  day_name:=lower(to_char(local_day,'FMDay'));
  day_end:=(local_day+1)::timestamp AT TIME ZONE 'Australia/Perth';
  SELECT array_agg(DISTINCT n ORDER BY n) INTO boundaries FROM (
   SELECT 360 n UNION ALL SELECT end_minutes UNION ALL SELECT 1440
   UNION ALL SELECT ceil(extract(epoch FROM b.t)/60)::integer
   FROM jsonb_array_elements(coalesce(breaks,'[]'::jsonb)) w
   CROSS JOIN LATERAL(VALUES((w->>'start')::time),((w->>'end')::time)) b(t)
   WHERE (w?'date' AND w->>'date'=local_day::text)
    OR (NOT(w?'date') AND lower(coalesce(w->>'scope',w->>'day','global')) IN('global','working_day',day_name))
  ) points WHERE n IS NOT NULL;
  FOREACH boundary IN ARRAY boundaries LOOP
   next_at:=least((local_day::timestamp+make_interval(mins=>boundary)) AT TIME ZONE 'Australia/Perth',day_end,max_at);
   IF next_at<=cursor_at THEN CONTINUE; END IF;
   IF pdc_bus_private.minute_available(cursor_at,p_bay_id) THEN
    seg:=ceil(extract(epoch FROM next_at-cursor_at)/60)::integer;
    IF remaining<=seg THEN RETURN cursor_at+make_interval(mins=>remaining); END IF;
    remaining:=remaining-seg;
   END IF;
   cursor_at:=next_at;
   EXIT WHEN cursor_at>=day_end OR cursor_at>=max_at;
  END LOOP;
  cursor_at:=greatest(cursor_at,day_end);
 END LOOP;
 RAISE EXCEPTION 'Bus shift duration exceeded calendar guard';
END

$function$;
