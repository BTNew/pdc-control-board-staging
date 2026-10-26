-- REVIEW CANDIDATE ONLY. Staging; no operational rows are changed by this DDL.
-- Derived from exact estimate engine a338ae78a36b80bf9474bab846e1f851.
-- The existing estimate engine and all validators remain untouched.
-- Complete staging-management deployment transaction; do not split.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';
DO $running_growth_deployment_gate$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR auth.uid() IS NOT NULL
  OR NOT pdc_codex_intake_private.management_connection()
  OR current_setting('app.environment',true)='production'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'running_growth_deployment_staging_management_required'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0))
 THEN RAISE EXCEPTION 'running_growth_deployment_clock_busy'; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0))
 THEN RAISE EXCEPTION 'running_growth_deployment_mutation_busy'; END IF;
END
$running_growth_deployment_gate$;
DO $running_growth_up$
DECLARE helper_metadata jsonb; pins_before jsonb; check_before jsonb; owner_name text;
 engine_sql text:=$engine_sql$CREATE OR REPLACE FUNCTION pdc_operation_updates_private.reconcile_running_growth_20261026(p_booking_id uuid, p_minutes integer, p_actor uuid, p_source text)
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
 root_booking public.workshop_bookings; p_vehicle_id uuid;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Operation approval is available on staging only.';
 END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 -- Only an existing running physical reservation can own this expansion.
 SELECT b.* INTO root_booking FROM public.workshop_bookings b
 JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE b.id=p_booking_id AND b.deleted_at IS NULL AND b.bay_id IS NOT NULL
  AND b.status IN('started','stoppage') AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET'
 FOR UPDATE OF b;
 IF NOT FOUND OR p_minutes IS NULL OR p_minutes NOT BETWEEN 1 AND 59999 THEN
  RAISE EXCEPTION 'A valid running reservation and duration are required.'
   USING ERRCODE='22023',DETAIL='running_growth_invalid_root';
 END IF;
 p_vehicle_id:=root_booking.vehicle_id;
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
  changed boolean NOT NULL DEFAULT false,before_row jsonb NOT NULL,calendar_bay_id uuid
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.pdc_tune_cascade_plan
  (ordinal,booking_id,vehicle_id,stage_id,stage_code,bay_id,status,original_start,original_end,
   original_minutes,minutes,version,final_start,final_end,technicians,before_row,calendar_bay_id)
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id),b.id,b.vehicle_id,b.stage_id,s.code,b.bay_id,b.status::text,
  b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,b.default_duration_minutes,b.version,
  b.scheduled_start_at,b.scheduled_end_at,
  coalesce((SELECT array_agg(DISTINCT a.technician_id) FROM public.workshop_booking_assignments a
    WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]),to_jsonb(b),
  CASE WHEN s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND b.bay_id IS NOT NULL
  AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 SELECT count(*) INTO graph_count FROM pg_temp.pdc_tune_cascade_plan;
 IF graph_count>10000 THEN RAISE EXCEPTION 'The workshop queue needs a smaller scheduling review.'
  USING DETAIL='operation_schedule_limit'; END IF;
 -- The caller supplies its authoritative base plus accepted extra work minutes.
 -- Expand only this running root; never manufacture or silently select another reservation.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan
  WHERE booking_id=p_booking_id AND status IN('started','stoppage') ORDER BY ordinal
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
  minutes:=p_minutes;
  IF minutes IS NULL OR minutes<1 THEN
   RAISE EXCEPTION 'This change would leave a booked station without work. Move or remove its booking before approving.'
    USING DETAIL='operation_schedule_empty_station';
  END IF;
  -- Reducing an estimate must not shorten a job that is already in progress.
  IF item.status IN('started','stoppage') THEN minutes:=greatest(minutes,item.original_minutes); END IF;
  proposed_end:=greatest(item.original_end,pdc_bus_private.clock_add_minutes(item.original_start,minutes,item.calendar_bay_id));
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
    proposed_start:=CASE WHEN item.calendar_bay_id IS NULL THEN public.workshop_admin_next_operational_minute(proposed_start)
     ELSE pdc_bus_private.clock_next_minute(proposed_start,item.calendar_bay_id) END;
    IF proposed_start IS NULL THEN RAISE EXCEPTION 'No open workshop time was found for this change.'
     USING DETAIL='operation_schedule_calendar_unavailable'; END IF;
   END IF;
   proposed_end:=pdc_bus_private.clock_add_minutes(proposed_start,minutes,item.calendar_bay_id);
   IF item.booking_id=p_booking_id THEN proposed_end:=greatest(proposed_end,item.original_end); END IF;
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
   default_duration_minutes=item.minutes,version=version+1,updated_by=coalesce(p_actor,updated_by),updated_at=clock_timestamp()
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
  IF auth.uid() IS NULL THEN
   -- System work keeps a system actor; never impersonate a previous staff user.
   -- The existing generic audit accepts NULL actors; workshop history requires a named user.
   PERFORM public.audit_pdc_event('update'::public.audit_action,'workshop_bookings',item.booking_id,item.vehicle_id,old_snapshot,new_snapshot,
    jsonb_build_object('source','running_growth_cascade_20261026','trigger_source',p_source,'actor_kind','system',
     'event_type','operation_change_schedule_updated','root_booking_id',p_booking_id,
     'approved_vehicle_id',p_vehicle_id,'buffer_minutes',60,'previous_duration_minutes',item.original_minutes,
     'duration_minutes',item.minutes,'moved',item.final_start IS DISTINCT FROM item.original_start));
  ELSE
   PERFORM public.workshop_write_history(item.booking_id,'operation_change_schedule_updated',old_snapshot,new_snapshot,
    jsonb_build_object('source','running_growth_cascade_20261026','trigger_source',p_source,'root_booking_id',p_booking_id,
     'approved_vehicle_id',p_vehicle_id,'buffer_minutes',60,'previous_duration_minutes',item.original_minutes,
     'duration_minutes',item.minutes,'moved',item.final_start IS DISTINCT FROM item.original_start));
  END IF;
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
$engine_sql$;
 helper_sql text:=$helper_sql$CREATE OR REPLACE FUNCTION public.workshop_extend_running_booking_538(p_booking_id uuid, p_source text, p_added_minutes integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE b public.workshop_bookings; planned integer; extra integer; new_end timestamptz; n integer;
 calendar_bay_id uuid; saved public.workshop_bookings;
BEGIN
 -- A running booking keeps the start already recorded. The finish moves later to the planner length,
 -- including hours added from another station. It is never pulled earlier.
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND OR b.deleted_at IS NOT NULL OR b.status NOT IN ('started'::public.workshop_booking_status,'stoppage'::public.workshop_booking_status) THEN
  RETURN jsonb_build_object('ok',true,'extended',false,'reason','not_running');
 END IF;
 planned:=public.workshop_booking_effective_duration_minutes(b.id);
 SELECT coalesce(sum(round((l->>'estimated_hours')::numeric*60)),0)::integer INTO extra
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(b.vehicle_id)) l
  JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE coalesce((l->>'active')::boolean,true)
   AND l->>'stage_code' IS DISTINCT FROM s.code
   AND jsonb_typeof(l->'estimated_hours')='number'
   AND EXISTS (SELECT 1 FROM pdc_fitter_private.operation_progress p WHERE p.booking_id=b.id AND p.line_identity=l->>'line_identity');
 planned:=greatest(coalesce(planned,0),0)+greatest(coalesce(extra,0),0);
 IF planned<1 OR b.scheduled_start_at IS NULL THEN
  RETURN jsonb_build_object('ok',true,'extended',false,'reason','hours_unknown','planned_minutes',planned);
 END IF;
 SELECT CASE WHEN s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END
  INTO calendar_bay_id FROM public.workshop_stages s WHERE s.id=b.stage_id;
 new_end:=pdc_bus_private.clock_add_minutes(b.scheduled_start_at,planned,calendar_bay_id);
 IF new_end IS NULL OR new_end<=b.scheduled_end_at THEN
  RETURN jsonb_build_object('ok',true,'extended',false,'reason','already_covers','scheduled_end_at',b.scheduled_end_at,'planned_minutes',planned);
 END IF;
 BEGIN
  PERFORM pdc_operation_updates_private.reconcile_running_growth_20261026(b.id,planned,auth.uid(),p_source);
  SELECT * INTO saved FROM public.workshop_bookings WHERE id=b.id;
  IF NOT FOUND OR saved.vehicle_id IS DISTINCT FROM b.vehicle_id OR saved.deleted_at IS NOT NULL
   OR saved.status IS DISTINCT FROM b.status OR saved.scheduled_start_at IS DISTINCT FROM b.scheduled_start_at
   OR saved.actual_start_at IS DISTINCT FROM b.actual_start_at OR saved.default_duration_minutes<planned
   OR saved.default_duration_minutes<b.default_duration_minutes OR saved.scheduled_end_at<new_end THEN
   RAISE EXCEPTION 'running_growth_readback_mismatch';
  END IF;
  planned:=saved.default_duration_minutes; new_end:=saved.scheduled_end_at;
 EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'The running job could not be extended. Its start was left where it is.';
 END;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','workshop_bookings',b.id,b.vehicle_id,auth.uid(),public.current_actor_email(),
  jsonb_build_object('status',b.status,'default_duration_minutes',b.default_duration_minutes,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,'actual_start_at',b.actual_start_at),
  jsonb_build_object('default_duration_minutes',planned,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',new_end,'actual_start_at',b.actual_start_at,'accounted','running_job_end_extended','planned_minutes',planned,'other_station_minutes',extra,'added_minutes',p_added_minutes),
  jsonb_build_object('source',coalesce(p_source,'running_booking_end_538')));
 RETURN jsonb_build_object('ok',true,'extended',true,'scheduled_end_at',new_end,'planned_minutes',planned,'other_station_minutes',extra);
