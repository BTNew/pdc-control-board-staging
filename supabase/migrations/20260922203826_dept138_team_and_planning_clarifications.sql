-- Bhavesh email 1a0c9a2b31476530, owner authorised action 23 September 2026.
-- One physical booking; helpers reserve staff, not another bay or shorter duration.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging required'; END IF;
END $guard$;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

CREATE TABLE pdc_bus_private.helper_labour(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id),
 technician_id uuid NOT NULL REFERENCES public.workshop_technicians(id),
 worked_at timestamptz NOT NULL,
 minutes integer NOT NULL CHECK(minutes BETWEEN 1 AND 720),
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 1 AND 2000),
 recorded_by uuid NOT NULL REFERENCES auth.users(id),
 request_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(recorded_by,request_id)
);
CREATE INDEX bus_helper_labour_booking_idx ON pdc_bus_private.helper_labour(booking_id);
CREATE INDEX bus_helper_labour_technician_idx ON pdc_bus_private.helper_labour(technician_id);
ALTER TABLE pdc_bus_private.helper_labour ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_bus_private.helper_labour FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_bus_private.team_payload(p_booking_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT jsonb_build_object(
 'helper_assignments',coalesce((SELECT jsonb_agg(jsonb_build_object('technician_id',a.technician_id,
 'technician_name',t.name,'assignment_type',a.assignment_type) ORDER BY t.name,a.technician_id)
 FROM public.workshop_booking_assignments a JOIN public.workshop_technicians t ON t.id=a.technician_id
 WHERE a.booking_id=p_booking_id AND a.released_at IS NULL AND a.assignment_type='secondary'),'[]'::jsonb),
 'helper_technician_ids',coalesce((SELECT jsonb_agg(a.technician_id ORDER BY a.technician_id)
 FROM public.workshop_booking_assignments a WHERE a.booking_id=p_booking_id AND a.released_at IS NULL AND a.assignment_type='secondary'),'[]'::jsonb),
 'helper_assignment_history',coalesce((SELECT jsonb_agg(jsonb_build_object('technician_id',a.technician_id,
 'technician_name',t.name,'assigned_at',a.assigned_at,'released_at',a.released_at) ORDER BY a.assigned_at,a.id)
 FROM public.workshop_booking_assignments a JOIN public.workshop_technicians t ON t.id=a.technician_id
 WHERE a.booking_id=p_booking_id AND a.assignment_type='secondary'),'[]'::jsonb),
 'helper_labour_minutes',coalesce((SELECT sum(h.minutes) FROM pdc_bus_private.helper_labour h WHERE h.booking_id=p_booking_id),0),
 'helper_labour',coalesce((SELECT jsonb_agg(jsonb_build_object('id',h.id,'technician_id',h.technician_id,
 'technician_name',t.name,'worked_at',h.worked_at,'minutes',h.minutes,'note',h.note,'recorded_at',h.recorded_at) ORDER BY h.worked_at,h.id)
 FROM pdc_bus_private.helper_labour h JOIN public.workshop_technicians t ON t.id=h.technician_id
 WHERE h.booking_id=p_booking_id),'[]'::jsonb));
$fn$;

CREATE FUNCTION pdc_bus_private.public_holiday_dates()
RETURNS date[] LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT ARRAY['2026-01-01','2026-01-26','2026-03-02','2026-04-03','2026-04-05','2026-04-06',
 '2026-04-25','2026-04-27','2026-06-01','2026-09-28','2026-12-25','2026-12-26','2026-12-28',
 '2027-01-01','2027-01-26','2027-03-01','2027-03-26','2027-03-28','2027-03-29','2027-04-25',
 '2027-04-26','2027-06-07','2027-09-27','2027-12-25','2027-12-26','2027-12-27','2027-12-28']::date[];
$fn$;
REVOKE ALL ON FUNCTION pdc_bus_private.public_holiday_dates() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_bus_private.planning_calendar()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 -- Perth public holidays, confirmed WA Government published 2 September 2026.
 -- https://www.wa.gov.au/service/employment/workplace-arrangements/public-holidays-western-australia
 WITH closed AS(
 SELECT unnest(pdc_bus_private.public_holiday_dates())::text d
 UNION SELECT x->>'date' FROM public.workshop_settings s
 CROSS JOIN LATERAL jsonb_array_elements(s.value) x
 WHERE s.key='closures' AND x->>'date' ~ '^\d{4}-\d{2}-\d{2}$'
 ) SELECT jsonb_build_object('closures',(SELECT jsonb_agg(d ORDER BY d) FROM closed),
 'timezone','Australia/Perth','verified',true,'verified_from','2026-01-01','verified_through','2027-12-31',
 'source','WA Government public holidays + configured workshop closures');
$fn$;

CREATE OR REPLACE FUNCTION pdc_bus_private.minute_available(p_at timestamptz,p_bay_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE bay integer; code text; local_at timestamp; breaks jsonb; closures jsonb;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' THEN RETURN public.workshop_calendar_minute_available(p_at); END IF;
 local_at:=p_at AT TIME ZONE 'Australia/Perth';
 SELECT coalesce(value,'[]'::jsonb) INTO breaks FROM public.workshop_settings WHERE key='break_windows';
 SELECT coalesce(value,'[]'::jsonb) INTO closures FROM public.workshop_settings WHERE key='closures';
 RETURN extract(isodow FROM local_at) BETWEEN 1 AND 5 AND local_at::time>=time '06:00'
 AND local_at::time<CASE WHEN bay IN(8,9) THEN time '14:00' ELSE time '15:00' END
 AND NOT (local_at::date=ANY(pdc_bus_private.public_holiday_dates()))
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(closures,'[]'::jsonb)) c WHERE c->>'date'=local_at::date::text)
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(breaks,'[]'::jsonb)) b
 WHERE local_at::time>=(b->>'start')::time AND local_at::time<(b->>'end')::time
 AND ((b?'date' AND b->>'date'=local_at::date::text) OR (NOT(b?'date') AND
 lower(coalesce(b->>'scope',b->>'day','global')) IN('global','working_day',lower(to_char(local_at,'FMDay'))))));
