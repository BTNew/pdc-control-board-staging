-- r642 (F257) / sort 392. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026: a Sublet page for Malaga Motor Trimmers (MMT). It lists every vehicle at PMB with an MMT
-- sublet line that carries a GP PO: PO, key, stock, customer, vehicle and the line. The trimmer ticks Built
-- (seat covers made), then Complete. Complete is the board's existing 'sublet done' tick on that PO line
-- (pdc_sublet_line_ticks_439), so the Sublet box on the board ticks off with it.
-- Who ticks: controllers, administrators and fitters (as on the board), plus any approved login whose email is
-- listed in pdc_mmt_private.providers (Craig adds the MMT login there). Everyone else with board access reads.
-- Changes to existing objects: one CHECK on pdc_sublet_line_ticks_439.changed_role also allows 'sublet_provider'.
-- No import function, pin, booking, location or Department 135 object changes. Pin count stays 241.
-- Kajel rows 9be0883b1a555f48f3c1ba9fa111c891 and apply b62fb7c29ffd2a1629f214f696e5cb14 are not edited.
-- Undo: supabase/rollbacks/20261028233000_r642_mmt_sublet.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard642$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r642: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r642: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r642: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks
             WHERE sort_order = 392 OR fault_id = 'F257' OR added_in = 'r642' OR check_name = 'mmt_sublet_642') THEN
    RAISE EXCEPTION 'r642: sort 392 or F257 is taken';
  END IF;
  IF to_regnamespace('pdc_mmt_private') IS NOT NULL THEN RAISE EXCEPTION 'r642: pdc_mmt_private exists'; END IF;
END $guard642$;

CREATE SCHEMA pdc_mmt_private;
REVOKE ALL ON SCHEMA pdc_mmt_private FROM PUBLIC, anon, authenticated;

-- Logins that may tick as the sublet provider (MMT). Empty until Craig adds one.
CREATE TABLE pdc_mmt_private.providers (
  email text PRIMARY KEY CHECK (email = lower(btrim(email)) AND email LIKE '%@%'),
  name text NOT NULL DEFAULT 'Malaga Motor Trimmers',
  active boolean NOT NULL DEFAULT true,
  added_at timestamptz NOT NULL DEFAULT now()
);

-- Built tick, one per MMT PO line. Complete lives in pdc_sublet_line_ticks_439.
CREATE TABLE pdc_mmt_private.builds (
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  line_key text NOT NULL CHECK (length(line_key) BETWEEN 4 AND 200),
  built boolean NOT NULL DEFAULT false,
  built_at timestamptz,
  built_by_email text,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (vehicle_id, line_key),
  CHECK ((built AND built_at IS NOT NULL AND built_by_email IS NOT NULL) OR (NOT built AND built_at IS NULL AND built_by_email IS NULL))
);

CREATE TABLE pdc_mmt_private.history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  line_key text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('built', 'complete')),
  ticked boolean NOT NULL,
  actor_id uuid NOT NULL,
  actor_email text NOT NULL,
  actor_role text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX history_vehicle_idx ON pdc_mmt_private.history (vehicle_id, created_at DESC);
ALTER TABLE pdc_mmt_private.providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_mmt_private.builds ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_mmt_private.history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA pdc_mmt_private FROM PUBLIC, anon, authenticated;

-- The provider's Complete tick is recorded with its own role name on the board's tick.
ALTER TABLE public.pdc_sublet_line_ticks_439 DROP CONSTRAINT pdc_sublet_line_ticks_439_changed_role_check;
ALTER TABLE public.pdc_sublet_line_ticks_439 ADD CONSTRAINT pdc_sublet_line_ticks_439_changed_role_check
  CHECK (changed_role = ANY (ARRAY['operator'::text, 'administrator'::text, 'fitter'::text, 'sublet_provider'::text]));

