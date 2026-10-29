-- r723 (F333). Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 13:39: on the Stock take, an X per item: "we physically looked at that car and it doesn't have a towbar".
-- X is a stock take note only (who and when); it does not change the board's work. Tick = done (board tick), X = seen,
-- not done. A car is "looked at" when every item is ticked or X'd.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard723$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r723: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r723: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r723: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 473 OR fault_id = 'F333' OR added_in = 'r723') THEN RAISE EXCEPTION 'r723: sort 473 or F333 is taken'; END IF;
  IF to_regclass('public.pdc_stock_take_x_723') IS NOT NULL THEN RAISE EXCEPTION 'r723: already applied'; END IF;
END $guard723$;

CREATE TABLE public.pdc_stock_take_x_723 (
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  line_identity text NOT NULL,
  x boolean NOT NULL,
  actor_email text,
  acted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (vehicle_id, line_identity)
);
ALTER TABLE public.pdc_stock_take_x_723 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_stock_take_x_723 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.set_pdc_stock_take_x_723(p_vehicle_id uuid, p_line_identity text, p_x boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, '')));
BEGIN
  IF v_role NOT IN ('operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'controller_required'); END IF;
  IF p_vehicle_id IS NULL OR p_x IS NULL OR coalesce(p_line_identity, '') !~* '^(source|manual):[0-9a-f-]{36}$' THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_line'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.vehicles WHERE id = p_vehicle_id AND deleted_at IS NULL) THEN RETURN jsonb_build_object('ok', false, 'error', 'invalid_line'); END IF;
  INSERT INTO public.pdc_stock_take_x_723 (vehicle_id, line_identity, x, actor_email, acted_at)
  VALUES (p_vehicle_id, p_line_identity, p_x, public.current_actor_email(), clock_timestamp())
  ON CONFLICT (vehicle_id, line_identity) DO UPDATE SET x = EXCLUDED.x, actor_email = EXCLUDED.actor_email, acted_at = EXCLUDED.acted_at
  WHERE public.pdc_stock_take_x_723.vehicle_id = EXCLUDED.vehicle_id AND public.pdc_stock_take_x_723.line_identity = EXCLUDED.line_identity;
  RETURN jsonb_build_object('ok', true, 'x', p_x);
END $fn$;
REVOKE ALL ON FUNCTION public.set_pdc_stock_take_x_723(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_stock_take_x_723(uuid, text, boolean) TO authenticated;

DO $edit723$
DECLARE v_old text; v_def text; s text;
  a1 text := $a$      LEFT JOIN LATERAL (SELECT u.display_name, u.full_name FROM public.pdc_user_roles u WHERE lower(u.email) = lower(c.actor_email) ORDER BY u.active DESC LIMIT 1) r ON true
    ), cars AS ($a$;
  b1 text := $b$      LEFT JOIN LATERAL (SELECT u.display_name, u.full_name FROM public.pdc_user_roles u WHERE lower(u.email) = lower(c.actor_email) ORDER BY u.active DESC LIMIT 1) r ON true
    ), xed AS ( -- r723 (F333): the stock take X (seen, not done)
      SELECT n.*, xx.x AS x_on, xx.acted_at AS x_at,
             coalesce(nullif(btrim(xu.full_name), ''), nullif(CASE WHEN xu.display_name LIKE '%@%' THEN '' ELSE btrim(xu.display_name) END, ''), split_part(xx.actor_email, '@', 1)) AS x_by
      FROM named n
      LEFT JOIN public.pdc_stock_take_x_723 xx ON xx.vehicle_id = n.id AND xx.line_identity = n.x->>'line_identity' AND xx.x
      LEFT JOIN LATERAL (SELECT u.display_name, u.full_name FROM public.pdc_user_roles u WHERE lower(u.email) = lower(xx.actor_email) ORDER BY u.active DESC LIMIT 1) xu ON true
    ), cars AS ($b$;
  a2 text := $a$'by', CASE WHEN n.panel_done IS NOT NULL THEN n.by_name END, 'at', n.acted_at)$a$;
  b2 text := $b$'by', CASE WHEN n.panel_done IS NOT NULL THEN n.by_name END, 'at', n.acted_at,
          'x', coalesce(n.x_on, false), 'x_by', CASE WHEN n.x_on THEN n.x_by END, 'x_at', CASE WHEN n.x_on THEN n.x_at END)$b$;
  a3 text := $a$      FROM named n GROUP BY n.id, n.stock_number, n.key_number, n.vehicle$a$;
  b3 text := $b$      FROM xed n GROUP BY n.id, n.stock_number, n.key_number, n.vehicle$b$;
  a4 text := $a$    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_missing_720), '') || '|' ||$a$;
  b4 text := $b$    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_missing_720), '') || '|' ||
    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_x_723), '') || '|' ||$b$;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.get_pdc_stock_take_720(text[])'::regprocedure;
  FOREACH s IN ARRAY ARRAY[a1, a2, a3] LOOP
    IF (length(v_old) - length(replace(v_old, s, ''))) / length(s) <> 1 THEN RAISE EXCEPTION 'r723: list anchor not found once: %', left(s, 60); END IF;
  END LOOP;
  v_def := regexp_replace(pg_get_functiondef('public.get_pdc_stock_take_720(text[])'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(replace(replace(v_old, a1, b1), a2, b2), a3, b3) || substring(v_def from '\$[a-zA-Z_]*\$$');
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.get_pdc_stock_take_rev_720()'::regprocedure;
  IF (length(v_old) - length(replace(v_old, a4, ''))) / length(a4) <> 1 THEN RAISE EXCEPTION 'r723: rev anchor not found once'; END IF;
  v_def := regexp_replace(pg_get_functiondef('public.get_pdc_stock_take_rev_720()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(v_old, a4, b4) || substring(v_def from '\$[a-zA-Z_]*\$$');
END $edit723$;

DO $check723$
DECLARE ok boolean; detail text; q text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('stock_take_x_723', 'F333', 'Stock take X (seen, not done) is controller only, staff-read only, and in the list and change marker.',
    $chk$
SELECT NOT has_function_privilege('anon', 'public.set_pdc_stock_take_x_723(uuid,text,boolean)', 'execute')
  AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.pdc_stock_take_x_723'::regclass)
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.get_pdc_stock_take_720(text[])')), 'pdc_stock_take_x_723') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.get_pdc_stock_take_rev_720()')), 'pdc_stock_take_x_723') > 0
 AS ok, 'stock take X in place' AS detail
$chk$, true, 473, 'r723');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_x_723') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r723: check red: %', detail; END IF;
  FOR q IN SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_720' LOOP
    EXECUTE q INTO ok, detail; IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r723: stock_take_720 red'; END IF;
  END LOOP;
END $check723$;
