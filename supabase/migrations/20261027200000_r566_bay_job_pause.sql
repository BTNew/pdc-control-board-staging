-- r569 (F183) / sort 340. Go-live of #554.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- The preview claimed r566 / F180 / sort 340. r566 / F180 was the Electrical
-- bay hide, applied and rolled back, so those numbers are not reused.
-- r568 / F182 / sort 339 is the live Bus 4x4 split. This check is
-- bay_job_pause_569 / F183 / sort 340. The function name stays
-- pause_bay_job_for_other_566 so the preview prosrc md5 still matches.
--
-- A controller can pause the live or stoppage job in a bay and start another
-- unstarted job of a different vehicle in that same bay. The paused job stays
-- on stoppage. Its remaining workshop minutes are booked immediately behind
-- the job that just started. Neither vehicle is deleted, hidden, or completed,
-- and neither job card is closed.
--
-- start_workshop_work refuses a bay that already holds a started or stoppage
-- row, so the paused job leaves the bay only inside this transaction, then
-- comes back behind the new job. A parts stoppage that is already stopped keeps
-- its reason. Start itself is not changed.
-- Pin count stays 241. workshop_clock_tick and workshop_move_booking are not
-- edited. The new function is not pinned.
-- Undo: supabase/rollbacks/20261027200000_r566_bay_job_pause.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r569: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r569: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r569: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563') THEN RAISE EXCEPTION 'r569: r563 / F177 sort 336 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_default_clock_gap_559' AND fault_id='F173' AND sort_order=334 AND added_in='r559') THEN RAISE EXCEPTION 'r569: r559 / F173 sort 334 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bus_component_split_568' AND fault_id='F182' AND sort_order=339 AND added_in='r568') THEN RAISE EXCEPTION 'r569: r568 / F182 sort 339 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=340 OR fault_id='F183' OR check_name='bay_job_pause_569' OR added_in='r569') THEN RAISE EXCEPTION 'r569: sort 340 or F183 is taken'; END IF;
 IF pg_catalog.to_regprocedure('public.pause_bay_job_for_other_566(uuid,integer,uuid,integer)') IS NOT NULL THEN RAISE EXCEPTION 'r569: already applied'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '83a2c8d5ff85b5a295343e5f3ef66ded' THEN RAISE EXCEPTION 'r569: clock tick is not the r559 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM 'f15067e423da1ce70957e5190c922d50' THEN RAISE EXCEPTION 'r569: workshop_move_booking is not the r559 body'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.pause_bay_job_for_other_566(p_live uuid, p_live_version integer, p_incoming uuid, p_incoming_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $pause566$
DECLARE
 v_live public.workshop_bookings%rowtype;
 v_in public.workshop_bookings%rowtype;
 v_stage text;
 v_bay integer;
 v_now timestamptz;
 v_window_end timestamptz;
 v_remain integer;
 v_blocker uuid;
 v_step jsonb;
 v_code text;
 v_meta jsonb := jsonb_build_object('source','pause_bay_job_for_other_566');