END $fn$;

CREATE OR REPLACE FUNCTION public.workshop_upsert_primary_assignment(
 p_booking_id uuid,p_technician_id uuid,p_start timestamptz,p_end timestamptz,p_notes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE b public.workshop_bookings; preserve_helpers boolean;
BEGIN
 SELECT * INTO STRICT b FROM public.workshop_bookings WHERE id=p_booking_id;
 preserve_helpers:=pdc_bus_private.active_vehicle(b.vehicle_id)
 AND EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=b.stage_id AND code='BUS_4X4');
 UPDATE public.workshop_booking_assignments SET released_at=now(),updated_at=now()
 WHERE booking_id=p_booking_id AND released_at IS NULL
 AND (CASE WHEN preserve_helpers AND assignment_type='secondary'
   THEN p_technician_id IS NULL OR technician_id=p_technician_id
   ELSE p_technician_id IS NULL OR technician_id<>p_technician_id OR assignment_type<>'primary' END);
 IF p_technician_id IS NULL THEN RETURN; END IF;
 INSERT INTO public.workshop_booking_assignments(booking_id,technician_id,assignment_type,assigned_by,scheduled_start_at,scheduled_end_at,notes)
 VALUES(p_booking_id,p_technician_id,'primary',auth.uid(),
 CASE WHEN preserve_helpers THEN b.scheduled_start_at ELSE p_start END,
 CASE WHEN preserve_helpers THEN b.scheduled_end_at ELSE p_end END,p_notes)
 ON CONFLICT(booking_id) WHERE assignment_type='primary' AND released_at IS NULL
 DO UPDATE SET technician_id=excluded.technician_id,assigned_by=excluded.assigned_by,
 scheduled_start_at=excluded.scheduled_start_at,scheduled_end_at=excluded.scheduled_end_at,
 notes=excluded.notes,released_at=NULL,updated_at=now();
