-- r452 undo (F65): restores workshop_clock_tick byte for byte (#368, md5 84af7607bfd0ce9907c89bae8644d5b6), puts its pin row back exactly
-- (release #368, its note and its updated_at) and drops the clock_tick_resaves_per_tick check. The pin count does not change.
-- Bookings the clock moved meanwhile stay where they are (normal clock history rows); QC cache rows the r452 tick kept are
-- the same sets the cache held before each re-save and stay valid (qc_cache_zero_mismatches checks them).
-- Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r452 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r452 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r452 undo: fault_regression_check changed'; END IF;
 IF NOT (SELECT md5(p.prosrc)='0aaaa15690ca286ed0db87fc72271d5a' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|v|postgres|search_path=pg_catalog, public|lock_timeout=3s|statement_timeout=120s' FROM pg_proc p WHERE p.oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS TRUE THEN RAISE EXCEPTION 'r452 undo: clock tick is not the r452 version; nothing restored'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)' AND prosrc_md5='0aaaa15690ca286ed0db87fc72271d5a' AND release='r452') THEN RAISE EXCEPTION 'r452 undo: r452 pin missing'; END IF;
 PERFORM set_config('pdc.r452_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true, p_now timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
 SET lock_timeout TO '3s'
 SET statement_timeout TO '120s'
AS $function$
#variable_conflict use_column
DECLARE bay record; item record; component record; predecessor record; block record;
 capacity_context text:=current_setting('pdc.workshop_capacity_manual',true);
 calendar_floors jsonb; rows jsonb; blocks jsonb; plan jsonb; movement jsonb; watermark jsonb;
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
 -- Future queued/planned work cannot seed a clock cascade. Keep the mutation
 -- lock above this check so its decision uses the same serialized state.
 -- Live work always takes the existing full path, including effective-end logic.
 IF NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.deleted_at IS NULL
   AND ((b.status='planned' AND b.actual_start_at IS NULL AND b.scheduled_start_at<p_now)
        OR b.status IN('started','stoppage'))
 ) THEN
  RETURN jsonb_build_object('ok',true,'clock_at',p_now,'applied',p_apply,
   'moved_count',0,'plans','[]'::jsonb,'issues','[]'::jsonb);
 END IF;
 -- An enabled overdue arrival or a live overrun is the only cascade seed.
 -- Queued work is a fixed obstacle, not a seed. When nothing can move, the
 -- locked plan writes no clock rows, so return the same empty result.
 IF NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id
  JOIN public.vehicles v ON v.id=b.vehicle_id
  LEFT JOIN public.workshop_bays y ON y.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND NOT (b.status='queued' AND b.bay_id IS NULL AND b.actual_start_at IS NULL)
   AND (y.is_active AND s.active AND s.planner_enabled) IS TRUE
   AND b.status='planned' AND b.actual_start_at IS NULL AND b.scheduled_start_at<p_now
 ) AND NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id
  JOIN public.vehicles v ON v.id=b.vehicle_id
  LEFT JOIN public.workshop_bays y ON y.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND NOT (b.status='queued' AND b.bay_id IS NULL AND b.actual_start_at IS NULL)
   AND (y.is_active AND s.active AND s.planner_enabled) IS TRUE
   AND b.status IN('started','stoppage') AND greatest(
    public.workshop_booking_effective_end_at(b.id),
    pdc_bus_private.clock_next_minute(p_now,CASE WHEN s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END)
   )>b.scheduled_end_at
 ) THEN
  RETURN jsonb_build_object('ok',true,'clock_at',p_now,'applied',p_apply,
   'moved_count',0,'plans','[]'::jsonb,'issues','[]'::jsonb);
 END IF;
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('planned','queued','started','stoppage') ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE;
 floor_at:=public.workshop_clock_next_minute(p_now);
 DROP TABLE IF EXISTS pg_temp.pdc_clock_effective_ends;
 DROP TABLE IF EXISTS pg_temp.clock_linked_plan;
 CREATE TEMP TABLE clock_linked_plan ON COMMIT DROP AS
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id) ordinal,b.id,b.vehicle_id,b.bay_id,b.stage_id,s.code stage,
  CASE WHEN s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END calendar_bay_id,
  -- A changed arrival date is a scheduling floor, not a reason to abort the
  -- entire resource chain. Preserve the same ETA buffer enforced by validation.
  CASE WHEN public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))='IT'
    AND v.eta_to_kewdale IS NOT NULL
    THEN (v.eta_to_kewdale+7)::timestamp AT TIME ZONE 'Australia/Perth' END eligible_start,
  b.status::text status,b.actual_start_at,b.scheduled_start_at original_start,b.scheduled_end_at original_end,
  b.scheduled_start_at final_start,b.scheduled_end_at final_end,CASE WHEN b.status='planned' AND b.actual_start_at IS NULL
   THEN greatest(b.default_duration_minutes,public.workshop_booking_capacity_duration_minutes(b.id,b.vehicle_id,b.stage_id,b.bay_id))
   ELSE b.default_duration_minutes END duration,b.version,
  CASE WHEN b.status='planned' AND b.actual_start_at IS NULL THEN b.scheduled_end_at ELSE public.workshop_booking_effective_end_at(b.id) END effective_end,w.accounted_through,
  coalesce((SELECT array_agg(DISTINCT a.technician_id) FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]) technicians,
  b.id::text component_id,0::integer delay,false changed,false seed,
  (y.is_active AND s.active AND s.planner_enabled) enabled,to_jsonb(b) before_row
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 JOIN public.vehicles v ON v.id=b.vehicle_id
 LEFT JOIN public.workshop_bays y ON y.id=b.bay_id LEFT JOIN public.workshop_clock_watermarks w ON w.booking_id=b.id
 WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
 AND NOT (b.status='queued' AND b.bay_id IS NULL AND b.actual_start_at IS NULL);
 CREATE UNIQUE INDEX ON clock_linked_plan(id);
 CREATE INDEX ON clock_linked_plan(component_id);
 -- p_now and the calendar configuration are stable during this locked plan.
 -- Cache only the repeated opening-time lookup; all movement/guard logic stays.
 SELECT coalesce(jsonb_object_agg(coalesce(c.calendar_bay_id::text,'default'),
   pdc_bus_private.clock_next_minute(p_now,c.calendar_bay_id)),'{}') INTO calendar_floors
 FROM (SELECT DISTINCT calendar_bay_id FROM pg_temp.clock_linked_plan) c;
 -- Cache the authoritative conflict ends once on this locked snapshot. The
 -- lookup accepts only this function owner's temp table and an exact current
 -- booking version/interval. Never trust caller-created temp data.
 CREATE TEMP TABLE pdc_clock_effective_ends ON COMMIT DROP AS
 SELECT b.id,b.version,b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,
   public.workshop_booking_effective_end_at(b.id) effective_end
 FROM public.workshop_bookings b JOIN pg_temp.clock_linked_plan p ON p.id=b.id;
 CREATE UNIQUE INDEX ON pdc_clock_effective_ends(id);
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
    floor_at:=(calendar_floors->>coalesce(item.calendar_bay_id::text,'default'))::timestamptz;
    IF item.status IN('started','stoppage') OR item.actual_start_at IS NOT NULL THEN
     UPDATE pg_temp.clock_linked_plan SET final_end=greatest(item.original_end,item.effective_end,floor_at),
      delay=greatest(0,pdc_bus_private.clock_minutes_between(greatest(item.original_end,coalesce(item.accounted_through,item.original_end)),greatest(item.original_end,item.effective_end,floor_at),item.calendar_bay_id))
      WHERE id=item.id;
     CONTINUE;
    END IF;
    proposed:=greatest(item.final_start,item.eligible_start);
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
     -- Reuse the existing exact-booking/version allocation context. Retain all
     -- booked minutes after reductions; source additions may increase capacity.
     -- The existing helper still enforces the current canonical minimum.
     PERFORM set_config('pdc.workshop_capacity_manual',jsonb_build_object('actor',auth.uid(),
      'booking',item.id,'version',item.version,'duration',item.duration)::text,true);
     UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
      default_duration_minutes=item.duration,version=version+1,
      updated_at=clock_timestamp(),updated_by=coalesce(auth.uid(),updated_by) WHERE id=item.id AND version=item.version AND status='planned' AND actual_start_at IS NULL AND deleted_at IS NULL;
     IF NOT FOUND THEN RAISE EXCEPTION 'Clock booking changed' USING errcode='40001'; END IF;
     PERFORM set_config('pdc.workshop_capacity_manual',coalesce(capacity_context,''),true);
     SELECT to_jsonb(b) INTO after_row FROM public.workshop_bookings b WHERE id=item.id;
     -- A trigger must not silently alter the accepted plan or its shift basis.
     IF (after_row->>'scheduled_start_at')::timestamptz IS DISTINCT FROM item.final_start
      OR (after_row->>'scheduled_end_at')::timestamptz IS DISTINCT FROM item.final_end
      OR (after_row->>'default_duration_minutes')::integer IS DISTINCT FROM item.duration
      OR item.duration<(item.before_row->>'default_duration_minutes')::integer
      OR public.workshop_booking_capacity_duration_minutes(item.id,item.vehicle_id,item.stage_id,item.bay_id) IS DISTINCT FROM item.duration
      OR (CASE WHEN item.calendar_bay_id IS NOT NULL
       THEN (after_row->>'bus_calendar_version')::integer IS DISTINCT FROM 1
         OR coalesce((item.before_row->>'bus_calendar_version')::integer,1)<>1
       ELSE after_row->'bus_calendar_version' IS DISTINCT FROM item.before_row->'bus_calendar_version' END)
     THEN RAISE EXCEPTION 'Clock persisted calendar differs from planned calendar' USING errcode='23514'; END IF;
     UPDATE pg_temp.pdc_clock_effective_ends SET version=item.version+1,
      scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
      default_duration_minutes=item.duration,effective_end=item.final_end WHERE id=item.id;
     UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,updated_at=clock_timestamp() WHERE booking_id=item.id AND released_at IS NULL;
     IF EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=item.id AND a.released_at IS NULL
      AND (a.scheduled_start_at IS DISTINCT FROM item.final_start OR a.scheduled_end_at IS DISTINCT FROM item.final_end))
     THEN RAISE EXCEPTION 'Clock assignment calendar differs from booking' USING errcode='23514'; END IF;
     IF after_row-ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent']
       IS DISTINCT FROM item.before_row-ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent'] THEN
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
 DROP TABLE pg_temp.pdc_clock_effective_ends;
 IF p_apply AND moved>0 THEN PERFORM public.workshop_bump_revision(); END IF;
 RETURN jsonb_build_object('ok',jsonb_array_length(issues)=0,'clock_at',p_now,'applied',p_apply,'moved_count',moved,'plans',plans,'issues',issues);
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='84af7607bfd0ce9907c89bae8644d5b6',release='#368',note='clock tick - do not interfere',
 updated_at='2026-10-20T10:55:01.195622+00:00'::timestamptz
 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)' AND prosrc_md5='0aaaa15690ca286ed0db87fc72271d5a' AND release='r452';
