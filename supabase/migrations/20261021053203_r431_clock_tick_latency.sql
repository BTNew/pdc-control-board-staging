-- r431 (F49, 21 Oct). Staging cdsmnqxtyyoeoznmbidd only. Approved by Craig 21 Oct (clock rule; step size 30 min).
-- Fault: the workshop clock tick went from ~0.2 s to ~1.3 s at 06:00 and ~3 s at 11:00 AWST (p95 3075 ms vs the 2 s limit,
-- lock timeout 3 s). Cause: planned jobs whose start passed without being started (two at 06:00, two at 11:00) are moved to the
-- next minute on every tick, and their delay is carried to every job linked by bay, vehicle or fitter (26 bookings in 7 bays,
-- out to mid-November), so the tick re-saves ~26 bookings every minute at ~105 ms each (all booking triggers and validation).
-- Second, smaller cost: workshop_clock_next_minute walks one minute at a time through closed hours (~44 ms overnight, ~140 ms
-- over a weekend per call), which is what made the tick drift down overnight from ~650 ms to ~200 ms.
-- Fix: (1) workshop_clock_next_minute jumps to the next calendar edge instead of walking minutes (same answer, checked below).
-- (2) workshop_clock_plan moves an overdue, not-started planned job to the next 30-minute mark (setting
-- 'clock_overdue_step_minutes', 1..60, default 30; 1 = old every-minute behaviour), so the chain is re-saved once per step.
-- Not touched: workshop_clock_tick (md5 asserted), its cron, any booking, history, settings rows, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r431: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r431: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r431: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r431: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM (VALUES ('public.workshop_clock_next_minute(timestamp with time zone)','6849b6c6eb2360f04a7f66a3828a351a'),('public.workshop_clock_plan(jsonb,jsonb,timestamp with time zone)','6846b2ae63456d905f66dad6868fb636')) e(sig,m)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public')<>2
 THEN RAISE EXCEPTION 'r431: clock helpers are not the expected versions; nothing changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r431' OR signature IN('public.workshop_clock_next_minute(timestamp with time zone)','public.workshop_clock_plan(jsonb,jsonb,timestamp with time zone)'))
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='clock_tick_latency_trend' OR added_in='r431') THEN RAISE EXCEPTION 'r431: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=240) THEN RAISE EXCEPTION 'r431: sort_order 240 taken'; END IF;
END $g$;

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

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.workshop_clock_next_minute(timestamp with time zone)','32c9642c7f1d89e9a981fa554b2a2122','r431','r431: jumps to the next calendar edge instead of walking minutes (was 6849b6c6eb2360f04a7f66a3828a351a)'),
 ('public.workshop_clock_plan(jsonb,jsonb,timestamp with time zone)','58384098be842b62c87b0fa374a15bb6','r431','r431: overdue not-started jobs move in clock_overdue_step_minutes steps (was 6846b2ae63456d905f66dad6868fb636)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('clock_tick_latency_trend','F49','The workshop clock tick is not creeping: no hour in the last 4 h has a median over 1 s, or over 300 ms and 3x the same hour on the previous weekday; also shows how many bookings the tick re-saved in the last 30 min',
  $chk$WITH j AS (SELECT jobid FROM cron.job WHERE jobname='staging-workshop-clock-cascade'),
d AS (SELECT d.start_time AT TIME ZONE 'Australia/Perth' t, extract(epoch FROM d.end_time-d.start_time)*1000 ms
  FROM cron.job_run_details d JOIN j ON j.jobid=d.jobid
  WHERE d.start_time>now()-interval '4 days' AND d.end_time IS NOT NULL),
h AS (SELECT date_trunc('hour',t) hr, count(*) n, percentile_cont(0.5) WITHIN GROUP (ORDER BY ms) p50 FROM d GROUP BY 1),
c AS (SELECT h.hr, h.n, h.p50, p.p50 prev_p50 FROM h
  LEFT JOIN h p ON p.hr=h.hr-CASE extract(isodow FROM h.hr) WHEN 1 THEN interval '3 days' WHEN 7 THEN interval '2 days' ELSE interval '1 day' END
  WHERE h.hr>=date_trunc('hour',now() AT TIME ZONE 'Australia/Perth')-interval '3 hours'),
bad AS (SELECT * FROM c WHERE c.n>=15 AND (c.p50>1000 OR (c.p50>300 AND c.prev_p50 IS NOT NULL AND c.p50>3*c.prev_p50))),
mv AS (SELECT count(*) n, count(DISTINCT clock_at) ticks FROM public.workshop_clock_history WHERE clock_at>now()-interval '30 minutes')
SELECT (SELECT count(*) FROM c WHERE n>=15)>=1 AND NOT EXISTS(SELECT 1 FROM bad) AS ok,
 'tick hourly p50 (AWST), last 4 h: '||coalesce((SELECT string_agg(to_char(hr,'HH24:MI')||' '||round(p50::numeric)||' ms'
   ||coalesce(' (prev weekday '||round(prev_p50::numeric)||')',''),', ' ORDER BY hr) FROM c),'no runs')
 ||'; limit: any hour over 1000 ms, or over 300 ms and 3x the same hour on the previous weekday'
 ||coalesce('; OVER: '||(SELECT string_agg(to_char(hr,'HH24:MI'),', ' ORDER BY hr) FROM bad),'')
 ||'; bookings re-saved by the tick, last 30 min: '||(SELECT n FROM mv)||' in '||(SELECT ticks FROM mv)||' ticks' AS detail$chk$,true,240,'r431');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM (VALUES ('public.workshop_clock_next_minute(timestamp with time zone)','32c9642c7f1d89e9a981fa554b2a2122'),('public.workshop_clock_plan(jsonb,jsonb,timestamp with time zone)','58384098be842b62c87b0fa374a15bb6')) e(sig,m)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public')<>2
 THEN RAISE EXCEPTION 'r431: a function did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r431: clock tick changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r431')<>2 THEN RAISE EXCEPTION 'r431: pins not written'; END IF;
 -- Spot check against the plain minute-by-minute answer (4 days of minutes), at a work time, overnight, Friday night and a Saturday.
 FOR x IN SELECT t FROM unnest(ARRAY[date_trunc('day',now() AT TIME ZONE 'Australia/Perth')+interval '9 hours 10 minutes 30 seconds',
    date_trunc('day',now() AT TIME ZONE 'Australia/Perth')+interval '16 hours 31 minutes',
    date_trunc('week',now() AT TIME ZONE 'Australia/Perth')+interval '4 days 16 hours 31 minutes',
    date_trunc('week',now() AT TIME ZONE 'Australia/Perth')+interval '5 days 10 hours']) u(l), LATERAL (SELECT l AT TIME ZONE 'Australia/Perth' t) z LOOP
  IF public.workshop_clock_next_minute(x.t) IS DISTINCT FROM (SELECT min(m) FROM generate_series(date_trunc('minute',x.t)+CASE WHEN date_trunc('minute',x.t)<x.t THEN interval '1 minute' ELSE interval '0' END,x.t+interval '4 days',interval '1 minute') m WHERE public.workshop_calendar_minute_available(m))
  THEN RAISE EXCEPTION 'r431: next open minute differs from the minute-by-minute answer at %',x.t; END IF;
 END LOOP;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r431: protected_function_md5s not ok: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='clock_tick_latency_trend') INTO x;
 IF x.detail IS NULL OR position('tick hourly p50' IN x.detail)=0 THEN RAISE EXCEPTION 'r431: new check did not run: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