END $fn$;

CREATE FUNCTION pdc_bus_private.sync_team_intervals()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
BEGIN
 IF NOT pdc_bus_private.active_vehicle(NEW.vehicle_id) OR NOT EXISTS(
 SELECT 1 FROM public.workshop_stages WHERE id=NEW.stage_id AND code='BUS_4X4') THEN RETURN NEW; END IF;
 IF NEW.deleted_at IS NOT NULL OR NEW.status NOT IN('queued','planned','started','stoppage') OR NEW.bay_id IS NULL THEN
  UPDATE public.workshop_booking_assignments SET released_at=clock_timestamp(),updated_at=clock_timestamp()
  WHERE booking_id=NEW.id AND released_at IS NULL AND assignment_type='secondary';
 ELSIF NEW.scheduled_start_at IS DISTINCT FROM OLD.scheduled_start_at OR NEW.scheduled_end_at IS DISTINCT FROM OLD.scheduled_end_at
  OR NEW.bay_id IS DISTINCT FROM OLD.bay_id THEN
  -- The assignment validator and exclusion constraint check every helper and primary atomically.
  UPDATE public.workshop_booking_assignments SET scheduled_start_at=NEW.scheduled_start_at,
  scheduled_end_at=NEW.scheduled_end_at,updated_at=clock_timestamp()
  WHERE booking_id=NEW.id AND released_at IS NULL;
 END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER bus_team_intervals_20260923 AFTER UPDATE OF scheduled_start_at,scheduled_end_at,bay_id,status,deleted_at
 ON public.workshop_bookings FOR EACH ROW EXECUTE FUNCTION pdc_bus_private.sync_team_intervals();

CREATE FUNCTION public.set_pdc_bus_booking_team(p_booking_id uuid,p_expected_version integer,
 p_primary_technician_id uuid,p_helper_technician_ids uuid[],p_request_id uuid,p_note text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
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
 OR NOT pdc_bus_private.active_vehicle(b.vehicle_id) OR NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=b.stage_id AND code='BUS_4X4')
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
END $fn$;

