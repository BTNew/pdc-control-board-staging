-- r746 (F352) / sort 466. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 30 Oct 2026 08:55 AWST (Key 213 / stock 13047225, Fitting): "if a vehicle has all its items
-- complete/ticked in fitting/elec etc... it needs to come off the planner and the left hand side".
-- Root cause: the planner list (workshop_station_eligibility) reads only vehicle_work_items.completed. Panel ticks
-- (pdc_panel_line_completion_565) and station overrides (pdc_station_completion_override_578) turn the station
-- icon green (r578) but never reach that flag, so a station with every line ticked stayed in Unallocated, and its
-- queued / planned bookings stayed on the planner.
-- Fix:
--  1. workshop_station_eligibility leaves out a station the r578 icon calls complete (QC rework keeps it in).
--  2. After a panel tick or station override, the vehicle's queued / planned bookings for a complete station are
--     deleted (reason "every line ticked", history + audit, kept in pdc_ops.r746_cleared_bookings) and the
--     vehicle's planner stations get a new revision so open planners refresh. Started / stopped jobs stay put.
--     The tick itself never fails because of this cleanup.
--  3. One sweep now for stations already complete.
-- vehicle_work_items, line ticks, the r578 icon, fitter_job_command and Department 135 are not changed. Pins stay.
-- Undo: supabase/rollbacks/20261030020000_r746_done_station_leaves_planner.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '120s';

-- Start a few seconds after the minute's clock tick (lock-free wait), so the sweep never holds the change lock at :00.
DO $window746$
DECLARE i integer := 0;
BEGIN
  LOOP
    EXIT WHEN extract(second FROM clock_timestamp()) BETWEEN 2 AND 15
      AND EXISTS (SELECT 1 FROM cron.job_run_details d JOIN cron.job j USING (jobid)
                  WHERE j.jobname = 'staging-workshop-clock-cascade'
                    AND d.start_time >= date_trunc('minute', clock_timestamp()) AND d.end_time IS NOT NULL);
    i := i + 1;
    IF i > 75 THEN RAISE EXCEPTION 'r746: clock tick not seen'; END IF;
    PERFORM pg_sleep(1);
  END LOOP;
END $window746$;

DO $guard746$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r746: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r746: staging only';
  END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks
             WHERE sort_order = 466 OR fault_id = 'F352' OR added_in = 'r746' OR check_name = 'done_station_leaves_planner_746') THEN
    RAISE EXCEPTION 'r746: sort 466 or F352 is taken';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_station_eligibility(text)')) <> '952da1c6a242d3014d1deae7a0585bac' THEN
    RAISE EXCEPTION 'r746: workshop_station_eligibility changed since the preview';
  END IF;
  IF to_regprocedure('pdc_work_categories_private.done_planner_stations_746(uuid[])') IS NOT NULL THEN RAISE EXCEPTION 'r746: already applied'; END IF;
END $guard746$;

CREATE TABLE IF NOT EXISTS pdc_ops.r746_function_backup (sig text PRIMARY KEY, def text NOT NULL, prosrc_md5 text NOT NULL, saved_at timestamptz NOT NULL DEFAULT clock_timestamp());
INSERT INTO pdc_ops.r746_function_backup(sig, def, prosrc_md5)
SELECT 'public.workshop_station_eligibility(text)', pg_get_functiondef(p.oid), md5(p.prosrc)
FROM pg_proc p WHERE p.oid = to_regprocedure('public.workshop_station_eligibility(text)')
ON CONFLICT (sig) DO NOTHING;

