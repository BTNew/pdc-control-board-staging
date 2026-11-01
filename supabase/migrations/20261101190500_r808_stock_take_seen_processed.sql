-- r808 (F443) / sort 590. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 1 Nov 2026 18:36: "change our stocktake page ... it shows all keys from lowest to highest and when i click onto one,
-- it drops down and marks the vehicle as "seen" and when i tick the items i click close at the bottom and it marks that
-- vehicle as orange as if its been processed". 18:37: "we dont need the vehicle catagories to tick, we need to see all
-- items and tick them".
-- Additive only: the r720/r723/r724 functions and tables stay as they are (the old page keeps working until the new page
-- goes live).
--   pdc_stock_take_round_808          one row per stock take (walk-around). The latest round is the current one.
--   pdc_stock_take_car_808            per round and car: seen (opened) and processed (Close pressed), with who and when.
--   get_pdc_stock_take_808()          every car at PMB with a numeric key, key low to high, with its stock take state (fast).
--   get_pdc_stock_take_car_808(v)     one car's work items (every station), loaded when the car is opened.
--   get_pdc_stock_take_rev_808()      change marker the page polls (ticks, X, missing, seen/processed, rounds, board rev).
--   set_pdc_stock_take_car_808(v, a)  a = 'seen' | 'processed' | 'reopen' (controllers).
--   start_pdc_stock_take_round_808()  a new stock take: every car back to Not seen (administrators). Old rounds are kept.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard808$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r808: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r808: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 590 OR fault_id = 'F443' OR added_in = 'r808' OR check_name = 'stock_take_808') THEN RAISE EXCEPTION 'r808: sort 590, F443 or r808 is taken'; END IF;
  IF to_regprocedure('public.set_panel_line_completion_565(uuid,text,boolean)') IS NULL
     OR to_regclass('public.pdc_stock_take_missing_720') IS NULL OR to_regclass('public.pdc_stock_take_x_723') IS NULL THEN RAISE EXCEPTION 'r808: r565/r720/r723 missing'; END IF;
  IF to_regclass('public.pdc_stock_take_car_808') IS NOT NULL THEN RAISE EXCEPTION 'r808: already applied'; END IF;
END $guard808$;

CREATE TABLE public.pdc_stock_take_round_808 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  started_by text
);
ALTER TABLE public.pdc_stock_take_round_808 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_stock_take_round_808 FROM PUBLIC, anon, authenticated;
INSERT INTO public.pdc_stock_take_round_808 (started_by) VALUES ('r808 release');

CREATE TABLE public.pdc_stock_take_car_808 (
  round_id bigint NOT NULL REFERENCES public.pdc_stock_take_round_808(id) ON DELETE CASCADE,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  seen_at timestamptz,
  seen_by text,
  processed_at timestamptz,
  processed_by text,
  acted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (round_id, vehicle_id)
);
ALTER TABLE public.pdc_stock_take_car_808 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_stock_take_car_808 FROM PUBLIC, anon, authenticated;
CREATE INDEX pdc_stock_take_car_808_acted ON public.pdc_stock_take_car_808 (acted_at DESC);