-- Who is asking: their tick role ('operator' / 'administrator' / 'fitter' / 'sublet_provider'), 'viewer' for read only, or NULL.
CREATE FUNCTION pdc_mmt_private.actor_role_642()
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  WITH me AS (
    SELECT r.role::text AS role FROM public.pdc_user_roles r
    WHERE r.auth_user_id = auth.uid() AND lower(r.email) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
      AND r.active AND r.account_status = 'approved'
  )
  SELECT CASE
    WHEN auth.uid() IS NULL THEN NULL
    WHEN EXISTS (SELECT 1 FROM me WHERE role IN ('administrator')) THEN 'administrator'
    WHEN EXISTS (SELECT 1 FROM me WHERE role IN ('operator')) THEN 'operator'
    WHEN EXISTS (SELECT 1 FROM me) AND EXISTS (SELECT 1 FROM pdc_mmt_private.providers p
         WHERE p.active AND p.email = lower(btrim(coalesce(auth.jwt()->>'email', ''))))
      THEN 'sublet_provider'
    WHEN EXISTS (SELECT 1 FROM me WHERE role IN ('fitter')) THEN 'fitter'
    WHEN EXISTS (SELECT 1 FROM me) THEN 'viewer'
  END
$fn$;
REVOKE ALL ON FUNCTION pdc_mmt_private.actor_role_642() FROM PUBLIC, anon, authenticated;

-- MMT PO lines: the GP PO's 'Description of sublet' names MMT or Malaga.
CREATE FUNCTION public.get_pdc_mmt_sublet_board_642()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE v_role text := pdc_mmt_private.actor_role_642();
BEGIN
  IF v_role IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authorized');
  END IF;
  RETURN jsonb_build_object(
    'ok', true, 'version', 'r642', 'provider', 'Malaga Motor Trimmers', 'role', v_role,
    'can_tick', v_role IN ('operator', 'administrator', 'fitter', 'sublet_provider'),
    'lines', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'vehicle_id', v.id, 'line_key', r.line_key, 'po_number', r.po_number,
        'stock_number', v.stock_number, 'key_number', v.key_number,
        'customer', v.customer_name,
        'vehicle', coalesce(nullif(btrim(v.vehicle_description), ''), v.model),
        'job_card_number', v.job_card_number,
        'description', left(replace(coalesce(r.description, ''), '^', ' '), 240),
        'built', coalesce(b.built, false), 'built_at', b.built_at, 'built_by_email', b.built_by_email,
        'built_version', coalesce(b.version, 0),
        'complete', coalesce(t.ticked, false), 'complete_at', t.ticked_at, 'complete_by_email', t.ticked_by_email,
        'complete_version', coalesce(t.version, 0))
        ORDER BY coalesce(t.ticked, false), coalesce(b.built, false), v.key_number NULLS LAST, v.stock_number)
      FROM public.pdc_service_line_po_refs_439 r
      JOIN public.vehicles v ON v.id = r.vehicle_id
      LEFT JOIN pdc_mmt_private.builds b ON b.vehicle_id = r.vehicle_id AND b.line_key = r.line_key
      LEFT JOIN public.pdc_sublet_line_ticks_439 t ON t.vehicle_id = r.vehicle_id AND t.line_key = r.line_key
      WHERE r.active AND r.description ~* '\m(mmt|malaga)'
        AND v.deleted_at IS NULL AND v.visible_on_board
        AND coalesce(nullif(v.location_override, ''), v.current_location) = 'PMB'), '[]'::jsonb));
END
$fn$;

