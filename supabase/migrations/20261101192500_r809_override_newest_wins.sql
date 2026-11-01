-- r809 (F444) / sort 591. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 1 Nov 2026 19:14: "on key 102 i unticked tint, its unticked in the side menu but the homescreen is showing green
-- still". Cause: a Tint station override (Craig, 29 Oct 16:32 AWST) with no line ticked counts as done (1 Nov rule:
-- skipped / not needed), so unticking the only Tint line changed nothing on the icons, planner or QC.
-- Craig chose 19:16: newest action wins. A line tick or untick made after a station override cancels that station's
-- override (completed = false, written to the override history with who and when), on every car. The station then shows
-- its real ticks. Setting the override again later works as before.
-- Retro: overrides already followed by a line change whose station is not fully ticked are cancelled the same way
-- (1 Nov 19:20: only key 102 Tint; 101 other overrides have later ticks but every line ticked, so they are left alone).
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard809$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r809: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r809: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 591 OR fault_id = 'F444' OR added_in = 'r809' OR check_name = 'override_newest_wins_809') THEN RAISE EXCEPTION 'r809: sort 591, F444 or r809 is taken'; END IF;
  IF to_regprocedure('pdc_work_categories_private.override_newest_wins_809()') IS NOT NULL THEN RAISE EXCEPTION 'r809: already applied'; END IF;
END $guard809$;

-- The station a line counts under, exactly as station_icon_completion_578 counts it (handoff first, then stage code).
CREATE FUNCTION pdc_work_categories_private.line_work_key_809(p_vehicle_id uuid, p_line_identity text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $fn$
  SELECT coalesce(pdc_work_categories_private.line_handoff_work_key_583(h.to_stage_code),
    CASE upper(btrim(coalesce(l->>'stage_code', '')))
      WHEN 'BUS_4X4' THEN 'bus4x4' WHEN 'BUS_MECHANICAL' THEN 'bus4x4' WHEN 'BUS_ACCESSORIES' THEN 'bus4x4'
      WHEN 'BUS_ELECTRICAL' THEN 'bus4x4' WHEN 'BUS_QA' THEN 'bus4x4'
      WHEN 'TINT' THEN 'tint' WHEN 'HOIST' THEN 'hoist' WHEN 'FITTING' THEN 'fitting' WHEN 'FABRICATION' THEN 'fabrication'
      WHEN 'ELECTRICAL' THEN 'electrical' WHEN 'TYRE' THEN 'tyre' WHEN 'SUBLET' THEN 'sublet' WHEN 'PARTS' THEN 'parts' ELSE NULL END)
  FROM jsonb_array_elements(coalesce(public.pdc_qc_operation_lines_379(p_vehicle_id), '[]'::jsonb)) l
  LEFT JOIN public.pdc_line_handoff_583 h ON h.vehicle_id = p_vehicle_id AND h.line_identity = l->>'line_identity'
  WHERE l->>'line_identity' = p_line_identity
  LIMIT 1
$fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.line_work_key_809(uuid, text) FROM PUBLIC, anon, authenticated;

-- Cancel one override (only if it is on and older than the line change), with a history row for who and when.
CREATE FUNCTION pdc_work_categories_private.cancel_override_809(p_vehicle_id uuid, p_work_key text, p_before timestamptz,
  p_actor_id uuid, p_actor_email text, p_actor_role text, p_at timestamptz)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $fn$
BEGIN
  IF p_work_key IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.pdc_station_completion_override_578
    WHERE vehicle_id = p_vehicle_id AND work_key = p_work_key AND completed AND acted_at < p_before) THEN
    RETURN false;
  END IF;
  INSERT INTO public.pdc_station_completion_history_578 (vehicle_id, work_key, completed, actor_id, actor_email, actor_role, acted_at)
  VALUES (p_vehicle_id, p_work_key, false, p_actor_id, p_actor_email, coalesce(p_actor_role, 'line_change_809'), p_at);
  UPDATE public.pdc_station_completion_override_578
  SET completed = false, actor_id = p_actor_id, actor_email = p_actor_email, actor_role = coalesce(p_actor_role, 'line_change_809'),
      acted_at = p_at, version = version + 1
  WHERE vehicle_id = p_vehicle_id AND work_key = p_work_key AND completed AND acted_at < p_before;
  RETURN true;