DELETE FROM pdc_ops.regression_checks WHERE check_name='clock_tick_resaves_per_tick' AND added_in='r452';

DO $p$ DECLARE chk record; BEGIN
 IF NOT (SELECT md5(p.prosrc)='84af7607bfd0ce9907c89bae8644d5b6' AND p.proacl::text||'|'||p.prosecdef::text||'|'||p.provolatile::text||'|'||p.proowner::regrole::text||'|'||coalesce(array_to_string(p.proconfig,'|'),'')='{postgres=X/postgres}|false|v|postgres|search_path=pg_catalog, public|lock_timeout=3s|statement_timeout=120s' FROM pg_proc p WHERE p.oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS TRUE THEN RAISE EXCEPTION 'r452 undo: old clock tick did not land'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r452_pins')::bigint
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)' AND prosrc_md5='84af7607bfd0ce9907c89bae8644d5b6' AND release='#368'
     AND note='clock tick - do not interfere' AND updated_at='2026-10-20T10:55:01.195622+00:00'::timestamptz)<>1 THEN RAISE EXCEPTION 'r452 undo: pin row not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r452') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r452') THEN RAISE EXCEPTION 'r452 undo: r452 rows remain'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO chk;
 IF chk.ok IS NOT TRUE THEN RAISE EXCEPTION 'r452 undo: protected_function_md5s not ok: %', chk.detail; END IF;
 PERFORM set_config('search_path','"$user", public, extensions',true);
END $p$;
