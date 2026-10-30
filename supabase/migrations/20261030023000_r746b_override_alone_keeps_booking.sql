-- r746b (F352 follow-up). Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 2026 09:26 AWST: "now i cant see key 105 on the fab bay". Key 105 / 13073068 had a Fabrication
-- override (bulk, 28 Oct) but PD line 13 (2.00 h) was never ticked; r746 counted the override as done and its
-- 1:15 pm Fab Bay booking was removed. Craig's rule is "all items complete/ticked", so an override alone is not done.
-- Fix: done_planner_stations_746 counts a station done only when every line is ticked (r578 total > 0 and done = total).
-- Every booking r746 removed for an override alone is put back: a future bay booking is re-created in the same bay,
-- time and technician (new id, history 'created'); anything else, or a slot that is no longer free, goes back to
-- Unallocated (the original row restored, history 'restored'). Recorded on pdc_ops.r746_cleared_bookings.

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '120s';

DO $window746b$
DECLARE i integer := 0;
BEGIN
  LOOP
    EXIT WHEN extract(second FROM clock_timestamp()) BETWEEN 2 AND 15
      AND EXISTS (SELECT 1 FROM cron.job_run_details d JOIN cron.job j USING (jobid)
                  WHERE j.jobname = 'staging-workshop-clock-cascade'
                    AND d.start_time >= date_trunc('minute', clock_timestamp()) AND d.end_time IS NOT NULL);
    i := i + 1;
    IF i > 75 THEN RAISE EXCEPTION 'r746b: clock tick not seen'; END IF;
    PERFORM pg_sleep(1);
  END LOOP;
END $window746b$;

DO $guard746b$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r746b: staging only';
  END IF;
  IF to_regprocedure('pdc_work_categories_private.done_planner_stations_746(uuid[])') IS NULL THEN RAISE EXCEPTION 'r746b: r746 not applied'; END IF;
