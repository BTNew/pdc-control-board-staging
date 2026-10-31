-- r779 (F431) / sort 565. Staging cdsmnqxtyyoeoznmbidd only.
--
-- F431. Craig 31 Oct 08:33 AWST (Fab planner, key 276 / 13091176): "why can't i move this vehicle to fabrication,
-- it has jobs for it". Toast: "This vehicle has no incomplete canonical requirement for that Workshop station." (x2)
-- Root cause: both job lines were moved from Fitting to Fab, so the fitting requirement became required = false, but
-- the car's queued FITTING booking (no bay, never started) was left behind. A Fab move pushes the car's other queued
-- bookings, the r-trigger workshop_enforce_booking_validation re-validates that stale FITTING booking, the validator
-- finds no open fitting requirement and refuses the whole move (canonical_requirement_missing_or_completed).
-- Proven in a rolled-back update of booking 5c36081e (FITTING, key 276): same error. r746 / r830 only clear a station
-- whose lines are all ticked; a station with no lines at all (all moved away) was never cleared.
-- 32 such bookings on 14 cars at release time (keys 152, 25, 276, 281, 366 and IT 13094135-13094143).
--
-- Fix:
--   * no_work_station_bookings_779: a queued booking with no bay, never started, on a planner station that has no
--     open required work item and no job lines left (r578 icon total 0), outside QC rework.
--   * clear_no_work_station_bookings_779: soft-deletes them like r746 (history row, r746_cleared_bookings row with
--     source r779_*, so they can be restored).
--   * the one-minute r830 sweep now also runs it, so a line move off a station clears its booking within a minute.
--   * one sweep now, then check no_work_station_bookings_779 must be green.
-- Rollback: supabase/rollbacks/20261031010000_r779_no_work_station_bookings.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard779$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r779: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r779: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r779: an import job is running'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 565 OR fault_id = 'F431' OR added_in = 'r779') THEN
    RAISE EXCEPTION 'r779: sort 565 or F431 or r779 is taken'; END IF;
  IF to_regprocedure('pdc_work_categories_private.no_work_station_bookings_779(uuid[])') IS NOT NULL THEN RAISE EXCEPTION 'r779: already applied'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_work_categories_private.sweep_done_station_bookings_830()'::regprocedure)) <> '8f937836105c82f6de70477701c69409'
  THEN RAISE EXCEPTION 'r779: the r830 sweep changed since the release was written'; END IF;
END $guard779$;

CREATE FUNCTION pdc_work_categories_private.no_work_station_bookings_779(p_vehicle_ids uuid[])
RETURNS TABLE(booking_id uuid, vehicle_id uuid, stage_code text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  -- r779 (F431): a queued, never-started booking with no bay on a planner station the car has no work for any more
  -- (no open required work item and no job lines left). Any reschedule of it is refused by workshop_validate_booking,
  -- which also blocks moves of the car's real stations.
  WITH b AS (
    SELECT wb.id, wb.vehicle_id, s.code, s.work_key
    FROM public.workshop_bookings wb
    JOIN public.workshop_stages s ON s.id = wb.stage_id AND s.active AND s.planner_enabled
    JOIN public.vehicles v ON v.id = wb.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state = 'active'
    WHERE wb.vehicle_id = ANY (coalesce(p_vehicle_ids, '{}'::uuid[]))
      AND wb.deleted_at IS NULL AND wb.status = 'queued' AND wb.bay_id IS NULL
      AND wb.actual_start_at IS NULL AND wb.actual_end_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.vehicle_work_items wi
                      WHERE wi.vehicle_id = wb.vehicle_id AND wi.required AND NOT wi.completed
                        AND public.workshop_canonical_stage_code(wi.work_key) = s.code)
  ), lines AS (
    SELECT r.vehicle_id, r.work_key, r.total
    FROM pg_catalog.jsonb_to_recordset(pdc_work_categories_private.station_icon_completion_578(
           ARRAY(SELECT DISTINCT b.vehicle_id FROM b))) AS r(vehicle_id uuid, work_key text, total integer)
  )
  SELECT b.id, b.vehicle_id, b.code
  FROM b
  WHERE NOT EXISTS (SELECT 1 FROM lines l WHERE l.vehicle_id = b.vehicle_id AND l.work_key = b.work_key AND coalesce(l.total, 0) > 0)
    AND NOT coalesce((public.pdc_qc_rework_scope_20260909(b.vehicle_id)->>'active')::boolean, false)
