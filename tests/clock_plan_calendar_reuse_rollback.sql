-- Owned disposable loopback copy only. Pure plans; rollback all test fixtures.
BEGIN;
SET LOCAL statement_timeout='120s';
DO $guard$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'loopback_required'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION pg_temp.original_clock_plan(p_rows jsonb, p_blocks jsonb, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb; live jsonb; block jsonb; orig timestamptz; proposed timestamptz; finish timestamptz;
 floor_at timestamptz:=public.workshop_clock_next_minute(p_now); cursor_at timestamptz;
 live_end timestamptz; prior_end timestamptz; obstacle_end timestamptz;
 delay_minutes integer:=0; need integer; duration integer; guard integer;
 moves jsonb:='[]'; marks jsonb:='[]'; calendar_bay_id uuid; live_floor timestamptz;
BEGIN
 IF jsonb_typeof(p_rows)<>'array' OR jsonb_typeof(p_blocks)<>'array' OR p_now IS NULL THEN RAISE EXCEPTION 'Invalid clock plan'; END IF;
 FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage') LOOP
  live_floor:=pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid);
  prior_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'accounted_through')::timestamptz,(live->>'end')::timestamptz));
  live_end:=greatest((live->>'end')::timestamptz,coalesce((live->>'effective_end')::timestamptz,(live->>'end')::timestamptz),live_floor);
  marks:=marks||jsonb_build_array(jsonb_build_object('id',live->>'id','through',greatest(prior_end,live_end)));
 END LOOP;
 FOR r IN SELECT x FROM jsonb_array_elements(p_rows) x
  WHERE x->>'status'='planned' AND nullif(x->>'actual_start','') IS NULL
  ORDER BY (x->>'start')::timestamptz,x->>'id'
 LOOP
  calendar_bay_id:=nullif(r->>'calendar_bay_id','')::uuid;
  floor_at:=pdc_bus_private.clock_next_minute(p_now,calendar_bay_id);
  orig:=(r->>'start')::timestamptz; duration:=(r->>'duration')::integer;
  IF duration IS NULL OR duration<1 THEN RAISE EXCEPTION 'Missing planned duration' USING errcode='22023'; END IF;
  -- Apply only the new live delay since the last successful clock transaction.
  FOR live IN SELECT x FROM jsonb_array_elements(p_rows) x WHERE x->>'status' IN ('started','stoppage') AND (x->>'start')::timestamptz<=orig LOOP
   live_floor:=pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid);
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
    IF live->>'status' IN ('started','stoppage') THEN live_end:=greatest(live_end,pdc_bus_private.clock_next_minute(p_now,nullif(live->>'calendar_bay_id','')::uuid)); END IF;
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

CREATE TEMP TABLE clock_cases(calendar_bay_id uuid,rows jsonb);
INSERT INTO clock_cases SELECT id,'[]'::jsonb FROM public.workshop_bays b WHERE EXISTS(SELECT 1 FROM public.workshop_stages s WHERE s.id=b.stage_id AND s.code='BUS_4X4') AND bay_number IN(1,8);
INSERT INTO clock_cases VALUES(NULL,'[]');
UPDATE clock_cases c SET rows=(SELECT jsonb_agg(jsonb_build_object('id',i::text,'status','planned','start','2026-10-19 06:00+08'::timestamptz+make_interval(hours=>i*2),
 'end','2026-10-19 06:00+08'::timestamptz+make_interval(hours=>i*2+1),'duration',60,'calendar_bay_id',c.calendar_bay_id)) FROM generate_series(1,24) i);
CREATE TEMP TABLE original_cases AS SELECT * FROM clock_cases;
DO $test$ DECLARE c record; at_time timestamptz; fixture integer; rows jsonb; blocks jsonb; before_result jsonb; after_result jsonb; BEGIN
 FOR c IN SELECT * FROM original_cases LOOP
  FOREACH at_time IN ARRAY ARRAY['2026-10-18 20:00+08'::timestamptz,'2026-10-19 06:00:31+08','2026-10-19 12:00+08','2026-10-19 16:31+08'] LOOP
   FOR fixture IN 0..3 LOOP
    rows:=c.rows; blocks:='[]';
    IF fixture>0 THEN rows:=rows||jsonb_build_array(jsonb_build_object('id','live','status',CASE WHEN fixture=1 THEN 'started' WHEN fixture=2 THEN 'stoppage' ELSE 'queued' END,
     'start','2026-10-19 06:00+08','end','2026-10-19 09:00+08','effective_end','2026-10-19 09:30+08','accounted_through','2026-10-19 08:30+08','calendar_bay_id',c.calendar_bay_id)); END IF;
    IF fixture=3 THEN blocks:='[{"start":"2026-10-19 10:00+08","end":"2026-10-19 11:00+08"}]'; END IF;
    before_result:=pg_temp.original_clock_plan(rows,blocks,at_time);
    after_result:=public.workshop_clock_plan(rows,blocks,at_time);
    IF before_result IS DISTINCT FROM after_result THEN RAISE EXCEPTION 'plan_parity_%_%_%',c.calendar_bay_id,at_time,fixture; END IF;
   END LOOP;
  END LOOP;
 END LOOP;
END $test$;
SELECT 'PASS: planned/live/stopped/queued/admin-block and normal/Bus-calendar plan parity' result;
ROLLBACK;
