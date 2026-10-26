-- r552 (F166) undo. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Restores the r452 clock tick and the r424 drag version gate. Does not rewrite booking rows.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r552 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r552 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r552 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'fa17068b106bbb9488c257e61d32e483' THEN RAISE EXCEPTION 'r552 undo: clock tick is not the r552 body'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true, p_now timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
 SET lock_timeout TO '3s'
 SET statement_timeout TO '120s'
AS $tick452$
#variable_conflict use_column
DECLARE bay record; item record; component record; predecessor record; block record;
 capacity_context text:=current_setting('pdc.workshop_capacity_manual',true);
 calendar_floors jsonb; rows jsonb; blocks jsonb; plan jsonb; movement jsonb; watermark jsonb;
 proposed timestamptz; finish timestamptz; obstacle timestamptz; floor_at timestamptz;
 delay integer; gap integer; count_changed integer; loop_count integer;
 moved integer:=0; component_moved integer; marks jsonb:='[]'; plans jsonb:='[]'; issues jsonb:='[]';
 state_code text; detail text; after_row jsonb; unavailable_date date; technician uuid; bus_rule jsonb;
 qc_lines jsonb; qc_computed_at timestamptz; qc_gen bigint; qc_global_gen bigint;
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
     -- r452 (F65): a re-time changes no QC line input, but the booking trigger drops the vehicle's QC
     -- line cache, so every later capacity check in this tick rebuilt the lines (about 25 ms each).
     -- Keep the cached set and both generations so it can be put back once the re-save is proven to
     -- have changed only clock fields (see below).
     SELECT c.lines,c.computed_at,e.gen INTO qc_lines,qc_computed_at,qc_gen
      FROM pdc_work_categories_private.qc_operation_lines_cache c
      JOIN pdc_work_categories_private.qc_operation_lines_cache_epoch e ON e.vehicle_id=c.vehicle_id
      WHERE c.vehicle_id=item.vehicle_id;
     SELECT e.gen INTO qc_global_gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
      WHERE e.vehicle_id='00000000-0000-0000-0000-000000000000'::uuid;
     PERFORM set_config('pdc.workshop_capacity_manual',jsonb_build_object('actor',auth.uid(),
      'booking',item.id,'version',item.version,'duration',item.duration)::text,true);
     UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
      default_duration_minutes=item.duration,version=version+1,
      updated_at=clock_timestamp(),updated_by=coalesce(auth.uid(),updated_by) WHERE id=item.id AND version=item.version AND status='planned' AND actual_start_at IS NULL AND deleted_at IS NULL;
     IF NOT FOUND THEN RAISE EXCEPTION 'Clock booking changed' USING errcode='40001'; END IF;
     PERFORM set_config('pdc.workshop_capacity_manual',coalesce(capacity_context,''),true);
     SELECT to_jsonb(b) INTO after_row FROM public.workshop_bookings b WHERE id=item.id;
     -- r452 (F65): QC lines read a booking's vehicle, stage, status, deletion, category, scope and
     -- creation time, never its clock fields. Put the same cached set back only when every other field
     -- is unchanged, this re-save was the only invalidation of the vehicle (generation +1) and no
     -- global invalidation is pending or happened (SKIP LOCKED: an in-flight one leaves it dropped).
     IF qc_lines IS NOT NULL
      AND after_row-ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent']
       IS NOT DISTINCT FROM item.before_row-ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent'] THEN
      INSERT INTO pdc_work_categories_private.qc_operation_lines_cache(vehicle_id,lines,computed_at)
      SELECT item.vehicle_id,qc_lines,qc_computed_at
      WHERE (SELECT e.gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
        WHERE e.vehicle_id=item.vehicle_id FOR SHARE OF e SKIP LOCKED)=qc_gen+1
       AND (SELECT e.gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
        WHERE e.vehicle_id='00000000-0000-0000-0000-000000000000'::uuid FOR SHARE OF e SKIP LOCKED)=qc_global_gen
      ON CONFLICT (vehicle_id) DO NOTHING;
     END IF;
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
     ON CONFLICT(booking_id) DO UPDATE SET accounted_through=greatest(public.workshop_clock_watermarks.accounted_through,excluded.accounted_through),updated_at=clock_timestamp()
     WHERE true;
    END LOOP;
    INSERT INTO public.workshop_clock_status(bay_id,last_checked_at,last_success_at,moved_count)
     SELECT bay_id,p_now,p_now,count(*) FILTER(WHERE changed)::integer FROM pg_temp.clock_linked_plan WHERE component_id=component.component_id AND bay_id IS NOT NULL GROUP BY bay_id
     ON CONFLICT(bay_id) DO UPDATE SET last_checked_at=excluded.last_checked_at,last_success_at=excluded.last_success_at,error_code=NULL,error_detail=NULL,moved_count=excluded.moved_count
     WHERE true;
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
     ON CONFLICT(bay_id) DO UPDATE SET last_checked_at=excluded.last_checked_at,error_code=excluded.error_code,error_detail=excluded.error_detail,moved_count=0
     WHERE true;
   END IF;
  END;
 END LOOP;
 DROP TABLE pg_temp.pdc_clock_effective_ends;
 IF p_apply AND moved>0 THEN PERFORM public.workshop_bump_revision(); END IF;
 RETURN jsonb_build_object('ok',jsonb_array_length(issues)=0,'clock_at',p_now,'applied',p_apply,'moved_count',moved,'plans',plans,'issues',issues);