-- Bookings this release removes, so each one can be checked or restored by hand.
CREATE TABLE IF NOT EXISTS pdc_ops.r746_cleared_bookings (
  booking_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  stage_code text NOT NULL,
  source text NOT NULL,
  override_only boolean NOT NULL,
  before_booking jsonb NOT NULL,
  actor_id uuid,
  actor_email text,
  cleared_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_ops.r746_cleared_bookings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_ops.r746_cleared_bookings FROM PUBLIC, anon, authenticated;

-- Planner stations the r578 icon calls complete (every active line ticked, or a controller override).
-- A vehicle in QC rework keeps its stations.
CREATE FUNCTION pdc_work_categories_private.done_planner_stations_746(p_vehicle_ids uuid[])
RETURNS TABLE(vehicle_id uuid, stage_id uuid, stage_code text, override_only boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  SELECT r.vehicle_id, s.id, s.code, NOT (coalesce(r.total, 0) > 0 AND r.done = r.total)
  FROM pg_catalog.jsonb_to_recordset(pdc_work_categories_private.station_icon_completion_578(coalesce(p_vehicle_ids, '{}'::uuid[])))
    AS r(vehicle_id uuid, work_key text, complete boolean, total integer, done integer)
  JOIN public.workshop_stages s ON s.work_key = r.work_key AND s.active AND s.planner_enabled
  WHERE r.complete
    AND NOT coalesce((public.pdc_qc_rework_scope_20260909(r.vehicle_id)->>'active')::boolean, false)
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.done_planner_stations_746(uuid[]) FROM PUBLIC, anon, authenticated;

-- Deletes queued / planned bookings of complete stations for these vehicles. Started and stopped jobs stay.
CREATE FUNCTION pdc_work_categories_private.clear_done_station_bookings_746(p_vehicle_ids uuid[], p_source text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_ids uuid[];
  v_targets jsonb;
  t jsonb;
  b public.workshop_bookings%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_n integer := 0;
BEGIN
  v_ids := ARRAY(
    SELECT DISTINCT x FROM pg_catalog.unnest(coalesce(p_vehicle_ids, '{}'::uuid[])) x
    WHERE x IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.workshop_bookings wb
                  WHERE wb.vehicle_id = x AND wb.deleted_at IS NULL AND wb.status IN ('queued', 'planned')));
  IF pg_catalog.cardinality(v_ids) = 0 THEN RETURN 0; END IF;

  SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('booking_id', wb.id, 'stage_code', d.stage_code, 'override_only', d.override_only) ORDER BY wb.id)
  INTO v_targets
  FROM pdc_work_categories_private.done_planner_stations_746(v_ids) d
  JOIN public.workshop_bookings wb
    ON wb.vehicle_id = d.vehicle_id AND wb.stage_id = d.stage_id
   AND wb.deleted_at IS NULL AND wb.status IN ('queued', 'planned');
  IF v_targets IS NULL THEN RETURN 0; END IF;

  -- Same change lock every board write takes, so the clock tick never meets a half-cleared vehicle.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc:workshop:top-level-mutation', 0));

  FOR t IN SELECT * FROM pg_catalog.jsonb_array_elements(v_targets) LOOP
    SELECT * INTO b FROM public.workshop_bookings
    WHERE id = (t->>'booking_id')::uuid AND deleted_at IS NULL AND status IN ('queued', 'planned')
    FOR UPDATE;
    CONTINUE WHEN NOT FOUND;
    v_before := public.workshop_booking_snapshot(b.id);
    UPDATE public.workshop_bookings
       SET status = 'deleted',
           deleted_at = pg_catalog.clock_timestamp(),
           deleted_reason = 'Every ' || pg_catalog.lower(t->>'stage_code') || ' line ticked (r746)',
           updated_by = coalesce(auth.uid(), b.updated_by),
           version = version + 1
     WHERE id = b.id AND deleted_at IS NULL AND status IN ('queued', 'planned');
    v_after := public.workshop_booking_snapshot(b.id);
    INSERT INTO pdc_ops.r746_cleared_bookings(booking_id, vehicle_id, stage_code, source, override_only, before_booking, actor_id, actor_email)
    VALUES (b.id, b.vehicle_id, t->>'stage_code', coalesce(p_source, 'unknown'), (t->>'override_only')::boolean, pg_catalog.to_jsonb(b),
            auth.uid(), public.current_actor_email())
    ON CONFLICT (booking_id) DO NOTHING;
    PERFORM public.workshop_write_history(b.id, 'deleted', v_before, v_after,
      pg_catalog.jsonb_build_object('reason', 'station_done_746', 'source', coalesce(p_source, 'unknown'),
                                    'stage_code', t->>'stage_code', 'override_only', (t->>'override_only')::boolean));
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.clear_done_station_bookings_746(uuid[], text) FROM PUBLIC, anon, authenticated;

-- Statement trigger on the tick and override tables: clean up, then refresh the vehicle's planner stations.
-- A failed cleanup is only a warning; the tick always saves.
CREATE FUNCTION pdc_work_categories_private.after_station_tick_746()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE v_ids uuid[]; v_stage text;
BEGIN
  SELECT pg_catalog.array_agg(DISTINCT n.vehicle_id) INTO v_ids FROM new_rows n WHERE n.vehicle_id IS NOT NULL;
  IF v_ids IS NULL THEN RETURN NULL; END IF;
  BEGIN
    PERFORM pdc_work_categories_private.clear_done_station_bookings_746(v_ids, TG_TABLE_NAME);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'r746: planner cleanup skipped for %: %', v_ids, SQLERRM;
  END;
  FOR v_stage IN
    SELECT DISTINCT s.code
    FROM public.vehicle_work_items wi
    JOIN public.workshop_stage_aliases wa ON wa.alias_normalized = public.workshop_normalize_identifier(wi.work_key)
    JOIN public.workshop_stages s ON s.code = wa.stage_code AND s.active AND s.planner_enabled
    WHERE wi.vehicle_id = ANY (v_ids) AND wi.required AND NOT wi.completed
    ORDER BY 1
  LOOP
    PERFORM public.workshop_bump_station_revision(v_stage);
  END LOOP;
  RETURN NULL;
END
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.after_station_tick_746() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER zz_station_done_746_ins AFTER INSERT ON public.pdc_panel_line_completion_565
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.after_station_tick_746();
CREATE TRIGGER zz_station_done_746_upd AFTER UPDATE ON public.pdc_panel_line_completion_565
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.after_station_tick_746();
CREATE TRIGGER zz_station_done_746_ins AFTER INSERT ON public.pdc_station_completion_override_578
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.after_station_tick_746();
CREATE TRIGGER zz_station_done_746_upd AFTER UPDATE ON public.pdc_station_completion_override_578
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.after_station_tick_746();

-- The planner list: a station the icon calls complete is not outstanding.
DO $elig746$
DECLARE v_oid oid := to_regprocedure('public.workshop_station_eligibility(text)'); v_src text; v_new text; v_old_tail text; v_new_tail text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  v_old_tail := E' )\n SELECT e.id,e.code,e.work_key,e.current_location,e.eta_to_kewdale,e.existing_booking,\n   e.approved_hours IS NOT NULL,\n   CASE WHEN e.approved_hours IS NULL THEN ''estimated_duration_missing'' ELSE NULL::text END\n FROM estimated e\n';
  IF (length(v_src) - length(replace(v_src, v_old_tail, ''))) / length(v_old_tail) <> 1 THEN RAISE EXCEPTION 'r746: eligibility tail not found exactly once'; END IF;
  v_new_tail := E' ),done AS MATERIALIZED (\n'
    || E'  -- r746 (F352): every line ticked (or a station override) means the station is done, so it is not outstanding.\n'
    || E'  -- Only rows with no open hours or with an override can be done, so only those reach the icon read.\n'
    || E'  SELECT d.vehicle_id FROM pdc_work_categories_private.done_planner_stations_746(ARRAY(\n'
    || E'   SELECT e.id FROM estimated e WHERE e.approved_hours IS NULL\n'
    || E'    OR EXISTS(SELECT 1 FROM public.pdc_station_completion_override_578 o WHERE o.vehicle_id=e.id AND o.work_key=e.work_key AND o.completed))) d\n'
    || E'  JOIN station st ON st.code=d.stage_code\n'
    || E' )\n SELECT e.id,e.code,e.work_key,e.current_location,e.eta_to_kewdale,e.existing_booking,\n   e.approved_hours IS NOT NULL,\n   CASE WHEN e.approved_hours IS NULL THEN ''estimated_duration_missing'' ELSE NULL::text END\n FROM estimated e\n'
    || E' WHERE NOT EXISTS(SELECT 1 FROM done d WHERE d.vehicle_id=e.id)\n';
  v_new := replace(v_src, v_old_tail, v_new_tail);
  EXECUTE replace(pg_get_functiondef(v_oid), v_src, v_new);
  IF (SELECT prosrc FROM pg_proc WHERE oid = v_oid) <> v_new THEN RAISE EXCEPTION 'r746: eligibility readback differs'; END IF;
END $elig746$;

-- One sweep for stations that are already complete, recorded as Craig (he asked for it; history needs an actor).
DO $sweep746$
DECLARE v_n integer;
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', '8a83b715-8d79-4b0e-95b2-02b55da6e8d7', 'role', 'authenticated',
    'email', 'craig.watson@broometoyota.com.au')::text, true);
  v_n :=pdc_work_categories_private.clear_done_station_bookings_746(ARRAY(
    SELECT DISTINCT b.vehicle_id FROM public.workshop_bookings b JOIN public.vehicles v ON v.id = b.vehicle_id
    WHERE b.deleted_at IS NULL AND b.status IN ('queued', 'planned') AND v.deleted_at IS NULL AND v.lifecycle_state = 'active'), 'r746_sweep');
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE 'r746: sweep cleared % bookings', v_n;
END $sweep746$;

