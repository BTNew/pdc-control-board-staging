-- Rollback-only restored-copy verification: identical station payloads without a clock mutation.
BEGIN;
CREATE TEMP TABLE snapshot_preserved AS
 SELECT (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b) bookings,
        (SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM public.workshop_booking_assignments a) assignments,
        md5(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)) clock_hash;
DO $actor$
DECLARE actor record;
BEGIN
 SELECT u.id,u.email INTO actor FROM auth.users u
 JOIN public.pdc_user_roles r ON r.email=lower(u.email)
 WHERE r.active AND r.role='administrator' ORDER BY u.id LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Fixture requires an existing administrator'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.id,'email',actor.email,'role','authenticated')::text,true);
END $actor$;
CREATE TEMP TABLE snapshot_timings(stage text,day date,elapsed_ms numeric,identical boolean,bookings integer,candidates integer);
DO $read$
DECLARE st text; day date; actual jsonb; expected jsonb; base jsonb; t timestamptz;
BEGIN
 FOREACH st IN ARRAY ARRAY['BUS_4X4','HOIST','FITTING','FABRICATION','ELECTRICAL','TINT','TYRE'] LOOP
  FOREACH day IN ARRAY ARRAY['2026-10-19'::date,'2026-10-21'::date] LOOP
   -- The preexisting canonical projection chain is the payload oracle.
   base:=public.get_station_workshop_snapshot_pre_170(st,day,day);
   base:=base||jsonb_build_object('admin_blocks',(
    SELECT coalesce(jsonb_agg(public.workshop_admin_block_snapshot(a.id) ORDER BY a.scheduled_start_at,a.id),'[]'::jsonb)
    FROM public.workshop_admin_blocks a JOIN public.workshop_stages s ON s.id=a.stage_id
    WHERE a.deleted_at IS NULL AND s.code=st
      AND a.scheduled_start_at<(day+1)::timestamp AT TIME ZONE 'Australia/Perth'
      AND a.scheduled_end_at>day::timestamp AT TIME ZONE 'Australia/Perth'));
   expected:=pdc_work_categories_private.snapshot(pdc_parts_private.planner_search_snapshot_20260917(
     public.workshop_overlay_authoritative_candidate_hours_175(public.workshop_overlay_canonical_booking_fields_397(base))));
   t:=clock_timestamp();
   actual:=public.get_station_workshop_snapshot(st,day,day);
   INSERT INTO snapshot_timings VALUES(st,day,extract(epoch FROM clock_timestamp()-t)*1000,
    actual=expected,jsonb_array_length(actual->'bookings'),jsonb_array_length(actual->'outstanding_candidates'));
   IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Snapshot payload changed for % %',st,day; END IF;
  END LOOP;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid IN('public.get_station_workshop_snapshot(text,date,date)'::regprocedure,
   'public.get_station_workshop_snapshot_pre_397(text,date,date)'::regprocedure) AND provolatile<>'s') THEN
  RAISE EXCEPTION 'Station reads must be STABLE'; END IF;
 IF EXISTS(SELECT 1 FROM snapshot_preserved p WHERE
   p.bookings IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b)
   OR p.assignments IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM public.workshop_booking_assignments a)
   OR p.clock_hash IS DISTINCT FROM md5(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure))) THEN
  RAISE EXCEPTION 'Read changed bookings, assignments or clock'; END IF;
 -- No top-level mutation/clock advisory lock is acquired by any station read.
 IF EXISTS(SELECT 1 FROM pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory') THEN
  RAISE EXCEPTION 'Station reads acquired an advisory mutation lock'; END IF;
END $read$;
DO $denial$
BEGIN
 PERFORM set_config('request.jwt.claims','{}',true);
 BEGIN
  PERFORM public.get_station_workshop_snapshot('FITTING','2026-10-19','2026-10-19');
  RAISE EXCEPTION 'Anonymous read was allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $denial$;
SELECT * FROM snapshot_timings ORDER BY stage,day;
SELECT 'PASS: 14 canonical payload comparisons, preserved booking/assignment/clock state, no mutation locks, anonymous denied' result;
ROLLBACK;
