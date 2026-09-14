-- Depends on bay configuration and booking capacity duration authority.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
  OR current_setting('app.environment',true)='production'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Capacity replanning is available on staging only.';
 END IF;
END $guard$;

CREATE TABLE public.workshop_capacity_receipts (
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 idempotency_key uuid NOT NULL,
 request jsonb NOT NULL,
 response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(actor_id,idempotency_key)
);
ALTER TABLE public.workshop_capacity_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.workshop_capacity_receipts FROM PUBLIC,anon,authenticated;

-- Internal planner writes only a transaction-local proposed schedule. It never
-- edits bookings, assignments, bays, quotes, history or station revisions.
CREATE OR REPLACE FUNCTION public.workshop_capacity_plan(
 p_stage_code text,p_bay_id uuid,p_efficiency_percent integer,p_floor timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public
SET statement_timeout TO '120s'
AS $function$
#variable_conflict use_column
DECLARE
 item record; vehicle record; v_stage_id uuid; stage text; compact boolean:=p_bay_id IS NULL;
 proposed_start timestamptz; proposed_end timestamptz; blocked_until timestamptz;
 predecessor_end timestamptz; successor_start timestamptz; unavailable_date date;
 technician uuid; n integer; duration integer; applied_n integer:=0; apply_id uuid;
 changes jsonb; warnings jsonb:='[]'; state_hash text; error text;
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
  changed boolean NOT NULL DEFAULT false,apply_order integer,before_row jsonb NOT NULL
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.workshop_capacity_plan
  (ordinal,booking_id,vehicle_id,stage_id,stage_code,bay_id,bay_number,status,original_start,original_end,effective_end,
   original_minutes,minutes,version,final_start,final_end,technicians,movable,target,before_row)
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
  to_jsonb(b)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
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
 -- Preserve the original order for bay, vehicle and technician dependencies.
 -- Compaction only moves selected-station jobs left. Capacity changes extend or
 -- shorten targets in place and move connected planned successors right.
 FOR item IN SELECT * FROM pg_temp.workshop_capacity_plan ORDER BY ordinal LOOP
  SELECT max(x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '5 hours' ELSE interval '0 minutes' END)
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
  SELECT max(x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '5 hours' ELSE interval '0 minutes' END)
   INTO predecessor_end FROM pg_temp.workshop_capacity_plan x WHERE x.ordinal<item.ordinal
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  proposed_start:=greatest(proposed_start,predecessor_end);
  n:=0;
  LOOP
   n:=n+1;
   IF n>1000 OR proposed_start>p_floor+interval '730 days' THEN
    RETURN jsonb_build_object('ok',true,'can_apply',false,'error','no_safe_slot',
      'message','No safe workshop slot was found within the scheduling limit.','changes','[]'::jsonb,'warnings',warnings);
   END IF;
   proposed_start:=public.workshop_admin_next_operational_minute(proposed_start);
   IF proposed_start IS NULL THEN RETURN jsonb_build_object('ok',false,'error','calendar_unavailable'); END IF;
   proposed_end:=public.workshop_add_operational_minutes(proposed_start,duration);
   IF proposed_end IS NULL THEN RETURN jsonb_build_object('ok',false,'error','calendar_unavailable'); END IF;
   SELECT max(a.scheduled_end_at) INTO blocked_until FROM public.workshop_admin_blocks a
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
  IF compact THEN
   SELECT min(x.final_start-CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '5 hours' ELSE interval '0 minutes' END)
    INTO successor_start FROM pg_temp.workshop_capacity_plan x WHERE x.ordinal>item.ordinal
     AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
   IF proposed_start>item.original_start OR proposed_end>coalesce(successor_start,proposed_end) THEN
    warnings:=warnings||jsonb_build_array(jsonb_build_object('booking_id',item.booking_id,
     'message','No safe earlier slot was available; this booking was left in place.'));
    CONTINUE;
   END IF;
  END IF;
  UPDATE pg_temp.workshop_capacity_plan SET final_start=proposed_start,final_end=proposed_end,
    changed=(proposed_start IS DISTINCT FROM item.original_start OR proposed_end IS DISTINCT FROM item.original_end
       OR duration IS DISTINCT FROM item.original_minutes)
   WHERE booking_id=item.booking_id;
 END LOOP;
 -- This catches fixed successors, cross-station handovers and secondary
 -- technicians. Existing unrelated conflicts do not prevent an unrelated edit.
 IF EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan a JOIN pg_temp.workshop_capacity_plan b ON a.ordinal<b.ordinal
   WHERE (a.changed OR b.changed) AND
    ((a.bay_id=b.bay_id AND a.final_end>b.final_start)
     OR (a.vehicle_id=b.vehicle_id AND a.final_end+interval '5 hours'>b.final_start)
     OR (a.technicians && b.technicians AND a.final_end>b.final_start))) THEN
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
  'stock_number',v.stock_number,'stage_code',x.stage_code,'bay_number',x.bay_number,'bay_id',x.bay_id,
  'old_start_at',x.original_start,'old_end_at',x.original_end,'new_start_at',x.final_start,'new_end_at',x.final_end,
  'old_minutes',x.original_minutes,'new_minutes',x.minutes) ORDER BY x.ordinal),'[]') INTO changes
 FROM pg_temp.workshop_capacity_plan x JOIN public.vehicles v ON v.id=x.vehicle_id WHERE x.changed;
 -- Hash the authoritative inputs as well as the proposed result. New bookings,
 -- operation estimates, absences, overrides and settings all invalidate review.
 SELECT md5(jsonb_build_object(
   'rows',(SELECT jsonb_agg(jsonb_build_array(x.before_row,x.minutes) ORDER BY x.ordinal) FROM pg_temp.workshop_capacity_plan x),
   'vehicles',(SELECT jsonb_agg(jsonb_build_array(v.id,v.version,v.visible_on_board,v.current_location,v.location_override,v.eta_to_kewdale,v.lifecycle_state,v.deleted_at) ORDER BY v.id)
      FROM public.vehicles v WHERE EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan x WHERE x.vehicle_id=v.id)),
   'bays',(SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM public.workshop_bays b),
   'settings',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.key) FROM public.workshop_settings s),
   'blocks',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.workshop_admin_blocks a WHERE a.deleted_at IS NULL),
   'assignments',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.workshop_booking_assignments a WHERE a.released_at IS NULL),
   'technicians',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id) FROM public.workshop_technicians t),
   'sublet',(SELECT jsonb_agg(to_jsonb(i) ORDER BY i.booking_id) FROM public.pdc_sublet_booking_instances i WHERE i.status IN('active','returned')),
   'requirements',(SELECT jsonb_agg(to_jsonb(wi) ORDER BY wi.vehicle_id,wi.work_key) FROM public.vehicle_work_items wi
       WHERE EXISTS(SELECT 1 FROM pg_temp.workshop_capacity_plan x WHERE x.vehicle_id=wi.vehicle_id)),
   'stage',stage,'bay',p_bay_id,'percent',p_efficiency_percent,'floor',p_floor,'changes',changes
  )::text) INTO state_hash;
 RETURN jsonb_build_object('ok',true,'can_apply',true,'stage_code',stage,'changes',changes,
  'warnings',warnings,'unchanged_count',(SELECT count(*) FROM pg_temp.workshop_capacity_plan WHERE target AND NOT changed),
  'state_hash',state_hash,'floor',p_floor,'efficiency_percent',p_efficiency_percent);