$function$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.no_work_station_bookings_779(uuid[]) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_work_categories_private.clear_no_work_station_bookings_779(p_vehicle_ids uuid[], p_source text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  t record;
  b public.workshop_bookings%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_n integer := 0;
BEGIN
  IF pg_catalog.cardinality(coalesce(p_vehicle_ids, '{}'::uuid[])) = 0 THEN RETURN 0; END IF;
  -- Same change lock every board write takes; the targets are worked out under it.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc:workshop:top-level-mutation', 0));
  FOR t IN SELECT * FROM pdc_work_categories_private.no_work_station_bookings_779(p_vehicle_ids) ORDER BY booking_id LOOP
    SELECT * INTO b FROM public.workshop_bookings
    WHERE id = t.booking_id AND deleted_at IS NULL AND status = 'queued' AND bay_id IS NULL AND actual_start_at IS NULL
    FOR UPDATE;
    CONTINUE WHEN NOT FOUND;
    v_before := public.workshop_booking_snapshot(b.id);
    UPDATE public.workshop_bookings
       SET status = 'deleted',
           deleted_at = pg_catalog.clock_timestamp(),
           deleted_reason = 'No ' || pg_catalog.lower(t.stage_code) || ' work left on this car (r779)',
           updated_by = coalesce(auth.uid(), b.updated_by),
           version = version + 1
     WHERE id = b.id AND deleted_at IS NULL AND status = 'queued' AND bay_id IS NULL;
    v_after := public.workshop_booking_snapshot(b.id);
    INSERT INTO pdc_ops.r746_cleared_bookings(booking_id, vehicle_id, stage_code, source, override_only, before_booking, actor_id, actor_email)
    VALUES (b.id, b.vehicle_id, t.stage_code, coalesce(p_source, 'r779_unknown'), false, pg_catalog.to_jsonb(b),
            auth.uid(), public.current_actor_email())
    ON CONFLICT (booking_id) DO NOTHING;
    PERFORM public.workshop_write_history(b.id, 'deleted', v_before, v_after,
      pg_catalog.jsonb_build_object('reason', 'station_no_work_779', 'source', coalesce(p_source, 'r779_unknown'),
                                    'stage_code', t.stage_code));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END
$function$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.clear_no_work_station_bookings_779(uuid[], text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.sweep_done_station_bookings_830()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $function$
DECLARE
  v_all uuid[];
  v_ids uuid[];
  v_stages text[];
  v_none_ids uuid[];
  v_none_stages text[];
  v_n integer := 0;
  v_stage text;
  v_actor uuid;
  v_email text;
  v_original_claims text := current_setting('request.jwt.claims', true);
BEGIN
  -- r830 (F390): safety net for r746. Every minute, a queued / planned booking on a station whose lines are all ticked
  -- is cleared, in case the tick trigger missed it (13073056 FITTING, 30 Oct 2026).
  -- r779 (F431): also clears a queued booking on a station the car has no work left for (lines moved away).
  v_all := ARRAY(SELECT DISTINCT vehicle_id FROM public.workshop_bookings
                 WHERE deleted_at IS NULL AND status IN ('queued','planned'));
  IF pg_catalog.cardinality(v_all) = 0 THEN RETURN 0; END IF;

  SELECT pg_catalog.array_agg(DISTINCT d.stage_code), pg_catalog.array_agg(DISTINCT d.vehicle_id)
    INTO v_stages, v_ids
  FROM pdc_work_categories_private.done_planner_stations_746(v_all) d
  JOIN public.workshop_bookings wb ON wb.vehicle_id = d.vehicle_id AND wb.stage_id = d.stage_id
   AND wb.deleted_at IS NULL AND wb.status IN ('queued','planned');

  SELECT pg_catalog.array_agg(DISTINCT x.stage_code), pg_catalog.array_agg(DISTINCT x.vehicle_id)
    INTO v_none_stages, v_none_ids
  FROM pdc_work_categories_private.no_work_station_bookings_779(v_all) x;

  IF v_ids IS NULL AND v_none_ids IS NULL THEN RETURN 0; END IF;

  -- Cron has no user: act as the workshop system actor (as workshop_sync_vehicle_stage_booking_duration does), because
  -- workshop_booking_history needs an actor.
  IF auth.uid() IS NULL THEN
    SELECT r.auth_user_id, r.email INTO v_actor, v_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id = r.auth_user_id
    WHERE r.active AND r.account_status = 'approved' AND r.role = 'administrator' AND r.auth_user_id IS NOT NULL
    ORDER BY r.created_at, r.id LIMIT 1;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PDC_830_SYSTEM_ACTOR_MISSING' USING errcode = '55000'; END IF;
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_actor, 'email', v_email, 'role', 'authenticated')::text, true);
  END IF;

  IF v_ids IS NOT NULL THEN
    v_n := pdc_work_categories_private.clear_done_station_bookings_746(v_ids, 'r830_sweep');
  END IF;
  IF v_none_ids IS NOT NULL THEN
    v_n := v_n + pdc_work_categories_private.clear_no_work_station_bookings_779(v_none_ids, 'r779_sweep');
  END IF;
  IF v_n > 0 THEN
    FOREACH v_stage IN ARRAY ARRAY(SELECT DISTINCT s FROM pg_catalog.unnest(coalesce(v_stages, '{}'::text[]) || coalesce(v_none_stages, '{}'::text[])) s) LOOP
      PERFORM public.workshop_bump_station_revision(v_stage);
    END LOOP;
  END IF;
  PERFORM set_config('request.jwt.claims', coalesce(v_original_claims, ''), true);
  RETURN v_n;
