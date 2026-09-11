-- Craig: 07:00–17:00 Monday–Friday. Retain booking identities and bays; use current authoritative work hours.
SET LOCAL statement_timeout='180s';
SET LOCAL lock_timeout='15s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
CREATE TEMP TABLE weekday_repair_plan ON COMMIT DROP AS
 SELECT b.*,s.code,bay.bay_number,v.stock_number,NULL::timestamptz next_start,NULL::timestamptz next_end,
  coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(b.vehicle_id,b.stage_id),b.default_duration_minutes) planned_minutes,
  (SELECT a.technician_id FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL ORDER BY CASE WHEN a.assignment_type='primary' THEN 0 ELSE 1 END,a.assigned_at DESC LIMIT 1) technician_id
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 JOIN public.workshop_bays bay ON bay.id=b.bay_id JOIN public.vehicles v ON v.id=b.vehicle_id
 WHERE b.deleted_at IS NULL AND b.status='planned' AND b.scheduled_end_at>now();
DO $repair$
DECLARE actor record; plan record; candidate timestamptz; finish timestamptz; blocked_until timestamptz;
 earliest timestamptz; horizon timestamptz; skip_day date; result jsonb; current_version integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'STAGING only'; END IF;
 SELECT * INTO STRICT actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role::text='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
 PERFORM public.workshop_require_planner_operator();
 PERFORM 1 FROM public.workshop_bookings b JOIN weekday_repair_plan p ON p.id=b.id FOR UPDATE OF b;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN weekday_repair_plan p ON p.id=b.id WHERE b.version<>p.version OR b.status<>p.status OR b.deleted_at IS NOT NULL) THEN RAISE EXCEPTION 'A booking changed during calendar preparation; retry with current bookings'; END IF;
 UPDATE public.workshop_settings SET value=CASE key
  WHEN 'working_week' THEN '["monday","tuesday","wednesday","thursday","friday"]'::jsonb
  WHEN 'day_start_time' THEN '"07:00"'::jsonb WHEN 'day_end_time' THEN '"17:00"'::jsonb
  WHEN 'overtime_windows' THEN '[]'::jsonb END,version=version+1,updated_by=actor.auth_user_id,updated_at=now()
 WHERE key IN('working_week','day_start_time','day_end_time','overtime_windows');
 earliest:=to_timestamp(ceil(extract(epoch FROM (clock_timestamp()+interval '1 minute'))/900)*900);
 horizon:=earliest+interval '300 days';
 FOR plan IN SELECT * FROM weekday_repair_plan ORDER BY scheduled_start_at,id LOOP
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
    SELECT CASE WHEN b.vehicle_id=plan.vehicle_id THEN greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id))+interval '5 hours' ELSE greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id)) END ends
    FROM public.workshop_bookings b WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND NOT EXISTS(SELECT 1 FROM weekday_repair_plan p WHERE p.id=b.id)
     AND ((b.vehicle_id=plan.vehicle_id AND b.scheduled_start_at<finish+interval '5 hours' AND greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id))+interval '5 hours'>candidate)
       OR (b.bay_id=plan.bay_id AND b.scheduled_start_at<finish AND greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id))>candidate)
       OR (plan.technician_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.technician_id=plan.technician_id AND a.released_at IS NULL) AND b.scheduled_start_at<finish AND greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id))>candidate))
    UNION ALL
    SELECT CASE WHEN p.vehicle_id=plan.vehicle_id THEN p.next_end+interval '5 hours' ELSE p.next_end END FROM weekday_repair_plan p WHERE p.next_start IS NOT NULL
     AND ((p.vehicle_id=plan.vehicle_id AND p.next_start<finish+interval '5 hours' AND p.next_end+interval '5 hours'>candidate)
       OR ((p.bay_id=plan.bay_id OR (plan.technician_id IS NOT NULL AND p.technician_id=plan.technician_id)) AND p.next_start<finish AND p.next_end>candidate))
    UNION ALL
    SELECT a.scheduled_end_at FROM public.workshop_admin_blocks a WHERE a.deleted_at IS NULL AND a.bay_id=plan.bay_id AND a.scheduled_start_at<finish AND a.scheduled_end_at>candidate
   ) x;
   IF blocked_until IS NOT NULL THEN candidate:=to_timestamp(ceil(extract(epoch FROM blocked_until)/900)*900); CONTINUE; END IF;
   UPDATE weekday_repair_plan SET next_start=candidate,next_end=finish WHERE id=plan.id;
   EXIT;
  END LOOP;
 END LOOP;
 -- All moves are forward. Move later work first to vacate each earlier continuation.
 FOR plan IN SELECT * FROM weekday_repair_plan ORDER BY scheduled_start_at DESC,id DESC LOOP
  SELECT version INTO current_version FROM public.workshop_bookings WHERE id=plan.id;
  result:=public.move_workshop_booking(plan.id,current_version,plan.code,plan.bay_number,plan.next_start,plan.planned_minutes,'Weekday calendar correction requested by Craig',jsonb_build_object('source','weekday_calendar_correction','previous_start',plan.scheduled_start_at,'previous_end',plan.scheduled_end_at));
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Calendar repair failed for %: %',plan.stock_number,result; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM weekday_repair_plan p JOIN public.workshop_bookings b ON b.id=p.id WHERE b.scheduled_start_at<>p.next_start OR b.scheduled_end_at<>p.next_end OR b.default_duration_minutes<>p.planned_minutes OR b.bay_id<>p.bay_id) THEN RAISE EXCEPTION 'Calendar repair verification mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM weekday_repair_plan p WHERE NOT public.workshop_calendar_minute_available(p.next_start) OR public.workshop_operational_minutes_between(p.next_start,p.next_end)<>p.planned_minutes) THEN RAISE EXCEPTION 'Closed-time booking'; END IF;
 IF public.workshop_calendar_minute_available('2026-09-12 07:00+08') OR public.workshop_calendar_minute_available('2026-09-13 07:00+08') OR public.workshop_calendar_minute_available('2026-09-14 17:00+08') OR public.workshop_calendar_minute_available('2026-09-14 06:59+08') THEN RAISE EXCEPTION 'Calendar is not weekdays7–17'; END IF;
 PERFORM public.workshop_bump_revision();
END $repair$;
