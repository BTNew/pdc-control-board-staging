CREATE OR REPLACE FUNCTION pdc_workshop_priority_private.state_hash(p_stock text,p_floor timestamptz)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
 SELECT md5(jsonb_build_object(
  'stock',p_stock,'floor',p_floor,
  'bookings',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_bookings x WHERE deleted_at IS NULL AND status IN('queued','planned','started','stoppage')),
  'vehicles',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.vehicles x WHERE deleted_at IS NULL),
  'bays',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_bays x),
  'stages',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_stages x),
  'classifications',(SELECT md5(string_agg(to_jsonb(x)::text,'' ORDER BY to_jsonb(x)::text)) FROM public.pdc_pilbara_service_classification_current x),
  'classification_history',(SELECT md5(string_agg(to_jsonb(x)::text,'' ORDER BY to_jsonb(x)::text)) FROM public.pdc_pilbara_service_classification_history x),
  'settings',(SELECT jsonb_agg(to_jsonb(x) ORDER BY key) FROM public.workshop_settings x),
  'blocks',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_admin_blocks x WHERE deleted_at IS NULL),
  'assignments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_booking_assignments x WHERE released_at IS NULL),
  'technicians',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.workshop_technicians x),
  'sublet',(SELECT jsonb_agg(to_jsonb(x) ORDER BY booking_id) FROM public.pdc_sublet_booking_instances x),
  'requirements',(SELECT jsonb_agg(to_jsonb(x) ORDER BY vehicle_id,work_key) FROM public.vehicle_work_items x),
  'reviews',(SELECT md5(string_agg(to_jsonb(x)::text,'' ORDER BY vehicle_id)) FROM public.pdc_new_vehicle_reviews x),
  'operations',(SELECT md5(string_agg(to_jsonb(x)::text,'' ORDER BY operation_id)) FROM public.pdc_pilbara_service_operations x),
  'email_operations',(SELECT md5(string_agg(to_jsonb(x)::text,'' ORDER BY to_jsonb(x)::text)) FROM public.pdc_authenticated_email_operation_lines x),
  'adjustments',(SELECT md5(string_agg(to_jsonb(x)::text,'' ORDER BY to_jsonb(x)::text)) FROM public.vehicle_workshop_line_adjustments x)
 )::text)
$fn$;

