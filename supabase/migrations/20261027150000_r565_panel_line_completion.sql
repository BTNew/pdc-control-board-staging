-- r565 (F179) / sort 337. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
--
-- Live before this apply: r562 / F176 / sort 335 is the key gate.
-- r563 / F177 / sort 336 is the arrival age. r564 / F178 is the Fitters key
-- badge and inserted no check, so sort 337 is free. This release is
-- r565 / F179 / sort 337. pdc_ops.fault_regression_check() runs the row below.
--
-- Source commit a6b3a20a claimed r563 / F177 / sort 337. F177 and r563 are the
-- arrival age, so this file is renumbered. Source up md5
-- 9df2a739f9ba1afd4b477c739d3471f8. Source down md5
-- a2bc3245c0acbd2dad5087878a7e72cb.
--
-- The vehicle side panel keeps its own chip layout when Edit is pressed.
-- Dragging a line uses the existing category and planner moves. This release
-- only adds a controller tick for one operation line: who ticked it and when,
-- with an untick. It does not change vehicles, workshop bookings, categories,
-- QC sign-off, or the pin table. Pin count stays 241.
-- Controllers are operator and administrator (User Management). Other approved
-- roles can read the ticks. The JWT user_metadata claim is not read.
-- Undo: supabase/rollbacks/20261027150000_r565_panel_line_completion.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r565: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r565: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r565: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_557' AND fault_id='F171' AND sort_order=332 AND added_in='r557') THEN RAISE EXCEPTION 'r565: r557 / F171 sort 332 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='newvehiclebuild_pdc_route_558' AND fault_id='F172' AND sort_order=333 AND added_in='r558') THEN RAISE EXCEPTION 'r565: r558 / F172 sort 333 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_default_clock_gap_559' AND fault_id='F173' AND sort_order=334 AND added_in='r559') THEN RAISE EXCEPTION 'r565: r559 / F173 sort 334 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_562' AND fault_id='F176' AND sort_order=335 AND added_in='r562') THEN RAISE EXCEPTION 'r565: r562 / F176 sort 335 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563') THEN RAISE EXCEPTION 'r565: r563 / F177 sort 336 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=337 OR fault_id='F179' OR check_name='panel_line_completion_565' OR added_in='r565') THEN RAISE EXCEPTION 'r565: sort 337 or F179 is taken'; END IF;
 IF pg_catalog.to_regclass('public.pdc_panel_line_completion_565') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_panel_line_completion_history_565') IS NOT NULL THEN RAISE EXCEPTION 'r565: already applied'; END IF;
END $g$;

CREATE TABLE public.pdc_panel_line_completion_565 (
 vehicle_id uuid NOT NULL,
 line_identity text NOT NULL,
 completed boolean NOT NULL,
 actor_id uuid,
 actor_email text,
 actor_role text,
 acted_at timestamptz,
 version integer NOT NULL DEFAULT 1,
 PRIMARY KEY (vehicle_id, line_identity),
 CONSTRAINT pdc_panel_line_completion_565_identity CHECK (line_identity ~* '^(source|manual):[0-9a-f-]{36}$'),
 CONSTRAINT pdc_panel_line_completion_565_role CHECK (actor_role IS NULL OR actor_role IN ('operator', 'administrator')),
 CONSTRAINT pdc_panel_line_completion_565_version CHECK (version > 0)
);
ALTER TABLE public.pdc_panel_line_completion_565 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_panel_line_completion_565 FROM PUBLIC, anon, authenticated;

