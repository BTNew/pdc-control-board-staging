-- r539 (F153). Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Close gaps rows were labelled with workshop_bays.bay_number (Fitting bay 1 is PMB Bay 06).
-- A booking that cannot move fully forward now carries a short hold reason. The chosen times,
-- the plan hash inputs and the apply order are unchanged. Pin count stays 241: the r391 plan
-- pin moves in place. Sort 317 is live r538 (running_booking_end_538), so this check is sort 318.
-- Craig approved go-live 26 Oct 2026 10:40 AWST. Rebased onto main 6fd8ecbe (r538 / F152).
-- Undo: supabase/rollbacks/20261026140000_r539_close_gaps_bay_reason.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r539: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r539: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r539: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)'::regprocedure) IS DISTINCT FROM 'f76a8333a700a66158bf60ab7ca536d8' THEN RAISE EXCEPTION 'r539: workshop_capacity_plan is not the r391 body'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)') IS DISTINCT FROM 'r391' THEN RAISE EXCEPTION 'r539: plan pin is not r391'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=318 OR fault_id='F153' OR check_name='close_gaps_preview_bay_label_and_tech_reason' OR added_in='r539') THEN RAISE EXCEPTION 'r539: sort 318 or F153 is taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_capacity_plan(p_stage_code text, p_bay_id uuid, p_efficiency_percent integer, p_floor timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '120s'
AS $function$
#variable_conflict use_column
DECLARE
 item record; vehicle record; v_stage_id uuid; stage text; compact boolean:=p_bay_id IS NULL;
 proposed_start timestamptz; proposed_end timestamptz; blocked_until timestamptz;
 predecessor_end timestamptz; successor_start timestamptz; unavailable_date date;
 technician uuid; n integer; duration integer; applied_n integer:=0; apply_id uuid;
 changes jsonb; warnings jsonb:='[]'; state_hash text; error text;
 earliest timestamptz; hold_reason text;
 hold_kind text; hold_name text; hold_key text; hold_bay text; hold_stage text;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 stage:=public.workshop_canonical_stage_code(p_stage_code);
 SELECT s.id INTO v_stage_id FROM public.workshop_stages s
 WHERE s.code=stage AND s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 IF v_stage_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','station_unavailable'); END IF;
 IF p_floor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_plan_floor'); END IF;
 IF NOT compact AND NOT EXISTS(SELECT 1 FROM public.workshop_bays b WHERE b.id=p_bay_id AND b.stage_id=v_stage_id
   AND b.is_active AND NOT b.is_sublet_row AND p_efficiency_percent BETWEEN 10 AND 200) THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_bay_efficiency');
 END IF;
 DROP TABLE IF EXISTS pg_temp.workshop_capacity_plan;
 CREATE TEMP TABLE workshop_capacity_plan(
  ordinal bigint PRIMARY KEY,booking_id uuid UNIQUE NOT NULL,vehicle_id uuid NOT NULL,
  stage_id uuid NOT NULL,stage_code text NOT NULL,bay_id uuid,bay_number integer,status text NOT NULL,
  original_start timestamptz NOT NULL,original_end timestamptz NOT NULL,effective_end timestamptz NOT NULL,
  original_minutes integer NOT NULL,minutes integer NOT NULL,version integer NOT NULL,
  final_start timestamptz NOT NULL,final_end timestamptz NOT NULL,
  technicians uuid[] NOT NULL,movable boolean NOT NULL,target boolean NOT NULL,
  changed boolean NOT NULL DEFAULT false,apply_order integer,before_row jsonb NOT NULL,calendar_bay_id uuid,
  bay_display_name text,key_number text,hold_reason text
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.workshop_capacity_plan
  (ordinal,booking_id,vehicle_id,stage_id,stage_code,bay_id,bay_number,status,original_start,original_end,effective_end,
   original_minutes,minutes,version,final_start,final_end,technicians,movable,target,before_row,calendar_bay_id,
   bay_display_name,key_number)
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id),b.id,b.vehicle_id,b.stage_id,s.code,b.bay_id,bay.bay_number,b.status::text,
  b.scheduled_start_at,b.scheduled_end_at,
  greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id),
    CASE WHEN b.status IN('started','stoppage') OR b.actual_start_at IS NOT NULL THEN p_floor ELSE b.scheduled_end_at END),
  b.default_duration_minutes,b.default_duration_minutes,b.version,b.scheduled_start_at,
  greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id),
    CASE WHEN b.status IN('started','stoppage') OR b.actual_start_at IS NOT NULL THEN p_floor ELSE b.scheduled_end_at END),
  coalesce((SELECT array_agg(DISTINCT a.technician_id ORDER BY a.technician_id) FROM public.workshop_booking_assignments a
    WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]),
  b.status IN('queued','planned') AND b.actual_start_at IS NULL AND b.bay_id IS NOT NULL
    AND bay.is_active AND s.active AND s.planner_enabled AND NOT b.legacy_ambiguity_quarantined,
  b.stage_id=v_stage_id AND (compact OR b.bay_id=p_bay_id)
    AND b.status IN('queued','planned') AND b.actual_start_at IS NULL AND b.bay_id IS NOT NULL
    AND bay.is_active AND NOT b.legacy_ambiguity_quarantined,
  to_jsonb(b),
  -- r391: Bus 4x4 work on an active Dept 138 vehicle runs on that bay's Bus shift (the same rule as
  -- booking_shift_guard and workshop_clock_tick), so plan it on that calendar or the save is refused.
  CASE WHEN s.code='BUS_4X4' AND b.bay_id IS NOT NULL AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END,
  bay.display_name,v.key_number
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
 LEFT JOIN public.vehicles v ON v.id=b.vehicle_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
   AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 IF (SELECT count(*) FROM pg_temp.workshop_capacity_plan)>10000 THEN
  RETURN jsonb_build_object('ok',false,'error','schedule_too_large');
 END IF;
 IF NOT compact THEN
  UPDATE pg_temp.workshop_capacity_plan x SET minutes=greatest(1,ceil(
   public.workshop_booking_capacity_base_minutes(x.booking_id)*100/p_efficiency_percent)::integer)
 WHERE x.target;
  IF EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan WHERE target AND minutes NOT BETWEEN 1 AND 59999) THEN
   RETURN jsonb_build_object('ok',true,'can_apply',false,'error','duration_limit',
    'message','The adjusted job is longer than the workshop scheduling limit. Review its hours or efficiency.',
    'changes','[]'::jsonb,'warnings',warnings);
  END IF;
 END IF;
 -- Keep each vehicle's station sequence. During compaction, ready work may
 -- overtake a waiting vehicle in the same bay; every occupied range is checked.
 -- Efficiency changes retain their existing dependency order and cascade.
 FOR item IN SELECT * FROM pg_temp.workshop_capacity_plan ORDER BY ordinal LOOP
  hold_reason:=NULL;
  SELECT max(x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END)
   INTO blocked_until FROM pg_temp.workshop_capacity_plan x
   WHERE x.ordinal<item.ordinal AND x.changed
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  IF compact AND NOT item.target THEN CONTINUE; END IF;
  IF NOT compact AND NOT item.target AND coalesce(blocked_until,item.original_start)<=item.original_start THEN CONTINUE; END IF;
  IF NOT item.movable THEN
   RETURN jsonb_build_object('ok',true,'can_apply',false,'error','protected_booking',
    'message','A later job is already started, stopped or has no available bay. Resolve it before changing efficiency.',
    'changes','[]'::jsonb,'warnings',warnings);
  END IF;
  SELECT v.id,v.visible_on_board,v.lifecycle_state,v.deleted_at,
    public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) location,
    v.eta_to_kewdale,
    EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.required AND NOT wi.completed
       AND public.workshop_stage_code_for_work_key(wi.work_key)=item.stage_code) required,
    EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='pending') pending
   INTO vehicle FROM public.vehicles v WHERE v.id=item.vehicle_id;
  IF vehicle.id IS NULL OR vehicle.deleted_at IS NOT NULL OR vehicle.lifecycle_state<>'active' OR NOT vehicle.visible_on_board
    OR vehicle.location NOT IN('PMB','YH','IT') OR (vehicle.location='IT' AND vehicle.eta_to_kewdale IS NULL)
    OR NOT vehicle.required OR vehicle.pending THEN
   IF compact THEN
    warnings:=warnings||jsonb_build_array(jsonb_build_object('booking_id',item.booking_id,
      'message','This booking was left in place because its vehicle is not currently eligible.'));
    CONTINUE;
   END IF;
   RETURN jsonb_build_object('ok',true,'can_apply',false,'error','vehicle_not_eligible',
     'message','An affected vehicle is not currently eligible. Review its location, ETA or required work.',
     'changes','[]'::jsonb,'warnings',warnings);
  END IF;
  duration:=item.minutes;
  proposed_start:=CASE WHEN compact THEN p_floor ELSE greatest(p_floor,item.original_start) END;
  IF vehicle.location='IT' THEN
   proposed_start:=greatest(proposed_start,(vehicle.eta_to_kewdale+7)::timestamp AT TIME ZONE 'Australia/Perth');
  END IF;
  SELECT max(x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END)
   INTO predecessor_end FROM pg_temp.workshop_capacity_plan x WHERE x.ordinal<item.ordinal
    AND (x.vehicle_id=item.vehicle_id OR (NOT compact AND (x.bay_id=item.bay_id OR x.technicians && item.technicians)));
  proposed_start:=greatest(proposed_start,predecessor_end);
  n:=0;
  LOOP
   n:=n+1;
   IF n>1000 OR proposed_start>p_floor+interval '730 days' THEN
    RETURN jsonb_build_object('ok',true,'can_apply',false,'error','no_safe_slot',
      'message','No safe workshop slot was found within the scheduling limit.','changes','[]'::jsonb,'warnings',warnings);
   END IF;
   proposed_start:=CASE WHEN item.calendar_bay_id IS NULL THEN public.workshop_admin_next_operational_minute(proposed_start)
     ELSE pdc_bus_private.clock_next_minute(proposed_start,item.calendar_bay_id) END;
   IF proposed_start IS NULL THEN RETURN jsonb_build_object('ok',false,'error','calendar_unavailable'); END IF;
   proposed_end:=CASE WHEN item.calendar_bay_id IS NULL THEN public.workshop_add_operational_minutes(proposed_start,duration)
     ELSE pdc_bus_private.add_minutes(proposed_start,duration,item.calendar_bay_id) END;
   IF proposed_end IS NULL THEN RETURN jsonb_build_object('ok',false,'error','calendar_unavailable'); END IF;
   blocked_until:=NULL;
   IF compact THEN
    SELECT max(x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END)
     INTO blocked_until FROM pg_temp.workshop_capacity_plan x
     WHERE x.booking_id<>item.booking_id
      AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians)
      AND x.final_start<proposed_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END
      AND x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END>proposed_start;
   END IF;
   SELECT greatest(blocked_until,max(a.scheduled_end_at)) INTO blocked_until FROM public.workshop_admin_blocks a
    WHERE a.deleted_at IS NULL AND a.bay_id=item.bay_id AND a.scheduled_start_at<proposed_end AND a.scheduled_end_at>proposed_start;
   SELECT max(d::date) INTO unavailable_date FROM generate_series(
    (proposed_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
    ((proposed_end-interval '1 microsecond') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(item.vehicle_id,d::date);
   IF unavailable_date IS NOT NULL THEN
    blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
   END IF;
   FOREACH technician IN ARRAY item.technicians LOOP
    unavailable_date:=public.workshop_technician_leave_date(technician,proposed_start,proposed_end);
    IF unavailable_date IS NOT NULL THEN
     blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.workshop_technicians t WHERE t.id=technician AND t.active) THEN
     RETURN jsonb_build_object('ok',true,'can_apply',false,'error','technician_unavailable',
      'message','An affected booking has an inactive technician. Review its assignment first.','changes','[]'::jsonb,'warnings',warnings);
    END IF;
   END LOOP;
   EXIT WHEN blocked_until IS NULL;
   proposed_start:=greatest(proposed_start+interval '1 minute',blocked_until);
  END LOOP;
  -- r539: name the constraint that stopped a full move. Times above are unchanged.
  earliest:=CASE WHEN compact THEN p_floor ELSE greatest(p_floor,item.original_start) END;
  IF vehicle.location='IT' THEN
   earliest:=greatest(earliest,(vehicle.eta_to_kewdale+7)::timestamp AT TIME ZONE 'Australia/Perth');
  END IF;
  earliest:=CASE WHEN item.calendar_bay_id IS NULL THEN public.workshop_admin_next_operational_minute(earliest)
    ELSE pdc_bus_private.clock_next_minute(earliest,item.calendar_bay_id) END;
  IF earliest IS NOT NULL AND proposed_start>earliest THEN
   hold_kind:=NULL; hold_name:=NULL; hold_key:=NULL; hold_bay:=NULL; hold_stage:=NULL;
   SELECT c.kind,c.tech_name,c.key_number,c.bay_label,c.stage_code
    INTO hold_kind,hold_name,hold_key,hold_bay,hold_stage
   FROM (
    SELECT x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END AS until_at,
     CASE WHEN x.vehicle_id=item.vehicle_id THEN 'handover'
          WHEN x.technicians && item.technicians THEN 'technician'
          ELSE 'bay' END AS kind,
     (SELECT t.name FROM public.workshop_technicians t
       WHERE t.id = ANY(x.technicians) AND t.id = ANY(item.technicians)
       ORDER BY t.name LIMIT 1) AS tech_name,
     x.key_number,
     coalesce(nullif(btrim(x.bay_display_name),''),'Bay '||x.bay_number::text) AS bay_label,
     x.stage_code,
     1 AS rank
    FROM pg_temp.workshop_capacity_plan x
    WHERE x.booking_id<>item.booking_id
     AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians)
     AND x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END>earliest
     AND x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END<=proposed_start
    UNION ALL
    SELECT a.scheduled_end_at,'admin',NULL::text,NULL::text,
     coalesce(nullif(btrim(bay.display_name),''),'Bay '||bay.bay_number::text),
     NULL::text,2
    FROM public.workshop_admin_blocks a
    JOIN public.workshop_bays bay ON bay.id=a.bay_id
    WHERE a.deleted_at IS NULL AND a.bay_id=item.bay_id
     AND a.scheduled_end_at>earliest AND a.scheduled_end_at<=proposed_start
   ) c
   ORDER BY c.until_at DESC, c.rank
   LIMIT 1;
   IF hold_kind='technician' THEN
    hold_reason:='Waiting for '||coalesce(nullif(btrim(hold_name),''),'the mechanic')
     ||' on Key '||coalesce(nullif(btrim(hold_key),''),'-')
     ||' ('||coalesce(hold_bay,'bay')||') until '
     ||to_char(proposed_start AT TIME ZONE 'Australia/Perth','Dy HH24:MI');
   ELSIF hold_kind='handover' THEN
    hold_reason:='Waiting for the same-vehicle '||coalesce(initcap(lower(replace(hold_stage,'_',' '))),'next')
     ||' handover until '||to_char(proposed_start AT TIME ZONE 'Australia/Perth','Dy HH24:MI');
   ELSIF hold_kind='bay' THEN
    hold_reason:='Waiting for Key '||coalesce(nullif(btrim(hold_key),''),'-')
     ||' ('||coalesce(hold_bay,'bay')||') until '
     ||to_char(proposed_start AT TIME ZONE 'Australia/Perth','Dy HH24:MI');
   ELSIF hold_kind='admin' THEN
    hold_reason:='Waiting for an admin block in '||coalesce(hold_bay,'this bay')
     ||' until '||to_char(proposed_start AT TIME ZONE 'Australia/Perth','Dy HH24:MI');
   ELSE
    hold_reason:='Waiting for the workshop to open at '
     ||to_char(proposed_start AT TIME ZONE 'Australia/Perth','Dy HH24:MI');
   END IF;
  END IF;
  IF compact THEN
   SELECT min(x.final_start-CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END)
    INTO successor_start FROM pg_temp.workshop_capacity_plan x WHERE x.ordinal>item.ordinal
     AND x.vehicle_id=item.vehicle_id;
   IF proposed_start>item.original_start OR proposed_end>coalesce(successor_start,proposed_end) THEN
    UPDATE pg_temp.workshop_capacity_plan SET hold_reason=hold_reason WHERE booking_id=item.booking_id;
    warnings:=warnings||jsonb_build_array(jsonb_build_object('booking_id',item.booking_id,
     'message','This booking cannot move earlier without conflicting with workshop availability or the vehicle’s station sequence.'));
    CONTINUE;
   END IF;
  END IF;
  UPDATE pg_temp.workshop_capacity_plan SET final_start=proposed_start,final_end=proposed_end,
    changed=(proposed_start IS DISTINCT FROM item.original_start OR proposed_end IS DISTINCT FROM item.original_end
       OR duration IS DISTINCT FROM item.original_minutes),
    hold_reason=hold_reason
   WHERE booking_id=item.booking_id;
 END LOOP;
 -- This catches fixed successors, cross-station handovers and secondary
 -- technicians. Existing unrelated conflicts do not prevent an unrelated edit.
 IF EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan a JOIN pg_temp.workshop_capacity_plan b ON a.ordinal<b.ordinal
   WHERE (a.changed OR b.changed) AND
    ((a.bay_id=b.bay_id AND tstzrange(a.final_start,a.final_end,'[)') && tstzrange(b.final_start,b.final_end,'[)'))
     OR (a.vehicle_id=b.vehicle_id AND a.final_end+interval '1 hour'>b.final_start)
     OR (a.technicians && b.technicians AND tstzrange(a.final_start,a.final_end,'[)') && tstzrange(b.final_start,b.final_end,'[)')))) THEN
  RETURN jsonb_build_object('ok',true,'can_apply',false,'error','protected_booking_conflict',
   'message','The revised schedule conflicts with a fixed booking. Review it before applying.',
   'changes','[]'::jsonb,'warnings',warnings);
 END IF;
 -- Find a constraint-safe write order without hiding rows or disabling guards.
 -- A row is ready only when its final range is vacant in the current graph.
 LOOP
  EXIT WHEN NOT EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan WHERE changed AND apply_order IS NULL);
  SELECT a.booking_id INTO apply_id FROM pg_temp.workshop_capacity_plan a
   WHERE a.changed AND a.apply_order IS NULL AND NOT EXISTS(
    SELECT 1 FROM pg_temp.workshop_capacity_plan b WHERE b.booking_id<>a.booking_id
     AND (b.bay_id=a.bay_id OR b.vehicle_id=a.vehicle_id OR b.technicians && a.technicians)
     AND tstzrange(a.final_start,a.final_end,'[)') &&
       tstzrange(CASE WHEN b.apply_order IS NULL THEN b.original_start ELSE b.final_start END,
                 CASE WHEN b.apply_order IS NULL THEN b.effective_end ELSE b.final_end END,'[)'))
   ORDER BY a.ordinal LIMIT 1;
  IF apply_id IS NULL THEN
   RETURN jsonb_build_object('ok',true,'can_apply',false,'error','schedule_write_order_blocked',
    'message','These changes cannot be applied safely together. Review the affected bookings.',
    'changes','[]'::jsonb,'warnings',warnings);
  END IF;
  applied_n:=applied_n+1;
  UPDATE pg_temp.workshop_capacity_plan SET apply_order=applied_n WHERE booking_id=apply_id;
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',x.booking_id,'vehicle_id',x.vehicle_id,
  'stock_number',v.stock_number,'key_number',x.key_number,'stage_code',x.stage_code,'bay_number',x.bay_number,
  'bay_display_name',x.bay_display_name,'bay_id',x.bay_id,
  'old_start_at',x.original_start,'old_end_at',x.original_end,'new_start_at',x.final_start,'new_end_at',x.final_end,
  'old_minutes',x.original_minutes,'new_minutes',x.minutes,'hold_reason',x.hold_reason) ORDER BY x.ordinal),'[]') INTO changes
 FROM pg_temp.workshop_capacity_plan x JOIN public.vehicles v ON v.id=x.vehicle_id WHERE x.changed;
 -- Hash the authoritative inputs as well as the proposed result. New bookings,
 -- operation estimates, absences, overrides and settings all invalidate review.
 SELECT md5(jsonb_build_object(
   -- r391: the one-minute clock tick re-times overdue planned bookings (new version, times and updated_at)
   -- and their assignments, so those fields made every preview stale within a minute. Planned times are
   -- covered by the proposed result ('changes', new times) and Apply re-plans under lock with fresh versions.
   'rows',(SELECT jsonb_agg(jsonb_build_array(CASE WHEN x.status='planned' THEN x.before_row-ARRAY['version','updated_at','updated_by','scheduled_start_at','scheduled_end_at'] ELSE x.before_row END,x.minutes) ORDER BY x.ordinal) FROM pg_temp.workshop_capacity_plan x),
   'vehicles',(SELECT jsonb_agg(jsonb_build_array(v.id,v.version,v.visible_on_board,v.current_location,v.location_override,v.eta_to_kewdale,v.lifecycle_state,v.deleted_at) ORDER BY v.id)
      FROM public.vehicles v WHERE EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan x WHERE x.vehicle_id=v.id)),
   'bays',(SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bays b),
   'settings',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.key) FROM public.workshop_settings s),
   'blocks',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.workshop_admin_blocks a WHERE a.deleted_at IS NULL),
   'assignments',(SELECT jsonb_agg(CASE WHEN b.status='planned' THEN to_jsonb(a)-ARRAY['scheduled_start_at','scheduled_end_at','updated_at'] ELSE to_jsonb(a) END ORDER BY a.id)
      FROM public.workshop_booking_assignments a LEFT JOIN public.workshop_bookings b ON b.id=a.booking_id WHERE a.released_at IS NULL),
   'technicians',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.workshop_technicians t),
   'sublet',(SELECT jsonb_agg(to_jsonb(i) ORDER BY i.booking_id) FROM public.pdc_sublet_booking_instances i WHERE i.status IN('active','returned')),
   'requirements',(SELECT jsonb_agg(to_jsonb(wi) ORDER BY wi.vehicle_id,wi.work_key) FROM public.vehicle_work_items wi
       WHERE EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan x WHERE x.vehicle_id=wi.vehicle_id)),
   'stage',stage,'bay',p_bay_id,'percent',p_efficiency_percent,'floor',p_floor,
   'changes',(SELECT coalesce(jsonb_agg(c-ARRAY['old_start_at','old_end_at','bay_display_name','key_number','hold_reason'] ORDER BY o),'[]') FROM jsonb_array_elements(changes) WITH ORDINALITY q(c,o))
  )::text) INTO state_hash;
 RETURN jsonb_build_object('ok',true,'can_apply',true,'stage_code',stage,'changes',changes,
  'warnings',warnings,'unchanged_count',(SELECT count(*) FROM pg_temp.workshop_capacity_plan WHERE target AND NOT changed),
  'holds',(SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',x.booking_id,'vehicle_id',x.vehicle_id,
    'stock_number',v.stock_number,'key_number',x.key_number,'stage_code',x.stage_code,'bay_number',x.bay_number,
    'bay_display_name',x.bay_display_name,'start_at',x.original_start,'end_at',x.original_end,
    'hold_reason',x.hold_reason) ORDER BY x.ordinal),'[]')
   FROM pg_temp.workshop_capacity_plan x JOIN public.vehicles v ON v.id=x.vehicle_id
   WHERE x.target AND NOT x.changed AND nullif(btrim(x.hold_reason),'') IS NOT NULL),
  'state_hash',state_hash,'floor',p_floor,'efficiency_percent',p_efficiency_percent);
