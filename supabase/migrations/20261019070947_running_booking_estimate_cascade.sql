-- STAGING ONLY. Extend running PMG work without moving its start or resetting progress.
DO $guard$ BEGIN IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF; END $guard$;

DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)'::regprocedure),chr(13),'')) <> 'eb045940ed19c9ce829be0c899ecb8ed' THEN RAISE EXCEPTION 'source_version_changed: reconcile_estimate_bookings_20261018'; END IF; END $guard$;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.reconcile_estimate_bookings_20261018(p_vehicle_id uuid, p_stage_codes text[], p_change_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '120s'
AS $function$
#variable_conflict use_column
<<plan>>
DECLARE
 item record; prior record; n integer; minutes integer; proposed_start timestamptz;
 proposed_end timestamptz; blocked_until timestamptz; unavailable_date date;
 old_snapshot jsonb; new_snapshot jsonb; receipt jsonb:='[]'; changed boolean;
 root_change boolean; technician uuid; validation jsonb; graph_count integer;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Operation approval is available on staging only.';
 END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.bay_id IS NOT NULL
    AND b.status IN('queued','planned','started','stoppage') AND s.code=ANY(p_stage_codes)
    AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET') THEN
  RETURN jsonb_build_object('bookings',receipt,'changed_count',0,'extended_count',0,'moved_count',0,'buffer_minutes',60);
 END IF;
 -- These are the same rows written by the existing planner. Preserve its guards
 -- and immediate overlap constraints; never hide or temporarily delete a job.
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL
  AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE NOWAIT;
 DROP TABLE IF EXISTS pg_temp.pdc_tune_cascade_plan;
 CREATE TEMP TABLE pdc_tune_cascade_plan(
  ordinal bigint PRIMARY KEY,booking_id uuid UNIQUE NOT NULL,vehicle_id uuid NOT NULL,
  stage_id uuid NOT NULL,stage_code text NOT NULL,bay_id uuid,status text NOT NULL,
  original_start timestamptz NOT NULL,original_end timestamptz NOT NULL,
  original_minutes integer NOT NULL,minutes integer NOT NULL,version integer NOT NULL,
  final_start timestamptz NOT NULL,final_end timestamptz NOT NULL,
  technicians uuid[] NOT NULL,root_change boolean NOT NULL DEFAULT false,
  changed boolean NOT NULL DEFAULT false,before_row jsonb NOT NULL
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.pdc_tune_cascade_plan
  (ordinal,booking_id,vehicle_id,stage_id,stage_code,bay_id,status,original_start,original_end,
   original_minutes,minutes,version,final_start,final_end,technicians,before_row)
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id),b.id,b.vehicle_id,b.stage_id,s.code,b.bay_id,b.status::text,
  b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,b.default_duration_minutes,b.version,
  b.scheduled_start_at,b.scheduled_end_at,
  coalesce((SELECT array_agg(DISTINCT a.technician_id) FROM public.workshop_booking_assignments a
    WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]),to_jsonb(b)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.bay_id IS NOT NULL
  AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 SELECT count(*) INTO graph_count FROM pg_temp.pdc_tune_cascade_plan;
 IF graph_count>10000 THEN RAISE EXCEPTION 'The workshop queue needs a smaller scheduling review.'
  USING DETAIL='operation_schedule_limit'; END IF;
 -- Category bookings use their own current work estimate; legacy bookings retain whole-station scope.
 -- Never manufacture a booking for a newly required, unbooked station.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan
  WHERE vehicle_id=p_vehicle_id AND stage_code=ANY(p_stage_codes) AND stage_code<>'BUS_4X4' AND bay_id IS NOT NULL AND status IN('planned','started','stoppage') ORDER BY ordinal
 LOOP
  IF EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan x
    JOIN public.workshop_bookings other_booking ON other_booking.id=x.booking_id
    JOIN public.workshop_bookings current_booking ON current_booking.id=item.booking_id
    WHERE x.vehicle_id=p_vehicle_id AND x.stage_id=item.stage_id AND x.bay_id IS NOT NULL
     AND x.booking_id<>item.booking_id
     AND (other_booking.work_category IS NULL OR current_booking.work_category IS NULL
      OR other_booking.work_category=current_booking.work_category)) THEN
   RAISE EXCEPTION 'This work scope has more than one active booking. Review those bookings before approving the operation.'
    USING DETAIL='operation_schedule_multiple_station_bookings';
  END IF;
  minutes:=public.workshop_booking_capacity_duration_minutes(item.booking_id,p_vehicle_id,item.stage_id,item.bay_id);
  IF minutes IS NULL OR minutes<1 THEN
   RAISE EXCEPTION 'This change would leave a booked station without work. Move or remove its booking before approving.'
    USING DETAIL='operation_schedule_empty_station';
  END IF;
  -- Reducing an estimate must not shorten a job that is already in progress.
  IF item.status IN('started','stoppage') THEN minutes:=greatest(minutes,item.original_minutes); END IF;
  proposed_end:=public.workshop_add_operational_minutes(item.original_start,minutes);
  UPDATE pg_temp.pdc_tune_cascade_plan SET minutes=plan.minutes,
   root_change=(plan.minutes IS DISTINCT FROM item.original_minutes OR proposed_end IS DISTINCT FROM item.original_end)
   WHERE booking_id=item.booking_id;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan WHERE root_change) THEN
  RETURN jsonb_build_object('bookings',receipt,'changed_count',0,'extended_count',0,'moved_count',0,'buffer_minutes',60);
 END IF;
 -- Dependency order is the original queue order. Every move is to the right,
 -- so a later bay or vehicle job can never jump ahead of its predecessor.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan ORDER BY ordinal LOOP
  root_change:=item.root_change;
  SELECT max(greatest(x.final_end,CASE WHEN x.status IN('started','stoppage') THEN date_trunc('minute',clock_timestamp()) ELSE x.final_end END)
      +CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END) INTO blocked_until
   FROM pg_temp.pdc_tune_cascade_plan x WHERE x.ordinal<item.ordinal AND x.changed
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  IF NOT root_change AND coalesce(blocked_until,item.original_start)<=item.original_start THEN CONTINUE; END IF;
  IF item.bay_id IS NULL THEN
   RAISE EXCEPTION 'A later job is queued without a bay. Review that booking before approving this change.'
    USING DETAIL='operation_schedule_queued_without_bay';
  END IF;
  proposed_start:=greatest(item.original_start,coalesce(blocked_until,item.original_start));
  IF item.status IN('started','stoppage') AND proposed_start>item.original_start THEN
   RAISE EXCEPTION 'A later job is already in progress or stopped. Resolve that booking before approving this change.'
    USING DETAIL='operation_schedule_protected_active_booking';
  END IF;
  minutes:=item.minutes;
  IF item.status IN('queued','planned') THEN
   minutes:=greatest(minutes,coalesce(public.workshop_booking_capacity_duration_minutes(item.booking_id,item.vehicle_id,item.stage_id,item.bay_id),minutes));
   proposed_start:=greatest(proposed_start,date_trunc('minute',clock_timestamp())+interval '1 minute');
  END IF;
  -- Once a booking moves, also respect unchanged predecessors and technician
  -- reservations. Unrelated jobs with no incoming change are left untouched.
  SELECT max(greatest(x.final_end,CASE WHEN x.status IN('started','stoppage') THEN date_trunc('minute',clock_timestamp()) ELSE x.final_end END)
     +CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END) INTO blocked_until
   FROM pg_temp.pdc_tune_cascade_plan x WHERE x.ordinal<item.ordinal
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  proposed_start:=greatest(proposed_start,coalesce(blocked_until,proposed_start));
  IF item.status IN('started','stoppage') AND proposed_start>item.original_start THEN
   RAISE EXCEPTION 'The current job cannot be moved automatically. Resolve its earlier booking conflict first.'
    USING DETAIL='operation_schedule_protected_active_booking';
  END IF;
  n:=0;
  LOOP
   n:=n+1;
   IF n>1000 THEN RAISE EXCEPTION 'No safe workshop slot was found for this change.'
    USING DETAIL='operation_schedule_no_slot'; END IF;
   IF item.status IN('queued','planned') THEN
    proposed_start:=public.workshop_admin_next_operational_minute(proposed_start);
    IF proposed_start IS NULL THEN RAISE EXCEPTION 'No open workshop time was found for this change.'
     USING DETAIL='operation_schedule_calendar_unavailable'; END IF;
   END IF;
   proposed_end:=public.workshop_add_operational_minutes(proposed_start,minutes);
   SELECT max(a.scheduled_end_at) INTO blocked_until FROM public.workshop_admin_blocks a
    WHERE a.deleted_at IS NULL AND a.bay_id=item.bay_id
     AND a.scheduled_start_at<proposed_end AND a.scheduled_end_at>proposed_start;
   SELECT max(d::date) INTO unavailable_date FROM generate_series(
    (proposed_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
    ((proposed_end-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(item.vehicle_id,d::date);
   IF unavailable_date IS NOT NULL THEN
    blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
   END IF;
   FOREACH technician IN ARRAY item.technicians LOOP
    unavailable_date:=public.workshop_technician_leave_date(technician,proposed_start,proposed_end);
    IF unavailable_date IS NOT NULL THEN
     blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
    END IF;
   END LOOP;
   EXIT WHEN blocked_until IS NULL;
   IF item.status IN('started','stoppage') THEN
    RAISE EXCEPTION 'The longer current job conflicts with an Admin block, Sublet visit or technician leave. Resolve that conflict before approving.'
     USING DETAIL='operation_schedule_protected_reservation';
   END IF;
   proposed_start:=greatest(proposed_start+interval '1 minute',blocked_until);
  END LOOP;
  changed:=proposed_start IS DISTINCT FROM item.original_start OR proposed_end IS DISTINCT FROM item.original_end OR minutes IS DISTINCT FROM item.original_minutes;
  UPDATE pg_temp.pdc_tune_cascade_plan SET final_start=proposed_start,final_end=proposed_end,
   minutes=plan.minutes,changed=plan.changed
   WHERE booking_id=item.booking_id;
 END LOOP;
 -- Move downstream jobs first, vacating intervals before earlier extensions.
 -- Immediate bay, vehicle and technician exclusion constraints remain enabled.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan WHERE changed ORDER BY ordinal DESC LOOP
  old_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
   default_duration_minutes=item.minutes,version=version+1,updated_by=p_actor,updated_at=clock_timestamp()
   WHERE id=item.booking_id AND version=item.version AND status::text=item.status AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'A booking changed while this operation was being approved. Refresh and try again.'
   USING ERRCODE='40001',DETAIL='operation_schedule_changed'; END IF;
  -- Retain every assignment and its identity, including secondary technicians.
  UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,
   scheduled_end_at=item.final_end,updated_at=clock_timestamp()
   WHERE booking_id=item.booking_id AND released_at IS NULL;
  new_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  IF (SELECT to_jsonb(b)-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes']
      FROM public.workshop_bookings b WHERE id=item.booking_id)
    IS DISTINCT FROM item.before_row-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes'] THEN
   RAISE EXCEPTION 'Operation approval changed protected booking details.' USING DETAIL='operation_schedule_readback_mismatch';
  END IF;
  PERFORM public.workshop_write_history(item.booking_id,'operation_change_schedule_updated',old_snapshot,new_snapshot,
   jsonb_build_object('source','owner_estimate_schedule_reconcile','change_id',p_change_id,
    'approved_vehicle_id',p_vehicle_id,'buffer_minutes',60,'previous_duration_minutes',item.original_minutes,
    'duration_minutes',item.minutes,'moved',item.final_start IS DISTINCT FROM item.original_start));
 END LOOP;
 -- Check the final vehicle handovers against the calculated plan. General
 -- planner validation separately verifies bay, technician, ETA and calendar.
 IF EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan a JOIN pg_temp.pdc_tune_cascade_plan b
   ON a.vehicle_id=b.vehicle_id AND a.ordinal<b.ordinal
   WHERE (a.changed OR b.changed) AND a.final_end+interval '1 hour'>b.final_start) THEN
  RAISE EXCEPTION 'The vehicle needs one hour between workshop jobs.' USING DETAIL='operation_schedule_handover_conflict';
 END IF;
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan WHERE changed LOOP
  FOREACH technician IN ARRAY item.technicians LOOP
   IF public.workshop_find_technician_conflict(item.booking_id,technician,item.final_start,item.final_end) IS NOT NULL THEN
    RAISE EXCEPTION 'The revised job conflicts with another technician booking.' USING DETAIL='operation_schedule_technician_conflict';
   END IF;
  END LOOP;
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',x.booking_id,'vehicle_id',x.vehicle_id,
  'stock_number',coalesce(nullif(btrim(v.stock_number),''),'—'),'stage_code',x.stage_code,'bay_id',x.bay_id,'bay_name',coalesce(nullif(btrim(b.display_name),''),'Bay '||b.bay_number),
  'previous_start_at',x.original_start,'previous_end_at',x.original_end,'start_at',x.final_start,'end_at',x.final_end,
  'previous_estimated_hours',x.original_minutes::numeric/60,'estimated_hours',x.minutes::numeric/60,
  'status',x.status) ORDER BY x.ordinal),'[]') INTO receipt
 FROM pg_temp.pdc_tune_cascade_plan x JOIN public.vehicles v ON v.id=x.vehicle_id
 LEFT JOIN public.workshop_bays b ON b.id=x.bay_id WHERE x.changed;
 RETURN jsonb_build_object('bookings',receipt,'changed_count',jsonb_array_length(receipt),
  'extended_count',(SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan WHERE changed AND minutes>original_minutes),
  'moved_count',(SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan WHERE changed AND final_start IS DISTINCT FROM original_start),
  'buffer_minutes',60);
