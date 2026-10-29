-- r711 (F321) / sort 460. Staging cdsmnqxtyyoeoznmbidd only. Craig, 29 Oct 2026 11:33 AWST.
-- Sublet · PSC: the MMT page again for Perth Sign Craft (PSC). Lists PMB vehicles with a GP PO line for signage:
-- the line names PSC / Perth Sign Craft / signcraft, or is signage, decals, stripping or a wrap with no other
-- company named (MMT seat-cover lines, Vision Group and Jason Signs are left out). Built, then Complete (the
-- board's sublet done tick), then Invoiced, exactly as r642. Built/Invoiced share pdc_mmt_private.builds (one row
-- per PO line; a line is MMT or PSC, never both).
-- Logins: pdc_mmt_private.providers gains a provider column (MMT / PSC). A PSC login is added later (Craig).
-- The pre-request hook keeps the fitter and MMT branches and adds a PSC branch. MMT's role helper now only
-- counts MMT logins. No import function, pin, booking, location or Department 135 object changes. Pins stay 241.
-- Undo: supabase/rollbacks/20261029040000_r711_psc_sublet.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard711$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r711: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r711: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r711: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks
             WHERE sort_order = 460 OR fault_id = 'F321' OR added_in = 'r711' OR check_name = 'psc_sublet_711') THEN
    RAISE EXCEPTION 'r711: sort 460 or F321 is taken';
  END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_check_fitter_request()'::regprocedure)) <> '494db85fba899c69f02a8e8836068779' THEN
    RAISE EXCEPTION 'r711: pre-request hook changed since r643';
  END IF;
END $guard711$;

ALTER TABLE pdc_mmt_private.providers ADD COLUMN provider text NOT NULL DEFAULT 'MMT' CHECK (provider IN ('MMT', 'PSC'));
ALTER TABLE pdc_mmt_private.history ADD COLUMN provider text NOT NULL DEFAULT 'MMT' CHECK (provider IN ('MMT', 'PSC'));

-- PSC lines: names PSC / Perth Sign Craft / signcraft, or signage / decal / stripping / sign writing / wrap with no
-- other company named. MMT seat-cover lines, Vision Group and Jason Signs are excluded.
CREATE FUNCTION pdc_mmt_private.psc_line_711(p_description text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog
AS $fn$
  SELECT coalesce(p_description, '') ~* '\m(psc|perth sign|sign ?craft)'
      OR (coalesce(p_description, '') ~* '(signage|decal|stripping|sign writ|\mwrap\M)'
          AND coalesce(p_description, '') !~* '\m(mmt|malaga)'
          AND coalesce(p_description, '') !~* '(vision group|jason sign)')
$fn$;
REVOKE ALL ON FUNCTION pdc_mmt_private.psc_line_711(text) FROM PUBLIC, anon, authenticated;

-- Who is asking, for one provider's page: 'administrator' / 'operator' / 'sublet_provider' (that provider's login)
-- / 'fitter' / 'viewer', or NULL when not signed in and approved.
CREATE FUNCTION pdc_mmt_private.actor_role_711(p_provider text)
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
         WHERE p.active AND p.provider = p_provider AND p.email = lower(btrim(coalesce(auth.jwt()->>'email', ''))))
      THEN 'sublet_provider'
    WHEN EXISTS (SELECT 1 FROM me WHERE role IN ('fitter')) THEN 'fitter'
    WHEN EXISTS (SELECT 1 FROM me) THEN 'viewer'
  END
$fn$;
REVOKE ALL ON FUNCTION pdc_mmt_private.actor_role_711(text) FROM PUBLIC, anon, authenticated;

-- MMT's helper now only counts MMT logins (a PSC login is never 'sublet_provider' on the MMT page).
CREATE OR REPLACE FUNCTION pdc_mmt_private.actor_role_642()
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  SELECT pdc_mmt_private.actor_role_711('MMT')
$fn$;
REVOKE ALL ON FUNCTION pdc_mmt_private.actor_role_642() FROM PUBLIC, anon, authenticated;