CREATE FUNCTION public.record_pdc_bus_helper_labour(p_booking_id uuid,p_expected_version integer,p_technician_id uuid,
 p_worked_at timestamptz,p_minutes integer,p_note text,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
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
 IF NOT FOUND OR b.deleted_at IS NOT NULL OR b.status NOT IN('started','stoppage','completed') OR b.actual_start_at IS NULL
 OR NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=b.stage_id AND code='BUS_4X4')
 OR NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=b.vehicle_id AND o.department='138')
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
END $fn$;
CREATE OR REPLACE FUNCTION public.workshop_booking_snapshot(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with active_assignment as (
    select a.booking_id, a.technician_id, t.name as technician_name, a.assignment_type
    from public.workshop_booking_assignments a
    join public.workshop_technicians t on t.id = a.technician_id
    where a.booking_id = p_booking_id
      and a.released_at is null
    order by case when a.assignment_type = 'primary' then 0 else 1 end, a.assigned_at desc
    limit 1
  )
  select jsonb_build_object(
    'booking_id', b.id,
    'vehicle_id', b.vehicle_id,
    'vehicle', jsonb_build_object(
      'bus_workflow_department138', pdc_bus_private.active_vehicle(v.id),'permanent_vehicle_id', v.permanent_vehicle_id,
      'stock_number', v.stock_number,
      'job_card_number', v.job_card_number,
      'customer_name', v.customer_name,
      'model', v.model
    ),
    'stage', jsonb_build_object(
      'id', s.id,
      'code', s.code,
      'display_name', s.display_name,
      'sort_order', s.sort_order
    ),
    'bay', case when bay.id is null then null else jsonb_build_object(
      'id', bay.id,
      'bay_number', bay.bay_number,
      'code', bay.code,
      'display_name', bay.display_name,
      'is_sublet_row', bay.is_sublet_row
    ) end,
    'status', b.status,
    'scheduled_start_at', b.scheduled_start_at,
    'scheduled_end_at', b.scheduled_end_at,
    'default_duration_minutes', b.default_duration_minutes,'bus_calendar_version', b.bus_calendar_version,
    'capacity_base_minutes',coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric),
    'capacity_efficiency_percent',coalesce(b.capacity_efficiency_percent,100),
    'capacity_estimate_minutes',b.capacity_estimate_minutes,
    'actual_start_at', b.actual_start_at,
    'actual_end_at', b.actual_end_at,
    'actual_duration_minutes', b.actual_duration_minutes,
    'stoppage_reason', b.stoppage_reason,
    'stoppage_started_at', b.stoppage_started_at,
    'stoppage_accumulated_minutes', b.stoppage_accumulated_minutes,
    'returned_to_queue_at', b.returned_to_queue_at,
    'deleted_at', b.deleted_at,
    'deleted_reason', b.deleted_reason,
    'version', b.version,
    'assignment', case when aa.technician_id is null then null else jsonb_build_object(
      'technician_id', aa.technician_id,
      'technician_name', aa.technician_name,
      'assignment_type', aa.assignment_type
    ) end,
    'updated_at', b.updated_at,
    'created_at', b.created_at
  )||pdc_bus_private.team_payload(b.id)
  from public.workshop_bookings b
  join public.vehicles v on v.id = b.vehicle_id
  join public.workshop_stages s on s.id = b.stage_id
  left join public.workshop_bays bay on bay.id = b.bay_id
  left join active_assignment aa on aa.booking_id = b.id
  where b.id = p_booking_id;
$function$;

CREATE OR REPLACE FUNCTION public.workshop_planner_booking_dto(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 with aa as(
  select a.booking_id,a.technician_id,t.name technician_name,a.assignment_type
  from public.workshop_booking_assignments a join public.workshop_technicians t on t.id=a.technician_id
  where a.booking_id=p_booking_id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1)
 select jsonb_build_object(
  'booking_id',b.id,'vehicle_id',b.vehicle_id,
  'stage',jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key),
  'bay',case when bay.id is null then null else jsonb_build_object('id',bay.id,'bay_number',bay.bay_number,'code',bay.code,'display_name',bay.display_name) end,
  'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',public.workshop_booking_effective_end_at(b.id),
  'default_duration_minutes',public.workshop_booking_effective_duration_minutes(b.id),
  'estimated_operation_hours',case when b.status in('queued','planned','started','stoppage') then public.workshop_vehicle_stage_estimated_hours(b.vehicle_id,s.code) else null end,
  'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
  'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
  'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,'version',b.version,
  'assignment',case when aa.technician_id is null then null else jsonb_build_object('technician_id',aa.technician_id,'technician_name',aa.technician_name,'assignment_type',aa.assignment_type) end)||pdc_bus_private.team_payload(b.id)
 from public.workshop_bookings b
 join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
 join public.workshop_stages s on s.id=b.stage_id left join public.workshop_bays bay on bay.id=b.bay_id
 left join aa on aa.booking_id=b.id where b.id=p_booking_id and b.deleted_at is null
$function$;

