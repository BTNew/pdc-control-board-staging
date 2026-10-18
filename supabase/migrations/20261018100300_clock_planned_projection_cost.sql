-- Planned, unstarted rows never use effective_end in the clock algorithm.
-- Retain authoritative effective ends for queued, live or actual-start rows.
DO $repair$
DECLARE d text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 SELECT replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),chr(13),'') INTO d;
 IF md5(d)<>'206824a8b76b490e5bdfb8ae24365869' THEN RAISE EXCEPTION 'reviewed_clock_changed'; END IF;
 IF position('public.workshop_booking_effective_end_at(b.id) effective_end' IN d)=0 THEN RAISE EXCEPTION 'clock_projection_missing'; END IF;
 EXECUTE replace(d,'public.workshop_booking_effective_end_at(b.id) effective_end',
  'CASE WHEN b.status=''planned'' AND b.actual_start_at IS NULL THEN b.scheduled_end_at ELSE public.workshop_booking_effective_end_at(b.id) END effective_end');
END $repair$;