-- PSC board (copy of get_pdc_mmt_sublet_board_642 with the PSC line rule and role).
CREATE FUNCTION public.get_pdc_psc_sublet_board_711()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE v_role text := pdc_mmt_private.actor_role_711('PSC');
BEGIN
  IF v_role IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authorized');
  END IF;
  RETURN jsonb_build_object(
    'ok', true, 'version', 'r711', 'provider', 'Perth Sign Craft', 'role', v_role,
    'can_tick', v_role IN ('operator', 'administrator', 'fitter', 'sublet_provider'),
    'lines', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'vehicle_id', v.id, 'line_key', r.line_key, 'po_number', r.po_number,
        'stock_number', v.stock_number, 'key_number', v.key_number,
        -- Days at PMG: age from when the vehicle got its key number (r562 key assigned, r563 key time as fallback).
        'key_at', coalesce(ka.assigned_at, aa.key_at),
        'days_at_pmg', CASE WHEN coalesce(ka.assigned_at, aa.key_at) IS NULL THEN NULL ELSE
          ((clock_timestamp() AT TIME ZONE 'Australia/Perth')::date - (coalesce(ka.assigned_at, aa.key_at) AT TIME ZONE 'Australia/Perth')::date) END,
        'customer', v.customer_name,
        'vehicle', coalesce(nullif(btrim(v.vehicle_description), ''), v.model),
        'job_card_number', v.job_card_number,
        'description', left(replace(coalesce(r.description, ''), '^', ' '), 240),
        'built', coalesce(b.built, false), 'built_at', b.built_at, 'built_by_email', b.built_by_email,
        'built_version', coalesce(b.version, 0),
        'complete', coalesce(t.ticked, false), 'complete_at', t.ticked_at, 'complete_by_email', t.ticked_by_email,
        'complete_version', coalesce(t.version, 0),
        'location', coalesce(nullif(v.location_override, ''), v.current_location))
        ORDER BY coalesce(t.ticked, false), coalesce(b.built, false), v.key_number NULLS LAST, v.stock_number)
      FROM public.pdc_service_line_po_refs_439 r
      JOIN public.vehicles v ON v.id = r.vehicle_id
      LEFT JOIN pdc_mmt_private.builds b ON b.vehicle_id = r.vehicle_id AND b.line_key = r.line_key
      LEFT JOIN public.pdc_vehicle_key_assigned_562 ka ON ka.vehicle_id = v.id
      LEFT JOIN public.pdc_vehicle_pmb_arrival_age_563 aa ON aa.vehicle_id = v.id
      LEFT JOIN public.pdc_sublet_line_ticks_439 t ON t.vehicle_id = r.vehicle_id AND t.line_key = r.line_key
      -- At PMB, or ticked Complete and not yet invoiced (wherever the vehicle has gone since). Invoiced lines leave the page.
      WHERE r.active AND pdc_mmt_private.psc_line_711(r.description)
        AND v.deleted_at IS NULL
        AND NOT coalesce(b.invoiced, false)
        AND ((v.visible_on_board AND coalesce(nullif(v.location_override, ''), v.current_location) = 'PMB')
             OR coalesce(t.ticked, false))), '[]'::jsonb));
END
$fn$;

