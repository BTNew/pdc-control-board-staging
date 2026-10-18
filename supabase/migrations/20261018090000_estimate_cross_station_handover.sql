DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF md5(replace(pg_get_functiondef('pdc_operation_updates_private.reconcile_bookings(uuid,text[],uuid,uuid)'::regprocedure),chr(13),''))<>'5cb064fddd6ce6381cc56a0732ac1338' THEN RAISE EXCEPTION 'reviewed_graph_changed'; END IF;
END $guard$;
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
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 SELECT count(*) INTO graph_count FROM pg_temp.pdc_tune_cascade_plan;
 IF graph_count>10000 THEN RAISE EXCEPTION 'The workshop queue needs a smaller scheduling review.'
  USING DETAIL='operation_schedule_limit'; END IF;
 -- Category bookings use their own current work estimate; legacy bookings retain whole-station scope.
 -- Never manufacture a booking for a newly required, unbooked station.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan
  WHERE vehicle_id=p_vehicle_id AND bay_id IS NOT NULL AND status='planned' ORDER BY ordinal
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
  minutes:=CASE WHEN item.status IN('queued','planned') THEN public.workshop_booking_capacity_duration_minutes(item.booking_id,p_vehicle_id,item.stage_id,item.bay_id) ELSE pdc_work_categories_private.minutes(item.booking_id,p_vehicle_id,item.stage_id) END;
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
   minutes:=coalesce(public.workshop_booking_capacity_duration_minutes(item.booking_id,item.vehicle_id,item.stage_id,item.bay_id),minutes);
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
END $function$