END
$function$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.sweep_done_station_bookings_830() FROM PUBLIC, anon, authenticated;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('no_work_station_bookings_779', 'F431',
  'No queued booking is left on a station the car has no work for (it blocks moves of the car''s real stations); the r830 sweep clears them each minute. A red right after a line move clears within a minute.',
  $chk$
SELECT n.n = 0 AND strpos(sw.src, 'clear_no_work_station_bookings_779') > 0 AS ok,
  'no-work queued bookings ' || n.n::text || ' | sweep ' || CASE WHEN strpos(sw.src, 'clear_no_work_station_bookings_779') > 0 THEN 'clears them' ELSE 'MISSING r779' END AS detail
FROM (SELECT count(*) AS n FROM pdc_work_categories_private.no_work_station_bookings_779(
        ARRAY(SELECT DISTINCT vehicle_id FROM public.workshop_bookings WHERE deleted_at IS NULL AND status = 'queued' AND bay_id IS NULL))) n,
     (SELECT prosrc AS src FROM pg_proc WHERE oid = 'pdc_work_categories_private.sweep_done_station_bookings_830()'::regprocedure) sw
$chk$, true, 565, 'r779');

-- One sweep now (as the system actor), then the check must be green.
DO $sweep779$
DECLARE v_n integer; v_ok boolean;
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  v_n := pdc_work_categories_private.sweep_done_station_bookings_830();
  RAISE NOTICE 'r779: sweep cleared % bookings', v_n;
  SELECT (SELECT count(*) FROM pdc_work_categories_private.no_work_station_bookings_779(
            ARRAY(SELECT DISTINCT vehicle_id FROM public.workshop_bookings WHERE deleted_at IS NULL AND status = 'queued' AND bay_id IS NULL))) = 0
    INTO v_ok;
  IF NOT v_ok THEN RAISE EXCEPTION 'r779: check red after the sweep'; END IF;
END $sweep779$;
