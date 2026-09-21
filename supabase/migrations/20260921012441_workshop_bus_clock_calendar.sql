-- Keep automatic carry-over on the same per-bay calendar as booking validation.
-- No booking is moved by this migration. The existing minute clock applies plans.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF md5(pg_get_functiondef('public.workshop_clock_plan(jsonb,jsonb,timestamptz)'::regprocedure))<>'24ab0fa6a045af25e28ab5cb024b5b13'
 OR md5(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure))<>'db78277273e8a418553d266d3a52165e'
 THEN RAISE EXCEPTION 'Clock changed since reviewed baseline'; END IF;
END $guard$;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

-- NULL calendar bay retains the canonical ordinary-workshop behaviour.
CREATE FUNCTION pdc_bus_private.clock_next_minute(p_at timestamptz,p_calendar_bay_id uuid)
RETURNS timestamptz LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $fn$
DECLARE t timestamptz:=date_trunc('minute',p_at); limit_at timestamptz:=p_at+interval '90 days';
 local_at timestamp; end_time time;
BEGIN
 IF p_calendar_bay_id IS NULL THEN RETURN public.workshop_clock_next_minute(p_at); END IF;
 IF p_at IS NULL THEN RAISE EXCEPTION 'Clock time required' USING errcode='22023'; END IF;
 SELECT CASE WHEN b.bay_number IN(8,9) THEN time '14:00' ELSE time '15:00' END INTO end_time
 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE b.id=p_calendar_bay_id AND s.code='BUS_4X4';
 IF NOT FOUND THEN RAISE EXCEPTION 'Invalid Bus calendar bay' USING errcode='22023'; END IF;
 IF t<p_at THEN t:=t+interval '1 minute'; END IF;
 WHILE NOT pdc_bus_private.minute_available(t,p_calendar_bay_id) LOOP
  local_at:=t AT TIME ZONE 'Australia/Perth';
  IF extract(isodow FROM local_at)>5 OR local_at::time>=end_time THEN
   t:=((local_at::date+1)+time '06:00') AT TIME ZONE 'Australia/Perth';
  ELSIF local_at::time<time '06:00' THEN
   t:=(local_at::date+time '06:00') AT TIME ZONE 'Australia/Perth';
  ELSE t:=t+interval '1 minute'; END IF;
  IF t>limit_at THEN RAISE EXCEPTION 'No Bus opening within 90 days' USING errcode='22023'; END IF;
 END LOOP;
 RETURN t;
END $fn$;

CREATE FUNCTION pdc_bus_private.clock_add_minutes(p_start timestamptz,p_minutes integer,p_calendar_bay_id uuid)
RETURNS timestamptz LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $fn$
BEGIN
 IF p_calendar_bay_id IS NULL THEN RETURN public.workshop_add_operational_minutes(p_start,p_minutes); END IF;
 -- Preserve the identity operation (including seconds), like the global helper.
 IF p_minutes=0 THEN RETURN p_start; END IF;
 RETURN pdc_bus_private.add_minutes(p_start,p_minutes,p_calendar_bay_id);
END $fn$;

CREATE FUNCTION pdc_bus_private.clock_minutes_between(p_start timestamptz,p_end timestamptz,p_calendar_bay_id uuid)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $fn$
DECLARE cursor_at timestamptz:=date_trunc('minute',p_start); stop_at timestamptz:=date_trunc('minute',p_end);
 local_day date; day_name text; day_end timestamptz; next_at timestamptz;
 breaks jsonb; boundaries integer[]; boundary integer; end_minutes integer; total_minutes integer:=0;