-- PSC ticks (copy of set_pdc_mmt_sublet_tick_642 with the PSC line rule and role).
CREATE FUNCTION public.set_pdc_psc_sublet_tick_711(
  p_vehicle_id uuid, p_line_key text, p_kind text, p_ticked boolean, p_expected_version integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_actor uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email', '')));
  v_role text := pdc_mmt_private.actor_role_711('PSC');
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
  IF p_vehicle_id IS NULL OR v_key = '' OR p_kind NOT IN ('built', 'complete', 'invoiced') OR p_ticked IS NULL
     OR p_expected_version IS NULL OR p_expected_version < 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_input');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.pdc_service_line_po_refs_439 r JOIN public.vehicles v ON v.id = r.vehicle_id
                 WHERE r.vehicle_id = p_vehicle_id AND r.line_key = v_key AND r.active
                   AND pdc_mmt_private.psc_line_711(r.description) AND v.deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_a_psc_line');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-439-line:' || p_vehicle_id::text || ':' || v_key, 0));
  SELECT * INTO v_build FROM pdc_mmt_private.builds WHERE vehicle_id = p_vehicle_id AND line_key = v_key FOR UPDATE;
  SELECT * INTO v_tick FROM public.pdc_sublet_line_ticks_439 WHERE vehicle_id = p_vehicle_id AND line_key = v_key FOR UPDATE;

  IF p_kind = 'invoiced' THEN
    IF coalesce(v_build.version, 0) <> p_expected_version THEN
      RETURN jsonb_build_object('ok', false, 'error', 'stale');
    END IF;
    IF p_ticked AND NOT coalesce(v_tick.ticked, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'complete_first_invoice');
    END IF;
    UPDATE pdc_mmt_private.builds b SET invoiced = p_ticked,
      invoiced_at = CASE WHEN p_ticked THEN now() END, invoiced_by_email = CASE WHEN p_ticked THEN v_email END,
      version = b.version + 1, updated_at = now()
    WHERE b.vehicle_id = p_vehicle_id AND b.line_key = v_key
    RETURNING * INTO v_build;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'build_first'); END IF;
    INSERT INTO pdc_mmt_private.history (vehicle_id, line_key, kind, ticked, actor_id, actor_email, actor_role, provider)
    VALUES (p_vehicle_id, v_key, 'invoiced', p_ticked, v_actor, v_email, v_role, 'PSC');
    RETURN jsonb_build_object('ok', true, 'kind', 'invoiced', 'ticked', v_build.invoiced, 'version', v_build.version);
  END IF;

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
    INSERT INTO pdc_mmt_private.history (vehicle_id, line_key, kind, ticked, actor_id, actor_email, actor_role, provider)
    VALUES (p_vehicle_id, v_key, 'built', p_ticked, v_actor, v_email, v_role, 'PSC');
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
  IF NOT p_ticked AND coalesce(v_build.invoiced, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_invoiced');
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
    'at', v_after.ticked_at, 'by_email', v_after.ticked_by_email, 'source', 'r711');
  INSERT INTO public.pdc_sublet_line_tick_history_439(history_id, vehicle_id, line_key, line_identity, actor_id, actor_email, actor_role,
    idempotency_key, request_sha256, before_state, after_state, response, reason)
  VALUES (gen_random_uuid(), p_vehicle_id, v_key, v_identity, v_actor, v_email, v_role, v_idem,
    encode(extensions.digest(convert_to(jsonb_build_object('r711', v_idem, 'line_key', v_key, 'ticked', p_ticked)::text, 'UTF8'), 'sha256'), 'hex'),
    CASE WHEN v_tick.line_key IS NULL THEN NULL ELSE to_jsonb(v_tick) END, to_jsonb(v_after), v_response,
    CASE WHEN p_ticked THEN 'PSC sublet ticked complete (r711)' ELSE 'PSC sublet unticked (r711)' END);
  INSERT INTO pdc_mmt_private.history (vehicle_id, line_key, kind, ticked, actor_id, actor_email, actor_role, provider)
  VALUES (p_vehicle_id, v_key, 'complete', p_ticked, v_actor, v_email, v_role, 'PSC');
  PERFORM public.audit_pdc_event('update', 'pdc_sublet_line_ticks_439', NULL, p_vehicle_id,
    CASE WHEN v_tick.line_key IS NULL THEN NULL ELSE to_jsonb(v_tick) END, to_jsonb(v_after),
    jsonb_build_object('action', 'set_pdc_psc_sublet_tick_711', 'line_key', v_key, 'ticked', p_ticked, 'actor_role', v_role));
  UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
  RETURN v_response;
END
$fn$;