CREATE OR REPLACE FUNCTION pdc_workshop_priority_private.reschedule(p_vehicle uuid,p_floor timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
#variable_conflict use_column
DECLARE
 v public.vehicles%rowtype; item record; bay record; picked uuid; picked_number integer; best_start timestamptz; best_end timestamptz;
 candidate timestamptz; finish timestamptz; minutes integer; best_minutes integer; earliest timestamptz:=p_floor;
 result jsonb; changes jsonb; targets jsonb; before_snapshot jsonb; after_snapshot jsonb; before_all jsonb;
 target_ids uuid[]; n integer:=0; parking_start timestamptz; b public.workshop_bookings%rowtype;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 SELECT * INTO STRICT v FROM public.vehicles WHERE id=p_vehicle;
 IF v.deleted_at IS NOT NULL OR NOT v.visible_on_board OR v.lifecycle_state<>'active'
    OR public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IS DISTINCT FROM 'PMB'
 THEN RAISE EXCEPTION 'Emergency priority is for vehicles that have arrived at PMB. Update the vehicle location first.'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=p_vehicle AND deleted_at IS NULL
  AND (status='stoppage' OR (status='started' AND greatest(scheduled_end_at,public.workshop_booking_effective_end_at(id))<=p_floor)))
 THEN RAISE EXCEPTION 'Resolve the current stoppage or update the running job before prioritising its remaining work.'; END IF;
 SELECT coalesce(jsonb_object_agg(id,to_jsonb(x)),'{}') INTO before_all FROM public.workshop_bookings x WHERE deleted_at IS NULL;
 -- Existing approved unbooked requirements are created through the standard API.
 -- Preview invokes this inside a rollback subtransaction, so nothing is reserved.
 result:=public.book_all_vehicle_stations(v.id,v.version);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION '%',coalesce(result->>'message','Required work could not be booked.'); END IF;
 DROP TABLE IF EXISTS pg_temp.emergency_effective;
 CREATE TEMP TABLE emergency_effective ON COMMIT DROP AS
 SELECT b.id,greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id)) AS ends
 FROM public.workshop_bookings b WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage');
 CREATE UNIQUE INDEX ON emergency_effective(id);
 DROP TABLE IF EXISTS pg_temp.emergency_plan;
 CREATE TEMP TABLE emergency_plan(
  ordinal bigint PRIMARY KEY,booking_id uuid UNIQUE NOT NULL,vehicle_id uuid NOT NULL,
  stage_id uuid NOT NULL,stage_code text NOT NULL,bay_id uuid,bay_number integer,status text NOT NULL,
  original_start timestamptz NOT NULL,original_end timestamptz NOT NULL,effective_end timestamptz NOT NULL,
  original_minutes integer NOT NULL,minutes integer NOT NULL,version integer NOT NULL,
  final_start timestamptz NOT NULL,final_end timestamptz NOT NULL,
  technicians uuid[] NOT NULL,movable boolean NOT NULL,target boolean NOT NULL,
  changed boolean NOT NULL DEFAULT false,apply_order integer,before_row jsonb NOT NULL,original_bay_id uuid,processed boolean NOT NULL DEFAULT false,parked boolean NOT NULL DEFAULT false
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.emergency_plan
  (ordinal,booking_id,vehicle_id,stage_id,stage_code,bay_id,bay_number,status,original_start,original_end,effective_end,
   original_minutes,minutes,version,final_start,final_end,technicians,movable,target,before_row)
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id),b.id,b.vehicle_id,b.stage_id,s.code,b.bay_id,bay.bay_number,b.status::text,
  b.scheduled_start_at,b.scheduled_end_at,
  greatest(b.scheduled_end_at,(SELECT ends FROM pg_temp.emergency_effective e WHERE e.id=b.id),
    CASE WHEN b.status IN('started','stoppage') OR b.actual_start_at IS NOT NULL THEN p_floor ELSE b.scheduled_end_at END),
  b.default_duration_minutes,b.default_duration_minutes,b.version,b.scheduled_start_at,
  greatest(b.scheduled_end_at,(SELECT ends FROM pg_temp.emergency_effective e WHERE e.id=b.id),
    CASE WHEN b.status IN('started','stoppage') OR b.actual_start_at IS NOT NULL THEN p_floor ELSE b.scheduled_end_at END),
  coalesce((SELECT array_agg(DISTINCT a.technician_id ORDER BY a.technician_id) FROM public.workshop_booking_assignments a
    WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]),
  b.status IN('queued','planned') AND b.actual_start_at IS NULL AND b.bay_id IS NOT NULL
    AND bay.is_active AND s.active AND s.planner_enabled AND NOT b.legacy_ambiguity_quarantined,
  b.vehicle_id=p_vehicle
    AND b.status IN('queued','planned') AND b.actual_start_at IS NULL AND b.bay_id IS NOT NULL
    AND bay.is_active AND NOT b.legacy_ambiguity_quarantined,
  to_jsonb(b)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
   AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 IF (SELECT count(*) FROM pg_temp.emergency_plan)>10000 THEN
  RETURN jsonb_build_object('ok',false,'error','schedule_too_large');
 END IF;

 UPDATE pg_temp.emergency_plan SET original_bay_id=bay_id;
 SELECT array_agg(booking_id) INTO target_ids FROM pg_temp.emergency_plan WHERE target AND movable;
 IF target_ids IS NULL THEN RAISE EXCEPTION 'No remaining planned workshop jobs are available to prioritise.'; END IF;
 IF EXISTS(SELECT 1 FROM pg_temp.emergency_plan WHERE vehicle_id=p_vehicle AND NOT target AND status NOT IN('started','stoppage'))
 THEN RAISE EXCEPTION 'This vehicle has an inactive or unresolved booking. Review its bay before prioritising.'; END IF;
 SELECT greatest(earliest,max(final_end+interval '1 hour')) INTO earliest FROM pg_temp.emergency_plan
  WHERE vehicle_id=p_vehicle AND NOT movable;
 -- Keep this vehicle's station sequence. Pick the earliest finish, then start,
 -- considering efficiency, fixed work, closures, Sublet and assigned technicians.
 FOR item IN SELECT * FROM pg_temp.emergency_plan WHERE booking_id=ANY(target_ids) ORDER BY ordinal LOOP
  IF NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=p_vehicle AND wi.required AND NOT wi.completed
    AND public.workshop_stage_code_for_work_key(wi.work_key)=item.stage_code) THEN
   RAISE EXCEPTION 'Review the completed or no-longer-required booking for % before prioritising.',item.stage_code;
  END IF;
  best_start:=NULL; best_end:=NULL; picked:=NULL;
  FOR bay IN SELECT * FROM public.workshop_bays WHERE stage_id=item.stage_id AND is_active AND NOT is_sublet_row ORDER BY bay_number,id LOOP
   -- An overrun in this bay has no reliable release time yet.
   IF EXISTS(SELECT 1 FROM public.workshop_bookings q WHERE q.bay_id=bay.id AND q.deleted_at IS NULL
     AND q.status IN('started','stoppage') AND greatest(q.scheduled_end_at,public.workshop_booking_effective_end_at(q.id))<=p_floor) THEN CONTINUE; END IF;
   minutes:=public.workshop_capacity_duration_minutes(public.workshop_booking_capacity_base_minutes(item.booking_id),bay.id);
   candidate:=pdc_workshop_priority_private.slot(item.booking_id,bay.id,minutes,earliest,'priority');
   IF candidate IS NULL THEN CONTINUE; END IF;
   finish:=public.workshop_add_operational_minutes(candidate,minutes);
   IF best_end IS NULL OR finish<best_end OR (finish=best_end AND candidate<best_start) THEN
    best_start:=candidate;best_end:=finish;picked:=bay.id;picked_number:=bay.bay_number;best_minutes:=minutes;
   END IF;
  END LOOP;
  IF picked IS NULL THEN RAISE EXCEPTION 'No safe bay is available for %. Check active work and technician availability.',item.stage_code; END IF;
  UPDATE pg_temp.emergency_plan SET bay_id=picked,bay_number=picked_number,minutes=best_minutes,
   final_start=best_start,final_end=best_end,processed=true,
   changed=(original_start IS DISTINCT FROM best_start OR original_end IS DISTINCT FROM best_end OR original_bay_id IS DISTINCT FROM picked OR original_minutes<>best_minutes)
   WHERE booking_id=item.booking_id;
  earliest:=best_end+interval '1 hour';
 END LOOP;
 -- Push only connected conflicts later, preserving other vehicles' original
 -- bay/station/technician ordering. Re-evaluate successors across departments.
 FOR item IN SELECT * FROM pg_temp.emergency_plan WHERE NOT target ORDER BY ordinal LOOP
  IF NOT item.movable THEN CONTINUE; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_temp.emergency_plan x WHERE x.changed AND x.processed
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians)
    AND x.final_start<item.original_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END
    AND x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END>item.original_start)
  THEN UPDATE pg_temp.emergency_plan SET processed=true WHERE booking_id=item.booking_id; CONTINUE; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vehicles z WHERE z.id=item.vehicle_id AND z.deleted_at IS NULL AND z.visible_on_board AND z.lifecycle_state='active'
    AND public.workshop_location_code(coalesce(nullif(z.location_override,''),z.current_location)) IN('PMB','YH','IT')
    AND (public.workshop_location_code(coalesce(nullif(z.location_override,''),z.current_location))<>'IT' OR z.eta_to_kewdale IS NOT NULL)
    AND EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=z.id AND wi.required AND NOT wi.completed AND public.workshop_stage_code_for_work_key(wi.work_key)=item.stage_code)
    AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=z.id AND r.status='pending'))
  THEN RAISE EXCEPTION 'A conflicting vehicle is not eligible for replanning. Review stock %.',(SELECT stock_number FROM public.vehicles WHERE id=item.vehicle_id); END IF;
  candidate:=greatest(p_floor,item.original_start);
  SELECT greatest(candidate,max(x.final_end+CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END))
   INTO candidate FROM pg_temp.emergency_plan x WHERE NOT x.target AND x.ordinal<item.ordinal
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  candidate:=pdc_workshop_priority_private.slot(item.booking_id,item.bay_id,item.minutes,candidate,'follower');
  IF candidate IS NULL THEN RAISE EXCEPTION 'No safe later slot for a conflicting booking.'; END IF;
  finish:=public.workshop_add_operational_minutes(candidate,item.minutes);
  UPDATE pg_temp.emergency_plan SET final_start=candidate,final_end=finish,processed=true,
    changed=(original_start IS DISTINCT FROM candidate OR original_end IS DISTINCT FROM finish) WHERE booking_id=item.booking_id;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_temp.emergency_plan a JOIN pg_temp.emergency_plan b ON a.ordinal<b.ordinal
   WHERE (a.changed OR b.changed) AND
    ((a.bay_id=b.bay_id AND tstzrange(a.final_start,a.final_end,'[)') && tstzrange(b.final_start,b.final_end,'[)'))
     OR (a.vehicle_id=b.vehicle_id AND tstzrange(a.final_start,a.final_end+interval '1 hour','[)') && tstzrange(b.final_start,b.final_end+interval '1 hour','[)'))
     OR (a.technicians && b.technicians AND tstzrange(a.final_start,a.final_end,'[)') && tstzrange(b.final_start,b.final_end,'[)'))))
 THEN RAISE EXCEPTION 'The emergency plan conflicts with protected work. Review the affected bookings.'; END IF;
 -- Apply into free ranges first. If moving earlier creates a dependency cycle,
 -- temporarily park one movable booking after the entire schedule, with all
 -- normal booking/technician/closure guards still enabled. This is atomic and
 -- no temporary placement is retained in the response or booking history.
 LOOP
  EXIT WHEN NOT EXISTS(SELECT 1 FROM pg_temp.emergency_plan WHERE changed AND apply_order IS NULL);
  n:=n+1; IF n>20000 THEN RAISE EXCEPTION 'Too many connected booking changes'; END IF;
  SELECT x.booking_id INTO picked FROM pg_temp.emergency_plan x
   WHERE changed AND apply_order IS NULL AND NOT EXISTS(
    SELECT 1 FROM public.workshop_bookings q WHERE q.id<>x.booking_id AND q.deleted_at IS NULL AND q.status IN('queued','planned','started','stoppage')
     AND (q.bay_id=x.bay_id OR q.vehicle_id=x.vehicle_id OR EXISTS(SELECT 1 FROM public.workshop_booking_assignments a
        WHERE a.booking_id=q.id AND a.released_at IS NULL AND a.technician_id=ANY(x.technicians)))
     AND q.scheduled_start_at<x.final_end AND coalesce((SELECT ends FROM pg_temp.emergency_effective e WHERE e.id=q.id),q.scheduled_end_at)>x.final_start)
   ORDER BY x.ordinal LIMIT 1;
  IF picked IS NULL THEN
   SELECT * INTO item FROM pg_temp.emergency_plan WHERE changed AND apply_order IS NULL AND NOT parked ORDER BY target DESC,ordinal LIMIT 1;
   IF NOT FOUND THEN RAISE EXCEPTION 'No safe order for saving these booking changes.'; END IF;
   SELECT * INTO STRICT b FROM public.workshop_bookings WHERE id=item.booking_id;
   SELECT greatest(p_floor,max(scheduled_end_at),(SELECT max(final_end) FROM pg_temp.emergency_plan))+interval '1 day'
    INTO parking_start FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('queued','planned','started','stoppage');
   parking_start:=pdc_workshop_priority_private.slot(item.booking_id,b.bay_id,b.default_duration_minutes,parking_start,'parking');
   IF parking_start IS NULL THEN RAISE EXCEPTION 'Unable to stage the booking changes safely.'; END IF;
   finish:=public.workshop_add_operational_minutes(parking_start,b.default_duration_minutes);
   UPDATE public.workshop_bookings SET scheduled_start_at=parking_start,scheduled_end_at=finish,updated_by=auth.uid()
    WHERE id=item.booking_id;
   UPDATE public.workshop_booking_assignments SET scheduled_start_at=parking_start,scheduled_end_at=finish,updated_at=clock_timestamp()
    WHERE booking_id=item.booking_id AND released_at IS NULL;
   UPDATE pg_temp.emergency_effective SET ends=finish WHERE id=item.booking_id;
   UPDATE pg_temp.emergency_plan SET parked=true WHERE booking_id=item.booking_id;
   CONTINUE;
  END IF;
  SELECT * INTO STRICT item FROM pg_temp.emergency_plan WHERE booking_id=picked;
  before_snapshot:=item.before_row;
  UPDATE public.workshop_bookings SET bay_id=item.bay_id,scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
    default_duration_minutes=item.minutes,version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid()
    WHERE id=item.booking_id AND version=item.version AND status IN('queued','planned') AND actual_start_at IS NULL AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'A booking changed before the emergency plan could be saved.'; END IF;
  UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,updated_at=clock_timestamp()
    WHERE booking_id=item.booking_id AND released_at IS NULL;
  after_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  PERFORM public.workshop_write_history(item.booking_id,'emergency_priority',before_snapshot,after_snapshot,
    jsonb_build_object('priority_vehicle_id',p_vehicle,'buffer_minutes',60,'source','control_board_emergency'));
  UPDATE pg_temp.emergency_effective SET ends=item.final_end WHERE id=item.booking_id;
  UPDATE pg_temp.emergency_plan SET apply_order=n WHERE booking_id=item.booking_id;
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',b.id,'vehicle_id',b.vehicle_id,'stock_number',z.stock_number,
   'stage_code',s.code,'bay_number',bay.bay_number,'priority',b.vehicle_id=p_vehicle,
   'old_start_at',before_all->b.id::text->'scheduled_start_at','old_end_at',before_all->b.id::text->'scheduled_end_at',
   'new_start_at',b.scheduled_start_at,'new_end_at',b.scheduled_end_at) ORDER BY b.vehicle_id<>p_vehicle,b.scheduled_start_at,b.id),'[]')
 INTO changes FROM public.workshop_bookings b JOIN public.vehicles z ON z.id=b.vehicle_id JOIN public.workshop_stages s ON s.id=b.stage_id
 JOIN public.workshop_bays bay ON bay.id=b.bay_id
 WHERE b.deleted_at IS NULL AND (NOT before_all ? b.id::text OR before_all->b.id::text IS DISTINCT FROM to_jsonb(b));
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',b.id,'stage_code',s.code,'bay_number',bay.bay_number,
   'start_at',b.scheduled_start_at,'end_at',b.scheduled_end_at) ORDER BY b.scheduled_start_at),'[]') INTO targets
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id JOIN public.workshop_bays bay ON bay.id=b.bay_id WHERE b.id=ANY(target_ids);
 RETURN jsonb_build_object('ok',true,'can_apply',true,'vehicle_id',v.id,'stock_number',v.stock_number,'customer',v.customer_name,
  'bookings',targets,'changes',changes,'shifted_count',(SELECT count(*) FROM jsonb_array_elements(changes) x WHERE x->>'vehicle_id'<>p_vehicle::text),
  'buffer_minutes',60);
