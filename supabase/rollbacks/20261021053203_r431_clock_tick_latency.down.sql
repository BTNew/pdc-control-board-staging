-- r431 undo (F49): restores workshop_clock_next_minute and workshop_clock_plan byte for byte, drops the r431 pins and the
-- clock_tick_latency_trend check. Bookings the clock already moved stay where they are (normal clock history rows).
-- The optional 'clock_overdue_step_minutes' setting, if someone added it, is left alone (the old functions ignore it).
-- Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r431 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r431 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r431 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r431 undo: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM (VALUES ('public.workshop_clock_next_minute(timestamp with time zone)','32c9642c7f1d89e9a981fa554b2a2122'),('public.workshop_clock_plan(jsonb,jsonb,timestamp with time zone)','58384098be842b62c87b0fa374a15bb6')) e(sig,m)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public')<>2
 THEN RAISE EXCEPTION 'r431 undo: functions are not the r431 versions; nothing restored'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_clock_next_minute(p_at timestamp with time zone)
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
END $function$;

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
END $function$;

DELETE FROM pdc_ops.expected_function_md5 WHERE release='r431' AND signature IN('public.workshop_clock_next_minute(timestamp with time zone)','public.workshop_clock_plan(jsonb,jsonb,timestamp with time zone)');
DELETE FROM pdc_ops.regression_checks WHERE check_name='clock_tick_latency_trend' AND added_in='r431';

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM (VALUES ('public.workshop_clock_next_minute(timestamp with time zone)','6849b6c6eb2360f04a7f66a3828a351a'),('public.workshop_clock_plan(jsonb,jsonb,timestamp with time zone)','6846b2ae63456d905f66dad6868fb636')) e(sig,m)
   JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m
   AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public')<>2
 THEN RAISE EXCEPTION 'r431 undo: old versions did not land'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r431') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r431') THEN RAISE EXCEPTION 'r431 undo: r431 rows remain'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r431 undo: clock tick changed'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r431 undo: protected_function_md5s not ok: %', x.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