CREATE OR REPLACE FUNCTION public.workshop_enforce_assignment_validation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_booking public.workshop_bookings%rowtype; v_result jsonb;
begin
  if new.released_at is not null then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('workshop:technician:'||new.technician_id::text,0));
  select * into v_booking from public.workshop_bookings where id=new.booking_id;
  if not found or v_booking.deleted_at is not null or v_booking.status not in ('queued','planned','started','stoppage') then
    raise exception 'Active booking is required for active technician assignment' using errcode='22023';
  end if;
  if new.scheduled_start_at is distinct from v_booking.scheduled_start_at or new.scheduled_end_at is distinct from v_booking.scheduled_end_at then
    raise exception 'Assignment interval must equal booking interval' using errcode='22023';
  end if;
  v_result:=public.workshop_validate_booking(v_booking.id,v_booking.vehicle_id,v_booking.stage_id,v_booking.bay_id,
    v_booking.scheduled_start_at,v_booking.scheduled_end_at,v_booking.default_duration_minutes,v_booking.status,new.technician_id,
    pdc_bus_private.active_vehicle(v_booking.vehicle_id) AND EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=v_booking.stage_id AND code='BUS_4X4'));
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'Workshop Planner validation rejected assignment: %',v_result::text using errcode='22023';
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.workshop_overlay_canonical_booking_fields_397(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_bookings jsonb;
BEGIN
  IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot->'bookings') IS DISTINCT FROM 'array' THEN
    RETURN p_snapshot;
  END IF;

  SELECT coalesce(jsonb_agg(
    CASE WHEN b.id IS NULL THEN item.booking ELSE item.booking||jsonb_build_object(
      'scheduled_start_at',b.scheduled_start_at,
      'scheduled_end_at',b.scheduled_end_at,
      'default_duration_minutes',b.default_duration_minutes,'bus_calendar_version',b.bus_calendar_version,
      'capacity_base_minutes',coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric),
    'capacity_efficiency_percent',coalesce(b.capacity_efficiency_percent,100),
    'capacity_estimate_minutes',b.capacity_estimate_minutes,
      'fitter_progress',pdc_fitter_private.progress(b.id),
      'status',b.status,
      'version',b.version,
      'actual_start_at',b.actual_start_at,
      'actual_end_at',b.actual_end_at,
      'stoppage_reason',b.stoppage_reason,
      'stoppage_started_at',b.stoppage_started_at,
      'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes
    )||pdc_bus_private.team_payload(b.id) END ORDER BY item.ordinality),'[]'::jsonb)
  INTO v_bookings
  FROM jsonb_array_elements(p_snapshot->'bookings') WITH ORDINALITY AS item(booking,ordinality)
  LEFT JOIN public.workshop_bookings b
    ON b.id=CASE
      WHEN coalesce(item.booking->>'booking_id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'booking_id')::uuid
      WHEN coalesce(item.booking->>'id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'id')::uuid
    END;

  RETURN jsonb_set(p_snapshot,'{bookings}',v_bookings,true)||jsonb_build_object('planning_calendar',pdc_bus_private.planning_calendar());
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
   'vehicle_id',b.vehicle_id,'supplier_lines',pdc_bus_private.supplier_lines(b.vehicle_id),'status',b.status,'stage_code',code,'stoppage_reason',b.stoppage_reason,'lines',lines,
   'progress',pdc_fitter_private.summary(lines,code),
   'catalog_hash',md5((SELECT coalesce(jsonb_agg(l->>'scope_hash' ORDER BY l->>'line_identity'),'[]'::jsonb)::text
      FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'=code)))
   ||pdc_fitter_private.timing(b.id,statement_timestamp())||pdc_bus_private.team_payload(b.id);
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
  )||pdc_bus_private.team_payload(b.id) ORDER BY CASE b.status WHEN 'started' THEN 0 WHEN 'stoppage' THEN 1 ELSE 2 END,
   b.scheduled_start_at NULLS LAST,b.id),'[]'::jsonb)
  FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  JOIN public.workshop_bays bay ON bay.id=b.bay_id
  JOIN public.vehicles v ON v.id=b.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
  WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND s.is_physical AND NOT s.is_sublet AND pdc_fitter_private.assigned(b.id,p_technician_id)));
END $function$;