CREATE TABLE public.pdc_panel_line_completion_history_565 (
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL,
 line_identity text NOT NULL,
 completed boolean NOT NULL,
 actor_id uuid,
 actor_email text,
 actor_role text,
 acted_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_panel_line_completion_history_565 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_panel_line_completion_history_565 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.pdc_panel_line_completion_history_guard_565()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $guard565$
BEGIN
 RAISE EXCEPTION 'pdc_panel_line_completion_history_565 is append-only';
END
$guard565$;

CREATE TRIGGER pdc_panel_line_completion_history_565_guard
BEFORE UPDATE OR DELETE ON public.pdc_panel_line_completion_history_565
FOR EACH ROW EXECUTE FUNCTION public.pdc_panel_line_completion_history_guard_565();

REVOKE ALL ON FUNCTION public.pdc_panel_line_completion_history_guard_565() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.set_panel_line_completion_565(p_vehicle_id uuid, p_line_identity text, p_completed boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $set565$
DECLARE
 v_role text;
 v_email text;
 v_uid uuid;
 v_line jsonb;
 v_now timestamptz;
 v_prev boolean;
 v_version integer;
BEGIN
 v_role := pg_catalog.lower(pg_catalog.btrim(coalesce(public.current_pdc_user_role()::text, '')));
 IF v_role NOT IN ('operator', 'administrator') THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'controller_required');
 END IF;
 IF p_vehicle_id IS NULL OR p_completed IS NULL OR p_line_identity IS NULL
    OR p_line_identity !~* '^(source|manual):[0-9a-f-]{36}$' THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'invalid_line');
 END IF;
 SELECT l INTO v_line
 FROM pg_catalog.jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 WHERE l->>'line_identity' = p_line_identity
   AND coalesce((l->>'active')::boolean, true)
   AND coalesce((l->>'rejected')::boolean, false) = false
 LIMIT 1;
 IF v_line IS NULL THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'operation_not_found');
 END IF;
 v_uid := auth.uid();
 v_email := public.current_actor_email();
 v_now := pg_catalog.clock_timestamp();
 SELECT completed, version INTO v_prev, v_version
 FROM public.pdc_panel_line_completion_565
 WHERE vehicle_id = p_vehicle_id AND line_identity = p_line_identity;
 IF FOUND AND v_prev IS NOT DISTINCT FROM p_completed THEN
  RETURN pg_catalog.jsonb_build_object('ok', true, 'code', 'unchanged', 'line_identity', p_line_identity, 'completed', p_completed);
 END IF;
 INSERT INTO public.pdc_panel_line_completion_history_565 (vehicle_id, line_identity, completed, actor_id, actor_email, actor_role, acted_at)
 VALUES (p_vehicle_id, p_line_identity, p_completed, v_uid, v_email, v_role, v_now);
 INSERT INTO public.pdc_panel_line_completion_565 (vehicle_id, line_identity, completed, actor_id, actor_email, actor_role, acted_at, version)
 VALUES (p_vehicle_id, p_line_identity, p_completed, v_uid, v_email, v_role, v_now, 1)
 ON CONFLICT (vehicle_id, line_identity) DO UPDATE
 SET completed = EXCLUDED.completed,
     actor_id = EXCLUDED.actor_id,
     actor_email = EXCLUDED.actor_email,
     actor_role = EXCLUDED.actor_role,
     acted_at = EXCLUDED.acted_at,
     version = public.pdc_panel_line_completion_565.version + 1
 WHERE public.pdc_panel_line_completion_565.vehicle_id = EXCLUDED.vehicle_id
   AND public.pdc_panel_line_completion_565.line_identity = EXCLUDED.line_identity;
 RETURN pg_catalog.jsonb_build_object(
  'ok', true, 'code', 'saved', 'line_identity', p_line_identity, 'completed', p_completed,
  'actor_email', v_email, 'actor_role', v_role, 'acted_at', v_now, 'version', coalesce(v_version, 0) + 1);
END
$set565$;