BEGIN
 IF p_calendar_bay_id IS NULL THEN RETURN public.workshop_operational_minutes_between(p_start,p_end); END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start OR stop_at<=cursor_at THEN RETURN 0; END IF;
 SELECT CASE WHEN b.bay_number IN(8,9) THEN 840 ELSE 900 END INTO end_minutes
 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE b.id=p_calendar_bay_id AND s.code='BUS_4X4';
 IF NOT FOUND THEN RAISE EXCEPTION 'Invalid Bus calendar bay' USING errcode='22023'; END IF;
 SELECT coalesce(value,'[]'::jsonb) INTO breaks FROM public.workshop_settings WHERE key='break_windows';
 WHILE cursor_at<stop_at LOOP
  local_day:=(cursor_at AT TIME ZONE 'Australia/Perth')::date;
  day_name:=lower(to_char(local_day,'FMDay'));
  day_end:=least((local_day+1)::timestamp AT TIME ZONE 'Australia/Perth',stop_at);
  -- All integer-minute availability changes are shift or configured-break boundaries.
  SELECT array_agg(DISTINCT n ORDER BY n) INTO boundaries FROM (
   SELECT 360 n UNION ALL SELECT end_minutes UNION ALL SELECT 1440
   UNION ALL SELECT ceil(extract(epoch FROM b.t)/60)::integer
   FROM jsonb_array_elements(coalesce(breaks,'[]'::jsonb)) w
   CROSS JOIN LATERAL(VALUES((w->>'start')::time),((w->>'end')::time)) b(t)
   WHERE (w?'date' AND w->>'date'=local_day::text)
    OR (NOT(w?'date') AND lower(coalesce(w->>'scope',w->>'day','global')) IN('global','working_day',day_name))
  ) points WHERE n IS NOT NULL;
  FOREACH boundary IN ARRAY boundaries LOOP
   next_at:=least((local_day::timestamp+make_interval(mins=>boundary)) AT TIME ZONE 'Australia/Perth',day_end);
   IF next_at<=cursor_at THEN CONTINUE; END IF;
   IF pdc_bus_private.minute_available(cursor_at,p_calendar_bay_id) THEN
    total_minutes:=total_minutes+floor(extract(epoch FROM next_at-cursor_at)/60)::integer;
   END IF;
   cursor_at:=next_at;
   EXIT WHEN cursor_at>=day_end;
  END LOOP;
  cursor_at:=day_end;
 END LOOP;
 RETURN total_minutes;
END $fn$;

CREATE OR REPLACE FUNCTION public.workshop_clock_plan(p_rows jsonb, p_blocks jsonb, p_now timestamp with time zone)
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
CREATE OR REPLACE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true, p_now timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
 SET lock_timeout TO '3s'
 SET statement_timeout TO '120s'