-- A person's short name for "who" labels (same rule as r720: full name, else a non-email display name, else the email name).
CREATE FUNCTION public.pdc_stock_take_who_808(p_email text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
  SELECT CASE WHEN p_email IS NULL THEN NULL ELSE coalesce(
    (SELECT coalesce(nullif(btrim(u.full_name), ''), nullif(CASE WHEN u.display_name LIKE '%@%' THEN '' ELSE btrim(u.display_name) END, ''))
       FROM public.pdc_user_roles u WHERE lower(u.email) = lower(p_email) ORDER BY u.active DESC LIMIT 1),
    split_part(p_email, '@', 1)) END
$fn$;
REVOKE ALL ON FUNCTION public.pdc_stock_take_who_808(text) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.set_pdc_stock_take_car_808(p_vehicle_id uuid, p_action text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); v_round bigint; v_email text := public.current_actor_email();
  v_now timestamptz := clock_timestamp(); v_row public.pdc_stock_take_car_808%ROWTYPE;
BEGIN
  IF v_role NOT IN ('operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'controller_required'); END IF;
  IF p_vehicle_id IS NULL OR p_action IS NULL OR p_action NOT IN ('seen', 'processed', 'reopen') THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_action'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.vehicles WHERE id = p_vehicle_id AND deleted_at IS NULL) THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_vehicle'); END IF;
  SELECT max(id) INTO v_round FROM public.pdc_stock_take_round_808;
  INSERT INTO public.pdc_stock_take_car_808 AS c (round_id, vehicle_id, seen_at, seen_by, processed_at, processed_by, acted_at)
  VALUES (v_round, p_vehicle_id, v_now, v_email,
          CASE WHEN p_action = 'processed' THEN v_now END, CASE WHEN p_action = 'processed' THEN v_email END, v_now)
  ON CONFLICT (round_id, vehicle_id) DO UPDATE SET
    -- the first person to open the car keeps "seen"; Close always records who closed it last; reopen clears Close only
    seen_at = coalesce(c.seen_at, EXCLUDED.seen_at), seen_by = CASE WHEN c.seen_at IS NULL THEN EXCLUDED.seen_by ELSE c.seen_by END,
    processed_at = CASE p_action WHEN 'processed' THEN EXCLUDED.processed_at WHEN 'reopen' THEN NULL ELSE c.processed_at END,
    processed_by = CASE p_action WHEN 'processed' THEN EXCLUDED.processed_by WHEN 'reopen' THEN NULL ELSE c.processed_by END,
    acted_at = CASE WHEN p_action = 'seen' AND c.seen_at IS NOT NULL THEN c.acted_at ELSE EXCLUDED.acted_at END
  WHERE c.round_id = EXCLUDED.round_id AND c.vehicle_id = EXCLUDED.vehicle_id
  RETURNING * INTO v_row;
  RETURN jsonb_build_object('ok', true, 'round', v_round, 'vehicle_id', p_vehicle_id, 'action', p_action,
    'seen_at', v_row.seen_at, 'seen_by', public.pdc_stock_take_who_808(v_row.seen_by),
    'processed_at', v_row.processed_at, 'processed_by', public.pdc_stock_take_who_808(v_row.processed_by));
END $fn$;
REVOKE ALL ON FUNCTION public.set_pdc_stock_take_car_808(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_stock_take_car_808(uuid, text) TO authenticated;

CREATE FUNCTION public.start_pdc_stock_take_round_808()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); v_id bigint;
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  INSERT INTO public.pdc_stock_take_round_808 (started_by) VALUES (public.current_actor_email()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'round', v_id);
END $fn$;
REVOKE ALL ON FUNCTION public.start_pdc_stock_take_round_808() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_pdc_stock_take_round_808() TO authenticated;

CREATE FUNCTION public.get_pdc_stock_take_rev_808()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
  SELECT CASE WHEN coalesce(public.current_pdc_user_role()::text IN ('viewer', 'operator', 'administrator'), false) THEN
    coalesce((SELECT max(acted_at)::text FROM public.pdc_panel_line_completion_565), '') || '|' ||
    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_missing_720), '') || '|' ||
    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_x_723), '') || '|' ||
    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_car_808), '') || '|' ||
    coalesce((SELECT max(id)::text FROM public.pdc_stock_take_round_808), '') || '|' ||
    coalesce((SELECT revision::text FROM public.pdc_email_vehicle_revision WHERE singleton), '')
  END
$fn$;
REVOKE ALL ON FUNCTION public.get_pdc_stock_take_rev_808() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_stock_take_rev_808() TO authenticated;

