-- Department138 shared timer: count recorded work, never buffer/queued waiting.
-- No imported/source estimates or existing elapsed-duration fields are rewritten.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging required'; END IF;
END $guard$;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

CREATE FUNCTION pdc_bus_private.pure_department138_bus(p_vehicle_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT count(*)>0 AND coalesce(bool_and(btrim(l->>'department') IS NOT DISTINCT FROM '138'),false)
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 WHERE l->>'stage_code'='BUS_4X4' AND coalesce((l->>'active')::boolean,true);
$fn$;
REVOKE ALL ON FUNCTION pdc_bus_private.pure_department138_bus(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE pdc_bus_private.activity_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id),
 effective_at timestamptz NOT NULL,
 from_status text,
 to_status text NOT NULL,
 bay_id uuid REFERENCES public.workshop_bays(id),
 is_origin boolean NOT NULL,
 recorded_by uuid REFERENCES auth.users(id),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX bus_activity_booking_idx ON pdc_bus_private.activity_events(booking_id,id);
CREATE INDEX bus_activity_bay_idx ON pdc_bus_private.activity_events(bay_id);
CREATE INDEX bus_activity_actor_idx ON pdc_bus_private.activity_events(recorded_by);
ALTER TABLE pdc_bus_private.activity_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_bus_private.activity_events FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE pdc_bus_private.activity_events_id_seq FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_bus_private.capture_activity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE origin boolean:=false; at_time timestamptz; previous_status text; in_scope boolean;
BEGIN
 IF NEW.actual_start_at IS NULL OR NOT pdc_bus_private.pure_department138_bus(NEW.vehicle_id) THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status AND NEW.bay_id IS NOT DISTINCT FROM OLD.bay_id
 AND NEW.actual_start_at IS NOT DISTINCT FROM OLD.actual_start_at AND NEW.actual_end_at IS NOT DISTINCT FROM OLD.actual_end_at
 AND NEW.deleted_at IS NOT DISTINCT FROM OLD.deleted_at
 THEN RETURN NEW; END IF;
 in_scope:=EXISTS(SELECT 1 FROM pdc_bus_private.activity_events e WHERE e.booking_id=NEW.id);
 IF NOT in_scope AND NOT (pdc_bus_private.active_vehicle(NEW.vehicle_id) AND EXISTS(
 SELECT 1 FROM public.workshop_stages s WHERE s.id=NEW.stage_id AND s.code='BUS_4X4')) THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' THEN
  previous_status:=CASE WHEN OLD.deleted_at IS NOT NULL THEN 'deleted' ELSE OLD.status::text END;
  -- An edited start boundary while already running is not a confirmed resume.
  IF OLD.status='started' AND NEW.status='started' AND OLD.actual_start_at IS DISTINCT FROM NEW.actual_start_at
  THEN previous_status:='unknown_start_boundary'; END IF;
 END IF;
 origin:=NOT in_scope AND NEW.status='started' AND (TG_OP='INSERT' OR OLD.actual_start_at IS NULL)
 AND NEW.actual_start_at<=clock_timestamp() AND NEW.bay_id IS NOT NULL;
 at_time:=CASE WHEN origin THEN NEW.actual_start_at
 WHEN NEW.status='completed' THEN coalesce(NEW.actual_end_at,clock_timestamp())
 WHEN NEW.status='stoppage' THEN coalesce(NEW.stoppage_started_at,clock_timestamp())
 WHEN NEW.status='queued' THEN coalesce(NEW.returned_to_queue_at,clock_timestamp())
 ELSE clock_timestamp() END;
 INSERT INTO pdc_bus_private.activity_events(booking_id,effective_at,from_status,to_status,bay_id,is_origin,recorded_by)
 VALUES(NEW.id,at_time,previous_status,CASE WHEN NEW.deleted_at IS NOT NULL THEN 'deleted' ELSE NEW.status::text END,NEW.bay_id,origin,auth.uid());
 RETURN NEW;
END $fn$;
CREATE TRIGGER bus_activity_events_20260923 AFTER INSERT OR UPDATE OF status,bay_id,actual_start_at,actual_end_at,deleted_at
 ON public.workshop_bookings FOR EACH ROW EXECUTE FUNCTION pdc_bus_private.capture_activity();

CREATE FUNCTION pdc_bus_private.operational_seconds(p_start timestamptz,p_end timestamptz,p_bay_id uuid)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE total numeric:=0; bay integer; code text; local_day timestamp; minutes_at timestamptz;
 lo timestamptz; hi timestamptz; breaks jsonb; closures jsonb;
BEGIN
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RETURN 0; END IF;
 IF p_bay_id IS NULL OR p_end-p_start>interval '730 days' THEN RETURN NULL; END IF;
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF code<>'BUS_4X4' THEN RETURN pdc_fitter_private.operational_seconds(p_start,p_end); END IF;
 SELECT value INTO breaks FROM public.workshop_settings WHERE key='break_windows';
 SELECT value INTO closures FROM public.workshop_settings WHERE key='closures';
 -- Read calendar data once; avoid hundreds of bay/settings queries per elapsed hour.
 FOR local_day IN SELECT d FROM generate_series((p_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
 (p_end AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d LOOP
  IF extract(isodow FROM local_day)>5 OR local_day::date=ANY(pdc_bus_private.public_holiday_dates())
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(closures,'[]'::jsonb)) c WHERE c->>'date'=local_day::date::text) THEN CONTINUE; END IF;
  lo:=greatest(p_start,(local_day+interval '6 hours') AT TIME ZONE 'Australia/Perth');
  hi:=least(p_end,(local_day+CASE WHEN bay IN(8,9) THEN interval '14 hours' ELSE interval '15 hours' END) AT TIME ZONE 'Australia/Perth');
  IF hi<=lo THEN CONTINUE; END IF;
  FOR minutes_at IN SELECT m FROM generate_series(date_trunc('minute',lo),date_trunc('minute',hi),interval '1 minute') m LOOP
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(breaks,'[]'::jsonb)) b
    WHERE (minutes_at AT TIME ZONE 'Australia/Perth')::time>=(b->>'start')::time
    AND (minutes_at AT TIME ZONE 'Australia/Perth')::time<(b->>'end')::time
    AND ((b?'date' AND b->>'date'=local_day::date::text) OR (NOT(b?'date') AND
     lower(coalesce(b->>'scope',b->>'day','global')) IN('global','working_day',lower(to_char(local_day,'FMDay')))))) THEN
    total:=total+greatest(0,extract(epoch FROM least(hi,minutes_at+interval '1 minute')-greatest(lo,minutes_at)));
   END IF;
  END LOOP;
 END LOOP;
 RETURN total;
