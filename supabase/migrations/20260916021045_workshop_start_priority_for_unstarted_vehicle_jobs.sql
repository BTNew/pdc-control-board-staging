-- Start is the physical-priority event for this vehicle: its other unstarted
-- bookings follow it, retaining their order and the one-hour handover.
-- Fixed work remains protected. Cyclic range changes use a valid temporary
-- reservation inside one atomic transaction; no constraints are bypassed.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Staging only';
 END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.start_workshop_work_pre_116(
 p_booking_id uuid,p_expected_version integer,p_actual_start_at timestamptz DEFAULT now(),
 p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public SET statement_timeout='120s' AS $function$
#variable_conflict use_column
DECLARE
 v_target public.workshop_bookings%rowtype;
 v_now timestamptz:=date_trunc('minute',statement_timestamp());
 v_end timestamptz; v_start timestamptz; v_blocked_until timestamptz;
 v_before jsonb; v_after jsonb; v_result jsonb; v_revision bigint; v_delta integer;
 v_item record; v_pair record; v_moving record; v_obstacle record; v_apply uuid;
 v_moving_id uuid; v_obstacle_id uuid; v_bay uuid; v_technician uuid; v_date date;
 v_n integer:=0; v_slot_n integer; v_apply_n integer:=0; v_minutes integer; v_final boolean;
 v_namespace text; v_boundary uuid[]; v_current_version integer;
 v_changed jsonb:='[]'::jsonb; v_code text; v_message text; v_error jsonb;
 v_parts_override_required boolean:=false; v_override_reason text; v_override_id uuid; v_initial_before jsonb;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 PERFORM public.workshop_require_version(p_expected_version);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:start:'||p_booking_id::text,0));
 SELECT * INTO v_target FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND OR v_target.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','booking_not_found'); END IF;
 IF v_target.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 IF v_target.status NOT IN('queued','planned') OR v_target.actual_start_at IS NOT NULL THEN
  RETURN jsonb_build_object('ok',false,'error','not_startable');
 END IF;
 IF v_target.bay_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','bay_required'); END IF;
 IF NOT public.workshop_calendar_minute_available(v_now) THEN RETURN jsonb_build_object('ok',false,'error','calendar_unavailable'); END IF;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 v_override_reason:=nullif(btrim(coalesce(p_metadata->>'parts_override_reason','')),'');
 IF EXISTS(SELECT 1 FROM public.workshop_stages s WHERE s.id=v_target.stage_id AND s.is_physical)
   AND NOT public.workshop_parts_ready(v_target.vehicle_id) THEN
  IF v_override_reason IS NULL THEN RETURN jsonb_build_object('ok',false,'error','parts_incomplete_entry'); END IF;
  PERFORM public.require_pdc_role('administrator');
  v_parts_override_required:=true;
 END IF;
 PERFORM public.workshop_lock_resources(v_target.bay_id,NULL);
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.bay_id=v_target.bay_id
   AND b.id<>v_target.id AND b.deleted_at IS NULL AND b.status IN('started','stoppage')) THEN
  RETURN jsonb_build_object('ok',false,'error','bay_already_started');
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.id=v_target.bay_id AND b.stage_id=v_target.stage_id AND b.is_active AND s.active AND s.is_physical) THEN
  RETURN jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station');
 END IF;
 v_minutes:=public.workshop_booking_effective_duration_minutes(p_booking_id);
 IF v_minutes IS NULL OR v_minutes NOT BETWEEN 1 AND 59999 THEN RETURN jsonb_build_object('ok',false,'error','invalid_schedule_interval'); END IF;
 v_end:=public.workshop_add_operational_minutes(v_now,v_minutes);
 v_delta:=CASE WHEN v_now>=v_target.scheduled_start_at
  THEN public.workshop_operational_minutes_between(v_target.scheduled_start_at,v_now)
  ELSE -public.workshop_operational_minutes_between(v_now,v_target.scheduled_start_at) END;

 DROP TABLE IF EXISTS pg_temp.workshop_start_plan;
 CREATE TEMP TABLE workshop_start_plan(
  ordinal bigint PRIMARY KEY,id uuid UNIQUE,vehicle_id uuid,bay_id uuid,stage_id uuid,
  original_start timestamptz,original_end timestamptz,effective_end timestamptz,
  final_start timestamptz,final_end timestamptz,minutes integer,version integer,
  technicians uuid[],movable boolean,changed boolean DEFAULT false,apply_order integer,
  current_start timestamptz,current_end timestamptz,write_count integer DEFAULT 0,
  parked boolean DEFAULT false,initial_snapshot jsonb
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.workshop_start_plan(ordinal,id,vehicle_id,bay_id,stage_id,original_start,original_end,effective_end,
  final_start,final_end,minutes,version,technicians,movable,changed,apply_order)
 SELECT row_number() OVER(ORDER BY CASE WHEN b.id=p_booking_id THEN 0 ELSE 1 END,b.scheduled_start_at,b.id),b.id,b.vehicle_id,b.bay_id,b.stage_id,
  b.scheduled_start_at,b.scheduled_end_at,e.ends,b.scheduled_start_at,e.ends,
  d.minutes,b.version,
  coalesce((SELECT array_agg(DISTINCT a.technician_id ORDER BY a.technician_id)
   FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL),
   CASE WHEN bay.default_technician_id IS NOT NULL THEN ARRAY[bay.default_technician_id] ELSE '{}'::uuid[] END),
  b.status IN('queued','planned') AND b.actual_start_at IS NULL AND NOT b.legacy_ambiguity_quarantined
   AND bay.is_active AND s.active AND b.bay_id IS NOT NULL,false,NULL
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
 -- Materialize each authoritative calculation once per booking; otherwise the
 -- planner can inline and repeat the operation/working-calendar scans.
 CROSS JOIN LATERAL(SELECT public.workshop_booking_effective_duration_minutes(b.id) minutes OFFSET 0) stored
 CROSS JOIN LATERAL(SELECT CASE WHEN b.id<>p_booking_id AND b.status IN('queued','planned') AND b.actual_start_at IS NULL
    THEN coalesce(public.workshop_capacity_duration_minutes(public.workshop_booking_capacity_base_minutes(b.id),b.bay_id),stored.minutes)
    ELSE stored.minutes END minutes OFFSET 0) d
 CROSS JOIN LATERAL(SELECT greatest(b.scheduled_end_at,
   public.workshop_add_operational_minutes(b.scheduled_start_at,stored.minutes),
   CASE WHEN b.status IN('started','stoppage') OR b.actual_start_at IS NOT NULL THEN v_now ELSE b.scheduled_end_at END) ends OFFSET 0) e
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND s.is_physical AND NOT s.is_sublet;
 IF (SELECT count(*) FROM pg_temp.workshop_start_plan)>10000 THEN RETURN jsonb_build_object('ok',false,'error','schedule_too_large'); END IF;
 UPDATE pg_temp.workshop_start_plan SET current_start=original_start,current_end=effective_end;
 UPDATE pg_temp.workshop_start_plan SET final_start=v_now,final_end=v_end,minutes=v_minutes,changed=true,movable=false WHERE id=p_booking_id;

 -- Direct obstacles prevent an actual start now. Never label a future slot as started.
 IF EXISTS(SELECT 1 FROM public.workshop_admin_blocks a WHERE a.bay_id=v_target.bay_id AND a.deleted_at IS NULL
    AND a.scheduled_start_at<v_end AND a.scheduled_end_at>v_now) THEN
  RETURN jsonb_build_object('ok',false,'error','admin_block_conflict','no_partial_save',true);
 END IF;
 IF EXISTS(SELECT 1 FROM generate_series((v_now AT TIME ZONE 'Australia/Perth')::date::timestamp,
     ((v_end-interval '1 microsecond') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
   WHERE public.pdc_sublet_away_on_date(v_target.vehicle_id,d::date)) THEN
  RETURN jsonb_build_object('ok',false,'error','sublet_away','no_partial_save',true);
 END IF;
 FOR v_technician IN SELECT unnest(technicians) FROM pg_temp.workshop_start_plan WHERE id=p_booking_id LOOP
  SELECT p.id INTO v_apply FROM pg_temp.workshop_start_plan p JOIN public.workshop_bookings b ON b.id=p.id
   WHERE p.id<>p_booking_id AND v_technician=ANY(p.technicians) AND b.status IN('started','stoppage')
   ORDER BY p.ordinal LIMIT 1;
  IF v_apply IS NOT NULL THEN
   RETURN jsonb_build_object('ok',false,'error','technician_overlap',
     'blocker',jsonb_build_object('booking_id',v_apply),'no_partial_save',true);
  END IF;
  IF public.workshop_technician_leave_date(v_technician,v_now,v_end) IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM public.workshop_technicians t WHERE t.id=v_technician AND t.active) THEN
   RETURN jsonb_build_object('ok',false,'error','technician_unavailable','no_partial_save',true);
  END IF;
 END LOOP;

 -- Resolve only collisions connected to this start. Forward-only propagation
 -- keeps the rest of the queue stable and includes vehicle and technician links.
 LOOP
  SELECT a.id a_id,b.id b_id,a.ordinal a_ord,b.ordinal b_ord,
    a.movable a_movable,b.movable b_movable,a.vehicle_id=b.vehicle_id same_vehicle,
    a.bay_id=b.bay_id same_bay
  INTO v_pair FROM pg_temp.workshop_start_plan a JOIN pg_temp.workshop_start_plan b ON a.ordinal<b.ordinal
  WHERE (a.changed OR b.changed)
   AND ((a.bay_id=b.bay_id AND a.final_start<b.final_end AND a.final_end>b.final_start)
     OR (a.vehicle_id=b.vehicle_id AND a.final_end+interval '1 hour'>b.final_start)
     OR (a.technicians && b.technicians AND a.final_start<b.final_end AND a.final_end>b.final_start))
  ORDER BY CASE WHEN a.id=p_booking_id OR b.id=p_booking_id THEN 0 ELSE 1 END,a.ordinal,b.ordinal LIMIT 1;
  EXIT WHEN NOT FOUND;
  v_n:=v_n+1;
  IF v_n>20000 THEN RETURN jsonb_build_object('ok',false,'error','schedule_too_large','no_partial_save',true); END IF;
  IF v_pair.same_vehicle THEN
   -- The chosen start is first; all other unstarted work retains its relative order.
   -- Running, stopped or otherwise protected work can never be displaced.
   IF NOT v_pair.b_movable THEN
    RETURN jsonb_build_object('ok',false,'error','vehicle_overlap','blocker',jsonb_build_object('booking_id',v_pair.b_id),'no_partial_save',true);
   END IF;
   v_moving_id:=v_pair.b_id;v_obstacle_id:=v_pair.a_id;
  ELSIF v_pair.a_id=p_booking_id THEN
   IF NOT v_pair.b_movable THEN RETURN jsonb_build_object('ok',false,'error',CASE WHEN v_pair.same_bay THEN 'bay_overlap' ELSE 'technician_overlap' END,'blocker',jsonb_build_object('booking_id',v_pair.b_id),'no_partial_save',true); END IF;
   v_moving_id:=v_pair.b_id;v_obstacle_id:=v_pair.a_id;
  ELSIF v_pair.b_id=p_booking_id THEN
   IF NOT v_pair.a_movable THEN RETURN jsonb_build_object('ok',false,'error',CASE WHEN v_pair.same_bay THEN 'bay_overlap' ELSE 'technician_overlap' END,'blocker',jsonb_build_object('booking_id',v_pair.a_id),'no_partial_save',true); END IF;
   v_moving_id:=v_pair.a_id;v_obstacle_id:=v_pair.b_id;
  ELSIF NOT v_pair.b_movable THEN
   IF NOT v_pair.a_movable THEN RETURN jsonb_build_object('ok',false,'error','fixed_booking_conflict','no_partial_save',true); END IF;
   v_moving_id:=v_pair.a_id;v_obstacle_id:=v_pair.b_id;
  ELSE
   v_moving_id:=v_pair.b_id;v_obstacle_id:=v_pair.a_id;
  END IF;
  SELECT * INTO v_moving FROM pg_temp.workshop_start_plan WHERE id=v_moving_id;
  SELECT * INTO v_obstacle FROM pg_temp.workshop_start_plan WHERE id=v_obstacle_id;
  v_start:=greatest(v_moving.final_start,v_moving.original_start,v_obstacle.final_end+
    CASE WHEN v_moving.vehicle_id=v_obstacle.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END);
  v_slot_n:=0;
  LOOP
   v_slot_n:=v_slot_n+1;
   IF v_slot_n>1000 OR v_start>v_now+interval '730 days' THEN RETURN jsonb_build_object('ok',false,'error','no_available_slot','no_partial_save',true); END IF;
   v_start:=public.workshop_admin_next_operational_minute(v_start);
   v_end:=public.workshop_add_operational_minutes(v_start,v_moving.minutes);
   IF v_start IS NULL OR v_end IS NULL THEN RETURN jsonb_build_object('ok',false,'error','calendar_unavailable','no_partial_save',true); END IF;
   SELECT max(a.scheduled_end_at) INTO v_blocked_until FROM public.workshop_admin_blocks a
    WHERE a.bay_id=v_moving.bay_id AND a.deleted_at IS NULL AND a.scheduled_start_at<v_end AND a.scheduled_end_at>v_start;
   SELECT max(d::date) INTO v_date FROM generate_series((v_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
     ((v_end-interval '1 microsecond') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(v_moving.vehicle_id,d::date);
   IF v_date IS NOT NULL THEN v_blocked_until:=greatest(v_blocked_until,(v_date+1)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
   FOREACH v_technician IN ARRAY v_moving.technicians LOOP
    IF NOT EXISTS(SELECT 1 FROM public.workshop_technicians t WHERE t.id=v_technician AND t.active) THEN RETURN jsonb_build_object('ok',false,'error','technician_unavailable','no_partial_save',true); END IF;
    v_date:=public.workshop_technician_leave_date(v_technician,v_start,v_end);
    IF v_date IS NOT NULL THEN v_blocked_until:=greatest(v_blocked_until,(v_date+1)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
   END LOOP;
   EXIT WHEN v_blocked_until IS NULL;
   v_start:=greatest(v_start+interval '1 minute',v_blocked_until);
  END LOOP;
  UPDATE pg_temp.workshop_start_plan SET final_start=v_start,final_end=v_end,changed=true WHERE id=v_moving_id;
 END LOOP;

 v_namespace:=public.workshop_qa_fixture_namespace(v_target.vehicle_id);
 IF v_namespace IS NOT NULL THEN
  SELECT array_agg(x.id ORDER BY x.id) INTO v_boundary FROM pg_temp.workshop_start_plan x
   WHERE x.changed AND public.workshop_qa_fixture_namespace(x.vehicle_id) IS DISTINCT FROM v_namespace;
  IF cardinality(v_boundary)>0 THEN RETURN jsonb_build_object('ok',false,'error','qa_fixture_boundary_violation',
   'qa_namespace',v_namespace,'non_fixture_booking_ids',to_jsonb(v_boundary),'shifted_booking_ids','[]'::jsonb,'shifted_count',0); END IF;
 END IF;

 -- Lock every affected resource before checking versions and writing.
 FOR v_bay IN SELECT DISTINCT bay_id FROM pg_temp.workshop_start_plan WHERE changed ORDER BY bay_id LOOP
  PERFORM public.workshop_lock_resources(v_bay,NULL);
 END LOOP;
 FOR v_technician IN SELECT DISTINCT unnest(technicians) FROM pg_temp.workshop_start_plan WHERE changed ORDER BY 1 LOOP
  PERFORM public.workshop_lock_resources(NULL,v_technician);
 END LOOP;
 FOR v_item IN SELECT * FROM pg_temp.workshop_start_plan WHERE changed ORDER BY id LOOP
  SELECT version INTO v_current_version FROM public.workshop_bookings WHERE id=v_item.id AND deleted_at IS NULL FOR UPDATE;
  IF v_current_version IS DISTINCT FROM v_item.version THEN RETURN jsonb_build_object('ok',false,'error','version_conflict','no_partial_save',true); END IF;
  PERFORM public.workshop_require_booking_active_vehicle(v_item.id,false);
  UPDATE pg_temp.workshop_start_plan SET initial_snapshot=public.workshop_booking_snapshot(v_item.id) WHERE id=v_item.id;
  IF EXISTS(SELECT 1 FROM public.workshop_admin_blocks a WHERE a.bay_id=v_item.bay_id AND a.deleted_at IS NULL
     AND a.scheduled_start_at<v_item.final_end AND a.scheduled_end_at>v_item.final_start) THEN
   RETURN jsonb_build_object('ok',false,'error','admin_block_conflict','no_partial_save',true);
  END IF;
 END LOOP;


 -- Compute a constraint-safe sequence before any operational write.
 -- Cycles arise when an earlier small job moves behind a long job started now:
 -- each final range can intersect the other's original range.
 DROP TABLE IF EXISTS pg_temp.workshop_start_writes;
 CREATE TEMP TABLE workshop_start_writes(
  sequence_no integer PRIMARY KEY,id uuid,start_at timestamptz,end_at timestamptz,
  expected_version integer,is_final boolean
 ) ON COMMIT DROP;
 LOOP
  EXIT WHEN NOT EXISTS(SELECT 1 FROM pg_temp.workshop_start_plan WHERE changed AND apply_order IS NULL);
  SELECT a.id INTO v_apply FROM pg_temp.workshop_start_plan a WHERE a.changed AND a.apply_order IS NULL
   AND NOT EXISTS(SELECT 1 FROM pg_temp.workshop_start_plan b WHERE b.id<>a.id
    AND (b.bay_id=a.bay_id OR b.vehicle_id=a.vehicle_id OR b.technicians && a.technicians)
    AND a.final_start<b.current_end+CASE WHEN b.vehicle_id=a.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END
    AND a.final_end+CASE WHEN b.vehicle_id=a.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END>b.current_start)
   ORDER BY a.ordinal LIMIT 1;
  v_final:=v_apply IS NOT NULL;
  IF NOT v_final THEN
   -- The target is never staged. Only movable affected work can reserve a
   -- temporary valid slot; fixed jobs keep their exact status and schedule.
   SELECT id INTO v_apply FROM pg_temp.workshop_start_plan
    WHERE changed AND apply_order IS NULL AND movable AND NOT parked ORDER BY ordinal LIMIT 1;
   IF v_apply IS NULL THEN RETURN jsonb_build_object('ok',false,'error','schedule_write_order_blocked','no_partial_save',true); END IF;
   SELECT * INTO v_moving FROM pg_temp.workshop_start_plan WHERE id=v_apply;
   -- Reserve beyond BOTH current and final ranges for every related resource,
   -- so no later final write can collide with this transaction's reservation.
   SELECT greatest(v_now,max(greatest(x.current_end,x.final_end)))+interval '1 hour'
    INTO v_start FROM pg_temp.workshop_start_plan x
    WHERE x.id<>v_apply AND (x.bay_id=v_moving.bay_id OR x.vehicle_id=v_moving.vehicle_id OR x.technicians && v_moving.technicians);
   v_slot_n:=0;
   LOOP
    v_slot_n:=v_slot_n+1;
    IF v_slot_n>1000 OR v_start>v_now+interval '730 days' THEN RETURN jsonb_build_object('ok',false,'error','no_available_slot','no_partial_save',true); END IF;
    v_start:=public.workshop_admin_next_operational_minute(v_start);
    v_end:=public.workshop_add_operational_minutes(v_start,v_moving.minutes);
    IF v_start IS NULL OR v_end IS NULL THEN RETURN jsonb_build_object('ok',false,'error','calendar_unavailable','no_partial_save',true); END IF;
    SELECT max(a.scheduled_end_at) INTO v_blocked_until FROM public.workshop_admin_blocks a
     WHERE a.bay_id=v_moving.bay_id AND a.deleted_at IS NULL AND a.scheduled_start_at<v_end AND a.scheduled_end_at>v_start;
    SELECT max(d::date) INTO v_date FROM generate_series((v_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
      ((v_end-interval '1 microsecond') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
     WHERE public.pdc_sublet_away_on_date(v_moving.vehicle_id,d::date);
    IF v_date IS NOT NULL THEN v_blocked_until:=greatest(v_blocked_until,(v_date+1)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
    FOREACH v_technician IN ARRAY v_moving.technicians LOOP
     v_date:=public.workshop_technician_leave_date(v_technician,v_start,v_end);
     IF v_date IS NOT NULL THEN v_blocked_until:=greatest(v_blocked_until,(v_date+1)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
    END LOOP;
    EXIT WHEN v_blocked_until IS NULL;
    v_start:=greatest(v_start+interval '1 minute',v_blocked_until);
   END LOOP;
  ELSE
   SELECT final_start,final_end INTO v_start,v_end FROM pg_temp.workshop_start_plan WHERE id=v_apply;
  END IF;
  v_apply_n:=v_apply_n+1;
  INSERT INTO pg_temp.workshop_start_writes
   SELECT v_apply_n,id,v_start,v_end,version+write_count,v_final FROM pg_temp.workshop_start_plan WHERE id=v_apply;
  UPDATE pg_temp.workshop_start_plan SET current_start=v_start,current_end=v_end,write_count=write_count+1,
   parked=parked OR NOT v_final,apply_order=CASE WHEN v_final THEN v_apply_n ELSE NULL END WHERE id=v_apply;
 END LOOP;

 BEGIN
  v_initial_before:=public.workshop_booking_snapshot(p_booking_id);
  FOR v_item IN SELECT w.*,p.minutes,p.initial_snapshot FROM pg_temp.workshop_start_writes w
    JOIN pg_temp.workshop_start_plan p ON p.id=w.id ORDER BY w.sequence_no LOOP
   UPDATE public.workshop_bookings SET scheduled_start_at=v_item.start_at,scheduled_end_at=v_item.end_at,
    status=CASE WHEN id=p_booking_id THEN 'started'::public.workshop_booking_status ELSE status END,
    actual_start_at=CASE WHEN id=p_booking_id THEN v_now ELSE actual_start_at END,
    stoppage_reason=CASE WHEN id=p_booking_id THEN NULL ELSE stoppage_reason END,
    stoppage_started_at=CASE WHEN id=p_booking_id THEN NULL ELSE stoppage_started_at END,
    default_duration_minutes=v_item.minutes,updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1
    WHERE id=v_item.id AND version=v_item.expected_version AND deleted_at IS NULL AND status IN('queued','planned');
   IF NOT FOUND THEN RAISE EXCEPTION 'Concurrent queue change' USING errcode='40001'; END IF;
   UPDATE public.workshop_booking_assignments SET scheduled_start_at=v_item.start_at,scheduled_end_at=v_item.end_at,
    updated_at=clock_timestamp() WHERE booking_id=v_item.id AND released_at IS NULL;
   IF v_item.is_final THEN
    v_after:=public.workshop_booking_snapshot(v_item.id);
    PERFORM public.workshop_write_history(v_item.id,CASE WHEN v_item.id=p_booking_id THEN 'start_snapped_to_now' ELSE 'start_cascade_shifted' END,
     v_item.initial_snapshot,v_after,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
       'start_target_id',p_booking_id,'database_clock_start',true,'safe_start_cascade',true,'start_priority',true));
    IF v_item.id<>p_booking_id THEN v_changed:=v_changed||jsonb_build_array(v_item.id); END IF;
   END IF;
  END LOOP;
  v_result:=public.workshop_start_booking(p_booking_id,p_expected_version+1,v_now,
   coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('database_clock_start',true,'safe_start_cascade',true));
  IF NOT coalesce((v_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'Concurrent start change' USING errcode='40001'; END IF;
  IF v_parts_override_required THEN
   INSERT INTO public.workshop_parts_overrides(vehicle_id,booking_id,work_key,intended_stage_id,reason,
    previous_state,resulting_state,approved_by,approved_by_email)
   VALUES(v_target.vehicle_id,v_target.id,'PARTS',v_target.stage_id,v_override_reason,v_initial_before,
    public.workshop_booking_snapshot(v_target.id),auth.uid(),public.current_actor_email()) RETURNING id INTO v_override_id;
  END IF;
  v_revision:=public.workshop_bump_revision();
  RETURN v_result||jsonb_build_object('revision',v_revision,'signed_shift_minutes',v_delta,
   'start_priority',true,'shifted_booking_ids',v_changed,'shifted_count',jsonb_array_length(v_changed),'parts_override_id',v_override_id,'no_partial_save',false);
 EXCEPTION WHEN exclusion_violation OR unique_violation OR check_violation OR SQLSTATE '22023' OR SQLSTATE '40001' THEN
  GET STACKED DIAGNOSTICS v_message=MESSAGE_TEXT;
  v_error:='{}'::jsonb;
  BEGIN v_error:=substring(v_message from '\{.*\}$')::jsonb; EXCEPTION WHEN OTHERS THEN NULL; END;
  v_code:=coalesce(v_error->>'error',v_error->>'code');
  IF v_code NOT IN('bay_overlap','vehicle_overlap','technician_overlap','admin_block_conflict','fixed_booking_conflict',
      'calendar_unavailable','calendar_duration_mismatch','sublet_away','technician_unavailable','version_conflict') OR v_code IS NULL THEN
   v_code:=CASE WHEN SQLSTATE='40001' THEN 'version_conflict' ELSE 'schedule_changed' END;
  END IF;
  RETURN jsonb_build_object('ok',false,'error',v_code,'no_partial_save',true);
 END;
END $function$;

-- The public start wrapper, role checks, serialization and existing ACLs stay in place.
COMMENT ON FUNCTION public.start_workshop_work_pre_116(uuid,integer,timestamptz,jsonb) IS
 'Canonical priority start. Moves same-vehicle unstarted work after the chosen job and cascades conflicting dependents. Preserves fixed work, one-hour handovers, assignments, QC and atomic rollback.';
NOTIFY pgrst,'reload schema';


CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp();
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$;