;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
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
   IF v_booking.status::text<>'planned' THEN
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
       AND NOT (public.pdc_vehicle_department_membership_20260919(p_vehicle_id)->'department_codes' ? '138') THEN
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
END $function$
;
CREATE OR REPLACE FUNCTION public.save_vehicle_workshop_line_hours_batch_768(p_vehicle_id uuid, p_stock_number text, p_job_card_number text, p_expected_vehicle_version bigint, p_estimated_rows jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_scope jsonb;
  v_vehicle_dealer text;
  v_vehicle public.vehicles%rowtype;
  v_receipt public.vehicle_workshop_hours_batch_receipts_768%rowtype;
  v_rows jsonb:=coalesce(p_estimated_rows,'[]'::jsonb);
  v_canonical_rows jsonb;
  v_request jsonb;
  v_request_hash text;
  v_current_rows jsonb:='[]'::jsonb;
  v_conflicts jsonb:='[]'::jsonb;
  v_changes jsonb:='[]'::jsonb;
  v_revision bigint;
  v_vehicle_after public.vehicles%rowtype;
  v_changed_count integer:=0;
  v_receipt_id uuid:=gen_random_uuid();
BEGIN
  IF v_actor IS NULL OR v_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;
  PERFORM public.require_pdc_role('operator');
  v_scope:=public.pdc_auditor_actor_scope();
  v_vehicle_dealer:=public.pdc_auditor_vehicle_dealer(p_vehicle_id);
  IF v_scope->>'environment' IS DISTINCT FROM 'staging'
     OR NOT public.pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,v_vehicle_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  IF p_vehicle_id IS NULL OR p_idempotency_key IS NULL
    OR nullif(btrim(coalesce(p_stock_number,'')),'') IS NULL
    OR nullif(btrim(coalesce(p_job_card_number,'')),'') IS NULL
    OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
    OR jsonb_typeof(v_rows)<>'array' OR jsonb_array_length(v_rows) NOT BETWEEN 1 AND 250
    OR EXISTS(
      SELECT 1 FROM jsonb_array_elements(v_rows) x
      WHERE jsonb_typeof(x)<>'object'
        OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x) k)
           IS DISTINCT FROM ARRAY['adjustment_id','estimated_hours','expected_line_version','line_key','operation_line_id','stage_code','work_key']::text[]
        OR coalesce(x->>'operation_line_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        OR coalesce(x->>'line_key','')<>('source:'||lower(coalesce(x->>'operation_line_id','')))
        OR coalesce(x->>'work_key','')<>lower(btrim(coalesce(x->>'work_key','')))
        OR coalesce(x->>'work_key','') IN ('parts','pit_inspection','unallocated_mapping_review')
        OR coalesce(x->>'stage_code','')<>upper(btrim(coalesce(x->>'stage_code','')))
        OR coalesce(x->>'stage_code','') !~ '^[A-Z][A-Z0-9_]{1,39}$'
        OR coalesce(x->>'expected_line_version','') !~ '^[0-9]+$'
        OR jsonb_typeof(x->'adjustment_id') IS NULL
        OR (jsonb_typeof(x->'adjustment_id')='string' AND coalesce(x->>'adjustment_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        OR jsonb_typeof(x->'adjustment_id') NOT IN ('string','null')
        OR jsonb_typeof(x->'estimated_hours') IS NULL
        OR jsonb_typeof(x->'estimated_hours') NOT IN ('number','null')
        OR (jsonb_typeof(x->'estimated_hours')='number' AND (
          coalesce(x->>'estimated_hours','') !~ '^(0|[0-9]+)(\.[0-9]{1,2})?$'
          OR (x->>'estimated_hours')::numeric<0 OR (x->>'estimated_hours')::numeric>999.99
        ))
    )
    OR (SELECT count(*) FROM jsonb_array_elements(v_rows))
      <>(SELECT count(DISTINCT lower(x->>'operation_line_id')) FROM jsonb_array_elements(v_rows) x)
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_hours_batch'); END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY lower(x->>'operation_line_id')),'[]'::jsonb)
    INTO v_canonical_rows FROM jsonb_array_elements(v_rows) x;
  v_request:=jsonb_build_object(
    'contract','vehicle_workshop_hours_batch_768.1','actor_id',v_actor,'vehicle_id',p_vehicle_id,
    'stock_number',btrim(p_stock_number),'job_card_number',btrim(p_job_card_number),
    'expected_vehicle_version',p_expected_vehicle_version,'estimated_rows',v_canonical_rows,
    'idempotency_key',p_idempotency_key);
  v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-workshop-hours-batch:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_receipt FROM public.vehicle_workshop_hours_batch_receipts_768
   WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_receipt.request_hash<>v_request_hash THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict','data',jsonb_build_object('receipt_id',v_receipt.receipt_id));
    END IF;
    RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  SELECT * INTO v_vehicle FROM public.vehicles
   WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF btrim(coalesce(v_vehicle.stock_number::text,''))<>btrim(p_stock_number) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_identity_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_request_t780 ON COMMIT DROP AS
  SELECT lower(x->>'operation_line_id')::uuid operation_line_id,
    NULLIF(x->>'adjustment_id','')::uuid adjustment_id,
    (x->>'expected_line_version')::bigint expected_line_version,
    x->>'line_key' line_key,upper(x->>'stage_code') stage_code,lower(x->>'work_key') work_key,
    CASE WHEN jsonb_typeof(x->'estimated_hours')='null' THEN NULL ELSE (x->>'estimated_hours')::numeric END estimated_hours
  FROM jsonb_array_elements(v_rows) x;
  CREATE UNIQUE INDEX ON pdc_hours_batch_request_t780(operation_line_id);

  -- Use the same canonical, current category projection as Vehicle Locations.
  -- Legacy classification history can be absent after an accepted source update.
  CREATE TEMP TABLE pdc_hours_batch_source_t780 ON COMMIT DROP AS
  SELECT (l->>'source_line_id')::uuid operation_line_id,p_vehicle_id vehicle_id,
    coalesce(l->>'source_contract','authenticated') source_contract,
    l->>'job_card_number' job_card_number,
    CASE l->>'stage_code' WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(l->>'stage_code') END work_key,
    l->>'stage_code' stage_code,l->>'description' description,
    (l->>'source_estimated_hours')::numeric source_estimated_hours,
    (l->>'estimated_hours')::numeric effective_estimated_hours,
    l->>'operation_no' operation_no,(l->>'original_line_number')::integer display_order
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  JOIN pdc_hours_batch_request_t780 r ON r.line_key=l->>'line_identity'
    AND r.operation_line_id::text=l->>'source_line_id'
  WHERE coalesce((l->>'active')::boolean,true)
    AND NOT coalesce((l->>'completed')::boolean,false)
    AND NOT coalesce((l->>'rejected')::boolean,false)
    AND l->>'source_kind'='authenticated';
  CREATE UNIQUE INDEX ON pdc_hours_batch_source_t780(operation_line_id);

  IF EXISTS(SELECT 1 FROM pdc_hours_batch_request_t780 WHERE work_key='parts' OR stage_code='PARTS') THEN
    RETURN jsonb_build_object('ok',false,'code','parts_not_hour_bearing','data',jsonb_build_object('vehicle_id',p_vehicle_id,'booking_created',false,'parts_mutated',false));
  END IF;

  PERFORM 1 FROM public.vehicle_workshop_line_adjustments a
   JOIN pdc_hours_batch_request_t780 r ON r.line_key=a.line_key
   WHERE a.vehicle_id=p_vehicle_id FOR UPDATE;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'line_key',r.line_key,'work_key',r.work_key,'stage_code',r.stage_code,
    'source_contract',s.source_contract,'source_estimated_hours',s.source_estimated_hours,
    'adjustment_id',a.adjustment_id,'line_version',coalesce(a.version,0),
    'estimated_hours',CASE WHEN a.adjustment_id IS NOT NULL AND a.active THEN a.estimated_hours ELSE s.effective_estimated_hours END,
    'active',coalesce(a.active,true)
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_current_rows
  FROM pdc_hours_batch_request_t780 r
  LEFT JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key;

  IF v_vehicle.version<>p_expected_vehicle_version THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'current_rows',v_current_rows));
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'requested_work_key',r.work_key,'requested_stage_code',r.stage_code,
    'requested_line_version',r.expected_line_version,'source_contract',s.source_contract,
    'current_work_key',s.work_key,'current_stage_code',s.stage_code,
    'current_adjustment_id',a.adjustment_id,'current_line_version',coalesce(a.version,0),
    'reason',CASE
      WHEN s.operation_line_id IS NULL THEN 'operation_line_not_found'
      WHEN coalesce(a.active,true)=false THEN 'operation_line_adjustment_inactive'
      WHEN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) header WHERE header->>'job_card_number'=btrim(p_job_card_number)) THEN 'job_card_identity_conflict'
      WHEN s.work_key<>r.work_key THEN 'work_key_conflict'
      WHEN s.stage_code<>r.stage_code THEN 'stage_identity_conflict'
      WHEN a.adjustment_id IS DISTINCT FROM r.adjustment_id THEN 'adjustment_identity_conflict'
      WHEN coalesce(a.version,0)<>r.expected_line_version THEN 'line_version_conflict'
      ELSE 'row_drift'
    END
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_conflicts
  FROM pdc_hours_batch_request_t780 r
  LEFT JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE s.operation_line_id IS NULL OR coalesce(a.active,true)=false
     OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) header WHERE header->>'job_card_number'=btrim(p_job_card_number))
     OR s.work_key IS DISTINCT FROM r.work_key OR s.stage_code IS DISTINCT FROM r.stage_code
     OR a.adjustment_id IS DISTINCT FROM r.adjustment_id OR coalesce(a.version,0)<>r.expected_line_version;
  IF jsonb_array_length(v_conflicts)>0 THEN
    RETURN jsonb_build_object('ok',false,'code','line_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'conflicts',v_conflicts,'current_rows',v_current_rows));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_changes_t780 ON COMMIT DROP AS
  SELECT r.operation_line_id,r.adjustment_id current_adjustment_id,r.expected_line_version,
    r.line_key,r.stage_code,r.work_key,r.estimated_hours,s.source_contract,s.job_card_number,s.description source_description,
    s.source_estimated_hours,s.effective_estimated_hours source_effective_hours,s.operation_no,s.display_order,
    CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE s.effective_estimated_hours END current_estimated_hours,
    coalesce(a.version,0) current_line_version
  FROM pdc_hours_batch_request_t780 r
  JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE r.estimated_hours IS DISTINCT FROM CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE s.effective_estimated_hours END;
  SELECT count(*) INTO v_changed_count FROM pdc_hours_batch_changes_t780;

  IF v_changed_count>0 THEN
    UPDATE public.vehicle_workshop_line_adjustments a SET
      stage_code=c.stage_code,
      description=c.source_description,
      estimated_hours=c.estimated_hours,
      correction_origin=CASE WHEN c.estimated_hours IS NULL THEN 'manual_operator_unknown' ELSE 'manual_operator' END,
      active=true,
      version=a.version+1,
      updated_by=v_actor,
      updated_at=clock_timestamp()
    FROM pdc_hours_batch_changes_t780 c
    WHERE a.adjustment_id=c.current_adjustment_id
      AND a.vehicle_id=p_vehicle_id;

    INSERT INTO public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,version,
      created_by,updated_by,source_operation_line_id,job_card_number,operation_code,display_order,manual_assignment_locked
    )
    SELECT p_vehicle_id,c.line_key,'source',c.stage_code,c.source_description,c.estimated_hours,
      CASE WHEN c.estimated_hours IS NULL THEN 'manual_operator_unknown' ELSE 'manual_operator' END,
      true,1,v_actor,v_actor,CASE WHEN c.source_contract='authenticated' THEN c.operation_line_id ELSE NULL END,
      c.job_card_number,c.operation_no,c.display_order,false
    FROM pdc_hours_batch_changes_t780 c WHERE c.current_adjustment_id IS NULL
    ON CONFLICT(vehicle_id,line_key) DO UPDATE SET
      stage_code=excluded.stage_code,description=excluded.description,estimated_hours=excluded.estimated_hours,
      correction_origin=excluded.correction_origin,
      active=true,version=public.vehicle_workshop_line_adjustments.version+1,updated_by=v_actor,updated_at=clock_timestamp();

    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operation_line_id',c.operation_line_id,'line_key',c.line_key,'work_key',c.work_key,'source_contract',c.source_contract,
      'source_estimated_hours',c.source_estimated_hours,
      'before',jsonb_build_object('adjustment_id',c.current_adjustment_id,'estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      'after',jsonb_build_object('adjustment_id',a.adjustment_id,'estimated_hours',a.estimated_hours,'version',a.version,'correction_origin',a.correction_origin)
    ) ORDER BY c.operation_line_id),'[]'::jsonb) INTO v_changes
    FROM pdc_hours_batch_changes_t780 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    SELECT CASE WHEN c.current_adjustment_id IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,
      'vehicle_workshop_line_adjustments',a.adjustment_id,p_vehicle_id,v_actor,v_email,
      jsonb_build_object('adjustment_id',c.current_adjustment_id,'operation_line_id',c.operation_line_id,
        'source_contract',c.source_contract,'source_estimated_hours',c.source_estimated_hours,
        'effective_estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      jsonb_build_object('adjustment_id',a.adjustment_id,'operation_line_id',c.operation_line_id,
        'source_contract',c.source_contract,'source_estimated_hours',c.source_estimated_hours,
        'effective_estimated_hours',a.estimated_hours,'version',a.version,'correction_origin',a.correction_origin),
      jsonb_build_object('source','vehicle_workshop_hours_batch_768.1','request_id',p_idempotency_key,
        'request_hash',v_request_hash,'bookings_changed',false,'parts_changed',false,'completion_changed',false)
    FROM pdc_hours_batch_changes_t780 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    UPDATE public.vehicles SET version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
    WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  ELSE
    v_vehicle_after:=v_vehicle;
  END IF;

  SELECT revision INTO v_revision FROM public.pdc_email_vehicle_revision WHERE singleton;
  v_receipt.response:=jsonb_build_object('ok',true,'code',CASE WHEN v_changed_count>0 THEN 'workshop_hours_batch_saved' ELSE 'workshop_hours_batch_no_changes' END,
    'replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_hash,'vehicle_id',p_vehicle_id,
    'vehicle_version_before',v_vehicle.version,'vehicle_version_after',v_vehicle_after.version,
    'revision',v_revision,'changed_count',v_changed_count,'changes',v_changes,
    'booking_created',false,'parts_mutated',false,'completion_changed',false);
  INSERT INTO public.vehicle_workshop_hours_batch_receipts_768(
    receipt_id,idempotency_key,actor_id,vehicle_id,request_hash,base_vehicle_version,response)
  VALUES(v_receipt_id,p_idempotency_key,v_actor,p_vehicle_id,v_request_hash,v_vehicle.version,v_receipt.response)
  RETURNING * INTO v_receipt;
  RETURN v_receipt.response;
END $function$
;