END $fn$;

CREATE FUNCTION pdc_bus_private.activity_timer(p_booking_id uuid,p_as_of timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE b public.workshop_bookings; e record; prev_at timestamptz; prev_status text; prev_bay uuid;
 known boolean:=true; seen boolean:=false; total numeric:=0; value numeric; running boolean:=false; boundary timestamptz;
BEGIN
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
 IF b.actual_start_at IS NULL AND EXISTS(SELECT 1 FROM pdc_bus_private.activity_events WHERE booking_id=b.id) THEN known:=false; END IF;
 IF b.actual_start_at IS NOT NULL THEN
  FOR e IN SELECT * FROM pdc_bus_private.activity_events WHERE booking_id=b.id ORDER BY id LOOP
   IF NOT seen THEN
    seen:=true; known:=e.is_origin AND e.to_status='started' AND e.bay_id IS NOT NULL;
    IF NOT known THEN EXIT; END IF;
   ELSE
    IF e.effective_at<prev_at OR e.is_origin OR e.from_status IS DISTINCT FROM prev_status THEN known:=false; EXIT; END IF;
    IF prev_status='started' AND prev_at<p_as_of THEN
     value:=pdc_bus_private.operational_seconds(prev_at,least(e.effective_at,p_as_of),prev_bay);
     IF value IS NULL THEN known:=false; EXIT; END IF;
     total:=total+value;
    END IF;
   END IF;
   prev_at:=e.effective_at;prev_status:=e.to_status;prev_bay:=e.bay_id;
   IF e.effective_at>p_as_of THEN EXIT; END IF;
  END LOOP;
  known:=known AND seen;
  IF known AND prev_at<=p_as_of THEN
   -- A changed current state without its evidence event is incomplete, not an invented pause.
   IF prev_status IS DISTINCT FROM (CASE WHEN b.deleted_at IS NOT NULL THEN 'deleted' ELSE b.status::text END)
   OR prev_bay IS DISTINCT FROM b.bay_id THEN known:=false; END IF;
   IF known AND prev_status='started' THEN
    value:=pdc_bus_private.operational_seconds(prev_at,p_as_of,prev_bay);
    IF value IS NULL THEN known:=false; ELSE total:=total+value; END IF;
    running:=known AND b.actual_end_at IS NULL AND pdc_bus_private.minute_available(p_as_of,prev_bay);
   END IF;
  END IF;
 END IF;
 IF running THEN
  boundary:=date_trunc('minute',p_as_of)+interval '1 minute';
  WHILE boundary<p_as_of+interval '1 day' AND pdc_bus_private.minute_available(boundary,prev_bay) LOOP
   boundary:=boundary+interval '1 minute';
  END LOOP;
 END IF;
 RETURN jsonb_build_object('elapsed_seconds',CASE WHEN known THEN floor(total) ELSE NULL END,
 'running',running AND known,'as_of',p_as_of,'next_change_at',CASE WHEN running AND known THEN boundary END,
 'history_complete',known,'review_required',NOT known,'basis','department138_bay_working_hours',
 'message',CASE WHEN NOT known THEN 'Progress update required: timing history is incomplete.' END);
END $fn$;
CREATE OR REPLACE FUNCTION pdc_fitter_private.timing_pre_dept138_20260923(p_booking_id uuid, p_as_of timestamp with time zone DEFAULT statement_timestamp())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
END $function$
;

CREATE OR REPLACE FUNCTION pdc_fitter_private.timing(p_booking_id uuid,p_as_of timestamptz DEFAULT statement_timestamp())
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE b public.workshop_bookings;
BEGIN
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND deleted_at IS NULL;
 IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
 IF pdc_bus_private.pure_department138_bus(b.vehicle_id) AND (EXISTS(SELECT 1 FROM pdc_bus_private.activity_events WHERE booking_id=b.id)
 OR (pdc_bus_private.active_vehicle(b.vehicle_id) AND EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=b.stage_id AND code='BUS_4X4')))
 THEN RETURN jsonb_build_object('actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
 'stoppage_started_at',b.stoppage_started_at,'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,
 'server_now',p_as_of,'timer',pdc_bus_private.activity_timer(b.id,p_as_of)); END IF;
 RETURN pdc_fitter_private.timing_pre_dept138_20260923(p_booking_id,p_as_of);
