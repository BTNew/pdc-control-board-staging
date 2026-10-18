-- Reuse only opening times for the same p_now/calendar within one pure plan.
-- Movement, block, live-work, delay and watermark rules are unchanged.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF md5(replace(pg_get_functiondef('public.workshop_clock_plan(jsonb,jsonb,timestamptz)'::regprocedure),chr(13),''))<>'246cf0e90872633e9c017a3f9872ee7e' THEN RAISE EXCEPTION 'reviewed_clock_plan_changed'; END IF;
END $guard$;
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
END $function$
;