CREATE OR REPLACE FUNCTION pdc_bus_private.snapshot(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE plan jsonb; vers integer; h text; ready jsonb; item record;
BEGIN
 IF NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',false,'error','active_department138_required'); END IF;
 SELECT w.plan,w.version INTO plan,vers FROM pdc_bus_private.workflow w WHERE w.vehicle_id=p_vehicle_id;
 plan:=coalesce(plan,'{}'::jsonb); h:=pdc_bus_private.catalog_hash(p_vehicle_id);
 ready:=coalesce(plan->'parts_readiness','{}'::jsonb);
 FOR item IN SELECT * FROM jsonb_each(ready) LOOP
  IF item.value->>'scope_hash' IS DISTINCT FROM h THEN
   ready:=jsonb_set(ready,ARRAY[item.key],item.value||jsonb_build_object('ready',null,'review_required',true));
  END IF;
 END LOOP;
 RETURN jsonb_build_object('current_stage','','next_stage','','waiting_reason','',
 'forecasts','{}'::jsonb,'qa_status','required','pit_status','required','rustproof_status',
 CASE WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(pdc_bus_private.supplier_lines(p_vehicle_id)) x WHERE x->>'supplier_phase'='late') THEN 'required' ELSE 'not_required' END,
 'wash_status','required','rft_status','not_ready','notes','')||plan||
 jsonb_build_object('ok',true,'vehicle_id',p_vehicle_id,'version',coalesce(vers,0),'scope_hash',h,
 'parts_readiness',ready,'supplier_lines',pdc_bus_private.supplier_lines(p_vehicle_id),
 'bookings',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',bay.bay_number,
  'status',b.status,'stage_code',s.code,'start_at',b.scheduled_start_at,'end_at',b.scheduled_end_at,
  'planned_minutes',b.default_duration_minutes,'actual_minutes',b.actual_duration_minutes,
  'technician_name',(SELECT t.name FROM public.workshop_technicians t WHERE t.id=coalesce(
   (SELECT a.technician_id FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL ORDER BY CASE WHEN a.assignment_type='primary' THEN 0 ELSE 1 END,a.assigned_at DESC LIMIT 1),bay.default_technician_id)),
  'technician_id',coalesce((SELECT a.technician_id FROM public.workshop_booking_assignments a
  WHERE a.booking_id=b.id AND a.released_at IS NULL ORDER BY CASE WHEN a.assignment_type='primary' THEN 0 ELSE 1 END,a.assigned_at DESC LIMIT 1),bay.default_technician_id)
 )||pdc_bus_private.team_payload(b.id) ORDER BY b.scheduled_start_at),'[]'::jsonb)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
 WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')),
 'booking_rules',jsonb_build_object('department','138','mechanical_shift','06:00–15:00',
 'electrical_shift','06:00–14:00','weekdays_only',true,'bay3_coaster_allowed',false,
 'buffer_working_days',jsonb_build_array(2,3),'pit_notice_hours',jsonb_build_array(48,72),
 'pit_notice_calendar_confirmed',true,'net_productive_capacity_confirmed',true,
 'no_automatic_reschedule',true),
 'planning_defaults',jsonb_build_object('qa_minutes',180,'pit_notice_working_days',jsonb_build_array(2,3)),
 'planning_calendar',pdc_bus_private.planning_calendar());
END $function$;