END $fn$;

-- Historical helper work can be entered after a started vehicle is unallocated.
-- Exact membership dates, actual start, no future work, note and version still required.
CREATE OR REPLACE FUNCTION public.record_pdc_bus_helper_labour(p_booking_id uuid, p_expected_version integer, p_technician_id uuid, p_worked_at timestamp with time zone, p_minutes integer, p_note text, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE b public.workshop_bookings; prior pdc_bus_private.receipts; result jsonb; request_hash text; before_data jsonb;
BEGIN
 IF auth.uid() IS NULL OR coalesce(public.current_pdc_user_role()::text,'') NOT IN('operator','administrator')
 THEN RAISE EXCEPTION 'Operator or administrator required' USING errcode='42501'; END IF;
 IF p_request_id IS NULL OR p_expected_version IS NULL OR p_technician_id IS NULL OR p_worked_at IS NULL
 OR p_minutes IS NULL OR p_minutes NOT BETWEEN 1 AND 720 OR length(btrim(coalesce(p_note,''))) NOT BETWEEN 1 AND 2000
 THEN RETURN jsonb_build_object('ok',false,'error','invalid_helper_labour'); END IF;
 request_hash:=md5(jsonb_build_array('helper_labour',p_booking_id,p_expected_version,p_technician_id,p_worked_at,p_minutes,p_note)::text);
 PERFORM pg_advisory_xact_lock(hashtextextended('bus-request:'||auth.uid()||':'||p_request_id,0));
 SELECT * INTO prior FROM pdc_bus_private.receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
  IF prior.request_hash<>request_hash THEN RETURN jsonb_build_object('ok',false,'error','request_conflict'); END IF;
  RETURN prior.result||jsonb_build_object('replayed',true);
 END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND OR b.deleted_at IS NOT NULL OR b.status NOT IN('started','stoppage','completed','queued') OR b.actual_start_at IS NULL
 OR NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=b.stage_id AND code='BUS_4X4')
 OR NOT pdc_bus_private.pure_department138_bus(b.vehicle_id)
 THEN RETURN jsonb_build_object('ok',false,'error','started_department138_booking_required'); END IF;
 IF b.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 IF p_worked_at<b.actual_start_at OR p_worked_at>least(clock_timestamp(),coalesce(b.actual_end_at,clock_timestamp()))
 OR NOT EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.technician_id=p_technician_id AND a.assignment_type='secondary'
  AND a.assigned_at<=p_worked_at AND (a.released_at IS NULL OR a.released_at>=p_worked_at))
 THEN RETURN jsonb_build_object('ok',false,'error','helper_assignment_or_work_time_invalid'); END IF;
 before_data:=public.workshop_booking_snapshot(b.id);
 INSERT INTO pdc_bus_private.helper_labour(booking_id,technician_id,worked_at,minutes,note,recorded_by,request_id)
 VALUES(b.id,p_technician_id,p_worked_at,p_minutes,btrim(p_note),auth.uid(),p_request_id);
 UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
 result:=jsonb_build_object('ok',true,'booking',public.workshop_booking_snapshot(b.id));
 PERFORM public.workshop_write_history(b.id,'helper_labour_recorded',before_data,result->'booking',
 jsonb_build_object('request_id',p_request_id,'separate_person_minutes',true));
 INSERT INTO pdc_bus_private.receipts(actor_id,request_id,request_hash,result) VALUES(auth.uid(),p_request_id,request_hash,result);
 RETURN result||jsonb_build_object('revision',public.workshop_bump_revision());
