-- r720 (F330) / sort 470. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 12:58: a Stock take tab. Craig, Oleg and Garrath walk PMB with iPads; every vehicle at PMB with work for the
-- chosen station(s), sorted by key number. Ticking an item ticks that line on the board (set_panel_line_completion_565, the
-- same tick as the side panel), and everyone else's screen shows it with who ticked it, within seconds.
--   get_pdc_stock_take_720(p_stations text[])  the list (read only; viewer and up).
--   get_pdc_stock_take_rev_720()               a cheap change marker the page polls; it reloads the list only on change.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard720$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r720: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r720: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r720: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 470 OR fault_id = 'F330' OR added_in = 'r720' OR check_name = 'stock_take_720') THEN RAISE EXCEPTION 'r720: sort 470 or F330 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r720: an import job is running'; END IF;
  IF to_regprocedure('public.get_pdc_stock_take_720(text[])') IS NOT NULL THEN RAISE EXCEPTION 'r720: already applied'; END IF;
END $guard720$;

-- Craig 13:15: "if we go to a bay and that vehicle isn't here, put down missing so we have to find it later".
-- One row per vehicle; shared, so everyone sees who flagged it. Cleared by tapping again (or when found).
CREATE TABLE public.pdc_stock_take_missing_720 (
  vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
  missing boolean NOT NULL,
  actor_email text,
  acted_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_stock_take_missing_720 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_stock_take_missing_720 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.set_pdc_stock_take_missing_720(p_vehicle_id uuid, p_missing boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, '')));
BEGIN
  IF v_role NOT IN ('operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'controller_required'); END IF;
  IF p_vehicle_id IS NULL OR p_missing IS NULL OR NOT EXISTS (SELECT 1 FROM public.vehicles WHERE id = p_vehicle_id AND deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_vehicle');
  END IF;
  INSERT INTO public.pdc_stock_take_missing_720 (vehicle_id, missing, actor_email, acted_at)
  VALUES (p_vehicle_id, p_missing, public.current_actor_email(), clock_timestamp())
  ON CONFLICT (vehicle_id) DO UPDATE SET missing = EXCLUDED.missing, actor_email = EXCLUDED.actor_email, acted_at = EXCLUDED.acted_at
  WHERE public.pdc_stock_take_missing_720.vehicle_id = EXCLUDED.vehicle_id;
  RETURN jsonb_build_object('ok', true, 'vehicle_id', p_vehicle_id, 'missing', p_missing);
END $fn$;
REVOKE ALL ON FUNCTION public.set_pdc_stock_take_missing_720(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_stock_take_missing_720(uuid, boolean) TO authenticated;

CREATE FUNCTION public.get_pdc_stock_take_720(p_stations text[] DEFAULT ARRAY['FITTING', 'FABRICATION'])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); v_st text[];
BEGIN
  IF v_role NOT IN ('viewer', 'operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  SELECT coalesce(array_agg(DISTINCT upper(btrim(s))), '{}') INTO v_st FROM unnest(coalesce(p_stations, '{}')) s WHERE btrim(coalesce(s, '')) <> '';
  IF cardinality(v_st) = 0 OR cardinality(v_st) > 12 THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_stations'); END IF;
  RETURN (
    WITH pmb AS (
      SELECT v.id, v.stock_number, v.key_number, coalesce(nullif(btrim(v.model), ''), nullif(btrim(v.vehicle_description), '')) AS vehicle
      FROM public.vehicles v
      WHERE v.deleted_at IS NULL AND v.lifecycle_state = 'active' AND coalesce(v.visible_on_board, true)
        AND public.workshop_location_code(coalesce(nullif(v.location_override, ''), v.current_location)) = 'PMB'
    ), lines AS (
      SELECT p.id, p.stock_number, p.key_number, p.vehicle, x
      FROM pmb p, jsonb_array_elements(public.pdc_qc_operation_lines_379(p.id)) x
      WHERE x->>'stage_code' = ANY (v_st) AND coalesce((x->>'active')::boolean, true) AND NOT coalesce((x->>'rejected')::boolean, false)
    ), named AS (
      SELECT l.*, c.completed AS panel_done, c.acted_at,
             coalesce(nullif(btrim(r.full_name), ''), nullif(CASE WHEN r.display_name LIKE '%@%' THEN '' ELSE btrim(r.display_name) END, ''), split_part(c.actor_email, '@', 1)) AS by_name
      FROM lines l
      LEFT JOIN public.pdc_panel_line_completion_565 c ON c.vehicle_id = l.id AND c.line_identity = l.x->>'line_identity'
      LEFT JOIN LATERAL (SELECT u.display_name, u.full_name FROM public.pdc_user_roles u WHERE lower(u.email) = lower(c.actor_email) ORDER BY u.active DESC LIMIT 1) r ON true
    ), cars AS (
      SELECT n.id, n.stock_number, n.key_number, n.vehicle,
        jsonb_agg(jsonb_build_object('id', n.x->>'line_identity', 'st', n.x->>'stage_code', 'd', n.x->>'description',
          'h', n.x->'estimated_hours', 'done', coalesce(n.panel_done, (n.x->>'completed')::boolean, false), -- the board's tick wins, as on the side panel
          'by', CASE WHEN n.panel_done IS NOT NULL THEN n.by_name END, 'at', n.acted_at)
          ORDER BY n.x->>'stage_code', n.x->>'description') AS lines
      FROM named n GROUP BY n.id, n.stock_number, n.key_number, n.vehicle
    )
    SELECT jsonb_build_object('ok', true, 'version', 'r720', 'now', clock_timestamp(), 'stations', to_jsonb(v_st),
      'can_tick', v_role IN ('operator', 'administrator'), 'rev', public.get_pdc_stock_take_rev_720(),
      'cars', coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'k', c.key_number, 's', c.stock_number, 'v', c.vehicle, 'l', c.lines,
        'missing', coalesce(m.missing, false), 'missing_by', CASE WHEN m.missing THEN coalesce(nullif(btrim(mu.full_name), ''), nullif(CASE WHEN mu.display_name LIKE '%@%' THEN '' ELSE btrim(mu.display_name) END, ''), split_part(m.actor_email, '@', 1)) END,
        'missing_at', CASE WHEN m.missing THEN m.acted_at END)
        ORDER BY nullif(regexp_replace(coalesce(c.key_number, ''), '\D', '', 'g'), '')::bigint NULLS LAST, c.stock_number), '[]'::jsonb))
    FROM cars c
    LEFT JOIN public.pdc_stock_take_missing_720 m ON m.vehicle_id = c.id
    LEFT JOIN LATERAL (SELECT u.display_name, u.full_name FROM public.pdc_user_roles u WHERE lower(u.email) = lower(m.actor_email) ORDER BY u.active DESC LIMIT 1) mu ON true
  );