END $tick452$;

DO $mv$
DECLARE src text; newsrc text;
BEGIN
 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'));
 newsrc:=replace(src,
  $new$ if v_booking.version<>p_expected_version then
  -- r552 (F166): a clock tick may have bumped the version. The open Schedule or drag
  -- still applies when the bay window is unchanged, or has moved by less than 15 minutes.
  -- A real move of the window, a bay change, or a change that was not the clock, is still a conflict.
  if not exists (
    select 1 from public.workshop_clock_history h
    where h.booking_id=p_booking_id
      and (h.before_data->>'version')::integer=p_expected_version
      and coalesce(h.before_data->>'bay_id','') is not distinct from coalesce(v_booking.bay_id::text,'')
      and public.workshop_clock_window_same_552(
        (h.before_data->>'scheduled_start_at')::timestamptz,
        (h.before_data->>'scheduled_end_at')::timestamptz,
        v_booking.scheduled_start_at,
        v_booking.scheduled_end_at)
  ) then
   return jsonb_build_object('ok',false,'error','version_conflict');
  end if;
  v_move_version:=v_booking.version;
 end if;$new$,
  $old$ if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;$old$);
 IF md5(newsrc) IS DISTINCT FROM '1c11423631f21d520b9c2d457df8bfe1' THEN RAISE EXCEPTION 'r552 undo: restored move body is not r424'; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $move424$'||newsrc||'$move424$';
END $mv$;

DROP FUNCTION public.workshop_clock_step_552(timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone, uuid);
DROP FUNCTION public.workshop_clock_window_same_552(timestamp with time zone, timestamp with time zone, timestamp with time zone, timestamp with time zone);

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0aaaa15690ca286ed0db87fc72271d5a', release='r452',
 note='r452: keeps the QC line cache across clock re-times (was 84af7607bfd0ce9907c89bae8644d5b6, #368 clock tick - do not interfere)', updated_at=now()
 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)' AND release='r552';

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='1c11423631f21d520b9c2d457df8bfe1', release='r424',
 note='F38: stopped jobs re-plannable, push-back warn-and-confirm, bay re-order/swap with undo', updated_at=now()
 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)' AND release='r552';

UPDATE pdc_ops.regression_checks SET
 description='The workshop clock tick re-saves no booking that did not change, and if it averages over 3 re-saves per tick in the last 30 min its p95 stays under 500 ms; shows the :00/:30 marks apart from the other minutes',
 check_sql=$chk452$WITH j AS (SELECT jobid FROM cron.job WHERE jobname='staging-workshop-clock-cascade'),
r AS (SELECT d.start_time, extract(epoch FROM d.end_time-d.start_time)*1000 ms,
  extract(minute FROM d.start_time AT TIME ZONE 'Australia/Perth')::integer IN (0,30) mark
  FROM cron.job_run_details d JOIN j ON j.jobid=d.jobid
  WHERE d.start_time>now()-interval '30 minutes' AND d.end_time IS NOT NULL),
h AS (SELECT clock_at, count(*) n,
  count(*) FILTER (WHERE (before_data->>'scheduled_start_at')::timestamptz IS NOT DISTINCT FROM (after_data->>'scheduled_start_at')::timestamptz
   AND (before_data->>'scheduled_end_at')::timestamptz IS NOT DISTINCT FROM (after_data->>'scheduled_end_at')::timestamptz
   AND before_data->'default_duration_minutes' IS NOT DISTINCT FROM after_data->'default_duration_minutes'
   AND before_data->'bay_id' IS NOT DISTINCT FROM after_data->'bay_id') unchanged
  FROM public.workshop_clock_history WHERE clock_at>now()-interval '30 minutes' GROUP BY clock_at),
