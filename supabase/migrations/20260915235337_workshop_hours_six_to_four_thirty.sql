-- User-requested 06:00–16:30 weekday calendar. Run through authenticated admin UI.
CREATE FUNCTION public.get_workshop_hours_for_setup()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
BEGIN
 PERFORM public.require_pdc_role('administrator');
 RETURN jsonb_build_object('ok',true,'settings',(SELECT jsonb_object_agg(key,value) FROM public.workshop_settings WHERE key IN('day_start_time','day_end_time','working_week')));
END $fn$;
CREATE FUNCTION public.set_workshop_hours_0600_1630()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET statement_timeout='180s' SET lock_timeout='10s' AS $fn$
DECLARE plan record; candidate timestamptz; finish timestamptz; blocked_until timestamptz;
 earliest timestamptz; horizon timestamptz; skip_day date; result jsonb; current_version integer; changes integer;
BEGIN
 PERFORM public.require_pdc_role('administrator');
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'STAGING only'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 IF (SELECT value FROM public.workshop_settings WHERE key='day_start_time')='"06:00"'::jsonb
 AND (SELECT value FROM public.workshop_settings WHERE key='day_end_time')='"16:30"'::jsonb
 THEN RETURN jsonb_build_object('ok',true,'already_applied',true,'changed_bookings',0); END IF;
 DROP TABLE IF EXISTS pg_temp.workshop_hours_repair_plan;
