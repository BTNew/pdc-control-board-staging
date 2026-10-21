-- r431 rolled-back test (F49). STAGING ONLY, :02-:45 window, one transaction that always rolls back.
-- Installs the candidate helpers inside the transaction, compares with pg_temp copies of the live ones.
-- Never calls workshop_clock_tick, never touches bookings or settings rows that persist.
BEGIN;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='70s';
DO $w$ BEGIN
 WHILE extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 6 LOOP PERFORM pg_sleep(0.5); END LOOP; -- wait for the window, no locks held yet
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r431 test: tick changed'; END IF;
END $w$;
CREATE FUNCTION pg_temp.old_next_minute(p_at timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE t timestamptz:=date_trunc('minute',p_at); limit_at timestamptz:=p_at+interval '90 days';
BEGIN
 IF t<p_at THEN t:=t+interval '1 minute'; END IF;
 WHILE NOT public.workshop_calendar_minute_available(t) LOOP
  t:=t+interval '1 minute';
  IF t>limit_at THEN RAISE EXCEPTION 'No workshop opening within 90 days' USING errcode='22023'; END IF;
 END LOOP;
 RETURN t;
END $function$
;

CREATE FUNCTION pg_temp.old_plan(p_rows jsonb, p_blocks jsonb, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb; live jsonb; block jsonb; orig timestamptz; proposed timestamptz; finish timestamptz;
 floor_at timestamptz:=public.workshop_clock_next_minute(p_now); cursor_at timestamptz;
 calendar_key text; calendar_floors jsonb:=jsonb_build_object('default',floor_at);
 live_end timestamptz; prior_end timestamptz; obstacle_end timestamptz;
 delay_minutes integer:=0; need integer; duration integer; guard integer;
 moves jsonb:='[]'; marks jsonb:='[]'; calendar_bay_id uuid; live_floor timestamptz;
BEGIN
 IF jsonb_typeof(p_rows)<>'array' OR jsonb_typeof(p_blocks)<>'array' OR p_now IS NULL THEN RAISE EXCEPTION 'Invalid clock plan'; END IF;
 FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage') LOOP
  calendar_key:=coalesce((nullif(live->>'calendar_bay_id','')::uuid)::text,'default');
  IF NOT(calendar_floors ? calendar_key) THEN
   calendar_floors:=jsonb_set(calendar_floors,ARRAY[calendar_key],to_jsonb(pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid)));
  END IF;
  live_floor:=(calendar_floors->>calendar_key)::timestamptz;
  prior_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'accounted_through')::timestamptz,(live->>'end')::timestamptz));
  live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz),live_floor);
  marks:=marks||jsonb_build_array(jsonb_build_object('id',live->>'id','through',greatest(prior_end,live_end)));
 END LOOP;
 FOR r IN SELECT x FROM jsonb_array_elements(p_rows) x
  WHERE x->>'status'='planned' AND nullif(x->>'actual_start','') IS NULL
  ORDER BY (x->>'start')::timestamptz,x->>'id'
 LOOP
  calendar_bay_id:=nullif(r->>'calendar_bay_id','')::uuid;
  calendar_key:=coalesce((calendar_bay_id)::text,'default');
  IF NOT(calendar_floors ? calendar_key) THEN
   calendar_floors:=jsonb_set(calendar_floors,ARRAY[calendar_key],to_jsonb(pdc_bus_private.clock_next_minute(p_now,calendar_bay_id)));
  END IF;
  floor_at:=(calendar_floors->>calendar_key)::timestamptz;
  orig:=(r->>'start')::timestamptz; duration:=(r->>'duration')::integer;
  IF duration IS NULL OR duration<1 THEN RAISE EXCEPTION 'Missing planned duration' USING errcode='22023'; END IF;
  -- Apply only the new live delay since the last successful clock transaction.
  FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage') AND (x->>'start')::timestamptz<=orig LOOP
   calendar_key:=coalesce((nullif(live->>'calendar_bay_id','')::uuid)::text,'default');
  IF NOT(calendar_floors ? calendar_key) THEN
   calendar_floors:=jsonb_set(calendar_floors,ARRAY[calendar_key],to_jsonb(pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid)));
  END IF;
  live_floor:=(calendar_floors->>calendar_key)::timestamptz;
  prior_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'accounted_through')::timestamptz,(live->>'end')::timestamptz));
   live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz),live_floor);
   delay_minutes:=greatest(delay_minutes,pdc_bus_private.clock_minutes_between(prior_end,live_end,calendar_bay_id));
  END LOOP;
  proposed:=pdc_bus_private.clock_next_minute(greatest(pdc_bus_private.clock_add_minutes(orig,delay_minutes,calendar_bay_id),floor_at,coalesce(cursor_at,orig)),calendar_bay_id);
  guard:=0;
  LOOP
   guard:=guard+1; IF guard>1000 THEN RAISE EXCEPTION 'Clock obstacle limit' USING errcode='22023'; END IF;
   finish:=pdc_bus_private.clock_add_minutes(proposed,duration,calendar_bay_id);
   obstacle_end:=NULL;
   -- Admin reservations and started work retain their real positions.
   FOR block IN SELECT x FROM jsonb_array_elements(p_blocks) x LOOP
    IF (block->>'start')::timestamptz<finish AND (block->>'end')::timestamptz>proposed THEN obstacle_end:=greatest(obstacle_end,(block->>'end')::timestamptz); END IF;
   END LOOP;
   FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage','queued') OR nullif(x->>'actual_start','') IS NOT NULL LOOP
    live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz));
    IF live->>'status' IN ('started','stoppage') THEN
    calendar_key:=coalesce((nullif(live->>'calendar_bay_id','')::uuid)::text,'default');
  IF NOT(calendar_floors ? calendar_key) THEN
   calendar_floors:=jsonb_set(calendar_floors,ARRAY[calendar_key],to_jsonb(pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid)));
  END IF;
  live_floor:=(calendar_floors->>calendar_key)::timestamptz;
    live_end:=greatest(live_end,live_floor); END IF;
    IF (live->>'start')::timestamptz<finish AND live_end>proposed THEN obstacle_end:=greatest(obstacle_end,live_end); END IF;
   END LOOP;
   EXIT WHEN obstacle_end IS NULL;
   proposed:=pdc_bus_private.clock_next_minute(obstacle_end,calendar_bay_id);
  END LOOP;
  -- Preserve all future gaps: carry the accumulated working-time delay weeks ahead.
  need:=pdc_bus_private.clock_minutes_between(orig,proposed,calendar_bay_id);
  delay_minutes:=greatest(delay_minutes,need);
  IF proposed IS DISTINCT FROM orig OR finish IS DISTINCT FROM (r->>'end')::timestamptz THEN
   moves:=moves||jsonb_build_array(jsonb_build_object('id',r->>'id','from',orig,'to',proposed,'end',finish,'duration',duration));
  END IF;
  cursor_at:=finish;
 END LOOP;
 RETURN jsonb_build_object('moves',moves,'watermarks',marks,'floor',floor_at);