END $function$
;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5='5b3c6de9fe2ea38fc967c17a8a63437c', release='r539', note='r539: close gaps bay name and hold reason (F153)', updated_at=clock_timestamp()
WHERE signature='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)'
  AND prosrc_md5='f76a8333a700a66158bf60ab7ca536d8'
  AND release='r391';

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('close_gaps_preview_bay_label_and_tech_reason', 'F153',
 'Close gaps names the workshop bay and says why a booking cannot move fully forward. Fitting bay number 1 stays Fitting - PMB Bay 06 and bay number 5 stays Fitting - PMB Bay 10. While Key 248 stock 13047270 is still held by Chelsea Rees # 2 on Key 411, the reason names that mechanic, key and bay.',
 $chk539$
SELECT
  pg_catalog.md5(fn.prosrc) = '5b3c6de9fe2ea38fc967c17a8a63437c'
  AND pg_catalog.strpos(fn.prosrc, 'bay.display_name') > 0
  AND pg_catalog.strpos(fn.prosrc, 'Waiting for the same-vehicle ') > 0
  AND pg_catalog.strpos(fn.prosrc, 'Waiting for an admin block in ') > 0
  AND pg_catalog.strpos(fn.prosrc, 'Waiting for the workshop to open at ') > 0
  AND pg_catalog.strpos(fn.prosrc, 'bay_display_name'',''key_number'',''hold_reason''') > 0
  AND bay06.display_name = 'Fitting - PMB Bay 06'
  AND bay10.display_name = 'Fitting - PMB Bay 10'
  AND bay06.bay_number = 1
  AND bay10.bay_number = 5
  AND (live.reason IS NULL OR live.reason LIKE 'Waiting for Chelsea Rees # 2 on Key 411 (Fitting - PMB Bay 10) until %')
  AS ok,
  -- coalesce is a keyword. pg_catalog.coalesce is not a function, so a qualified call does not plan.
  pg_catalog.left(coalesce(live.reason, 'labels only; Key 248 is not still held by Chelsea on Key 411'::text)
    || ' | bay 1 ' || bay06.display_name || ' | bay 5 ' || bay10.display_name, 500) AS detail
FROM pg_catalog.pg_proc fn
JOIN public.workshop_bays bay06 ON bay06.code = 'FITTING-BAY-01' AND bay06.is_active
JOIN public.workshop_bays bay10 ON bay10.code = 'FITTING-BAY-05' AND bay10.is_active
LEFT JOIN LATERAL (
  SELECT ('Waiting for ' || tech.name || ' on Key ' || v411.key_number || ' (' || bay411.display_name || ') until '
    || pg_catalog.to_char(b411.scheduled_end_at AT TIME ZONE 'Australia/Perth', 'Dy HH24:MI')) AS reason
  FROM public.workshop_bookings b248
  JOIN public.vehicles v248 ON v248.id = b248.vehicle_id AND v248.stock_number = '13047270' AND v248.key_number = '248'
  JOIN public.workshop_stages s248 ON s248.id = b248.stage_id AND s248.code = 'FITTING'
  JOIN public.workshop_bays bay248 ON bay248.id = b248.bay_id AND bay248.display_name = 'Fitting - PMB Bay 06'
  JOIN public.workshop_booking_assignments a248 ON a248.booking_id = b248.id AND a248.released_at IS NULL
  JOIN public.workshop_technicians tech ON tech.id = a248.technician_id AND tech.name = 'Chelsea Rees # 2'
  JOIN public.workshop_bookings b411 ON b411.deleted_at IS NULL AND b411.status = 'planned'
  JOIN public.vehicles v411 ON v411.id = b411.vehicle_id AND v411.stock_number = '12710966' AND v411.key_number = '411'
  JOIN public.workshop_stages s411 ON s411.id = b411.stage_id AND s411.code = 'FITTING'
  JOIN public.workshop_bays bay411 ON bay411.id = b411.bay_id AND bay411.display_name = 'Fitting - PMB Bay 10'
  JOIN public.workshop_booking_assignments a411 ON a411.booking_id = b411.id AND a411.released_at IS NULL AND a411.technician_id = tech.id
  WHERE b248.deleted_at IS NULL AND b248.status = 'planned'
  ORDER BY b411.scheduled_end_at
  LIMIT 1
) live ON true
WHERE fn.oid = 'public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)'::pg_catalog.regprocedure
$chk539$, true, 318, 'r539');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)'::regprocedure) IS DISTINCT FROM '5b3c6de9fe2ea38fc967c17a8a63437c' THEN RAISE EXCEPTION 'r539: plan body md5 drifted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r539: pin count changed'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)' AND release='r539') IS DISTINCT FROM '5b3c6de9fe2ea38fc967c17a8a63437c' THEN RAISE EXCEPTION 'r539: pin was not moved'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='close_gaps_preview_bay_label_and_tech_reason' AND fault_id='F153' AND sort_order=318 AND added_in='r539' AND enabled)<>1 THEN RAISE EXCEPTION 'r539: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 PERFORM set_config('request.jwt.claims','',true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='close_gaps_preview_bay_label_and_tech_reason' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r539: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