REVOKE ALL ON FUNCTION public.set_panel_line_completion_565(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_panel_line_completion_565(uuid, text, boolean) TO authenticated;

CREATE FUNCTION public.get_panel_line_completions_565(p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $get565$
DECLARE
 v_role text;
BEGIN
 v_role := pg_catalog.lower(pg_catalog.btrim(coalesce(public.current_pdc_user_role()::text, '')));
 IF v_role NOT IN ('viewer', 'operator', 'importer', 'administrator', 'fitter', 'salesperson') THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'role_required');
 END IF;
 IF p_vehicle_id IS NULL THEN
  RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'invalid_line');
 END IF;
 RETURN pg_catalog.jsonb_build_object('ok', true, 'lines', coalesce((
  SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
   'line_identity', c.line_identity,
   'completed', c.completed,
   'actor_email', c.actor_email,
   'actor_role', c.actor_role,
   'acted_at', c.acted_at,
   'version', c.version))
  FROM public.pdc_panel_line_completion_565 c
  WHERE c.vehicle_id = p_vehicle_id
 ), '[]'::jsonb));
END
$get565$;

REVOKE ALL ON FUNCTION public.get_panel_line_completions_565(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_panel_line_completions_565(uuid) TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('panel_line_completion_565', 'F179',
 'A workshop controller can tick one side-panel line completed, with who and when, and untick it. The pin count stays 241. The tick does not rewrite a vehicle. Controllers are operator and administrator.',
 $chk565$
SELECT
  pins.n = 241
  AND added.n = 0
  AND current_row.relrowsecurity
  AND history_row.relrowsecurity
  AND guard.present
  AND setter.present
  AND setter.controller
  AND setter.unchanged
  AND setter.no_vehicle_update
  AND setter.no_booking_update
  AND setter.no_user_metadata
  AND setter.auth_exec
  AND setter.anon_blocked
  AND reader.present
  AND reader.reads_viewer
  AND reader.auth_exec
  AND reader.anon_blocked
  AND anchors.live
  AS ok,
  ('pins ' || pins.n::pg_catalog.text || ' | panel line completion') AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r565') added
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_panel_line_completion_565'
) current_row
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_panel_line_completion_history_565'
) history_row
CROSS JOIN (
  SELECT count(*) = 1 AS present
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_proc p ON p.oid = t.tgfoid
  WHERE n.nspname = 'public' AND c.relname = 'pdc_panel_line_completion_history_565'
    AND t.tgname = 'pdc_panel_line_completion_history_565_guard' AND NOT t.tgisinternal
    AND pg_catalog.strpos(p.prosrc, 'append-only') > 0
) guard
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'controller_required') > 0 AND pg_catalog.strpos(p.prosrc, 'operator') > 0 AND pg_catalog.strpos(p.prosrc, 'administrator') > 0), false) AS controller,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'unchanged') > 0), false) AS unchanged,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'workshop_bookings') = 0), false) AS no_booking_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'user_metadata') = 0), false) AS no_user_metadata,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'set_panel_line_completion_565'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid, p_line_identity text, p_completed boolean'
) setter
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'viewer') > 0 AND pg_catalog.strpos(p.prosrc, 'fitter') > 0), false) AS reads_viewer,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'get_panel_line_completions_565'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid'
) reader
CROSS JOIN (
  SELECT count(*) = 2 AS live
  FROM pdc_ops.regression_checks
  WHERE (check_name = 'new_to_pmb_ack_557' AND fault_id = 'F171' AND sort_order = 332 AND added_in = 'r557')
     OR (check_name = 'newvehiclebuild_pdc_route_558' AND fault_id = 'F172' AND sort_order = 333 AND added_in = 'r558')
) anchors
$chk565$, true, 337, 'r565');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r565: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r565') THEN RAISE EXCEPTION 'r565: a pin was inserted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' AND fault_id='F179' AND sort_order=337 AND added_in='r565' AND enabled)<>1 THEN RAISE EXCEPTION 'r565: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' LOOP
  EXECUTE r.check_sql INTO probe;
  IF probe.ok IS NOT TRUE THEN RAISE EXCEPTION 'r565: check not ok: %', probe.detail; END IF;
 END LOOP;
END $post$;