END $function$;
REVOKE ALL ON FUNCTION public.workshop_capacity_plan(text,uuid,integer,timestamptz) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.replan_workshop_capacity(
 p_stage_code text,p_bay_number integer DEFAULT NULL,p_efficiency_percent integer DEFAULT NULL,
 p_apply boolean DEFAULT false,p_expected_plan_hash text DEFAULT NULL,p_idempotency_key uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public
SET statement_timeout TO '120s'
AS $function$
DECLARE
 stage text; sid uuid; bay uuid; old_percent integer; floor_at timestamptz; epoch bigint;
 plan jsonb; request jsonb; receipt public.workshop_capacity_receipts%rowtype; item record;
 old_snapshot jsonb; new_snapshot jsonb; response jsonb; expected_hash text; count_changed integer:=0;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
  OR current_setting('app.environment',true)='production'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Capacity replanning is available on staging only.';
 END IF;
 PERFORM public.workshop_require_planner_operator();
 IF p_apply IS NULL OR (p_bay_number IS NULL)<>(p_efficiency_percent IS NULL)
  OR (p_efficiency_percent IS NOT NULL AND p_efficiency_percent NOT BETWEEN 10 AND 200) THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_capacity_request');
 END IF;
 stage:=public.workshop_canonical_stage_code(p_stage_code);
 SELECT id INTO sid FROM public.workshop_stages WHERE code=stage AND active AND planner_enabled
  AND is_physical AND NOT is_sublet AND code<>'SUBLET';
 IF sid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','station_unavailable'); END IF;
 IF p_bay_number IS NOT NULL THEN
  SELECT b.id,b.efficiency_percent INTO bay,old_percent FROM public.workshop_bays b
   WHERE b.stage_id=sid AND b.bay_number=p_bay_number AND b.is_active AND NOT b.is_sublet_row;
  IF bay IS NULL THEN RETURN jsonb_build_object('ok',false,'error','bay_unavailable'); END IF;
 END IF;
 request:=jsonb_build_object('stage_code',stage,'bay_number',p_bay_number,'efficiency_percent',p_efficiency_percent,
   'expected_plan_hash',p_expected_plan_hash);
 IF p_apply THEN
  IF p_idempotency_key IS NULL OR p_expected_plan_hash IS NULL THEN
   RETURN jsonb_build_object('ok',false,'error','review_required');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  SELECT * INTO receipt FROM public.workshop_capacity_receipts
   WHERE actor_id=auth.uid() AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
   IF receipt.request IS DISTINCT FROM request THEN RETURN jsonb_build_object('ok',false,'error','idempotency_key_reused'); END IF;
   RETURN receipt.response||jsonb_build_object('replay',true);
  END IF;
  IF p_expected_plan_hash !~ '^[0-9]{10,12}\.[a-f0-9]{32}$' THEN
   RETURN jsonb_build_object('ok',false,'error','stale_preview');
  END IF;
  epoch:=split_part(p_expected_plan_hash,'.',1)::bigint;
  floor_at:=to_timestamp(epoch);
  -- The review reserves no data. Its quarter-hour cutoff is embedded in the
  -- fingerprint, reused on Apply, and rejected once it is in the past.
  IF floor_at<date_trunc('minute',clock_timestamp()) OR floor_at>clock_timestamp()+interval '15 minutes' THEN
   RETURN jsonb_build_object('ok',false,'error','stale_preview','message','Refresh the preview before applying.');
  END IF;
  PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL
   AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE NOWAIT;
  PERFORM 1 FROM public.workshop_bays ORDER BY id FOR UPDATE NOWAIT;
  PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE NOWAIT;
  PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE NOWAIT;
  PERFORM 1 FROM public.workshop_settings ORDER BY key FOR SHARE NOWAIT;
  -- Prevent eligibility, absence and operation inserts from changing the
  -- reviewed input between graph validation and the final booking write.
  -- NOWAIT fails promptly instead of freezing the board behind another edit.
  LOCK TABLE public.vehicles,public.vehicle_work_items,public.workshop_technicians,
   public.pdc_sublet_booking_instances,public.pdc_new_vehicle_reviews,
   public.pdc_authenticated_email_operation_lines,public.pdc_pilbara_service_operations,
   public.vehicle_workshop_line_adjustments,public.pdc_pilbara_service_classification_current,
   public.pdc_pilbara_service_classification_history IN SHARE MODE NOWAIT;
  SELECT b.efficiency_percent INTO old_percent FROM public.workshop_bays b WHERE b.id=bay;
 ELSE
  epoch:=(floor(extract(epoch FROM clock_timestamp())/900)+1)::bigint*900;
  floor_at:=to_timestamp(epoch);
 END IF;
 plan:=public.workshop_capacity_plan(stage,bay,p_efficiency_percent,floor_at);
 IF coalesce((plan->>'ok')::boolean,false) IS NOT TRUE OR coalesce((plan->>'can_apply')::boolean,false) IS NOT TRUE THEN RETURN plan; END IF;
 expected_hash:=epoch::text||'.'||(plan->>'state_hash');
 response:=(plan-'state_hash')||jsonb_build_object('plan_hash',expected_hash,'applied',false);
 IF NOT p_apply THEN RETURN response; END IF;
 IF expected_hash IS DISTINCT FROM p_expected_plan_hash THEN
  RETURN jsonb_build_object('ok',false,'error','stale_preview','message','The schedule changed. Refresh the preview before applying.');
 END IF;
 -- All permanent changes live inside this subtransaction. A failed booking
 -- guard rolls back the bay setting, every prior booking and all history.
 BEGIN
  IF bay IS NOT NULL AND old_percent IS DISTINCT FROM p_efficiency_percent THEN
   UPDATE public.workshop_bays SET efficiency_percent=p_efficiency_percent,version=version+1,
     updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=bay;
  END IF;
  FOR item IN SELECT * FROM pg_temp.workshop_capacity_plan WHERE changed ORDER BY apply_order LOOP
   old_snapshot:=public.workshop_booking_snapshot(item.booking_id);
   UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
    default_duration_minutes=item.minutes,version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
    WHERE id=item.booking_id AND version=item.version AND status::text=item.status AND actual_start_at IS NULL AND deleted_at IS NULL;
   IF NOT FOUND THEN RAISE EXCEPTION 'Booking changed during capacity apply' USING ERRCODE='40001'; END IF;
   UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,updated_at=clock_timestamp()
    WHERE booking_id=item.booking_id AND released_at IS NULL;
   new_snapshot:=public.workshop_booking_snapshot(item.booking_id);
   IF (SELECT to_jsonb(b)-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes',
      'capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes',
      'version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at']
      FROM public.workshop_bookings b WHERE b.id=item.booking_id)
    IS DISTINCT FROM item.before_row-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes',
      'capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes',
      'version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at'] THEN
    RAISE EXCEPTION 'Capacity apply changed protected booking details';
   END IF;
   PERFORM public.workshop_write_history(item.booking_id,CASE WHEN bay IS NULL THEN 'gaps_closed' ELSE 'bay_efficiency_updated' END,
    old_snapshot,new_snapshot,jsonb_build_object('source','workshop_capacity','plan_hash',expected_hash,
      'efficiency_percent',p_efficiency_percent,'buffer_minutes',300));
   count_changed:=count_changed+1;
  END LOOP;
  response:=response||jsonb_build_object('applied',true,'replay',false,'changed_count',count_changed);
  INSERT INTO public.workshop_capacity_receipts(actor_id,idempotency_key,request,response)
   VALUES(auth.uid(),p_idempotency_key,request,response);
 EXCEPTION WHEN check_violation OR exclusion_violation OR invalid_parameter_value OR serialization_failure OR raise_exception THEN
  RETURN jsonb_build_object('ok',false,'error','capacity_apply_rejected',
    'message','The revised schedule could not be saved safely. No changes were saved. Refresh and review the affected bookings.');
 END;
 RETURN response;
END $function$;
REVOKE ALL ON FUNCTION public.replan_workshop_capacity(text,integer,integer,boolean,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replan_workshop_capacity(text,integer,integer,boolean,text,uuid) TO authenticated;