CREATE TEMP TABLE workshop_hours_repair_plan ON COMMIT DROP AS
 SELECT b.*,s.code,bay.bay_number,v.stock_number,NULL::timestamptz next_start,NULL::timestamptz next_end,
  coalesce(public.workshop_booking_capacity_duration_minutes(b.id,b.vehicle_id,b.stage_id,b.bay_id),b.default_duration_minutes) planned_minutes,
  (SELECT a.technician_id FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL ORDER BY CASE WHEN a.assignment_type='primary' THEN 0 ELSE 1 END,a.assigned_at DESC LIMIT 1) technician_id
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 JOIN public.workshop_bays bay ON bay.id=b.bay_id JOIN public.vehicles v ON v.id=b.vehicle_id
 WHERE b.deleted_at IS NULL AND b.status='planned' AND b.scheduled_end_at>now();
 PERFORM 1 FROM public.workshop_bookings b JOIN pg_temp.workshop_hours_repair_plan p ON p.id=b.id FOR UPDATE OF b;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN pg_temp.workshop_hours_repair_plan p ON p.id=b.id WHERE b.version<>p.version OR b.status<>p.status OR b.deleted_at IS NOT NULL) THEN RAISE EXCEPTION 'A booking changed during calendar preparation; retry with current bookings'; END IF;
 UPDATE public.workshop_settings SET value=CASE key
  WHEN 'working_week' THEN '["monday","tuesday","wednesday","thursday","friday"]'::jsonb
  WHEN 'day_start_time' THEN '"06:00"'::jsonb WHEN 'day_end_time' THEN '"16:30"'::jsonb END,version=version+1,updated_by=auth.uid(),updated_at=now()
 WHERE key IN('working_week','day_start_time','day_end_time');
 earliest:=to_timestamp(ceil(extract(epoch FROM (clock_timestamp()+interval '1 minute'))/900)*900);
 horizon:=earliest+interval '300 days';
 FOR plan IN SELECT * FROM pg_temp.workshop_hours_repair_plan ORDER BY scheduled_start_at,id LOOP
  candidate:=greatest(plan.scheduled_start_at,earliest);
  LOOP
   IF candidate>=horizon THEN RAISE EXCEPTION 'No weekday slot for %',plan.stock_number; END IF;
   IF NOT public.workshop_calendar_minute_available(candidate) THEN candidate:=candidate+interval '15 minutes'; CONTINUE; END IF;
   finish:=public.workshop_add_operational_minutes(candidate,plan.planned_minutes);
   IF plan.technician_id IS NOT NULL THEN
    skip_day:=public.workshop_technician_leave_date(plan.technician_id,candidate,finish);
    IF skip_day IS NOT NULL THEN candidate:=(skip_day+1)::timestamp AT TIME ZONE 'Australia/Perth'; CONTINUE; END IF;
   END IF;
   SELECT d::date INTO skip_day FROM generate_series((candidate AT TIME ZONE 'Australia/Perth')::date::timestamp,((finish-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(plan.vehicle_id,d::date) ORDER BY d DESC LIMIT 1;
   IF FOUND THEN candidate:=(skip_day+1)::timestamp AT TIME ZONE 'Australia/Perth'; CONTINUE; END IF;
   SELECT max(x.ends) INTO blocked_until FROM (
    SELECT CASE WHEN b.vehicle_id=plan.vehicle_id THEN greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id))+interval '1 hour' ELSE greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id)) END ends
    FROM public.workshop_bookings b WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND NOT EXISTS(SELECT 1 FROM pg_temp.workshop_hours_repair_plan p WHERE p.id=b.id)
     AND ((b.vehicle_id=plan.vehicle_id AND b.scheduled_start_at<finish+interval '1 hour' AND greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id))+interval '1 hour'>candidate)
       OR (b.bay_id=plan.bay_id AND b.scheduled_start_at<finish AND greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id))>candidate)
       OR (plan.technician_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.technician_id=plan.technician_id AND a.released_at IS NULL) AND b.scheduled_start_at<finish AND greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id))>candidate))
    UNION ALL
    SELECT CASE WHEN p.vehicle_id=plan.vehicle_id THEN p.next_end+interval '1 hour' ELSE p.next_end END FROM pg_temp.workshop_hours_repair_plan p WHERE p.next_start IS NOT NULL
     AND ((p.vehicle_id=plan.vehicle_id AND p.next_start<finish+interval '1 hour' AND p.next_end+interval '1 hour'>candidate)
       OR ((p.bay_id=plan.bay_id OR (plan.technician_id IS NOT NULL AND p.technician_id=plan.technician_id)) AND p.next_start<finish AND p.next_end>candidate))
    UNION ALL
    SELECT a.scheduled_end_at FROM public.workshop_admin_blocks a WHERE a.deleted_at IS NULL AND a.bay_id=plan.bay_id AND a.scheduled_start_at<finish AND a.scheduled_end_at>candidate
   ) x;
   IF blocked_until IS NOT NULL THEN candidate:=to_timestamp(ceil(extract(epoch FROM blocked_until)/900)*900); CONTINUE; END IF;
   UPDATE pg_temp.workshop_hours_repair_plan SET next_start=candidate,next_end=finish WHERE id=plan.id;
   EXIT;
  END LOOP;
 END LOOP;
 -- All moves are forward. Move later work first to vacate each earlier continuation.
 FOR plan IN SELECT * FROM pg_temp.workshop_hours_repair_plan ORDER BY scheduled_start_at DESC,id DESC LOOP
  SELECT version INTO current_version FROM public.workshop_bookings WHERE id=plan.id;
  result:=public.move_workshop_booking(plan.id,current_version,plan.code,plan.bay_number,plan.next_start,plan.planned_minutes,'Workshop hours 06:00–16:30 requested by Craig',jsonb_build_object('source','workshop_hours_0600_1630','previous_start',plan.scheduled_start_at,'previous_end',plan.scheduled_end_at));
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Calendar repair failed for %: %',plan.stock_number,result; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_temp.workshop_hours_repair_plan p JOIN public.workshop_bookings b ON b.id=p.id WHERE b.scheduled_start_at<>p.next_start OR b.scheduled_end_at<>p.next_end OR b.default_duration_minutes<>p.planned_minutes OR b.bay_id<>p.bay_id) THEN RAISE EXCEPTION 'Calendar repair verification mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM pg_temp.workshop_hours_repair_plan p WHERE NOT public.workshop_calendar_minute_available(p.next_start) OR public.workshop_operational_minutes_between(p.next_start,p.next_end)<>p.planned_minutes) THEN RAISE EXCEPTION 'Closed-time booking'; END IF;
 IF public.workshop_calendar_minute_available('2026-09-19 06:00+08') OR public.workshop_calendar_minute_available('2026-09-20 06:00+08') OR public.workshop_calendar_minute_available('2026-09-21 16:30+08') OR public.workshop_calendar_minute_available('2026-09-21 05:59+08') OR NOT public.workshop_calendar_minute_available('2026-09-21 06:00+08') THEN RAISE EXCEPTION 'Calendar verification failed'; END IF;
 PERFORM public.workshop_bump_revision();

 SELECT count(*) INTO changes FROM pg_temp.workshop_hours_repair_plan WHERE next_start<>scheduled_start_at OR next_end<>scheduled_end_at;
 RETURN jsonb_build_object('ok',true,'changed_bookings',changes,'start','06:00','end','16:30');
END $fn$;
REVOKE ALL ON FUNCTION public.get_workshop_hours_for_setup(),public.set_workshop_hours_0600_1630() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_workshop_hours_for_setup(),public.set_workshop_hours_0600_1630() TO authenticated;