END
$function$
$helper_sql$;
 old_check text:=$old_check$
SELECT
 (SELECT md5(p.prosrc)='f0e6e008fa511fcbbe0e87f17f3dd7b3'
   AND p.prosrc LIKE '%running_job_end_extended%'
   AND p.prosrc LIKE '%scheduled_start_at IS NOT DISTINCT FROM%'
   AND p.prosrc LIKE '%actual_start_at IS NOT DISTINCT FROM%'
   AND strpos(p.prosrc, '::public.workshop_booking_status')>0
   AND p.proconfig::text LIKE '%search_path=pg_catalog%'
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)'))
 AND (SELECT md5(p.prosrc)=(SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e
    WHERE e.signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND e.release='r538')
   AND p.prosrc LIKE '%workshop_extend_running_booking_538%'
   AND p.prosrc LIKE '%keeps its start%'
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
 AND EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE t.tgname='workshop_extend_running_after_hours_538' AND n.nspname='public' AND c.relname='vehicle_workshop_line_adjustments' AND NOT t.tgisinternal)
 AND EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE t.tgname='fitter_extend_other_station_538' AND n.nspname='pdc_fitter_private' AND c.relname='operation_progress' AND NOT t.tgisinternal)
 AND (
  pg_catalog.to_regprocedure('karratha135_pdc.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)') IS NULL
  OR (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('karratha135_pdc.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
   IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
 ) AS ok,
 'running booking finish includes hours added from another station' AS detail
$old_check$;
 new_check text:=$new_check$
SELECT
 (SELECT md5(p.prosrc)='37a4c927372e9df884f5d187ab51d1c7'
   AND p.prosrc LIKE '%running_job_end_extended%'
   AND p.prosrc LIKE '%saved.scheduled_start_at IS DISTINCT FROM b.scheduled_start_at%'
   AND p.prosrc LIKE '%saved.actual_start_at IS DISTINCT FROM b.actual_start_at%'
   AND strpos(p.prosrc, '::public.workshop_booking_status')>0
   AND p.proconfig::text LIKE '%search_path=pg_catalog%'
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)'))
 AND (SELECT md5(p.prosrc)=(SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e
    WHERE e.signature='public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)' AND e.release='r538')
   AND p.prosrc LIKE '%workshop_extend_running_booking_538%'
   AND p.prosrc LIKE '%keeps its start%'
  FROM pg_catalog.pg_proc p
  WHERE p.oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
 AND EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE t.tgname='workshop_extend_running_after_hours_538' AND n.nspname='public' AND c.relname='vehicle_workshop_line_adjustments' AND NOT t.tgisinternal)
 AND EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE t.tgname='fitter_extend_other_station_538' AND n.nspname='pdc_fitter_private' AND c.relname='operation_progress' AND NOT t.tgisinternal)
 AND (
  pg_catalog.to_regprocedure('karratha135_pdc.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)') IS NULL
  OR (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('karratha135_pdc.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
   IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)'))
 )
 AND (SELECT md5(prosrc)='079644c4c29195a9262582547a57d276' AND NOT prosecdef
   FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)'))
 AND NOT has_function_privilege('authenticated','pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)','EXECUTE')
 AND NOT has_function_privilege('anon','pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)','EXECUTE')
 AS ok,
 'running booking finish includes hours added from another station' AS detail
$new_check$;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 IF md5(pg_get_functiondef(to_regprocedure('pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)'))) IS DISTINCT FROM 'a338ae78a36b80bf9474bab846e1f851' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_capacity_plan(text,uuid,integer,timestamptz)'))) IS DISTINCT FROM '89c6e721f0715ec435ec538c334838f0' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_capacity_plan(text,uuid,integer,timestamptz)'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_extend_running_after_hours_538()'))) IS DISTINCT FROM '1b2c507e05f0247bec9d41446e2cb5eb' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_extend_running_after_hours_538()'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_reconcile_adjustment_booking_duration()'))) IS DISTINCT FROM 'ef3116918cfb1d1c44cc45ef6e425bab' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_reconcile_adjustment_booking_duration()'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.clock_add_minutes(timestamptz,integer,uuid)')) IS DISTINCT FROM 'd0a395e6739423c1e4f5f2329fa5cd75' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.clock_add_minutes(timestamptz,integer,uuid)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.clock_next_minute(timestamptz,uuid)')) IS DISTINCT FROM '734b6fc0d468b8a8a9cee2b955f9b21b' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.clock_next_minute(timestamptz,uuid)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.add_minutes(timestamptz,integer,uuid)')) IS DISTINCT FROM 'c43afa5c1312392aa5d3666a8aa7cf65' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.add_minutes(timestamptz,integer,uuid)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.active_vehicle(uuid)')) IS DISTINCT FROM '7b033ee2e646cc4411b17876df3b279d' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.active_vehicle(uuid)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_bus_private.booking_shift_guard()')) IS DISTINCT FROM '245d4bf9a0324bc65563f48c1a62c619' THEN RAISE EXCEPTION 'running_growth_dependency_changed: pdc_bus_private.booking_shift_guard()'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')) IS DISTINCT FROM 'ae08aa9b0dc99e7c93b1710efdcb5070' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_enforce_assignment_validation()')) IS DISTINCT FROM 'e270480a19b571c79e960fca2d1a2fb2' THEN RAISE EXCEPTION 'running_growth_dependency_changed: public.workshop_enforce_assignment_validation()'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_find_technician_conflict(uuid,uuid,timestamptz,timestamptz)')) IS DISTINCT FROM 'daea24a73f5e571bfd8cf5e3fac856f9' THEN RAISE EXCEPTION 'running_growth_dependency_changed: workshop_find_technician_conflict'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.audit_pdc_event(public.audit_action,text,uuid,uuid,jsonb,jsonb,jsonb)')) IS DISTINCT FROM '8abc0d10dc601bcdbbb195502856cf13' THEN RAISE EXCEPTION 'running_growth_dependency_changed: audit_pdc_event'; END IF;
 SELECT to_jsonb(p)-'prosrc' INTO STRICT helper_metadata FROM pg_proc p WHERE oid=to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)');
 SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY signature),'[]') INTO pins_before FROM pdc_ops.expected_function_md5 e;
 SELECT to_jsonb(c) INTO STRICT check_before FROM pdc_ops.regression_checks c WHERE check_name='running_booking_end_538' AND fault_id='F152' AND sort_order=317;

 IF md5(pg_get_functiondef(to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)'))) IS DISTINCT FROM 'f70d2eb94c4825f8ec61efb4354a3dbe' THEN RAISE EXCEPTION 'Running helper source changed'; END IF;
 IF to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'Running growth private function already exists'; END IF;
 -- Normalize only the source literals when a Windows runner serializes this file.
 engine_sql:=replace(engine_sql,chr(13),''); helper_sql:=replace(helper_sql,chr(13),'');
 old_check:=replace(old_check,chr(13),''); new_check:=replace(new_check,chr(13),'');
 IF check_before->>'check_sql' IS DISTINCT FROM old_check THEN RAISE EXCEPTION 'r538 regression check source changed'; END IF;
 IF md5(engine_sql)<>'a53b5d76a81b6a42aef826d8d433170f' OR md5(helper_sql)<>'876704abdee272bb2724cb640c895c33' THEN RAISE EXCEPTION 'Candidate literal changed'; END IF;
 EXECUTE engine_sql;
 SELECT pg_get_userbyid(proowner) INTO STRICT owner_name FROM pg_proc WHERE oid=to_regprocedure('pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)');
 EXECUTE format('ALTER FUNCTION pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text) OWNER TO %I',owner_name);
 REVOKE ALL ON FUNCTION pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
 EXECUTE helper_sql;
 UPDATE pdc_ops.regression_checks SET check_sql=new_check WHERE check_name='running_booking_end_538' AND fault_id='F152' AND sort_order=317 AND check_sql=old_check;
 IF NOT FOUND THEN RAISE EXCEPTION 'r538 check update missed'; END IF;
 IF md5(pg_get_functiondef(to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)'))) IS DISTINCT FROM 'a53b5d76a81b6a42aef826d8d433170f'
 OR md5(pg_get_functiondef(to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)'))) IS DISTINCT FROM '876704abdee272bb2724cb640c895c33' THEN RAISE EXCEPTION 'Running growth definition readback mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
 WHERE p.oid=to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)') AND a.grantee<>p.proowner) THEN RAISE EXCEPTION 'Private running growth function has external grants'; END IF;
 IF (SELECT p.prosecdef OR p.proowner<>e.proowner OR p.proconfig IS DISTINCT FROM e.proconfig FROM pg_proc p,pg_proc e
 WHERE p.oid=to_regprocedure('pdc_operation_updates_private.reconcile_running_growth_20261026(uuid,integer,uuid,text)') AND e.oid=to_regprocedure('pdc_operation_updates_private.reconcile_estimate_bookings_20261018(uuid,text[],uuid,uuid)')) THEN RAISE EXCEPTION 'Private running growth metadata mismatch'; END IF;
 IF (SELECT to_jsonb(p)-'prosrc' FROM pg_proc p WHERE oid=to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)')) IS DISTINCT FROM helper_metadata THEN RAISE EXCEPTION 'Running helper metadata changed'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY signature),'[]') FROM pdc_ops.expected_function_md5 e) IS DISTINCT FROM pins_before THEN RAISE EXCEPTION 'Function pins changed'; END IF;
 IF (SELECT to_jsonb(c)-'check_sql' FROM pdc_ops.regression_checks c WHERE check_name='running_booking_end_538' AND fault_id='F152' AND sort_order=317) IS DISTINCT FROM check_before-'check_sql' THEN RAISE EXCEPTION 'Regression check metadata changed'; END IF;
END $running_growth_up$;
COMMIT;