-- The confirmed Nick identity updates only the future default of an unused bay.
-- Andy is the existing Andrew; no duplicate technician or authentication account.
DO $resource$
DECLARE nick uuid; andrew uuid; bay public.workshop_bays; before_data jsonb; before_bookings text;
BEGIN
 SELECT id INTO STRICT nick FROM public.workshop_technicians WHERE name='Nick Darker' AND code='1747' AND active AND role_type='technician';
 SELECT id INTO STRICT andrew FROM public.workshop_technicians WHERE name='Andrew McCormick' AND code='2371' AND active AND role_type='technician';
 SELECT b.* INTO STRICT bay FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE s.code='BUS_4X4' AND b.bay_number=8 FOR UPDATE OF b;
 before_data:=to_jsonb(bay);
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]')::text) INTO before_bookings FROM public.workshop_bookings b;
 IF bay.default_technician_id IS NOT NULL AND bay.default_technician_id<>nick THEN RAISE EXCEPTION 'Bay8 default changed; review required'; END IF;
 IF bay.default_technician_id IS NULL THEN
  IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE bay_id=bay.id) THEN RAISE EXCEPTION 'Bay8 has history; explicit existing booking review required'; END IF;
  UPDATE public.workshop_bays SET default_technician_id=nick,version=version+1,updated_by=NULL WHERE id=bay.id;
 END IF;
 INSERT INTO pdc_bus_private.resource_configuration_audit(change_key,source_message_id,approved_by,before_resources,after_resources,review_items,preserved_bookings_md5)
 VALUES('dept138_confirmed_names_20260923','1a0c9a2b31476530','Craig Watson authorised action 23 September 2026',
 before_data,(SELECT to_jsonb(b) FROM public.workshop_bays b WHERE id=bay.id),
 jsonb_build_array(jsonb_build_object('email_name','Andy McCormick','confirmed_name','Andrew McCormick','technician_id',andrew),
 jsonb_build_object('email_typo','Nick Darter','confirmed_name','Nick Darker','technician_id',nick,'main_bay',8,'full_productive_shift','06:00-14:00')),
 before_bookings);
 IF before_bookings IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]')::text) FROM public.workshop_bookings b)
 THEN RAISE EXCEPTION 'Existing booking changed'; END IF;
END $resource$;

REVOKE ALL ON FUNCTION pdc_bus_private.team_payload(uuid),pdc_bus_private.planning_calendar(),pdc_bus_private.sync_team_intervals()
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.set_pdc_bus_booking_team(uuid,integer,uuid,uuid[],uuid,text),
 public.record_pdc_bus_helper_labour(uuid,integer,uuid,timestamptz,integer,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.set_pdc_bus_booking_team(uuid,integer,uuid,uuid[],uuid,text),
 public.record_pdc_bus_helper_labour(uuid,integer,uuid,timestamptz,integer,text,uuid) TO authenticated;

-- Named electrical technicians retain their 06:00-14:00 availability in any bay.
CREATE FUNCTION pdc_bus_private.technician_shift_problem(p_technician_id uuid,p_bay_id uuid,p_start timestamptz,p_end timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE tech_name text;
BEGIN
 SELECT name INTO tech_name FROM public.workshop_technicians WHERE id=p_technician_id;
 IF tech_name NOT IN('Nick Darker','Gabriel Colborne') OR tech_name IS NULL THEN RETURN NULL; END IF;
 IF EXISTS(
 SELECT 1 FROM generate_series((p_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
  (p_end AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
 CROSS JOIN LATERAL generate_series((d+interval '14 hours') AT TIME ZONE 'Australia/Perth',
  (d+interval '14 hours 59 minutes') AT TIME ZONE 'Australia/Perth',interval '1 minute') m
 WHERE m>=p_start AND m<p_end AND pdc_bus_private.minute_available(m,p_bay_id))
 THEN RETURN jsonb_build_object('ok',false,'error','bus_technician_shift_conflict',
 'technician_id',p_technician_id,'technician_name',tech_name,'shift_end','14:00',
 'message','This technician works 06:00-14:00; use an electrical-shift booking or choose a crew available for this complete booking.'); END IF;
 RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION pdc_bus_private.technician_shift_problem(uuid,uuid,timestamptz,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
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
    select a.booking_id into v_conflict from public.workshop_booking_assignments a
    where a.booking_id is distinct from p_booking_id and a.technician_id=p_technician_id and a.released_at is null
      and tstzrange(a.scheduled_start_at,public.workshop_booking_effective_end_at(a.booking_id),'[)') && tstzrange(p_scheduled_start_at,v_candidate_end,'[)')
    order by a.scheduled_start_at,a.id limit 1;
    if v_conflict is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict_booking_id',v_conflict); end if;
  end if;
  return jsonb_build_object('ok',true);
end $function$
;