END $function$
;

CREATE OR REPLACE FUNCTION public.workshop_clock_next_minute(p_at timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
-- r431 (F49): same answer as the old minute-by-minute walk, but it jumps straight to the next point where
-- availability can change (day start/end, any break or overtime edge, midnight), so an overnight call is
-- about 3 checks instead of ~800, and a weekend about 8 instead of ~3,700. The answer is still decided by
-- workshop_calendar_minute_available. If the settings cannot be read as times it falls back to one minute.
DECLARE t timestamptz:=date_trunc('minute',p_at); limit_at timestamptz:=p_at+interval '90 days';
 cfg jsonb; edges integer[]; local_day date; m integer; nb integer;
BEGIN
 IF p_at IS NULL THEN RETURN NULL; END IF;
 IF t<p_at THEN t:=t+interval '1 minute'; END IF;
 SELECT jsonb_object_agg(key,value) INTO cfg FROM public.workshop_settings
  WHERE key IN('day_start_time','day_end_time','break_windows','overtime_windows');
 BEGIN
  -- Every window edge of every scope (a superset of the real edges is always safe).
  SELECT array_agg(DISTINCT n ORDER BY n) INTO edges FROM (
   SELECT ceil(extract(epoch FROM (cfg->>'day_start_time')::time)/60)::integer n
   UNION ALL SELECT ceil(extract(epoch FROM (cfg->>'day_end_time')::time)/60)::integer
   UNION ALL SELECT ceil(extract(epoch FROM x.e)/60)::integer
   FROM jsonb_array_elements(CASE WHEN jsonb_typeof(cfg->'break_windows')='array' THEN cfg->'break_windows' ELSE '[]'::jsonb END
                          ||CASE WHEN jsonb_typeof(cfg->'overtime_windows')='array' THEN cfg->'overtime_windows' ELSE '[]'::jsonb END) w
   CROSS JOIN LATERAL(VALUES((w->>'start')::time),((w->>'end')::time)) x(e)
  ) p WHERE n IS NOT NULL AND n>0 AND n<1440;
 EXCEPTION WHEN OTHERS THEN edges:=NULL;
 END;
 LOOP
  IF t>limit_at THEN RAISE EXCEPTION 'No workshop opening within 90 days' USING errcode='22023'; END IF;
  IF public.workshop_calendar_minute_available(t) THEN RETURN t; END IF;
  IF edges IS NULL THEN t:=t+interval '1 minute'; CONTINUE; END IF;
  local_day:=(t AT TIME ZONE 'Australia/Perth')::date;
  m:=floor(extract(epoch FROM (t AT TIME ZONE 'Australia/Perth')-local_day::timestamp)/60)::integer;
  SELECT min(e) INTO nb FROM unnest(edges) e WHERE e>m;
  t:=(local_day::timestamp+make_interval(mins=>coalesce(nb,1440))) AT TIME ZONE 'Australia/Perth';
 END LOOP;
END 
$function$;

CREATE OR REPLACE FUNCTION public.workshop_clock_plan(p_rows jsonb, p_blocks jsonb, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb; live jsonb; block jsonb; orig timestamptz; proposed timestamptz; finish timestamptz;
 floor_at timestamptz:=public.workshop_clock_next_minute(p_now); cursor_at timestamptz;
 calendar_key text; calendar_floors jsonb:=jsonb_build_object('default',floor_at);
 live_end timestamptz; prior_end timestamptz; obstacle_end timestamptz;
 delay_minutes integer:=0; need integer; duration integer; guard integer;
 moves jsonb:='[]'; marks jsonb:='[]'; calendar_bay_id uuid; live_floor timestamptz;
 step_floor timestamptz; step_minutes integer:=coalesce((SELECT CASE WHEN jsonb_typeof(value)='number' AND (value#>>'{}')::numeric BETWEEN 1 AND 60 THEN (value#>>'{}')::numeric::integer END FROM public.workshop_settings WHERE key='clock_overdue_step_minutes'),30);
BEGIN
 IF jsonb_typeof(p_rows)<>'array' OR jsonb_typeof(p_blocks)<>'array' OR p_now IS NULL THEN RAISE EXCEPTION 'Invalid clock plan'; END IF;
 FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage') LOOP
  calendar_key:=coalesce((nullif(live->>'calendar_bay_id','')::uuid)::text,'default');
  IF NOT(calendar_floors ? calendar_key) THEN
   calendar_floors:=jsonb_set(calendar_floors,ARRAY[calendar_key],to_jsonb(pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid)));
  END IF;
  live_floor:=(calendar_floors->>calendar_key)::timestamptz;
  prior_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'accounted_through')::timestamptz,(live->>'end')::timestamptz));
  live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz),live_floor);
  marks:=marks||jsonb_build_array(jsonb_build_object('id',live->>'id','through',greatest(prior_end,live_end)));
 END LOOP;
 FOR r IN SELECT x FROM jsonb_array_elements(p_rows) x
  WHERE x->>'status'='planned' AND nullif(x->>'actual_start','') IS NULL
  ORDER BY (x->>'start')::timestamptz,x->>'id'
 LOOP
  calendar_bay_id:=nullif(r->>'calendar_bay_id','')::uuid;
  calendar_key:=coalesce((calendar_bay_id)::text,'default');
  IF NOT(calendar_floors ? calendar_key) THEN
   calendar_floors:=jsonb_set(calendar_floors,ARRAY[calendar_key],to_jsonb(pdc_bus_private.clock_next_minute(p_now,calendar_bay_id)));
  END IF;
  floor_at:=(calendar_floors->>calendar_key)::timestamptz;
  orig:=(r->>'start')::timestamptz; duration:=(r->>'duration')::integer;
  IF duration IS NULL OR duration<1 THEN RAISE EXCEPTION 'Missing planned duration' USING errcode='22023'; END IF;
  -- Apply only the new live delay since the last successful clock transaction.
  FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage') AND (x->>'start')::timestamptz<=orig LOOP
   calendar_key:=coalesce((nullif(live->>'calendar_bay_id','')::uuid)::text,'default');
  IF NOT(calendar_floors ? calendar_key) THEN
   calendar_floors:=jsonb_set(calendar_floors,ARRAY[calendar_key],to_jsonb(pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid)));
  END IF;
  live_floor:=(calendar_floors->>calendar_key)::timestamptz;
  prior_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'accounted_through')::timestamptz,(live->>'end')::timestamptz));
   live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz),live_floor);
   delay_minutes:=greatest(delay_minutes,pdc_bus_private.clock_minutes_between(prior_end,live_end,calendar_bay_id));
  END LOOP;
  -- r431 (F49): a planned job whose start has already passed without being started is moved to the next
 -- step mark (default every 30 minutes) instead of to the next minute, so it and every job its delay carries
 -- are re-saved once a step instead of every minute. Jobs not yet overdue and live overruns are unchanged.
 -- Setting workshop_settings 'clock_overdue_step_minutes' to 1 gives the old every-minute behaviour.
 IF orig<floor_at AND step_minutes>1 THEN
  step_floor:=date_trunc('hour',floor_at)+make_interval(mins=>(ceil(extract(epoch FROM floor_at-date_trunc('hour',floor_at))/60/step_minutes)*step_minutes)::integer);
  step_floor:=pdc_bus_private.clock_next_minute(greatest(step_floor,floor_at),calendar_bay_id);
 ELSE step_floor:=floor_at; END IF;
 proposed:=pdc_bus_private.clock_next_minute(greatest(pdc_bus_private.clock_add_minutes(orig,delay_minutes,calendar_bay_id),step_floor,coalesce(cursor_at,orig)),calendar_bay_id);
  guard:=0;
  LOOP
   guard:=guard+1; IF guard>1000 THEN RAISE EXCEPTION 'Clock obstacle limit' USING errcode='22023'; END IF;
   finish:=pdc_bus_private.clock_add_minutes(proposed,duration,calendar_bay_id);
   obstacle_end:=NULL;
   -- Admin reservations and started work retain their real positions.
   FOR block IN SELECT x FROM jsonb_array_elements(p_blocks) x LOOP
    IF (block->>'start')::timestamptz<finish AND (block->>'end')::timestamptz>proposed THEN obstacle_end:=greatest(obstacle_end,(block->>'end')::timestamptz); END IF;
   END LOOP;
   FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage','queued') OR nullif(x->>'actual_start','') IS NOT NULL LOOP
    live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz));
    IF live->>'status' IN ('started','stoppage') THEN
    calendar_key:=coalesce((nullif(live->>'calendar_bay_id','')::uuid)::text,'default');
  IF NOT(calendar_floors ? calendar_key) THEN
   calendar_floors:=jsonb_set(calendar_floors,ARRAY[calendar_key],to_jsonb(pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid)));
  END IF;
  live_floor:=(calendar_floors->>calendar_key)::timestamptz;
    live_end:=greatest(live_end,live_floor); END IF;
    IF (live->>'start')::timestamptz<finish AND live_end>proposed THEN obstacle_end:=greatest(obstacle_end,live_end); END IF;
   END LOOP;
   EXIT WHEN obstacle_end IS NULL;
   proposed:=pdc_bus_private.clock_next_minute(obstacle_end,calendar_bay_id);
  END LOOP;
  -- Preserve all future gaps: carry the accumulated working-time delay weeks ahead.
  need:=pdc_bus_private.clock_minutes_between(orig,proposed,calendar_bay_id);
  delay_minutes:=greatest(delay_minutes,need);
  IF proposed IS DISTINCT FROM orig OR finish IS DISTINCT FROM (r->>'end')::timestamptz THEN
   moves:=moves||jsonb_build_array(jsonb_build_object('id',r->>'id','from',orig,'to',proposed,'end',finish,'duration',duration));
  END IF;
  cursor_at:=finish;
 END LOOP;
 RETURN jsonb_build_object('moves',moves,'watermarks',marks,'floor',floor_at);