END $fn$;

CREATE OR REPLACE FUNCTION pdc_workshop_priority_private.request(p_stock_number text,p_apply boolean DEFAULT false,p_plan_hash text DEFAULT NULL,p_idempotency_key uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET statement_timeout='120s' AS $fn$
DECLARE
 stock text:=public.normalize_vehicle_stock_number(p_stock_number); vehicle_id uuid; floor_at timestamptz;
 epoch bigint; fingerprint text; result jsonb; receipt pdc_workshop_priority_private.receipts%rowtype;
 request jsonb:=jsonb_build_object('stock',public.normalize_vehicle_stock_number(p_stock_number),'plan_hash',p_plan_hash);
 failure text; code text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
 PERFORM public.workshop_require_planner_operator();
 IF stock IS NULL OR stock='' OR length(stock)>80 OR p_apply IS NULL THEN RETURN jsonb_build_object('ok',false,'message','Enter a vehicle stock number.'); END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0)) THEN
  RETURN jsonb_build_object('ok',false,'error','busy','message','The schedule is being updated. Try preview again shortly.');
 END IF;
 IF p_apply THEN
  IF p_idempotency_key IS NULL OR p_plan_hash IS NULL THEN RETURN jsonb_build_object('ok',false,'error','review_required','message','Preview the emergency plan first.'); END IF;
  SELECT * INTO receipt FROM pdc_workshop_priority_private.receipts WHERE actor_id=auth.uid() AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
   IF receipt.request IS DISTINCT FROM request THEN RETURN jsonb_build_object('ok',false,'error','idempotency_key_reused','message','Preview the emergency plan again.'); END IF;
   RETURN receipt.response||jsonb_build_object('replay',true);
  END IF;
  IF p_plan_hash !~ '^[0-9]{10,12}\.[a-f0-9]{32}$' THEN RETURN jsonb_build_object('ok',false,'error','stale_preview','message','Preview the emergency plan again.'); END IF;
  epoch:=split_part(p_plan_hash,'.',1)::bigint;floor_at:=to_timestamp(epoch);
  IF floor_at<date_trunc('minute',clock_timestamp()) OR floor_at>clock_timestamp()+interval '15 minutes' THEN
   RETURN jsonb_build_object('ok',false,'error','stale_preview','message','The preview expired. Preview the emergency plan again.');
  END IF;
 ELSE
  epoch:=(floor(extract(epoch FROM clock_timestamp())/900)+1)::bigint*900;floor_at:=to_timestamp(epoch);
 END IF;
 -- Use the same resource lock order as capacity replanning, failing quickly on contention.
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_bays ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_settings ORDER BY key FOR SHARE NOWAIT;
 LOCK TABLE public.vehicles,public.vehicle_work_items,public.workshop_technicians,public.pdc_sublet_booking_instances,
  public.pdc_new_vehicle_reviews,public.pdc_authenticated_email_operation_lines,public.pdc_pilbara_service_operations,
  public.vehicle_workshop_line_adjustments,public.pdc_pilbara_service_classification_current,public.pdc_pilbara_service_classification_history IN SHARE MODE NOWAIT;
 IF (SELECT count(*) FROM public.vehicles WHERE public.normalize_vehicle_stock_number(stock_number)=stock AND deleted_at IS NULL AND visible_on_board AND lifecycle_state='active')<>1 THEN
  RETURN jsonb_build_object('ok',false,'error','vehicle_not_unique','message','No single active vehicle matches that stock number. Check Vehicle Locations.');
 END IF;
 SELECT id INTO vehicle_id FROM public.vehicles WHERE public.normalize_vehicle_stock_number(stock_number)=stock AND deleted_at IS NULL AND visible_on_board AND lifecycle_state='active';
 fingerprint:=epoch::text||'.'||pdc_workshop_priority_private.state_hash(stock,floor_at);
 IF p_apply AND fingerprint IS DISTINCT FROM p_plan_hash THEN RETURN jsonb_build_object('ok',false,'error','stale_preview','message','Bookings changed. Preview the emergency plan again.'); END IF;
 BEGIN
  result:=pdc_workshop_priority_private.reschedule(vehicle_id,floor_at);
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION '%',coalesce(result->>'message','Unable to prepare the emergency plan.'); END IF;
  IF NOT p_apply THEN RAISE EXCEPTION USING ERRCODE='PZ001',MESSAGE='Rollback preview'; END IF;
 EXCEPTION WHEN SQLSTATE 'PZ001' THEN NULL;
 END;
 result:=result||jsonb_build_object('plan_hash',fingerprint,'applied',p_apply,'floor',floor_at);
 IF p_apply THEN INSERT INTO pdc_workshop_priority_private.receipts(actor_id,idempotency_key,request,response) VALUES(auth.uid(),p_idempotency_key,request,result); END IF;
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS failure=MESSAGE_TEXT,code=RETURNED_SQLSTATE;
 RETURN jsonb_build_object('ok',false,'error',CASE WHEN code IN('55P03','40P01','40001') THEN 'busy' ELSE 'emergency_rejected' END,
  'message',CASE WHEN code IN('55P03','40P01','40001') THEN 'The schedule is being updated. Try preview again shortly.' ELSE failure END||' No changes were saved.');
END $fn$;