s AS (SELECT (SELECT count(*) FROM r) runs, coalesce((SELECT sum(n) FROM h),0) resaves, coalesce((SELECT sum(unchanged) FROM h),0) unchanged,
  (SELECT count(*) FROM h) ticks, coalesce((SELECT max(n) FROM h),0) max_n,
  (SELECT to_char(clock_at AT TIME ZONE 'Australia/Perth','HH24:MI') FROM h ORDER BY n DESC, clock_at DESC LIMIT 1) max_at,
  coalesce((SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY ms) FROM r),0) p95,
  (SELECT max(ms) FROM r WHERE mark) mark_max,
  (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY ms) FROM r WHERE NOT mark) other_p95),
a AS (SELECT s.*, round(s.resaves::numeric/greatest(s.runs,1),1) avg_n FROM s)
SELECT a.unchanged=0 AND NOT (a.avg_n>3 AND a.p95>=500) AS ok,
 'last 30 min: '||a.resaves||' bookings re-saved by the tick in '||a.ticks||' of '||a.runs||' ticks (avg '||a.avg_n||' per tick'
 ||CASE WHEN a.max_n>0 THEN ', most '||a.max_n||' at '||a.max_at||' AWST' ELSE '' END||'), '||a.unchanged||' re-saved with nothing changed'
 ||'; tick p95 '||round(a.p95::numeric)||' ms (other minutes p95 '||coalesce(round(a.other_p95::numeric)||' ms','n/a')
 ||', :00/:30 marks max '||coalesce(round(a.mark_max::numeric)||' ms','n/a')||')'
 ||'; limit: no unchanged re-save, and over 3 re-saves per tick only while tick p95 stays under 500 ms'
 ||CASE WHEN a.unchanged>0 THEN '; FAIL: unchanged re-saves' WHEN a.avg_n>3 AND a.p95>=500 THEN '; FAIL: many re-saves and slow ticks'
   WHEN a.avg_n>3 THEN '; WARN: over 3 re-saves per tick (ticks still fast)' ELSE '' END AS detail
FROM a$chk452$
WHERE check_name='clock_tick_resaves_per_tick' AND added_in='r452';

UPDATE pdc_ops.regression_checks SET
 description='workshop_clock_tick ran every minute for the last 30 minutes with p95 under 2 s, and no whole tick failed (lock timeout, deadlock, statement timeout or any error) in the last 24 hours (r402).',
 check_sql=$ticks402$WITH j AS (SELECT jobid FROM cron.job WHERE jobname='staging-workshop-clock-cascade'),
d AS (SELECT d.status, d.start_time, extract(epoch FROM d.end_time-d.start_time)*1000 ms FROM cron.job_run_details d JOIN j ON j.jobid=d.jobid
  WHERE d.start_time>now()-interval '24 hours'),
r AS (SELECT * FROM d WHERE start_time>now()-interval '30 minutes'),
f AS (SELECT * FROM d WHERE status<>'succeeded')
SELECT (SELECT count(*) FROM r)>=25 AND (SELECT count(*) FROM f)=0 AND coalesce((SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY ms) FROM r),0)<2000 AS ok,
 'last 30 min: '||(SELECT count(*) FROM r)||' runs, p95 '||round(coalesce((SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY ms) FROM r),0)::numeric)||' ms, max '||round(coalesce((SELECT max(ms) FROM r),0)::numeric)||' ms; last 24 h: '||(SELECT count(*) FROM d)||' runs, '||(SELECT count(*) FROM f)||' whole-tick failures'
 ||coalesce(' (AWST '||(SELECT string_agg(to_char(f.start_time AT TIME ZONE 'Australia/Perth','DD Mon HH24:MI'),', ' ORDER BY f.start_time) FROM f)||')','') AS detail$ticks402$
WHERE check_name='clock_ticks_recent';

DELETE FROM pdc_ops.regression_checks WHERE check_name='schedule_stale_version_window_552' AND added_in='r552';

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '0aaaa15690ca286ed0db87fc72271d5a' THEN RAISE EXCEPTION 'r552 undo: clock tick did not return to r452'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '1c11423631f21d520b9c2d457df8bfe1' THEN RAISE EXCEPTION 'r552 undo: move did not return to r424'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r552 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r552' OR check_name='schedule_stale_version_window_552') THEN RAISE EXCEPTION 'r552 undo: check remains'; END IF;
 IF to_regprocedure('public.workshop_clock_step_552(timestamptz,timestamptz,timestamptz,timestamptz,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r552 undo: step helper remains'; END IF;
END $p$;
