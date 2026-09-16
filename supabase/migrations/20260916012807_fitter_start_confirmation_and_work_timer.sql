-- Confirm fitter actions from the same canonical booking read by the planners.
-- Timers count workshop opening time and exclude actual recorded stoppages.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.operational_seconds(p_start timestamptz,p_end timestamptz)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE a timestamptz:=date_trunc('minute',p_start); z timestamptz:=date_trunc('minute',p_end); seconds numeric;
BEGIN
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RETURN 0; END IF;
 seconds:=public.workshop_operational_minutes_between(a,z)*60;
 IF public.workshop_calendar_minute_available(a) THEN seconds:=seconds-extract(epoch FROM p_start-a); END IF;
 IF public.workshop_calendar_minute_available(z) THEN seconds:=seconds+extract(epoch FROM p_end-z); END IF;
 RETURN greatest(0,seconds);
END $fn$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.running_until(p_as_of timestamptz)
RETURNS timestamptz LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE settings jsonb; windows jsonb; day date:=(p_as_of AT TIME ZONE 'Australia/Perth')::date;
 day_name text:=lower(to_char(day,'FMDay')); boundary record;
BEGIN
 IF NOT public.workshop_calendar_minute_available(p_as_of) THEN RETURN NULL; END IF;
 SELECT jsonb_object_agg(key,value) INTO settings FROM public.workshop_settings
 WHERE key IN('day_start_time','day_end_time','break_windows','overtime_windows');
 windows:=coalesce(settings->'break_windows','[]'::jsonb)||coalesce(settings->'overtime_windows','[]'::jsonb);
 FOR boundary IN SELECT DISTINCT (day::timestamp+make_interval(mins=>n)) AT TIME ZONE 'Australia/Perth' at_time
 FROM (
  SELECT ceil(extract(epoch FROM (settings->>'day_start_time')::time)/60)::integer n
  UNION ALL SELECT ceil(extract(epoch FROM (settings->>'day_end_time')::time)/60)::integer
  UNION ALL SELECT 1440
  UNION ALL SELECT ceil(extract(epoch FROM t)/60)::integer FROM jsonb_array_elements(windows) w
   CROSS JOIN LATERAL(VALUES((w->>'start')::time),((w->>'end')::time)) times(t)
   WHERE (w ? 'date' AND w->>'date'=day::text)
    OR (NOT(w ? 'date') AND lower(coalesce(w->>'scope',w->>'day','global')) IN('global','working_day',day_name))
 ) x WHERE (day::timestamp+make_interval(mins=>n)) AT TIME ZONE 'Australia/Perth'>p_as_of ORDER BY at_time
 LOOP
  IF NOT public.workshop_calendar_minute_available(boundary.at_time) THEN RETURN boundary.at_time; END IF;
 END LOOP;
 RETURN date_trunc('minute',p_as_of)+interval '1 minute';
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
 RETURN date_trunc('minute',p_as_of)+interval '1 minute';
END $fn$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.timing(p_booking_id uuid,p_as_of timestamptz DEFAULT statement_timestamp())
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE b public.workshop_bookings%rowtype; stop_at timestamptz; seconds numeric:=0; paused numeric:=0;
 recorded_wall_minutes integer:=0; missing_minutes integer:=0; running boolean:=false; row record;