AS $function$
#variable_conflict use_column
DECLARE bay record; item record; component record; predecessor record; block record;
 rows jsonb; blocks jsonb; plan jsonb; movement jsonb; watermark jsonb;
 proposed timestamptz; finish timestamptz; obstacle timestamptz; floor_at timestamptz;
 delay integer; gap integer; count_changed integer; loop_count integer;
 moved integer:=0; component_moved integer; marks jsonb:='[]'; plans jsonb:='[]'; issues jsonb:='[]';
 state_code text; detail text; after_row jsonb; unavailable_date date; technician uuid; bus_rule jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING only'; END IF;
 IF NOT public.workshop_future_only_schedule_enabled() THEN RETURN jsonb_build_object('ok',true,'disabled',true,'moved_count',0); END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0)) THEN RETURN jsonb_build_object('ok',true,'busy',true,'moved_count',0); END IF;
 -- Match the existing planner's mutation gate, then lock a stable snapshot.
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('planned','queued','started','stoppage') ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE;
 floor_at:=public.workshop_clock_next_minute(p_now);
 DROP TABLE IF EXISTS pg_temp.clock_linked_plan;
 CREATE TEMP TABLE clock_linked_plan ON COMMIT DROP AS
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id) ordinal,b.id,b.vehicle_id,b.bay_id,b.stage_id,s.code stage,
  CASE WHEN s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END calendar_bay_id,
  b.status::text status,b.actual_start_at,b.scheduled_start_at original_start,b.scheduled_end_at original_end,
  b.scheduled_start_at final_start,b.scheduled_end_at final_end,b.default_duration_minutes duration,b.version,
  public.workshop_booking_effective_end_at(b.id) effective_end,w.accounted_through,
  coalesce((SELECT array_agg(DISTINCT a.technician_id) FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]) technicians,
  b.id::text component_id,0::integer delay,false changed,false seed,
  (y.is_active AND s.active AND s.planner_enabled) enabled,to_jsonb(b) before_row
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays y ON y.id=b.bay_id LEFT JOIN public.workshop_clock_watermarks w ON w.booking_id=b.id
 WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage');
 CREATE UNIQUE INDEX ON clock_linked_plan(id);
 CREATE INDEX ON clock_linked_plan(component_id);
 -- Keep each connected resource group atomic; unrelated bays can still advance.
 LOOP
  UPDATE pg_temp.clock_linked_plan a SET component_id=q.leader FROM
   (SELECT a1.id,min(b1.component_id) leader FROM pg_temp.clock_linked_plan a1 JOIN pg_temp.clock_linked_plan b1
    ON a1.bay_id=b1.bay_id OR a1.vehicle_id=b1.vehicle_id OR a1.technicians && b1.technicians GROUP BY a1.id) q
   WHERE a.id=q.id AND q.leader<a.component_id;
  GET DIAGNOSTICS count_changed=ROW_COUNT; EXIT WHEN count_changed=0;
 END LOOP;
 FOR component IN SELECT DISTINCT p.component_id FROM pg_temp.clock_linked_plan p
  WHERE p.enabled AND ((p.status='planned' AND p.actual_start_at IS NULL AND p.original_start<p_now)
   OR (p.status IN('started','stoppage') AND greatest(p.effective_end,pdc_bus_private.clock_next_minute(p_now,p.calendar_bay_id))>p.original_end)) ORDER BY p.component_id
 LOOP
  BEGIN
   marks:='[]'; component_moved:=0;
   FOR bay IN SELECT DISTINCT bay_id FROM pg_temp.clock_linked_plan WHERE component_id=component.component_id AND bay_id IS NOT NULL ORDER BY bay_id LOOP
    PERFORM public.workshop_lock_resources(bay.bay_id,NULL);
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'status',status,'start',original_start,'end',original_end,'effective_end',effective_end,
     'duration',duration,'actual_start',actual_start_at,'accounted_through',accounted_through,'calendar_bay_id',calendar_bay_id)),'[]') INTO rows FROM pg_temp.clock_linked_plan WHERE bay_id=bay.bay_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('start',scheduled_start_at,'end',scheduled_end_at)),'[]') INTO blocks
     FROM public.workshop_admin_blocks WHERE bay_id=bay.bay_id AND deleted_at IS NULL AND scheduled_end_at>=p_now;
    plan:=public.workshop_clock_plan(rows,blocks,p_now);
    marks:=marks||(plan->'watermarks');
    FOR movement IN SELECT x FROM jsonb_array_elements(plan->'moves') x LOOP
     UPDATE pg_temp.clock_linked_plan SET final_start=(movement->>'to')::timestamptz,final_end=(movement->>'end')::timestamptz,seed=true
      WHERE id=(movement->>'id')::uuid;
    END LOOP;
   END LOOP;
   -- Walk the original chronological order. Resource edges only point forward.
   FOR item IN SELECT * FROM pg_temp.clock_linked_plan WHERE component_id=component.component_id ORDER BY ordinal LOOP
    floor_at:=pdc_bus_private.clock_next_minute(p_now,item.calendar_bay_id);
    IF item.status IN('started','stoppage') OR item.actual_start_at IS NOT NULL THEN
     UPDATE pg_temp.clock_linked_plan SET final_end=greatest(item.original_end,item.effective_end,floor_at),
      delay=greatest(0,pdc_bus_private.clock_minutes_between(greatest(item.original_end,coalesce(item.accounted_through,item.original_end)),greatest(item.original_end,item.effective_end,floor_at),item.calendar_bay_id))
      WHERE id=item.id;
     CONTINUE;
    END IF;
    proposed:=item.final_start;
    delay:=greatest(0,pdc_bus_private.clock_minutes_between(item.original_start,proposed,item.calendar_bay_id));
    FOR predecessor IN SELECT * FROM pg_temp.clock_linked_plan x WHERE x.component_id=component.component_id AND x.ordinal<item.ordinal
     AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians)
     AND (x.changed OR x.delay>0) ORDER BY x.ordinal LOOP
     delay:=greatest(delay,predecessor.delay);
     proposed:=greatest(proposed,predecessor.final_end+CASE WHEN predecessor.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END);
    END LOOP;
    proposed:=greatest(proposed,pdc_bus_private.clock_add_minutes(item.original_start,delay,item.calendar_bay_id));
    IF NOT item.seed AND proposed<=item.original_start THEN CONTINUE; END IF;
    IF item.status<>'planned' OR item.bay_id IS NULL OR NOT item.enabled THEN
     RAISE EXCEPTION 'A dependent booking cannot move automatically: %',item.id USING errcode='22023'; END IF;
    -- Preserve unchanged predecessors too, without reordering a vehicle's jobs.
    SELECT max(x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END) INTO obstacle
     FROM pg_temp.clock_linked_plan x WHERE x.component_id=component.component_id AND x.ordinal<item.ordinal
      AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
    proposed:=greatest(proposed,obstacle,floor_at); loop_count:=0;
    LOOP
     loop_count:=loop_count+1; IF loop_count>1000 THEN RAISE EXCEPTION 'Clock obstacle limit' USING errcode='22023'; END IF;
     proposed:=pdc_bus_private.clock_next_minute(proposed,item.calendar_bay_id);
     finish:=pdc_bus_private.clock_add_minutes(proposed,item.duration,item.calendar_bay_id);
     SELECT max(scheduled_end_at) INTO obstacle FROM public.workshop_admin_blocks
      WHERE bay_id=item.bay_id AND deleted_at IS NULL AND scheduled_start_at<finish AND scheduled_end_at>proposed;
     -- Started, stopped and queued bookings are fixed obstacles in either direction.
     SELECT greatest(obstacle,max(greatest(x.original_end,x.effective_end,CASE WHEN x.status IN('started','stoppage') THEN pdc_bus_private.clock_next_minute(p_now,x.calendar_bay_id) END))) INTO obstacle
      FROM pg_temp.clock_linked_plan x WHERE x.id<>item.id AND (x.status IN('started','stoppage','queued') OR x.actual_start_at IS NOT NULL)
       AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians)
       AND x.original_start<finish AND greatest(x.original_end,x.effective_end,CASE WHEN x.status IN('started','stoppage') THEN pdc_bus_private.clock_next_minute(p_now,x.calendar_bay_id) END)>proposed;
     SELECT max(d::date) INTO unavailable_date FROM generate_series((proposed AT TIME ZONE 'Australia/Perth')::date::timestamp,
      ((finish-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d WHERE public.pdc_sublet_away_on_date(item.vehicle_id,d::date);
     IF unavailable_date IS NOT NULL THEN obstacle:=greatest(obstacle,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
     FOREACH technician IN ARRAY item.technicians LOOP
      unavailable_date:=public.workshop_technician_leave_date(technician,proposed,finish);
      IF unavailable_date IS NOT NULL THEN obstacle:=greatest(obstacle,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
     END LOOP;
     EXIT WHEN obstacle IS NULL; proposed:=greatest(proposed+interval '1 minute',obstacle);
    END LOOP;
    IF item.calendar_bay_id IS NOT NULL THEN
     bus_rule:=pdc_bus_private.booking_rule(item.vehicle_id,item.bay_id,item.id);
     IF bus_rule->>'ok' IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Bus workflow: %',bus_rule USING errcode='23514';
     END IF;
    END IF;
    UPDATE pg_temp.clock_linked_plan SET final_start=proposed,final_end=finish,
     delay=greatest(delay,pdc_bus_private.clock_minutes_between(item.original_start,proposed,item.calendar_bay_id)),
     changed=(proposed IS DISTINCT FROM item.original_start OR finish IS DISTINCT FROM item.original_end) WHERE id=item.id;
   END LOOP;
   IF EXISTS(SELECT 1 FROM pg_temp.clock_linked_plan a JOIN pg_temp.clock_linked_plan b
    ON a.component_id=b.component_id AND a.ordinal<b.ordinal
    WHERE a.component_id=component.component_id AND (a.changed OR b.changed)
     AND (a.bay_id=b.bay_id OR a.vehicle_id=b.vehicle_id OR a.technicians && b.technicians)
     AND a.final_end+CASE WHEN a.vehicle_id=b.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END>b.final_start) THEN
    RAISE EXCEPTION 'A dependent current or queued job prevents preserving workshop order' USING errcode='22023';
   END IF;
   IF p_apply THEN
    FOR item IN SELECT * FROM pg_temp.clock_linked_plan WHERE component_id=component.component_id AND changed ORDER BY ordinal DESC LOOP
     UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,version=version+1,
      updated_at=clock_timestamp(),updated_by=coalesce(auth.uid(),updated_by) WHERE id=item.id AND version=item.version AND status='planned' AND actual_start_at IS NULL AND deleted_at IS NULL;
     IF NOT FOUND THEN RAISE EXCEPTION 'Clock booking changed' USING errcode='40001'; END IF;
     SELECT to_jsonb(b) INTO after_row FROM public.workshop_bookings b WHERE id=item.id;
     -- A trigger must not silently alter the accepted plan or its shift basis.
     IF (after_row->>'scheduled_start_at')::timestamptz IS DISTINCT FROM item.final_start
      OR (after_row->>'scheduled_end_at')::timestamptz IS DISTINCT FROM item.final_end
      OR (after_row->>'default_duration_minutes')::integer IS DISTINCT FROM item.duration
      OR (CASE WHEN item.calendar_bay_id IS NOT NULL
       THEN (after_row->>'bus_calendar_version')::integer IS DISTINCT FROM 1
         OR coalesce((item.before_row->>'bus_calendar_version')::integer,1)<>1
       ELSE after_row->'bus_calendar_version' IS DISTINCT FROM item.before_row->'bus_calendar_version' END)
     THEN RAISE EXCEPTION 'Clock persisted calendar differs from planned calendar' USING errcode='23514'; END IF;
     UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,updated_at=clock_timestamp() WHERE booking_id=item.id AND released_at IS NULL;
     IF EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=item.id AND a.released_at IS NULL
      AND (a.scheduled_start_at IS DISTINCT FROM item.final_start OR a.scheduled_end_at IS DISTINCT FROM item.final_end))
     THEN RAISE EXCEPTION 'Clock assignment calendar differs from booking' USING errcode='23514'; END IF;
     IF after_row-ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version']
       IS DISTINCT FROM item.before_row-ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version'] THEN
      RAISE EXCEPTION 'Clock changed protected booking fields' USING errcode='23514'; END IF;
     INSERT INTO public.workshop_clock_history(booking_id,bay_id,clock_at,before_data,after_data) VALUES(item.id,item.bay_id,p_now,item.before_row,after_row);
     component_moved:=component_moved+1;
    END LOOP;
    FOR watermark IN SELECT x FROM jsonb_array_elements(marks) x LOOP
     INSERT INTO public.workshop_clock_watermarks(booking_id,accounted_through) VALUES((watermark->>'id')::uuid,(watermark->>'through')::timestamptz)
     ON CONFLICT(booking_id) DO UPDATE SET accounted_through=greatest(public.workshop_clock_watermarks.accounted_through,excluded.accounted_through),updated_at=clock_timestamp();
    END LOOP;
    INSERT INTO public.workshop_clock_status(bay_id,last_checked_at,last_success_at,moved_count)
     SELECT bay_id,p_now,p_now,count(*) FILTER(WHERE changed)::integer FROM pg_temp.clock_linked_plan WHERE component_id=component.component_id AND bay_id IS NOT NULL GROUP BY bay_id
     ON CONFLICT(bay_id) DO UPDATE SET last_checked_at=excluded.last_checked_at,last_success_at=excluded.last_success_at,error_code=NULL,error_detail=NULL,moved_count=excluded.moved_count;
   END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'bay_id',bay_id,'from',original_start,'to',final_start,'end',final_end,'duration',duration) ORDER BY ordinal),'[]') INTO plan
    FROM pg_temp.clock_linked_plan WHERE component_id=component.component_id AND changed;
   moved:=moved+component_moved; plans:=plans||jsonb_build_array(jsonb_build_object('component',component.component_id,'moves',plan));
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '23514' OR SQLSTATE '23P01' OR SQLSTATE '40001' OR lock_not_available THEN
   GET STACKED DIAGNOSTICS state_code=RETURNED_SQLSTATE,detail=MESSAGE_TEXT;
   issues:=issues||jsonb_build_array(jsonb_build_object('component',component.component_id,'code',state_code,'detail',detail));
   IF p_apply THEN
    INSERT INTO public.workshop_clock_status(bay_id,last_checked_at,error_code,error_detail)
     SELECT DISTINCT bay_id,p_now,state_code,detail FROM pg_temp.clock_linked_plan WHERE component_id=component.component_id AND bay_id IS NOT NULL
     ON CONFLICT(bay_id) DO UPDATE SET last_checked_at=excluded.last_checked_at,error_code=excluded.error_code,error_detail=excluded.error_detail,moved_count=0;
   END IF;
  END;
 END LOOP;
 IF p_apply AND moved>0 THEN PERFORM public.workshop_bump_revision(); END IF;
 RETURN jsonb_build_object('ok',jsonb_array_length(issues)=0,'clock_at',p_now,'applied',p_apply,'moved_count',moved,'plans',plans,'issues',issues);
END $function$
;

REVOKE ALL ON FUNCTION pdc_bus_private.clock_next_minute(timestamptz,uuid),
 pdc_bus_private.clock_add_minutes(timestamptz,integer,uuid),
 pdc_bus_private.clock_minutes_between(timestamptz,timestamptz,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
