-- Staging only: avoid building the full clock plan when it cannot move work.
-- Existing clock guards, serialization, due/live cascades and history are retained.
DO $migration$
DECLARE body text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
  OR NOT pdc_codex_intake_private.management_connection() THEN
  RAISE EXCEPTION 'Staging management connection required';
 END IF;
 body:=pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure);
 IF md5(body)<>'bb2101ca900128c504e3b2a23aef3479' THEN RAISE EXCEPTION 'Clock definition changed; review before deploying'; END IF;
 IF strpos(body,$needle$ PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('planned','queued','started','stoppage') ORDER BY id FOR UPDATE;$needle$)=0 THEN RAISE EXCEPTION 'Clock insertion point missing'; END IF;
 EXECUTE replace(body,$needle$ PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('planned','queued','started','stoppage') ORDER BY id FOR UPDATE;$needle$,$replacement$ -- Future queued/planned work cannot seed a clock cascade. Keep the mutation
 -- lock above this check so its decision uses the same serialized state.
 -- Live work always takes the existing full path, including effective-end logic.
 IF NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.deleted_at IS NULL
   AND ((b.status='planned' AND b.actual_start_at IS NULL AND b.scheduled_start_at<p_now)
        OR b.status IN('started','stoppage'))
 ) THEN
  RETURN jsonb_build_object('ok',true,'clock_at',p_now,'applied',p_apply,
   'moved_count',0,'plans','[]'::jsonb,'issues','[]'::jsonb);
 END IF;
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('planned','queued','started','stoppage') ORDER BY id FOR UPDATE;$replacement$);
END $migration$;