END $fn$;

-- The change marker: last panel tick plus the board revision. Cheap enough to poll every few seconds.
CREATE FUNCTION public.get_pdc_stock_take_rev_720()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
  SELECT CASE WHEN coalesce(public.current_pdc_user_role()::text IN ('viewer', 'operator', 'administrator'), false) THEN
    coalesce((SELECT max(acted_at)::text FROM public.pdc_panel_line_completion_565), '') || '|' ||
    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_missing_720), '') || '|' ||
    coalesce((SELECT revision::text FROM public.pdc_email_vehicle_revision WHERE singleton), '')
  END
$fn$;

-- (get_pdc_stock_take_720 calls the marker at run time, so the create order does not matter.)
REVOKE ALL ON FUNCTION public.get_pdc_stock_take_720(text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_pdc_stock_take_rev_720() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_stock_take_720(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_stock_take_rev_720() TO authenticated;

DO $check720$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('stock_take_720', 'F330',
    'Stock take reads are staff only (no anon) and ticks go through set_panel_line_completion_565 (controllers only).',
    $chk$
SELECT to_regprocedure('public.get_pdc_stock_take_720(text[])') IS NOT NULL
  AND to_regprocedure('public.get_pdc_stock_take_rev_720()') IS NOT NULL
  AND NOT has_function_privilege('anon', 'public.get_pdc_stock_take_720(text[])', 'execute')
  AND NOT has_function_privilege('anon', 'public.get_pdc_stock_take_rev_720()', 'execute')
  AND NOT has_function_privilege('anon', 'public.set_pdc_stock_take_missing_720(uuid,boolean)', 'execute')
  AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.pdc_stock_take_missing_720'::regclass)
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.set_panel_line_completion_565(uuid,text,boolean)')), '''controller_required''') > 0
 AS ok, 'stock take in place' AS detail
$chk$, true, 470, 'r720');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_720') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r720: check red: %', detail; END IF;
END $check720$;