END $fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.cancel_override_809(uuid, text, timestamptz, uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_work_categories_private.override_newest_wins_809()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $fn$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.completed IS NOT DISTINCT FROM NEW.completed THEN RETURN NULL; END IF;
  END IF;
  -- cheap exit: no override on this car at all
  IF NOT EXISTS (SELECT 1 FROM public.pdc_station_completion_override_578 WHERE vehicle_id = NEW.vehicle_id AND completed) THEN RETURN NULL; END IF;
  PERFORM pdc_work_categories_private.cancel_override_809(NEW.vehicle_id,
    pdc_work_categories_private.line_work_key_809(NEW.vehicle_id, NEW.line_identity), coalesce(NEW.acted_at, clock_timestamp()),
    NEW.actor_id, NEW.actor_email, NEW.actor_role, coalesce(NEW.acted_at, clock_timestamp()));
  RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.override_newest_wins_809() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER zz_override_newest_wins_809 AFTER INSERT OR UPDATE OF completed ON public.pdc_panel_line_completion_565
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.override_newest_wins_809();

-- Retro: an override already followed by a line change on its station, where the station is not fully ticked.
DO $retro809$
DECLARE r record; n integer := 0;
BEGIN
  FOR r IN
    WITH o AS (
      SELECT o.* FROM public.pdc_station_completion_override_578 o
      JOIN public.vehicles v ON v.id = o.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state = 'active'
      WHERE o.completed
    ), later AS (
      SELECT DISTINCT ON (o.vehicle_id, o.work_key) o.vehicle_id, o.work_key, o.acted_at AS o_at,
        pc.actor_id, pc.actor_email, pc.actor_role, pc.acted_at
      FROM o
      JOIN public.pdc_panel_line_completion_565 pc ON pc.vehicle_id = o.vehicle_id AND pc.acted_at > o.acted_at
      WHERE pdc_work_categories_private.line_work_key_809(pc.vehicle_id, pc.line_identity) = o.work_key
      ORDER BY o.vehicle_id, o.work_key, pc.acted_at DESC
    ), icons AS (
      SELECT (s->>'vehicle_id')::uuid AS vehicle_id, s->>'work_key' AS work_key, (s->>'done')::int AS done, (s->>'total')::int AS total
      FROM jsonb_array_elements(pdc_work_categories_private.station_icon_completion_578(ARRAY(SELECT DISTINCT vehicle_id FROM later))) s
    )
    SELECT l.* FROM later l JOIN icons i ON i.vehicle_id = l.vehicle_id AND i.work_key = l.work_key WHERE i.done < i.total
  LOOP
    IF pdc_work_categories_private.cancel_override_809(r.vehicle_id, r.work_key, r.acted_at, r.actor_id, r.actor_email, r.actor_role, r.acted_at) THEN n := n + 1; END IF;
  END LOOP;
  RAISE NOTICE 'r809: % override(s) cancelled by an earlier line change', n;
  IF n > 5 THEN RAISE EXCEPTION 'r809: retro would cancel % overrides (expected 1); stopped', n; END IF;
END $retro809$;

DO $check809$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('override_newest_wins_809', 'F444',
    'A line tick or untick after a station override cancels the override (newest action wins); no override is on while an untick newer than it sits on its station.',
    $chk$
WITH o AS (SELECT * FROM public.pdc_station_completion_override_578 WHERE completed),
bad AS (
  SELECT 1 FROM o JOIN public.pdc_panel_line_completion_565 pc ON pc.vehicle_id = o.vehicle_id AND pc.acted_at > o.acted_at + interval '2 seconds'
  JOIN public.vehicles v ON v.id = o.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state = 'active'
  WHERE pc.completed = false AND pdc_work_categories_private.line_work_key_809(pc.vehicle_id, pc.line_identity) = o.work_key
  LIMIT 1)
SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'zz_override_newest_wins_809' AND tgrelid = 'public.pdc_panel_line_completion_565'::regclass AND tgenabled <> 'D')
  AND NOT EXISTS (SELECT 1 FROM bad)
  AND NOT has_function_privilege('authenticated', 'pdc_work_categories_private.cancel_override_809(uuid,text,timestamptz,uuid,text,text,timestamptz)', 'execute')
 AS ok, 'override newest wins in place' AS detail
$chk$, true, 591, 'r809');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'override_newest_wins_809') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r809: check red: %', detail; END IF;
END $check809$;