REVOKE ALL ON FUNCTION public.get_pdc_psc_sublet_board_711() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_pdc_psc_sublet_tick_711(uuid, text, text, boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_psc_sublet_board_711() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_pdc_psc_sublet_tick_711(uuid, text, text, boolean, integer) TO authenticated;

-- Pre-request hook: fitter branch unchanged; MMT branch now MMT logins only; PSC branch added.
CREATE OR REPLACE FUNCTION public.pdc_check_fitter_request()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE path text:=ltrim(coalesce(current_setting('request.path',true),''),'/');
 v_provider text;
BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_user_roles
   WHERE (auth_user_id=auth.uid() OR email=lower(auth.jwt()->>'email')) AND role::text='fitter') THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=auth.uid()
    AND email=lower(auth.jwt()->>'email') AND active AND account_status='approved' AND role::text='fitter')
   OR path NOT IN ('rpc/get_fitter_roster','rpc/get_fitter_jobs','rpc/get_fitter_job','rpc/get_fitter_refresh','rpc/fitter_job_command','rpc/record_pdc_usage_20260914','rpc/handoff_operation_line_583','rpc/undo_line_handoff_583','rpc/list_line_handoffs_583','rpc/set_line_later_627')
   OR current_setting('request.method',true) <> 'POST' THEN
    RAISE EXCEPTION 'This account can access Fitters bay only' USING errcode='42501';
  END IF;
 END IF;
 -- r643 (F258) / r711 (F321): a sublet provider login reads its own role row and uses its own page only.
 SELECT p.provider INTO v_provider FROM pdc_mmt_private.providers p
  WHERE p.active AND p.email=lower(btrim(coalesce(auth.jwt()->>'email',''))) LIMIT 1;
 IF v_provider IS NOT NULL THEN
  IF path='pdc_user_roles' AND current_setting('request.method',true) IN ('GET','HEAD') THEN RETURN; END IF;
  IF v_provider='MMT' AND (path NOT IN ('rpc/get_pdc_mmt_sublet_board_642','rpc/set_pdc_mmt_sublet_tick_642','rpc/record_pdc_login','rpc/record_pdc_usage_20260914')
   OR current_setting('request.method',true) <> 'POST') THEN
    RAISE EXCEPTION 'This account can access Sublet · MMT only' USING errcode='42501';
  END IF;
  IF v_provider='PSC' AND (path NOT IN ('rpc/get_pdc_psc_sublet_board_711','rpc/set_pdc_psc_sublet_tick_711','rpc/record_pdc_login','rpc/record_pdc_usage_20260914')
   OR current_setting('request.method',true) <> 'POST') THEN
    RAISE EXCEPTION 'This account can access Sublet · PSC only' USING errcode='42501';
  END IF;
 END IF;
END $function$;

DO $check711$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('psc_sublet_711', 'F321',
    'PSC sublet page: anon cannot read or tick, MMT seat-cover lines never count as PSC, provider logins locked to their page, pins stay 241.',
    $chk711$
SELECT
  NOT pg_catalog.has_function_privilege('anon', 'public.get_pdc_psc_sublet_board_711()', 'execute')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.set_pdc_psc_sublet_tick_711(uuid,text,text,boolean,integer)', 'execute')
  AND NOT pdc_mmt_private.psc_line_711('MMT 2 ROWS SEAT COVERS CANVAS^Avis signage on front seats')
  AND pdc_mmt_private.psc_line_711('Avis Signage & Stripping - Fit Supplied Signage')
  AND pdc_mmt_private.psc_line_711('Avery Onyx black wrap to outer moon roof^Fitted by signcraft')
  AND NOT pdc_mmt_private.psc_line_711('Silverstone Signage - Vision Group to supply & fit')
  AND position('rpc/get_pdc_psc_sublet_board_711' IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_check_fitter_request()'::regprocedure)) > 0
  AND position('rpc/get_pdc_mmt_sublet_board_642' IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_check_fitter_request()'::regprocedure)) > 0
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'PSC sublet page private, MMT lines excluded, logins locked' AS detail
$chk711$,
    true, 460, 'r711');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'psc_sublet_711') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r711: check red: %', detail; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r711: pin count changed'; END IF;
END $check711$;