END $function$;

DO $t$ DECLARE n int:=0; bad int:=0; x record; r jsonb; d0 timestamptz; BEGIN
 -- 1. next open minute: candidate equals the old minute walk (every 23m11s over 14 days, plus day edges).
 FOR x IN SELECT t FROM generate_series(date_trunc('day',now()),date_trunc('day',now())+interval '14 days',interval '23 minutes 11 seconds') t
  UNION ALL SELECT d+o FROM generate_series(date_trunc('day',now() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth',date_trunc('day',now() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth'+interval '7 days',interval '1 day') d,
   unnest(ARRAY[interval '5 hours 59 minutes',interval '6 hours',interval '6 hours 1 second',interval '16 hours 29 minutes 59 seconds',interval '16 hours 30 minutes',interval '23 hours 59 minutes 30 seconds']) o LOOP
  n:=n+1; IF public.workshop_clock_next_minute(x.t) IS DISTINCT FROM pg_temp.old_next_minute(x.t) THEN bad:=bad+1; END IF;
 END LOOP;
 IF bad>0 THEN RAISE EXCEPTION 'r431 test: % of % next-minute samples differ',bad,n; END IF;
 -- 2. plan: not-overdue rows identical to the old plan; overdue row goes to the next :00/:30; step 1 = old behaviour.
 d0:=public.workshop_clock_next_minute(date_trunc('day',now() AT TIME ZONE 'Australia/Perth') AT TIME ZONE 'Australia/Perth'+interval '1 day 6 hours');
 r:=jsonb_build_array(jsonb_build_object('id','a','status','planned','start',d0+interval '2 hours','end',d0+interval '3 hours','duration',60),
   jsonb_build_object('id','b','status','planned','start',d0+interval '3 hours','end',d0+interval '4 hours','duration',60));
 IF public.workshop_clock_plan(r,'[]',d0+interval '6 minutes 0.3 seconds') IS DISTINCT FROM pg_temp.old_plan(r,'[]',d0+interval '6 minutes 0.3 seconds') THEN RAISE EXCEPTION 'r431 test: non-overdue plan differs'; END IF;
 r:=jsonb_build_array(jsonb_build_object('id','a','status','planned','start',d0,'end',d0+interval '1 hour','duration',60),
   jsonb_build_object('id','b','status','planned','start',d0+interval '1 hour','end',d0+interval '2 hours','duration',60));
 IF (public.workshop_clock_plan(r,'[]',d0+interval '6 minutes 0.3 seconds')->'moves'->0->>'to')::timestamptz IS DISTINCT FROM d0+interval '30 minutes'
  OR (public.workshop_clock_plan(r,'[]',d0+interval '6 minutes 0.3 seconds')->'moves'->1->>'to')::timestamptz IS DISTINCT FROM d0+interval '90 minutes'
 THEN RAISE EXCEPTION 'r431 test: overdue step wrong: %',public.workshop_clock_plan(r,'[]',d0+interval '6 minutes 0.3 seconds'); END IF;
 INSERT INTO public.workshop_settings(key,value) VALUES('clock_overdue_step_minutes','1');
 IF public.workshop_clock_plan(r,'[]',d0+interval '6 minutes 0.3 seconds') IS DISTINCT FROM pg_temp.old_plan(r,'[]',d0+interval '6 minutes 0.3 seconds') THEN RAISE EXCEPTION 'r431 test: step 1 differs from old'; END IF;
 RAISE NOTICE 'r431 test ok: % next-minute samples identical; plan parity, 30-min step and step-1 parity ok',n;
 IF extract(second FROM clock_timestamp())>45 THEN RAISE EXCEPTION 'r431 test: ran past :45'; END IF;
END $t$;
ROLLBACK;
