-- Undo 20261019143000_workshop_clock_skip_unchanged.sql. Restores the reviewed
-- clock body and refuses to run if that rewritten body has drifted.
DO $repair$
DECLARE definition text; needle text; replacement text; occurrences integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure
  AND md5(replace(prosrc,chr(13),''))='84af7607bfd0ce9907c89bae8644d5b6' AND NOT prosecdef AND provolatile='v'
  AND proowner='postgres'::regrole
  AND proconfig=ARRAY['search_path=pg_catalog, public','lock_timeout=3s','statement_timeout=120s'])
 THEN RAISE EXCEPTION 'reviewed_clock_changed'; END IF;
 replacement:=$needle$  RETURN jsonb_build_object('ok',true,'clock_at',p_now,'applied',p_apply,
   'moved_count',0,'plans','[]'::jsonb,'issues','[]'::jsonb);
 END IF;
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('planned','queued','started','stoppage') ORDER BY id FOR UPDATE;$needle$;
 needle:=$insert$  RETURN jsonb_build_object('ok',true,'clock_at',p_now,'applied',p_apply,
   'moved_count',0,'plans','[]'::jsonb,'issues','[]'::jsonb);
 END IF;
 -- An enabled overdue arrival or a live overrun is the only cascade seed.
 -- Queued work is a fixed obstacle, not a seed. When nothing can move, the
 -- locked plan writes no clock rows, so return the same empty result.
 IF NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id
  JOIN public.vehicles v ON v.id=b.vehicle_id
  LEFT JOIN public.workshop_bays y ON y.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND NOT (b.status='queued' AND b.bay_id IS NULL AND b.actual_start_at IS NULL)
   AND (y.is_active AND s.active AND s.planner_enabled) IS TRUE
   AND b.status='planned' AND b.actual_start_at IS NULL AND b.scheduled_start_at<p_now
 ) AND NOT EXISTS(
  SELECT 1 FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id
  JOIN public.vehicles v ON v.id=b.vehicle_id
  LEFT JOIN public.workshop_bays y ON y.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND NOT (b.status='queued' AND b.bay_id IS NULL AND b.actual_start_at IS NULL)
   AND (y.is_active AND s.active AND s.planner_enabled) IS TRUE
   AND b.status IN('started','stoppage') AND greatest(
    public.workshop_booking_effective_end_at(b.id),
    pdc_bus_private.clock_next_minute(p_now,CASE WHEN s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END)
   )>b.scheduled_end_at
 ) THEN
  RETURN jsonb_build_object('ok',true,'clock_at',p_now,'applied',p_apply,
   'moved_count',0,'plans','[]'::jsonb,'issues','[]'::jsonb);
 END IF;
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL AND status IN('planned','queued','started','stoppage') ORDER BY id FOR UPDATE;$insert$;
 definition:=pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure);
 occurrences:=(length(definition)-length(replace(definition,needle,'')))/length(needle);
 IF occurrences<>1 THEN RAISE EXCEPTION 'clock_skip_rollback_missing'; END IF;
 EXECUTE replace(definition,needle,replacement);
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure
  AND md5(replace(prosrc,chr(13),''))='a7cd97007e7fdd96b01c90929d42fe2d' AND NOT prosecdef AND provolatile='v'
  AND proowner='postgres'::regrole
  AND proconfig=ARRAY['search_path=pg_catalog, public','lock_timeout=3s','statement_timeout=120s'])
 THEN RAISE EXCEPTION 'clock_skip_rollback_failed'; END IF;
END $repair$;