BEGIN
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND deleted_at IS NULL;
 IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
 IF b.actual_start_at IS NOT NULL THEN
  stop_at:=least(coalesce(b.actual_end_at,p_as_of),p_as_of);
  seconds:=pdc_fitter_private.operational_seconds(b.actual_start_at,stop_at);
  -- Resume and completion evidence carry the preceding open stoppage. The
  -- legacy accumulated counter is wall minutes and cannot be subtracted from
  -- opening-hours time when a stoppage crosses a night or a weekend.
  FOR row IN
   SELECT (h.before_data->>'stoppage_started_at')::timestamptz pause_start,
    CASE WHEN h.event_type='completed' THEN coalesce((h.after_data->>'actual_end_at')::timestamptz,h.created_at)
     ELSE h.created_at END pause_end
   FROM public.workshop_booking_history h WHERE h.booking_id=b.id AND h.event_type IN('resumed','completed')
    AND h.before_data->>'stoppage_started_at' IS NOT NULL
  LOOP
   paused:=paused+pdc_fitter_private.operational_seconds(greatest(row.pause_start,b.actual_start_at),least(row.pause_end,stop_at));
   recorded_wall_minutes:=recorded_wall_minutes+greatest(0,floor(extract(epoch FROM row.pause_end-row.pause_start)/60)::integer);
  END LOOP;
  IF b.status='stoppage' AND b.stoppage_started_at IS NOT NULL THEN
   paused:=paused+pdc_fitter_private.operational_seconds(greatest(b.stoppage_started_at,b.actual_start_at),stop_at);
  END IF;
  -- Old imported counters without individual history remain conservative and
  -- explicitly marked incomplete instead of inventing exact work intervals.
  missing_minutes:=greatest(0,coalesce(b.stoppage_accumulated_minutes,0)-recorded_wall_minutes);
  seconds:=greatest(0,seconds-paused-missing_minutes*60);
  running:=b.status='started' AND b.actual_end_at IS NULL AND p_as_of>=b.actual_start_at
    AND public.workshop_calendar_minute_available(p_as_of);
 END IF;
 RETURN jsonb_build_object('actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
  'stoppage_started_at',b.stoppage_started_at,'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,
  'server_now',p_as_of,'timer',jsonb_build_object('elapsed_seconds',floor(seconds),'running',running,
    'as_of',p_as_of,'next_change_at',CASE WHEN running THEN pdc_fitter_private.running_until(p_as_of) END,
    'history_complete',missing_minutes=0,'basis','workshop_opening_hours'));
END $fn$;

REVOKE ALL ON FUNCTION pdc_fitter_private.operational_seconds(timestamptz,timestamptz),
 pdc_fitter_private.running_until(timestamptz),pdc_fitter_private.timing(uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;

-- Existing public function ACLs and role checks are retained by CREATE OR REPLACE.
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
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision())
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

CREATE OR REPLACE FUNCTION public.get_fitter_job(p_technician_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; lines jsonb;
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 lines:=pdc_fitter_private.lines(b.vehicle_id,b.id);
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'version',b.version,
   'status',b.status,'stage_code',code,'stoppage_reason',b.stoppage_reason,'lines',lines,
   'progress',pdc_fitter_private.summary(lines,code),
   'catalog_hash',md5((SELECT coalesce(jsonb_agg(l->>'scope_hash' ORDER BY l->>'line_identity'),'[]'::jsonb)::text
      FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'=code)))
   ||pdc_fitter_private.timing(b.id,statement_timestamp());
END $function$;

CREATE OR REPLACE FUNCTION public.get_fitter_jobs(p_technician_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT EXISTS(SELECT 1 FROM public.workshop_technicians WHERE id=p_technician_id AND active)
 THEN RETURN jsonb_build_object('ok',false,'error','mechanic_unavailable'); END IF;
 RETURN jsonb_build_object('ok',true,'generated_at',statement_timestamp(),'server_now',statement_timestamp(),'technician_id',p_technician_id,
 'bays',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.display_name,
   'number',b.bay_number,'stage',s.display_name,'active',b.is_active) ORDER BY s.sort_order,b.bay_number),'[]'::jsonb)
   FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.default_technician_id=p_technician_id AND s.active AND s.is_physical AND NOT b.is_sublet_row),
 'jobs',(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,'version',b.version,'status',b.status,'stage_code',s.code,'stage_name',s.display_name,
    'bay_id',bay.id,'bay_number',bay.bay_number,'bay_name',bay.display_name,'bay_active',bay.is_active,
    'start_at',b.scheduled_start_at,'end_at',b.scheduled_end_at,
    'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
    'stoppage_started_at',b.stoppage_started_at,'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,
    'stoppage_reason',b.stoppage_reason,'vehicle_id',v.id,'stock',v.stock_number,
    'job_card',v.job_card_number,'customer',v.customer_name,'vehicle',v.vehicle_description,
    'progress',pdc_fitter_private.progress(b.id)
  ) ORDER BY CASE b.status WHEN 'started' THEN 0 WHEN 'stoppage' THEN 1 ELSE 2 END,
   b.scheduled_start_at NULLS LAST,b.id),'[]'::jsonb)
  FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  JOIN public.workshop_bays bay ON bay.id=b.bay_id
  JOIN public.vehicles v ON v.id=b.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
  WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND s.is_physical AND NOT s.is_sublet AND pdc_fitter_private.assigned(b.id,p_technician_id)));
END $function$;