END $function$;

DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure),chr(13),'')) <> '5e24a4852e1034fbc1c4e83fcd7fdb44' THEN RAISE EXCEPTION 'source_version_changed: workshop_sync_vehicle_stage_booking_duration'; END IF; END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid, p_stage_code text, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 v_stage text:=public.workshop_canonical_stage_code(p_stage_code);v_booking public.workshop_bookings%rowtype;
 v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;
 v_increment integer;v_from timestamptz;v_cascade jsonb;
 v_original_claims text:=current_setting('request.jwt.claims',true);v_initiator_uid uuid:=auth.uid();v_initiator_email text:=public.current_actor_email();
 v_system_actor uuid;v_system_email text;
BEGIN
 IF p_vehicle_id IS NULL OR v_stage IS NULL THEN RETURN 0;END IF;
 SELECT r.auth_user_id,r.email INTO v_system_actor,v_system_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND r.role='administrator' AND r.auth_user_id IS NOT NULL ORDER BY r.created_at,r.id LIMIT 1;
 IF v_system_actor IS NULL THEN RAISE EXCEPTION 'PDC_156_WORKSHOP_SYSTEM_ACTOR_MISSING' USING errcode='55000';END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:estimate-sync:'||p_vehicle_id::text,0));
 LOCK TABLE public.workshop_bookings,public.workshop_booking_assignments IN EXCLUSIVE MODE;
 FOR v_booking IN SELECT b.* FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status::text IN('queued','planned','started','stoppage')
    AND public.workshop_canonical_stage_code(s.code)=v_stage ORDER BY b.scheduled_start_at,b.id FOR UPDATE OF b LOOP
  v_minutes:=CASE WHEN v_booking.status IN('queued','planned') THEN coalesce(public.workshop_booking_capacity_duration_minutes(v_booking.id,p_vehicle_id,v_booking.stage_id,v_booking.bay_id),v_booking.default_duration_minutes) ELSE coalesce(pdc_work_categories_private.minutes(v_booking.id,p_vehicle_id,v_booking.stage_id),60) END;
  v_end:=public.workshop_add_operational_minutes(v_booking.scheduled_start_at,v_minutes);
  IF v_booking.default_duration_minutes IS DISTINCT FROM v_minutes OR v_booking.scheduled_end_at IS DISTINCT FROM v_end THEN
   v_before:=public.workshop_booking_snapshot(v_booking.id);
   IF v_booking.status::text NOT IN('planned','started','stoppage') OR (v_stage='BUS_4X4' AND v_booking.status::text<>'planned') THEN
    INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
    VALUES(v_booking.id,'operation_estimate_duration_reconcile_deferred',v_before,v_before,
     jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'proposed_duration_minutes',v_minutes,'reason','protected_non_planned_booking_window','protected_status',v_booking.status::text,
      'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
   ELSE
    SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
    v_increment:=greatest(1,coalesce(v_increment,15));
    v_from:=CASE WHEN v_booking.scheduled_start_at>clock_timestamp() THEN v_booking.scheduled_start_at ELSE
      date_trunc('minute',clock_timestamp())+
      (v_increment-mod((extract(epoch from clock_timestamp())/60)::bigint,v_increment)) * interval '1 minute' END;
    IF public.pdc_vehicle_department_membership_20260919(p_vehicle_id)->'department_codes' ? '139'
       AND v_stage<>'BUS_4X4' THEN
    v_cascade:=pdc_operation_updates_private.reconcile_estimate_bookings_20261018(
      p_vehicle_id,ARRAY[v_stage],NULL,v_system_actor);
    v_count:=v_count+coalesce((v_cascade->>'changed_count')::integer,0);
    ELSE
    v_cascade:=public.workshop_admin_repack_planned(v_booking.bay_id,v_from,
      jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
       'operation_estimate_duration_cascade',true,'recover_overdue',v_booking.scheduled_start_at<=clock_timestamp(),
       'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email));
    v_count:=v_count+coalesce((v_cascade->>'shifted_count')::integer,0);
    END IF;
   END IF;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RETURN v_count;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RAISE;
END $function$;

DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure),chr(13),'')) <> '9a1833bf2d0ee5b871102a6340ef7277' THEN RAISE EXCEPTION 'source_version_changed: set_workshop_stage_estimated_minutes_407'; END IF; END $guard$;