-- Tick or untick Built or Complete on one MMT PO line. Complete needs Built first; Built cannot be unticked while
-- Complete is ticked. Complete writes the board's sublet tick (same table, history and audit as r439).
CREATE FUNCTION public.set_pdc_mmt_sublet_tick_642(
  p_vehicle_id uuid, p_line_key text, p_kind text, p_ticked boolean, p_expected_version integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_actor uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email', '')));
  v_role text := pdc_mmt_private.actor_role_642();
  v_key text := btrim(coalesce(p_line_key, ''));
  v_build pdc_mmt_private.builds%ROWTYPE;
  v_tick public.pdc_sublet_line_ticks_439%ROWTYPE;
  v_after public.pdc_sublet_line_ticks_439%ROWTYPE;
  v_identity text;
  v_idem uuid := gen_random_uuid();
  v_response jsonb;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('operator', 'administrator', 'fitter', 'sublet_provider') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authorized');
  END IF;
  IF p_vehicle_id IS NULL OR v_key = '' OR p_kind NOT IN ('built', 'complete') OR p_ticked IS NULL
     OR p_expected_version IS NULL OR p_expected_version < 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_input');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pdc_service_line_po_refs_439 r JOIN public.vehicles v ON v.id = r.vehicle_id
                 WHERE r.vehicle_id = p_vehicle_id AND r.line_key = v_key AND r.active
                   AND r.description ~* '\m(mmt|malaga)' AND v.deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_an_mmt_line');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-439-line:' || p_vehicle_id::text || ':' || v_key, 0));
  SELECT * INTO v_build FROM pdc_mmt_private.builds WHERE vehicle_id = p_vehicle_id AND line_key = v_key FOR UPDATE;
  SELECT * INTO v_tick FROM public.pdc_sublet_line_ticks_439 WHERE vehicle_id = p_vehicle_id AND line_key = v_key FOR UPDATE;

  IF p_kind = 'built' THEN
    IF coalesce(v_build.version, 0) <> p_expected_version THEN
      RETURN jsonb_build_object('ok', false, 'error', 'stale');
    END IF;
    IF NOT p_ticked AND coalesce(v_tick.ticked, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'complete_first');
    END IF;
    INSERT INTO pdc_mmt_private.builds AS b (vehicle_id, line_key, built, built_at, built_by_email, version, updated_at)
    VALUES (p_vehicle_id, v_key, p_ticked, CASE WHEN p_ticked THEN now() END, CASE WHEN p_ticked THEN v_email END, 1, now())
    ON CONFLICT (vehicle_id, line_key) DO UPDATE SET
      built = excluded.built, built_at = excluded.built_at, built_by_email = excluded.built_by_email,
      version = b.version + 1, updated_at = now()
    WHERE b.vehicle_id = excluded.vehicle_id AND b.line_key = excluded.line_key
    RETURNING * INTO v_build;
    INSERT INTO pdc_mmt_private.history (vehicle_id, line_key, kind, ticked, actor_id, actor_email, actor_role)
    VALUES (p_vehicle_id, v_key, 'built', p_ticked, v_actor, v_email, v_role);
    RETURN jsonb_build_object('ok', true, 'kind', 'built', 'ticked', v_build.built, 'version', v_build.version,
                              'at', v_build.built_at, 'by_email', v_build.built_by_email);
  END IF;

  -- Complete: the board's sublet done tick.
  IF coalesce(v_tick.version, 0) <> p_expected_version THEN
    RETURN jsonb_build_object('ok', false, 'error', 'stale');
  END IF;
  IF p_ticked AND NOT coalesce(v_build.built, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'build_first');
  END IF;
  SELECT l->>'line_identity' INTO v_identity
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  WHERE pdc_work_categories_private.sublet_line_key_439(l) = v_key LIMIT 1;

  INSERT INTO public.pdc_sublet_line_ticks_439 AS t (vehicle_id, line_key, line_identity, ticked, ticked_by, ticked_by_email, ticked_role,
    ticked_at, changed_by, changed_by_email, changed_role, version, updated_at)
  VALUES (p_vehicle_id, v_key, v_identity, p_ticked, CASE WHEN p_ticked THEN v_actor END, CASE WHEN p_ticked THEN v_email END,
    CASE WHEN p_ticked THEN v_role END, CASE WHEN p_ticked THEN clock_timestamp() END, v_actor, v_email, v_role, 1, clock_timestamp())
  ON CONFLICT (vehicle_id, line_key) DO UPDATE SET line_identity = coalesce(excluded.line_identity, t.line_identity),
    ticked = excluded.ticked, ticked_by = excluded.ticked_by, ticked_by_email = excluded.ticked_by_email,
    ticked_role = excluded.ticked_role, ticked_at = excluded.ticked_at, changed_by = excluded.changed_by,
    changed_by_email = excluded.changed_by_email, changed_role = excluded.changed_role,
    version = t.version + 1, updated_at = clock_timestamp()
  WHERE t.vehicle_id = excluded.vehicle_id AND t.line_key = excluded.line_key AND t.version = p_expected_version
  RETURNING * INTO v_after;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'stale'); END IF;

  v_response := jsonb_build_object('ok', true, 'kind', 'complete', 'ticked', v_after.ticked, 'version', v_after.version,
    'at', v_after.ticked_at, 'by_email', v_after.ticked_by_email, 'source', 'r642');
  INSERT INTO public.pdc_sublet_line_tick_history_439(history_id, vehicle_id, line_key, line_identity, actor_id, actor_email, actor_role,
    idempotency_key, request_sha256, before_state, after_state, response, reason)
  VALUES (gen_random_uuid(), p_vehicle_id, v_key, v_identity, v_actor, v_email, v_role, v_idem,
    encode(extensions.digest(convert_to(jsonb_build_object('r642', v_idem, 'line_key', v_key, 'ticked', p_ticked)::text, 'UTF8'), 'sha256'), 'hex'),
    CASE WHEN v_tick.line_key IS NULL THEN NULL ELSE to_jsonb(v_tick) END, to_jsonb(v_after), v_response,
    CASE WHEN p_ticked THEN 'MMT sublet ticked complete (r642)' ELSE 'MMT sublet unticked (r642)' END);
  INSERT INTO pdc_mmt_private.history (vehicle_id, line_key, kind, ticked, actor_id, actor_email, actor_role)
  VALUES (p_vehicle_id, v_key, 'complete', p_ticked, v_actor, v_email, v_role);
  PERFORM public.audit_pdc_event('update', 'pdc_sublet_line_ticks_439', NULL, p_vehicle_id,
    CASE WHEN v_tick.line_key IS NULL THEN NULL ELSE to_jsonb(v_tick) END, to_jsonb(v_after),
    jsonb_build_object('action', 'set_pdc_mmt_sublet_tick_642', 'line_key', v_key, 'ticked', p_ticked, 'actor_role', v_role));
  UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
  RETURN v_response;