INSERT INTO pdc_ops.regression_checks(check_name, sort_order, fault_id, added_in, enabled, description, check_sql)
VALUES ('done_station_leaves_planner_746', 466, 'F352', 'r746', true,
  'A planner station whose lines are all ticked (or overridden) is not in Unallocated and keeps no queued / planned booking; the tick and override tables carry the cleanup triggers.',
  $chk746$
SELECT trg.n = 4 AND elig.ok AND left_over.n = 0 AS ok,
  ('triggers ' || trg.n::text || ' | eligibility ' || CASE WHEN elig.ok THEN 'filters done' ELSE 'missing filter' END
   || ' | open bookings on done stations ' || left_over.n::text) AS detail
FROM (SELECT count(*) AS n FROM pg_catalog.pg_trigger
      WHERE tgname IN ('zz_station_done_746_ins', 'zz_station_done_746_upd') AND NOT tgisinternal AND tgenabled = 'O'
        AND tgrelid IN ('public.pdc_panel_line_completion_565'::regclass, 'public.pdc_station_completion_override_578'::regclass)) trg
CROSS JOIN (SELECT pg_catalog.strpos(prosrc, 'done_planner_stations_746') > 0 AS ok FROM pg_catalog.pg_proc
            WHERE oid = pg_catalog.to_regprocedure('public.workshop_station_eligibility(text)')) elig
CROSS JOIN (
  SELECT count(*) AS n
  FROM pdc_work_categories_private.done_planner_stations_746(ARRAY(
    SELECT DISTINCT c.vehicle_id FROM (
      SELECT vehicle_id, acted_at FROM public.pdc_panel_line_completion_565 WHERE completed
      UNION ALL SELECT vehicle_id, acted_at FROM public.pdc_station_completion_override_578 WHERE completed) c
    WHERE c.acted_at < pg_catalog.clock_timestamp() - interval '2 minutes'
      AND c.acted_at > pg_catalog.clock_timestamp() - interval '14 days'
    LIMIT 300)) d
  JOIN public.workshop_bookings b ON b.vehicle_id = d.vehicle_id AND b.stage_id = d.stage_id
   AND b.deleted_at IS NULL AND b.status IN ('queued', 'planned')
   AND b.updated_at < pg_catalog.clock_timestamp() - interval '2 minutes'
) left_over
$chk746$);

DO $post746$
DECLARE ok boolean; detail text;
BEGIN
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'done_station_leaves_planner_746') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r746: check red: %', detail; END IF;
END $post746$;