END $guard746b$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.done_planner_stations_746(p_vehicle_ids uuid[])
RETURNS TABLE(vehicle_id uuid, stage_id uuid, stage_code text, override_only boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  -- r746b: done = every active line ticked. A station override alone does not take a car off the planner.
  SELECT r.vehicle_id, s.id, s.code, false
  FROM pg_catalog.jsonb_to_recordset(pdc_work_categories_private.station_icon_completion_578(coalesce(p_vehicle_ids, '{}'::uuid[])))
    AS r(vehicle_id uuid, work_key text, complete boolean, total integer, done integer)
  JOIN public.workshop_stages s ON s.work_key = r.work_key AND s.active AND s.planner_enabled
  WHERE coalesce(r.total, 0) > 0 AND r.done = r.total
    AND NOT coalesce((public.pdc_qc_rework_scope_20260909(r.vehicle_id)->>'active')::boolean, false)
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.done_planner_stations_746(uuid[]) FROM PUBLIC, anon, authenticated;

ALTER TABLE pdc_ops.r746_cleared_bookings ADD COLUMN IF NOT EXISTS restored_at timestamptz;
ALTER TABLE pdc_ops.r746_cleared_bookings ADD COLUMN IF NOT EXISTS restored_as text;
ALTER TABLE pdc_ops.r746_cleared_bookings ADD COLUMN IF NOT EXISTS restored_booking_id uuid;

DO $restore746b$
DECLARE
  c record; v_old public.workshop_bookings%rowtype; v_new public.workshop_bookings%rowtype;
  v_now timestamptz; v_before jsonb; v_after jsonb; v_rebooked integer := 0; v_unalloc integer := 0; v_skipped integer := 0;
  v_craig uuid := '8a83b715-8d79-4b0e-95b2-02b55da6e8d7';
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_craig::text, 'role', 'authenticated',
    'email', 'craig.watson@broometoyota.com.au')::text, true);
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation', 0));
  FOR c IN SELECT * FROM pdc_ops.r746_cleared_bookings WHERE override_only AND restored_at IS NULL
           ORDER BY (before_booking->>'scheduled_start_at')::timestamptz NULLS LAST, booking_id LOOP
    v_now := clock_timestamp();
    SELECT * INTO v_old FROM public.workshop_bookings WHERE id = c.booking_id FOR UPDATE;
    IF NOT FOUND OR v_old.deleted_at IS NULL
       OR EXISTS (SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id = v_old.vehicle_id AND b.stage_id = v_old.stage_id
                  AND b.deleted_at IS NULL AND b.status IN ('queued', 'planned', 'started', 'stoppage')) THEN
      UPDATE pdc_ops.r746_cleared_bookings SET restored_at = v_now, restored_as = 'skipped: rebooked already' WHERE booking_id = c.booking_id;
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;
    -- 1. Same bay, time and technician when the job is still ahead and the slot is free.
    IF c.before_booking->>'status' = 'planned' AND c.before_booking->>'bay_id' IS NOT NULL
       AND (c.before_booking->>'scheduled_start_at')::timestamptz > v_now + interval '2 minutes' THEN
      BEGIN
        INSERT INTO public.workshop_bookings
        SELECT (jsonb_populate_record(NULL::public.workshop_bookings, c.before_booking || jsonb_build_object(
          'id', gen_random_uuid(), 'status', 'planned', 'deleted_at', NULL, 'deleted_reason', NULL, 'returned_to_queue_at', NULL,
          'version', 1, 'created_by', v_craig, 'updated_by', v_craig, 'created_at', v_now, 'updated_at', v_now))).*
        RETURNING * INTO v_new;
        INSERT INTO public.workshop_booking_assignments(booking_id, technician_id, assignment_type, assigned_at, assigned_by, scheduled_start_at, scheduled_end_at, notes)
        SELECT v_new.id, a.technician_id, a.assignment_type, v_now, v_craig, v_new.scheduled_start_at, v_new.scheduled_end_at, a.notes
        FROM public.workshop_booking_assignments a
        WHERE a.booking_id = c.booking_id AND a.released_at BETWEEN c.cleared_at - interval '3 minutes' AND c.cleared_at + interval '1 second';
        PERFORM public.workshop_write_history(v_new.id, 'created', NULL, public.workshop_booking_snapshot(v_new.id),
          jsonb_build_object('reason', 'r746b_restore', 'replaces_booking_id', c.booking_id));
        UPDATE pdc_ops.r746_cleared_bookings SET restored_at = v_now, restored_as = 'same bay and time', restored_booking_id = v_new.id
        WHERE booking_id = c.booking_id;
        v_rebooked := v_rebooked + 1;
        CONTINUE;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'r746b: % back to Unallocated (%)', c.booking_id, SQLERRM;
      END;
    END IF;
    -- 2. Otherwise the original booking goes back to Unallocated (same as the planner's Restore).
    BEGIN
      v_before := public.workshop_booking_snapshot(c.booking_id);
      INSERT INTO public.workshop_transition_authorizations(txid, booking_id, transition, authorized_by)
      VALUES (txid_current(), c.booking_id, 'restore', v_craig);
      UPDATE public.workshop_bookings
         SET status = 'queued', bay_id = NULL, deleted_at = NULL, deleted_reason = NULL,
             returned_to_queue_at = v_now, updated_by = v_craig, version = version + 1
       WHERE id = c.booking_id AND deleted_at IS NOT NULL;
      v_after := public.workshop_booking_snapshot(c.booking_id);
      PERFORM public.workshop_write_history(c.booking_id, 'restored', v_before, v_after, jsonb_build_object('reason', 'r746b_restore'));
      UPDATE pdc_ops.r746_cleared_bookings SET restored_at = v_now, restored_as = 'Unallocated', restored_booking_id = c.booking_id
      WHERE booking_id = c.booking_id;
      v_unalloc := v_unalloc + 1;
    EXCEPTION WHEN OTHERS THEN
      -- e.g. the car has left PMB since; the booking stays removed and the reason is kept.
      UPDATE pdc_ops.r746_cleared_bookings SET restored_at = v_now, restored_as = 'not restored: ' || SQLERRM WHERE booking_id = c.booking_id;
      v_skipped := v_skipped + 1;
    END;
  END LOOP;
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE 'r746b: same slot %, Unallocated %, skipped %', v_rebooked, v_unalloc, v_skipped;
END $restore746b$;