END
$fn$;

REVOKE ALL ON FUNCTION public.get_pdc_mmt_sublet_board_642() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_pdc_mmt_sublet_tick_642(uuid, text, text, boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_mmt_sublet_board_642() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_pdc_mmt_sublet_tick_642(uuid, text, text, boolean, integer) TO authenticated;

DO $check642$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('mmt_sublet_642', 'F257',
    'MMT sublet page: private tables with RLS on, anon cannot read or tick, no Complete without Built, pins stay 241.',
    $chk642$
SELECT
  (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'pdc_mmt_private.builds'::regclass)
  AND NOT pg_catalog.has_function_privilege('anon', 'public.get_pdc_mmt_sublet_board_642()', 'execute')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.set_pdc_mmt_sublet_tick_642(uuid,text,text,boolean,integer)', 'execute')
  AND NOT pg_catalog.has_table_privilege('authenticated', 'pdc_mmt_private.providers', 'select')
  AND NOT EXISTS (SELECT 1 FROM public.pdc_sublet_line_ticks_439 t
                  WHERE t.ticked AND t.changed_role = 'sublet_provider'
                    AND NOT EXISTS (SELECT 1 FROM pdc_mmt_private.builds b WHERE b.vehicle_id = t.vehicle_id AND b.line_key = t.line_key AND b.built))
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'MMT sublet ticks stay private and in order' AS detail
$chk642$,
    true, 392, 'r642');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'mmt_sublet_642') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r642: check red: %', detail; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r642: pin count changed'; END IF;
END $check642$;