-- The list: every car at PMB with a numeric key (WPC and no-key cars are not walked), key low to high, with its stock take
-- state only. Fast (no work lines), so the page can reload it whenever anything changes.
CREATE FUNCTION public.get_pdc_stock_take_808()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); v_round bigint; v_round_at timestamptz;
BEGIN
  IF v_role NOT IN ('viewer', 'operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  SELECT id, started_at INTO v_round, v_round_at FROM public.pdc_stock_take_round_808 ORDER BY id DESC LIMIT 1;
  RETURN (
    WITH pmb AS (
      SELECT v.id, v.stock_number, btrim(v.key_number) AS key_number, coalesce(nullif(btrim(v.model), ''), nullif(btrim(v.vehicle_description), '')) AS vehicle
      FROM public.vehicles v
      WHERE v.deleted_at IS NULL AND v.lifecycle_state = 'active' AND coalesce(v.visible_on_board, true)
        AND btrim(coalesce(v.key_number, '')) ~ '^\d+$'
        AND public.workshop_location_code(coalesce(nullif(v.location_override, ''), v.current_location)) = 'PMB'
    )
    SELECT jsonb_build_object('ok', true, 'version', 'r808', 'now', clock_timestamp(),
      'round', v_round, 'round_at', v_round_at, 'can_tick', v_role IN ('operator', 'administrator'), 'can_reset', v_role = 'administrator',
      'rev', public.get_pdc_stock_take_rev_808(),
      'cars', coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'k', p.key_number, 's', p.stock_number, 'v', p.vehicle,
          'missing', coalesce(m.missing, false),
          'missing_by', CASE WHEN m.missing THEN public.pdc_stock_take_who_808(m.actor_email) END, 'missing_at', CASE WHEN m.missing THEN m.acted_at END,
          'seen_at', c.seen_at, 'seen_by', public.pdc_stock_take_who_808(c.seen_by),
          'processed_at', c.processed_at, 'processed_by', public.pdc_stock_take_who_808(c.processed_by))
        ORDER BY p.key_number::bigint, p.stock_number), '[]'::jsonb))
    FROM pmb p
    LEFT JOIN public.pdc_stock_take_missing_720 m ON m.vehicle_id = p.id
    LEFT JOIN public.pdc_stock_take_car_808 c ON c.round_id = v_round AND c.vehicle_id = p.id
  );
END $fn$;
REVOKE ALL ON FUNCTION public.get_pdc_stock_take_808() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_stock_take_808() TO authenticated;