BEGIN
 IF auth.uid() IS NULL OR coalesce(public.workshop_is_planner_operator(), false) IS NOT TRUE THEN
  RETURN jsonb_build_object('ok', false, 'error', 'not_authorized');
 END IF;
 IF p_live IS NULL OR p_incoming IS NULL OR p_live = p_incoming OR p_live_version IS NULL OR p_incoming_version IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'error', 'not_unstarted');
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation', 0));
 IF p_live < p_incoming THEN
  SELECT * INTO v_live FROM public.workshop_bookings WHERE id = p_live FOR UPDATE;
  SELECT * INTO v_in FROM public.workshop_bookings WHERE id = p_incoming FOR UPDATE;
 ELSE
  SELECT * INTO v_in FROM public.workshop_bookings WHERE id = p_incoming FOR UPDATE;
  SELECT * INTO v_live FROM public.workshop_bookings WHERE id = p_live FOR UPDATE;
 END IF;
 IF v_live.id IS NULL OR v_in.id IS NULL OR v_live.deleted_at IS NOT NULL OR v_in.deleted_at IS NOT NULL THEN
  RETURN jsonb_build_object('ok', false, 'error', 'booking_not_found');
 END IF;
 IF v_live.version <> p_live_version OR v_in.version <> p_incoming_version THEN
  RETURN jsonb_build_object('ok', false, 'error', 'version_conflict');
 END IF;
 IF v_live.vehicle_id = v_in.vehicle_id THEN
  RETURN jsonb_build_object('ok', false, 'error', 'same_vehicle');
 END IF;
 IF v_live.stage_id IS DISTINCT FROM v_in.stage_id THEN
  RETURN jsonb_build_object('ok', false, 'error', 'different_station');
 END IF;
 IF v_live.status NOT IN ('started', 'stoppage') OR v_live.bay_id IS NULL OR v_live.actual_start_at IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'error', 'not_live');
 END IF;
 IF v_live.status = 'stoppage' AND nullif(btrim(coalesce(v_live.stoppage_reason, '')), '') IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'error', 'not_live');
 END IF;
 IF v_in.status NOT IN ('queued', 'planned') OR v_in.actual_start_at IS NOT NULL THEN
  RETURN jsonb_build_object('ok', false, 'error', 'not_unstarted');
 END IF;
 IF coalesce(v_in.default_duration_minutes, 0) <= 0 THEN
  RETURN jsonb_build_object('ok', false, 'error', 'bad_duration');
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.vehicles v
    WHERE v.id = v_live.vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
 ) OR NOT EXISTS (
   SELECT 1 FROM public.vehicles v
    WHERE v.id = v_in.vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
 ) THEN
  RETURN jsonb_build_object('ok', false, 'error', 'vehicle_not_found');
 END IF;
 SELECT s.code, b.bay_number INTO v_stage, v_bay
   FROM public.workshop_bays b
   JOIN public.workshop_stages s ON s.id = b.stage_id
  WHERE b.id = v_live.bay_id;
 IF v_stage IS NULL OR v_bay IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'error', 'bay_required');
 END IF;
 v_now := date_trunc('minute', clock_timestamp());
 v_remain := public.workshop_operational_minutes_between(v_now, public.workshop_booking_effective_end_at(v_live.id));
 IF v_remain < 1 THEN
  v_remain := greatest(coalesce(v_live.default_duration_minutes, 0), 15);
 END IF;
 IF v_remain > 10000 THEN
  RETURN jsonb_build_object('ok', false, 'error', 'remaining_too_long');
 END IF;
 v_window_end := public.workshop_add_operational_minutes(
  public.workshop_add_operational_minutes(v_now, v_in.default_duration_minutes), v_remain);
 SELECT o.id INTO v_blocker
   FROM public.workshop_bookings o
  WHERE o.bay_id = v_live.bay_id
    AND o.id <> v_live.id
    AND o.id <> v_in.id
    AND o.deleted_at IS NULL
    AND o.status IN ('queued', 'planned', 'started', 'stoppage')
    AND o.scheduled_start_at < v_window_end
    AND public.workshop_booking_effective_end_at(o.id) > v_now
  LIMIT 1;
 IF v_blocker IS NOT NULL THEN
  RETURN jsonb_build_object('ok', false, 'error', 'bay_busy_with_others', 'blocker', v_blocker);
 END IF;
 BEGIN
  IF v_live.status = 'started' THEN
   v_step := public.stop_workshop_work(v_live.id, v_live.version, 'Paused so another job can use this bay', v_meta);
   IF coalesce((v_step->>'ok')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'pause_step:%', coalesce(v_step->>'error', 'stop_failed');
   END IF;
   SELECT * INTO v_live FROM public.workshop_bookings WHERE id = p_live FOR UPDATE;
  END IF;
  UPDATE public.workshop_bookings
     SET bay_id = NULL,
         stoppage_reason = CASE
           WHEN nullif(btrim(coalesce(stoppage_reason, '')), '') IS NULL
             THEN 'Paused so another job can use this bay'
           ELSE stoppage_reason
         END,
         updated_by = auth.uid(),
         version = version + 1
   WHERE id = v_live.id
     AND status = 'stoppage'
     AND deleted_at IS NULL
     AND actual_start_at IS NOT NULL
     AND bay_id IS NOT NULL;
  IF NOT FOUND THEN
   RAISE EXCEPTION 'pause_step:%', 'not_live';
  END IF;
  v_step := public.workshop_move_booking(v_in.id, v_in.version, v_stage, v_bay, v_now, v_in.default_duration_minutes, v_meta);
  IF coalesce((v_step->>'ok')::boolean, false) IS NOT TRUE THEN
   RAISE EXCEPTION 'pause_step:%', coalesce(v_step->>'error', 'move_failed');
  END IF;
  SELECT version INTO v_in.version FROM public.workshop_bookings WHERE id = v_in.id;
  v_step := public.start_workshop_work(v_in.id, v_in.version, v_now, v_meta);
  IF coalesce((v_step->>'ok')::boolean, false) IS NOT TRUE THEN
   RAISE EXCEPTION 'pause_step:%', coalesce(v_step->>'error', 'start_failed');
  END IF;
  SELECT scheduled_end_at, version INTO v_in.scheduled_end_at, v_in.version
    FROM public.workshop_bookings WHERE id = v_in.id;
  IF v_in.scheduled_end_at IS NULL THEN
   RAISE EXCEPTION 'pause_step:%', 'start_failed';
  END IF;
  SELECT version INTO v_live.version FROM public.workshop_bookings WHERE id = v_live.id;
  v_step := public.workshop_move_booking(v_live.id, v_live.version, v_stage, v_bay, v_in.scheduled_end_at, v_remain, v_meta);
  IF coalesce((v_step->>'ok')::boolean, false) IS NOT TRUE THEN
   RAISE EXCEPTION 'pause_step:%', coalesce(v_step->>'error', 'move_failed');
  END IF;
 EXCEPTION WHEN OTHERS THEN
  IF left(SQLERRM, 11) = 'pause_step:' THEN
   v_code := substr(SQLERRM, 12);
  ELSE
   v_code := 'pause_failed';
  END IF;
  IF v_code IS NULL OR v_code = '' THEN
   v_code := 'pause_failed';
  END IF;
  RETURN jsonb_build_object('ok', false, 'error', v_code);
 END;
 RETURN jsonb_build_object(
  'ok', true,
  'remaining_minutes', v_remain,
  'paused_start', v_in.scheduled_end_at,
  'incoming_booking_id', v_in.id,
  'live_booking_id', v_live.id);
END
$pause566$;

REVOKE ALL ON FUNCTION public.pause_bay_job_for_other_566(uuid, integer, uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pause_bay_job_for_other_566(uuid, integer, uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.pause_bay_job_for_other_566(uuid, integer, uuid, integer) TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('bay_job_pause_569', 'F183',
 'r569: pause_bay_job_for_other_566 is security definer, search_path pg_catalog public, granted to authenticated only. It pauses a live bay job behind another unstarted job and does not complete, cancel, or rewrite a vehicle. Clock tick and workshop_move_booking stay on the r559 bodies. Pin count stays 241.',
$chk566$
SELECT
 pins.n = 241
 AND NOT EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 e WHERE e.release = 'r569')
 AND tick.md5 = '83a2c8d5ff85b5a295343e5f3ef66ded'
 AND move.md5 = 'f15067e423da1ce70957e5190c922d50'
 AND pause.prosecdef
 AND pause.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
 AND pg_catalog.strpos(pause.prosrc, 'stop_workshop_work') > 0
 AND pg_catalog.strpos(pause.prosrc, 'workshop_move_booking') > 0
 AND pg_catalog.strpos(pause.prosrc, 'start_workshop_work') > 0
 AND pg_catalog.strpos(pause.prosrc, 'bay_id = NULL') > 0
 AND pg_catalog.strpos(pause.prosrc, 'pause_step:') > 0
 AND pg_catalog.strpos(pause.prosrc, 'complete_workshop_work') = 0
 AND pg_catalog.strpos(pause.prosrc, 'cancel_workshop_booking') = 0
 AND pg_catalog.strpos(pause.prosrc, 'pg_catalog.coalesce') = 0
 AND pg_catalog.has_function_privilege('authenticated'::name, pause.oid, 'EXECUTE')
 AND NOT pg_catalog.has_function_privilege('anon'::name, pause.oid, 'EXECUTE')
 AS ok,
 'pause '||pg_catalog.md5(pause.prosrc)||' tick '||tick.md5||' move '||move.md5 AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (
  SELECT p.prosrc, p.prosecdef, p.proconfig, p.oid
    FROM pg_catalog.pg_proc p
   WHERE p.oid = pg_catalog.to_regprocedure('public.pause_bay_job_for_other_566(uuid,integer,uuid,integer)')
) pause
CROSS JOIN (
  SELECT md5(p.prosrc) AS md5
    FROM pg_catalog.pg_proc p
   WHERE p.oid = pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')
) tick
CROSS JOIN (
  SELECT md5(p.prosrc) AS md5
    FROM pg_catalog.pg_proc p
   WHERE p.oid = pg_catalog.to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')
) move
$chk566$, true, 340, 'r569');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r569: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r569') THEN RAISE EXCEPTION 'r569: a pin was inserted'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '83a2c8d5ff85b5a295343e5f3ef66ded' THEN RAISE EXCEPTION 'r569: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM 'f15067e423da1ce70957e5190c922d50' THEN RAISE EXCEPTION 'r569: move body changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='bay_job_pause_569' AND fault_id='F183' AND sort_order=340 AND added_in='r569' AND enabled)<>1 THEN RAISE EXCEPTION 'r569: check missing'; END IF;
 PERFORM set_config('request.jwt.claims', '', true);
 PERFORM set_config('search_path', 'pg_catalog', true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='bay_job_pause_569' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r569: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