END $function$
;

REVOKE ALL ON FUNCTION pdc_bus_private.capture_activity(),
 pdc_bus_private.operational_seconds(timestamptz,timestamptz,uuid),
 pdc_bus_private.activity_timer(uuid,timestamptz),
 pdc_fitter_private.timing_pre_dept138_20260923(uuid,timestamptz)
 FROM PUBLIC,anon,authenticated,service_role;

-- The shared crew APIs are also Department138-only, including mixed-line safeguards.
CREATE OR REPLACE FUNCTION public.set_pdc_bus_booking_team(p_booking_id uuid, p_expected_version integer, p_primary_technician_id uuid, p_helper_technician_ids uuid[], p_request_id uuid, p_note text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE b public.workshop_bookings; h uuid; members uuid[]; result jsonb; prior pdc_bus_private.receipts;
 request_hash text; before_data jsonb; problem jsonb;
BEGIN
 IF auth.uid() IS NULL OR coalesce(public.current_pdc_user_role()::text,'') NOT IN('operator','administrator')
 THEN RAISE EXCEPTION 'Operator or administrator required' USING errcode='42501'; END IF;
 IF p_request_id IS NULL OR p_expected_version IS NULL OR p_primary_technician_id IS NULL
 OR p_helper_technician_ids IS NULL OR cardinality(p_helper_technician_ids)>8 OR length(coalesce(p_note,''))>2000
 THEN RETURN jsonb_build_object('ok',false,'error','invalid_team'); END IF;
 members:=ARRAY[p_primary_technician_id]||p_helper_technician_ids;
 IF EXISTS(SELECT 1 FROM unnest(members) m WHERE m IS NULL)
 OR cardinality(members)<>(SELECT count(DISTINCT m) FROM unnest(members) m)
 THEN RETURN jsonb_build_object('ok',false,'error','invalid_team'); END IF;
 request_hash:=md5(jsonb_build_array('booking_team',p_booking_id,p_expected_version,p_primary_technician_id,p_helper_technician_ids,p_note)::text);
 PERFORM pg_advisory_xact_lock(hashtextextended('bus-request:'||auth.uid()||':'||p_request_id,0));
 SELECT * INTO prior FROM pdc_bus_private.receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
  IF prior.request_hash<>request_hash THEN RETURN jsonb_build_object('ok',false,'error','request_conflict'); END IF;
  RETURN prior.result||jsonb_build_object('replayed',true);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND OR b.deleted_at IS NOT NULL OR b.status NOT IN('planned','queued','started','stoppage') OR b.bay_id IS NULL
 OR NOT pdc_bus_private.active_vehicle(b.vehicle_id) OR NOT pdc_bus_private.pure_department138_bus(b.vehicle_id) OR NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=b.stage_id AND code='BUS_4X4')
 THEN RETURN jsonb_build_object('ok',false,'error','active_department138_booking_required'); END IF;
 IF b.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 FOREACH h IN ARRAY ARRAY(SELECT m FROM unnest(members) m ORDER BY m) LOOP
  PERFORM public.workshop_lock_resources(NULL,h);
  IF NOT EXISTS(SELECT 1 FROM public.workshop_technicians t WHERE id=h AND active AND role_type='technician'
   AND (cardinality(t.can_fit_stages)=0 OR 'BUS_4X4'=ANY(t.can_fit_stages)))
  THEN RETURN jsonb_build_object('ok',false,'error','technician_unavailable','technician_id',h); END IF;
  problem:=public.workshop_validate_booking(b.id,b.vehicle_id,b.stage_id,b.bay_id,b.scheduled_start_at,
   b.scheduled_end_at,b.default_duration_minutes,b.status,h,true);
  IF problem->>'ok' IS DISTINCT FROM 'true' THEN RETURN problem||jsonb_build_object('technician_id',h); END IF;
 END LOOP;
 before_data:=public.workshop_booking_snapshot(b.id);
 UPDATE public.workshop_booking_assignments SET released_at=clock_timestamp(),updated_at=clock_timestamp()
 WHERE booking_id=b.id AND released_at IS NULL;
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at,notes)
 SELECT b.id,m,CASE WHEN m=p_primary_technician_id THEN 'primary' ELSE 'secondary' END::public.workshop_assignment_type,
 auth.uid(),b.scheduled_start_at,b.scheduled_end_at,coalesce(p_note,'') FROM unnest(members) m;
 UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
 result:=jsonb_build_object('ok',true,'booking',public.workshop_booking_snapshot(b.id));
 PERFORM public.workshop_write_history(b.id,'team_changed',before_data,result->'booking',
 jsonb_build_object('note',coalesce(p_note,''),'request_id',p_request_id,'single_physical_booking',true));
 INSERT INTO pdc_bus_private.receipts(actor_id,request_id,request_hash,result) VALUES(auth.uid(),p_request_id,request_hash,result);
 RETURN result||jsonb_build_object('revision',public.workshop_bump_revision());
END $function$
;