CREATE OR REPLACE FUNCTION public.set_workshop_stage_estimated_minutes_407(p_vehicle_id uuid, p_expected_vehicle_version integer, p_booking_id uuid, p_expected_booking_version integer, p_stage_code text, p_total_minutes integer, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_stage text:=public.workshop_canonical_stage_code(p_stage_code); v_stage_id uuid; v_bay_number integer;
  v_vehicle public.vehicles%rowtype; v_booking public.workshop_bookings%rowtype;
  v_adjustment public.vehicle_workshop_line_adjustments%rowtype; v_before_adjustment jsonb; v_after_adjustment jsonb;
  v_line_key text; v_current_minutes integer; v_manual_minutes integer:=0; v_base_minutes integer; v_delta_minutes integer; v_delta_hours numeric;
  v_authoritative_minutes integer; v_capacity_minutes integer; v_cascade jsonb; v_request jsonb; v_request_sha text; v_response jsonb; v_existing public.pdc_workshop_stage_estimate_receipts_407%rowtype; v_receipt_id uuid;
BEGIN
  IF v_actor IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_booking_id IS NULL OR p_expected_booking_version IS NULL OR v_stage IS NULL OR p_total_minutes IS NULL OR p_total_minutes NOT BETWEEN 1 AND 59999 OR p_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_stage_estimate_input');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  v_request:=jsonb_build_object('contract','pdc-workshop-stage-estimated-minutes-407','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'booking_id',p_booking_id,'expected_booking_version',p_expected_booking_version,'stage_code',v_stage,'total_minutes',p_total_minutes,'idempotency_key',p_idempotency_key,'actor_id',v_actor);
  v_request_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-407-stage-estimate-actor:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_existing FROM public.pdc_workshop_stage_estimate_receipts_407 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN v_existing.response||jsonb_build_object('replay',true);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-407-stage-estimate-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF v_vehicle.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('current_version',v_vehicle.version)); END IF;
  SELECT id INTO v_stage_id FROM public.workshop_stages WHERE code=v_stage AND active FOR SHARE;
  IF v_stage_id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','stage_not_found'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed AND public.workshop_canonical_stage_code(wi.work_key)=v_stage FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','canonical_requirement_missing_or_completed');
  END IF;
  SELECT * INTO v_booking FROM public.workshop_bookings WHERE id=p_booking_id AND vehicle_id=p_vehicle_id AND stage_id=v_stage_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_booking.status::text NOT IN('queued','planned','started','stoppage') OR (v_stage='BUS_4X4' AND v_booking.status::text IN('started','stoppage')) THEN RETURN jsonb_build_object('ok',false,'code','booking_not_editable'); END IF;
  IF v_booking.version<>p_expected_booking_version THEN RETURN jsonb_build_object('ok',false,'code','version_conflict','data',jsonb_build_object('current_version',v_booking.version)); END IF;
  SELECT bay_number INTO v_bay_number FROM public.workshop_bays WHERE id=v_booking.bay_id AND is_active FOR SHARE;
  IF v_bay_number IS NULL THEN RETURN jsonb_build_object('ok',false,'code','bay_inactive_or_wrong_station'); END IF;

  v_line_key:='manual:planner-stage:'||v_stage;
  SELECT * INTO v_adjustment FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=p_vehicle_id AND line_key=v_line_key FOR UPDATE;
  IF FOUND AND v_adjustment.active THEN v_manual_minutes:=round(coalesce(v_adjustment.estimated_hours,0)*60)::integer; END IF;
  v_current_minutes:=coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,v_stage_id),0);
  v_base_minutes:=greatest(0,v_current_minutes-v_manual_minutes);
  IF p_total_minutes<v_base_minutes THEN
    RETURN jsonb_build_object('ok',false,'code','estimated_minutes_below_authenticated_work','data',jsonb_build_object('minimum_minutes',v_base_minutes));
  END IF;
  v_delta_minutes:=p_total_minutes-v_base_minutes;
  v_delta_hours:=round(v_delta_minutes::numeric/60,2);
  PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','407',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','407',true);
  v_before_adjustment:=CASE WHEN v_adjustment.adjustment_id IS NULL THEN NULL ELSE to_jsonb(v_adjustment) END;
  IF v_delta_minutes=0 THEN
    IF v_adjustment.adjustment_id IS NOT NULL AND v_adjustment.active THEN
      UPDATE public.vehicle_workshop_line_adjustments SET active=false,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE adjustment_id=v_adjustment.adjustment_id RETURNING * INTO v_adjustment;
    END IF;
  ELSIF v_adjustment.adjustment_id IS NULL THEN
    INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,version,created_by,updated_by)
    VALUES(p_vehicle_id,v_line_key,'manual',v_stage,'Planner stage time adjustment',v_delta_hours,'manual_operator',true,1,v_actor,v_actor) RETURNING * INTO v_adjustment;
  ELSE
    UPDATE public.vehicle_workshop_line_adjustments SET stage_code=v_stage,description='Planner stage time adjustment',estimated_hours=v_delta_hours,correction_origin='manual_operator',active=true,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE adjustment_id=v_adjustment.adjustment_id RETURNING * INTO v_adjustment;
  END IF;
  v_after_adjustment:=CASE WHEN v_adjustment.adjustment_id IS NULL THEN NULL ELSE to_jsonb(v_adjustment) END;
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','',true);
  v_authoritative_minutes:=coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,v_stage_id),0);
  IF v_authoritative_minutes<>p_total_minutes THEN RAISE EXCEPTION 'PDC_407_CANONICAL_MINUTE_RECONCILIATION_FAILED expected %, got %',p_total_minutes,v_authoritative_minutes USING errcode='55000'; END IF;

  v_capacity_minutes:=public.workshop_booking_capacity_duration_minutes(v_booking.id,p_vehicle_id,v_stage_id,v_booking.bay_id);
  IF v_booking.status IN('started','stoppage') THEN
    v_capacity_minutes:=greatest(v_capacity_minutes,v_booking.default_duration_minutes);
    v_cascade:=pdc_operation_updates_private.reconcile_estimate_bookings_20261018(p_vehicle_id,ARRAY[v_stage],NULL,v_actor)||jsonb_build_object('ok',true);
  ELSE
  v_cascade:=public.cascade_workshop_schedule(
    'extend',
    p_booking_id,p_expected_booking_version,v_stage,v_bay_number,v_booking.scheduled_start_at,v_capacity_minutes,NULL,
    greatest(0,v_capacity_minutes-v_booking.default_duration_minutes),NULL,
    jsonb_build_object('source','stage_estimated_minutes_407','request_id',p_idempotency_key,'canonical_minutes',p_total_minutes,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes));
  END IF;
  IF coalesce((v_cascade->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'PDC_407_CASCADE_FAILED: %',v_cascade USING errcode='55000'; END IF;
  SELECT * INTO v_booking FROM public.workshop_bookings WHERE id=p_booking_id;
  IF v_booking.default_duration_minutes<>v_capacity_minutes THEN RAISE EXCEPTION 'PDC_407_BOOKING_READBACK_FAILED' USING errcode='55000'; END IF;
  v_receipt_id:=extensions.uuid_generate_v5('40700000-0000-5000-8000-000000000407'::uuid,'stage-estimate:'||v_actor::text||':'||p_idempotency_key::text);
  v_response:=jsonb_build_object('ok',true,'code','workshop_stage_estimated_minutes_saved','replay',false,'receipt_id',v_receipt_id,'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle.version,'booking_id',p_booking_id,'booking_version',v_booking.version,'stage_code',v_stage,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes,'total_minutes',p_total_minutes,'adjustment',v_after_adjustment,'cascade',v_cascade);
  INSERT INTO public.pdc_workshop_stage_estimate_receipts_407(receipt_id,actor_id,actor_email,vehicle_id,booking_id,stage_code,total_minutes,idempotency_key,request_sha256,request_payload,response)
  VALUES(v_receipt_id,v_actor,v_email,p_vehicle_id,p_booking_id,v_stage,p_total_minutes,p_idempotency_key,v_request_sha,v_request,v_response);
  IF v_adjustment.adjustment_id IS NOT NULL THEN
    INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    VALUES(CASE WHEN v_before_adjustment IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,'vehicle_workshop_line_adjustments',v_adjustment.adjustment_id,p_vehicle_id,v_actor,v_email,v_before_adjustment,v_after_adjustment,jsonb_build_object('action','set_workshop_stage_estimated_minutes_407','receipt_id',v_receipt_id,'stage_code',v_stage,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes,'total_minutes',p_total_minutes,'booking_id',p_booking_id));
  END IF;
  RETURN v_response;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','',true);
  RAISE;
END $function$;

DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure),chr(13),'')) <> '9d1c771bdb23702607fc7996bbe86998' THEN RAISE EXCEPTION 'source_version_changed: workshop_validate_booking'; END IF; END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_validate_booking(p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_scheduled_start_at timestamp with time zone, p_scheduled_end_at timestamp with time zone, p_duration_minutes integer, p_status workshop_booking_status, p_technician_id uuid, p_allow_unchanged_past boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_preserve_historical_calendar boolean:=false; v_bus_calendar boolean:=false; v_bus_rule jsonb; v_bus_end timestamptz; v_bus_unchanged boolean:=false;
  v_vehicle public.vehicles%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_conflict uuid;
  v_local_date date := (p_scheduled_start_at at time zone 'Australia/Perth')::date;
  v_active boolean := p_status in ('queued','planned','started','stoppage'); v_estimated_duration integer; v_candidate_end timestamptz; v_registered_synthetic boolean := false;
begin
  if not v_active then return jsonb_build_object('ok',true); end if;
 v_bus_calendar:=pdc_bus_private.active_vehicle(p_vehicle_id) AND EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id AND s.code='BUS_4X4');
 IF v_bus_calendar THEN
  v_bus_unchanged:=EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.bay_id=p_bay_id AND b.deleted_at IS NULL
   AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at AND b.default_duration_minutes=p_duration_minutes AND b.status IN('planned','started','stoppage'));
  IF NOT v_bus_unchanged THEN
   v_bus_rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,p_booking_id);
   IF v_bus_rule->>'ok' IS DISTINCT FROM 'true' THEN RETURN v_bus_rule; END IF;
   IF NOT pdc_bus_private.minute_available(p_scheduled_start_at,p_bay_id) THEN RETURN jsonb_build_object('ok',false,'error','bus_shift_outside_hours'); END IF;
   v_bus_end:=pdc_bus_private.add_minutes(p_scheduled_start_at,p_duration_minutes,p_bay_id);
   IF p_scheduled_end_at IS DISTINCT FROM v_bus_end AND p_scheduled_end_at IS DISTINCT FROM public.workshop_add_operational_minutes(p_scheduled_start_at,p_duration_minutes)
   THEN RETURN jsonb_build_object('ok',false,'error','calendar_duration_mismatch'); END IF;
   p_scheduled_end_at:=v_bus_end;
  END IF;
 END IF;
  v_registered_synthetic:=exists(
    select 1
    from public.pdc_overnight_synthetic_fleet_registry_363 r
    join public.vehicles x on x.id=p_vehicle_id
     and r.run_id='HERMES-TEST-RUN-20260824'
     and r.vehicle_id=x.id
     and x.stock_number=r.stock_number
     and x.customer_name=r.customer_name
     and x.job_card_number=r.job_card_number
     and x.vehicle_description=r.vehicle_description
     and x.source_system='hermes_overnight_synthetic'
     and x.source_batch_id=r.run_id
     and x.source_record_id=r.stock_number
     and x.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
  );
  if p_duration_minutes is null or p_duration_minutes<1 then
    return jsonb_build_object('ok',false,'error','minimum_duration','minimum_minutes',1);
  end if;
  if p_scheduled_start_at is null or p_scheduled_end_at is null or p_scheduled_end_at<=p_scheduled_start_at
     or date_trunc('minute',p_scheduled_start_at)<>p_scheduled_start_at
     or date_trunc('minute',p_scheduled_end_at)<>p_scheduled_end_at then
    return jsonb_build_object('ok',false,'error','invalid_schedule_interval');
  end if;
  if not p_allow_unchanged_past
     and p_status in ('queued','planned')
     and p_scheduled_start_at < date_trunc('minute',statement_timestamp()) then
    return jsonb_build_object('ok',false,'error','past_start');
  end if;
  -- Stopping work records a real event; changing future hours must not invalidate
  -- the unchanged interval of a job that already started under the old calendar.
  -- This exemption never applies to a move, resize, start, or changed identity.
  v_preserve_historical_calendar:=p_allow_unchanged_past AND p_status='stoppage' AND EXISTS(
    SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id
      AND b.deleted_at IS NULL AND b.status='started' AND b.actual_start_at IS NOT NULL
      AND b.vehicle_id=p_vehicle_id AND b.stage_id=p_stage_id AND b.bay_id=p_bay_id
      AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at
      AND b.default_duration_minutes=p_duration_minutes);
  if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND not public.workshop_calendar_minute_available(p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','calendar_unavailable');
  end if;
  if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at)<>p_duration_minutes then
    return jsonb_build_object('ok',false,'error','calendar_duration_mismatch');
  end if;
  select * into v_vehicle from public.vehicles where id=p_vehicle_id and deleted_at is null and lifecycle_state='active';
  if not found then return jsonb_build_object('ok',false,'error','vehicle_inactive_or_missing'); end if;
  if exists(select 1 from public.pdc_new_vehicle_reviews r where r.vehicle_id=p_vehicle_id and r.status='pending') then return jsonb_build_object('ok',false,'error','new_vehicle_review_required'); end if;
  select * into v_stage from public.workshop_stages where id=p_stage_id and active and planner_enabled;
  if not found then return jsonb_build_object('ok',false,'error','station_inactive_or_missing'); end if; v_estimated_duration:=coalesce(public.workshop_capacity_manual_minutes(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id,p_duration_minutes),public.workshop_booking_capacity_duration_minutes(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id)); v_candidate_end:=case when p_status in ('queued','planned') and v_estimated_duration is not null then CASE WHEN v_bus_calendar THEN CASE WHEN v_bus_unchanged THEN p_scheduled_end_at ELSE pdc_bus_private.add_minutes(p_scheduled_start_at,v_estimated_duration,p_bay_id) END ELSE public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) END else p_scheduled_end_at end; if p_status in ('queued','planned') and v_estimated_duration is not null and p_duration_minutes<>v_estimated_duration and not v_registered_synthetic then return jsonb_build_object('ok',false,'error','operation_estimate_duration_mismatch','expected_minutes',v_estimated_duration); end if;
  if public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location)) not in ('PMB','YH','IT') then
    return jsonb_build_object('ok',false,'error','location_ineligible');
  end if;
  if public.workshop_location_code(coalesce(nullif(v_vehicle.location_override,''),v_vehicle.current_location))='IT' then
    if v_vehicle.eta_to_kewdale is null then return jsonb_build_object('ok',false,'error','it_eta_missing'); end if;
    if v_local_date<v_vehicle.eta_to_kewdale+7 then return jsonb_build_object('ok',false,'error','it_before_eta_plus_seven','earliest_permitted_date',v_vehicle.eta_to_kewdale+7); end if;
  end if;
  if not exists(
    select 1 from public.vehicle_work_items wi
    where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
      and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage.code
  ) then return jsonb_build_object('ok',false,'error','canonical_requirement_missing_or_completed'); end if;
  if p_status<>'queued' then
    if p_bay_id is null then return jsonb_build_object('ok',false,'error','bay_required'); end if;
    select * into v_bay from public.workshop_bays where id=p_bay_id and stage_id=p_stage_id and is_active;
    if not found then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
  end if;
  if p_bay_id is not null then
    select b.id into v_conflict from public.workshop_bookings b
    where b.id is distinct from p_booking_id and b.deleted_at is null
      and b.status in ('planned','started','stoppage') and b.bay_id=p_bay_id
      and tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by b.scheduled_start_at,b.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','bay_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  select b.id into v_conflict from public.workshop_bookings b
  where b.id is distinct from p_booking_id and b.deleted_at is null
    and b.status in ('queued','planned','started','stoppage') and b.vehicle_id=p_vehicle_id
    and NOT (b.status='queued' AND b.bay_id IS NULL)
    and tstzrange(b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
  order by b.scheduled_start_at,b.id limit 1;
  if v_conflict is not null then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if;
  if p_technician_id is not null then
    IF v_bus_calendar AND NOT (v_bus_unchanged AND EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=p_booking_id AND a.technician_id=p_technician_id AND a.released_at IS NULL)) THEN
      v_bus_rule:=pdc_bus_private.technician_shift_problem(p_technician_id,p_bay_id,p_scheduled_start_at,v_candidate_end);
      IF v_bus_rule IS NOT NULL THEN RETURN v_bus_rule; END IF;
    END IF;
    if not exists(select 1 from public.workshop_technicians t where t.id=p_technician_id and t.active) then
      return jsonb_build_object('ok',false,'error','technician_inactive_or_missing');
    end if;
    if public.workshop_technician_leave_date(p_technician_id,p_scheduled_start_at,v_candidate_end) is not null then
      return jsonb_build_object('ok',false,'error','technician_leave_conflict');
    end if;
    -- Historical assignments only reserve time while their booking is active.
    select a.booking_id into v_conflict from public.workshop_booking_assignments a
    join public.workshop_bookings assigned_booking on assigned_booking.id=a.booking_id
    where a.booking_id is distinct from p_booking_id and a.technician_id=p_technician_id and a.released_at is null
      and assigned_booking.deleted_at is null
      and assigned_booking.status in ('queued','planned','started','stoppage')
      and NOT (assigned_booking.status='queued' AND assigned_booking.bay_id IS NULL)
      and tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.booking_id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by a.scheduled_start_at,a.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  return jsonb_build_object('ok',true);
