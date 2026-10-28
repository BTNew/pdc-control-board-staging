-- r614 (F229) / sort 378. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026: overriding a vehicle's location to QC should tick every item as completed.
-- A trigger on vehicles fires only when location_override changes to QC and ticks every open line
-- through set_panel_line_completion_565 (same controller check, same history rows, same transaction as
-- the override). Imports never set location_override, so they never fire it. Untick stays per line.
-- Pin count stays 241. Kajel and Department 135 untouched.
-- Undo: supabase/rollbacks/20261028170000_r614_qc_override_ticks.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard614$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r614: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r614: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r614: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks
             WHERE sort_order = 378 OR fault_id = 'F229' OR added_in = 'r614' OR check_name = 'qc_override_ticks_614') THEN
    RAISE EXCEPTION 'r614: sort 378 or F229 is taken';
  END IF;
  IF to_regprocedure('public.complete_all_panel_lines_614(uuid)') IS NOT NULL OR to_regprocedure('public.vehicles_qc_override_ticks_614()') IS NOT NULL THEN RAISE EXCEPTION 'r614: function exists'; END IF;
END $guard614$;

-- Runs as the caller, so set_panel_line_completion_565 still checks they are a controller.
CREATE FUNCTION public.complete_all_panel_lines_614(p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
DECLARE v_line jsonb; v_res jsonb; v_ticked integer := 0; v_already integer := 0;
BEGIN
  IF coalesce(public.current_pdc_user_role()::text, '') NOT IN ('operator', 'administrator') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'controller_required');
  END IF;
  IF p_vehicle_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_vehicle'); END IF;
  FOR v_line IN
    SELECT l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
    WHERE coalesce((l->>'active')::boolean, true) AND NOT coalesce((l->>'rejected')::boolean, false)
      AND l->>'line_identity' ~* '^(source|manual):[0-9a-f-]{36}$'
  LOOP
    v_res := public.set_panel_line_completion_565(p_vehicle_id, v_line->>'line_identity', true);
    IF v_res->>'code' = 'saved' THEN v_ticked := v_ticked + 1;
    ELSIF v_res->>'code' = 'unchanged' THEN v_already := v_already + 1;
    ELSE RETURN jsonb_build_object('ok', false, 'error', coalesce(v_res->>'error', 'tick_failed'), 'ticked', v_ticked);
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'code', 'all_lines_ticked', 'ticked', v_ticked, 'already', v_already);
END
$fn$;

REVOKE ALL ON FUNCTION public.complete_all_panel_lines_614(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_all_panel_lines_614(uuid) TO authenticated;

CREATE FUNCTION public.vehicles_qc_override_ticks_614()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
BEGIN
  PERFORM public.complete_all_panel_lines_614(NEW.id);
  RETURN NULL;
END
$fn$;
REVOKE ALL ON FUNCTION public.vehicles_qc_override_ticks_614() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER vehicles_qc_override_ticks_614
AFTER UPDATE OF location_override ON public.vehicles
FOR EACH ROW
WHEN (NEW.location_override = 'QC' AND OLD.location_override IS DISTINCT FROM 'QC' AND NEW.deleted_at IS NULL)
EXECUTE FUNCTION public.vehicles_qc_override_ticks_614();

DO $check614$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('qc_override_ticks_614', 'F229',
    'Overriding to QC ticks every item: trigger is on, tick-all runs as the caller through set_panel_line_completion_565 and is closed to anon.',
    $chk614$
SELECT
  NOT (SELECT prosecdef FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.complete_all_panel_lines_614(uuid)'))
  AND strpos((SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.complete_all_panel_lines_614(uuid)')), 'public.set_panel_line_completion_565(') > 0
  AND NOT pg_catalog.has_function_privilege('anon', 'public.complete_all_panel_lines_614(uuid)', 'execute')
  AND EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgname = 'vehicles_qc_override_ticks_614' AND tgrelid = 'public.vehicles'::regclass AND tgenabled = 'O')
 AS ok,
 'QC override tick-all is invoker-only and uses the controller tick' AS detail
$chk614$,
    true, 378, 'r614');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'qc_override_ticks_614') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r614: check red: %', detail; END IF;
END $check614$;