-- One car's items (loaded when the car is opened): every work item, whatever the station; job card notes come as notes
-- (not ticked). Done = the board's panel tick when there is one, else the line's own completion or the fitter's (as the
-- station icons count it). x = the stock take red cross (r723: looked, it is not there).
CREATE FUNCTION public.get_pdc_stock_take_car_808(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, '')));
BEGIN
  IF v_role NOT IN ('viewer', 'operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  IF p_vehicle_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.vehicles WHERE id = p_vehicle_id AND deleted_at IS NULL) THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_vehicle'); END IF;
  RETURN (
    WITH raw AS (
      SELECT x FROM jsonb_array_elements(coalesce(public.pdc_qc_operation_lines_379(p_vehicle_id), '[]'::jsonb)) x
      WHERE coalesce((x->>'active')::boolean, true) AND NOT coalesce((x->>'rejected')::boolean, false) AND x->>'line_identity' IS NOT NULL
    ), fitter AS (
      SELECT DISTINCT ON (fp.line_identity) fp.line_identity, fp.completed
      FROM pdc_fitter_private.operation_progress fp
      JOIN public.workshop_bookings wb ON wb.id = fp.booking_id
      WHERE wb.vehicle_id = p_vehicle_id AND wb.deleted_at IS NULL
      ORDER BY fp.line_identity, fp.updated_at DESC, fp.booking_id
    ), lines AS (
      SELECT r.x->>'line_identity' AS li,
        upper(coalesce(nullif(btrim(h.to_stage_code), ''), r.x->>'stage_code', '')) AS st, r.x->>'description' AS d, r.x->'estimated_hours' AS h,
        coalesce(pc.completed, coalesce((r.x->>'completed')::boolean, false) OR coalesce(f.completed, false)) AS done,
        CASE WHEN pc.completed IS NOT NULL THEN pc.acted_at END AS at, CASE WHEN pc.completed IS NOT NULL THEN pc.actor_email END AS by_email,
        coalesce(xx.x, false) AS x_on, xx.actor_email AS x_email, xx.acted_at AS x_at
      FROM raw r
      LEFT JOIN public.pdc_line_handoff_583 h ON h.vehicle_id = p_vehicle_id AND h.line_identity = r.x->>'line_identity'
      LEFT JOIN public.pdc_panel_line_completion_565 pc ON pc.vehicle_id = p_vehicle_id AND pc.line_identity = r.x->>'line_identity'
      LEFT JOIN fitter f ON f.line_identity = r.x->>'line_identity'
      LEFT JOIN public.pdc_stock_take_x_723 xx ON xx.vehicle_id = p_vehicle_id AND xx.line_identity = r.x->>'line_identity' AND xx.x
    )
    SELECT jsonb_build_object('ok', true, 'id', p_vehicle_id, 'now', clock_timestamp(),
      'l', coalesce(jsonb_agg(jsonb_build_object('id', l.li, 'st', l.st, 'd', l.d, 'h', l.h, 'done', l.done,
            'by', public.pdc_stock_take_who_808(l.by_email), 'at', l.at,
            'x', l.x_on AND NOT l.done, 'x_by', CASE WHEN l.x_on THEN public.pdc_stock_take_who_808(l.x_email) END, 'x_at', CASE WHEN l.x_on THEN l.x_at END)
          ORDER BY l.st, l.d) FILTER (WHERE l.st <> 'JOB_CARD_NOTES'), '[]'::jsonb),
      'n', coalesce(jsonb_agg(l.d ORDER BY l.d) FILTER (WHERE l.st = 'JOB_CARD_NOTES'), '[]'::jsonb))
    FROM lines l
  );
END $fn$;
REVOKE ALL ON FUNCTION public.get_pdc_stock_take_car_808(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_stock_take_car_808(uuid) TO authenticated;

DO $check808$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('stock_take_808', 'F443',
    'Stock take r808: staff-only reads (no anon), seen/processed writes for controllers only, new stock take for administrators only, tables locked to the API.',
    $chk$
SELECT to_regprocedure('public.get_pdc_stock_take_808()') IS NOT NULL
  AND NOT has_function_privilege('anon', 'public.get_pdc_stock_take_808()', 'execute')
  AND NOT has_function_privilege('anon', 'public.get_pdc_stock_take_rev_808()', 'execute')
  AND NOT has_function_privilege('anon', 'public.get_pdc_stock_take_car_808(uuid)', 'execute')
  AND NOT has_function_privilege('anon', 'public.set_pdc_stock_take_car_808(uuid,text)', 'execute')
  AND NOT has_function_privilege('anon', 'public.start_pdc_stock_take_round_808()', 'execute')
  AND NOT has_function_privilege('authenticated', 'public.pdc_stock_take_who_808(text)', 'execute')
  AND NOT has_table_privilege('authenticated', 'public.pdc_stock_take_car_808', 'select')
  AND NOT has_table_privilege('authenticated', 'public.pdc_stock_take_round_808', 'select')
  AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.pdc_stock_take_car_808'::regclass)
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.set_pdc_stock_take_car_808(uuid,text)')), 'controller_required') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.start_pdc_stock_take_round_808()')), 'administrator_required') > 0
  AND EXISTS (SELECT 1 FROM public.pdc_stock_take_round_808)
 AS ok, 'stock take r808 in place' AS detail
$chk$, true, 590, 'r808');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_808') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r808: check red: %', detail; END IF;
END $check808$;