end $function$;

-- An Unallocated reservation retains historical dates, but reserves no capacity.
-- Keep immediate exclusion protection for every actual bay reservation and live stoppage.
SET LOCAL lock_timeout = '10s';
DO $guard$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.workshop_bookings'::regclass
  AND conname='workshop_bookings_active_vehicle_no_overlap' AND contype='x' AND NOT condeferrable
  AND pg_get_constraintdef(oid)=$expected$EXCLUDE USING gist (vehicle_id WITH =, tstzrange(scheduled_start_at, scheduled_end_at, '[)'::text) WITH &&) WHERE (((deleted_at IS NULL) AND (NOT legacy_ambiguity_quarantined) AND (status = ANY (ARRAY['queued'::workshop_booking_status, 'planned'::workshop_booking_status, 'started'::workshop_booking_status, 'stoppage'::workshop_booking_status]))))$expected$)
 THEN RAISE EXCEPTION 'source_version_changed: workshop_bookings_active_vehicle_no_overlap'; END IF;
END $guard$;
ALTER TABLE public.workshop_bookings DROP CONSTRAINT workshop_bookings_active_vehicle_no_overlap,
 ADD CONSTRAINT workshop_bookings_active_vehicle_no_overlap EXCLUDE USING gist
 (vehicle_id WITH =, tstzrange(scheduled_start_at,scheduled_end_at,'[)') WITH &&)
 WHERE (deleted_at IS NULL AND NOT legacy_ambiguity_quarantined
  AND status IN('queued','planned','started','stoppage')
  AND NOT(status='queued' AND bay_id IS NULL));


NOTIFY pgrst, 'reload schema';