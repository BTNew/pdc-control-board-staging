-- r724 (F334). Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 13:53: on the Stock take, a box to add the key number and stock number of a car that is out there but not
-- on the list. Shared list (who and when), with where the board thinks that stock is. "Sorted" clears it.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard724$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r724: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r724: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r724: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 474 OR fault_id = 'F334' OR added_in = 'r724') THEN RAISE EXCEPTION 'r724: sort 474 or F334 is taken'; END IF;
  IF to_regclass('public.pdc_stock_take_found_724') IS NOT NULL THEN RAISE EXCEPTION 'r724: already applied'; END IF;
END $guard724$;

CREATE TABLE public.pdc_stock_take_found_724 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key_number text,
  stock_number text,
  note text,
  actor_email text,
  added_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  sorted_at timestamptz,
  sorted_by text,
  CONSTRAINT stock_take_found_has_id CHECK (coalesce(btrim(key_number), '') <> '' OR coalesce(btrim(stock_number), '') <> ''),
  CONSTRAINT stock_take_found_sizes CHECK (length(coalesce(key_number, '')) <= 32 AND length(coalesce(stock_number, '')) <= 40 AND length(coalesce(note, '')) <= 300)
);
ALTER TABLE public.pdc_stock_take_found_724 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_stock_take_found_724 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.set_pdc_stock_take_found_724(p_key text, p_stock text, p_note text DEFAULT NULL, p_sorted_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); v_id uuid;
  k text := nullif(upper(regexp_replace(coalesce(p_key, ''), '\s+', '', 'g')), '');
  s text := nullif(upper(regexp_replace(coalesce(p_stock, ''), '\s+', '', 'g')), '');
BEGIN
  IF v_role NOT IN ('operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'controller_required'); END IF;
  IF p_sorted_id IS NOT NULL THEN
    UPDATE public.pdc_stock_take_found_724 SET sorted_at = clock_timestamp(), sorted_by = public.current_actor_email()
    WHERE id = p_sorted_id AND sorted_at IS NULL;
    RETURN jsonb_build_object('ok', true, 'sorted', p_sorted_id);
  END IF;
  IF k IS NULL AND s IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'key_or_stock_required'); END IF;
  IF length(coalesce(k, '')) > 32 OR length(coalesce(s, '')) > 40 OR length(coalesce(p_note, '')) > 300 THEN RETURN jsonb_build_object('ok', false, 'error', 'too_long'); END IF;
  INSERT INTO public.pdc_stock_take_found_724 (key_number, stock_number, note, actor_email)
  VALUES (k, s, nullif(btrim(coalesce(p_note, '')), ''), public.current_actor_email()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END $fn$;
REVOKE ALL ON FUNCTION public.set_pdc_stock_take_found_724(text, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_stock_take_found_724(text, text, text, uuid) TO authenticated;

-- The open "found" list, with where the board has that stock (or that key) now.
CREATE FUNCTION public.get_pdc_stock_take_found_724()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, '')));
BEGIN
  IF v_role NOT IN ('viewer', 'operator', 'administrator') THEN RETURN jsonb_build_object('ok', false, 'error', 'not_authorized'); END IF;
  RETURN jsonb_build_object('ok', true, 'found', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', f.id, 'k', f.key_number, 's', f.stock_number, 'note', f.note, 'at', f.added_at,
      'by', coalesce(nullif(btrim(u.full_name), ''), nullif(CASE WHEN u.display_name LIKE '%@%' THEN '' ELSE btrim(u.display_name) END, ''), split_part(f.actor_email, '@', 1)),
      'board', m.board) ORDER BY f.added_at DESC)
    FROM public.pdc_stock_take_found_724 f
    LEFT JOIN LATERAL (SELECT x.display_name, x.full_name FROM public.pdc_user_roles x WHERE lower(x.email) = lower(f.actor_email) ORDER BY x.active DESC LIMIT 1) u ON true
    LEFT JOIN LATERAL (
      SELECT jsonb_build_object('stock', v.stock_number, 'key', v.key_number,
        'where', coalesce(nullif(v.location_override, ''), nullif(v.current_location, ''), 'unknown'),
        'on_board', v.lifecycle_state = 'active' AND coalesce(v.visible_on_board, true), 'state', v.lifecycle_state::text) AS board
      FROM public.vehicles v
      WHERE v.deleted_at IS NULL AND ((f.stock_number IS NOT NULL AND upper(v.stock_number) = f.stock_number)
        OR (f.stock_number IS NULL AND f.key_number IS NOT NULL AND upper(coalesce(v.key_number, '')) = f.key_number AND v.lifecycle_state = 'active'))
      ORDER BY (v.lifecycle_state = 'active') DESC, v.updated_at DESC LIMIT 1) m ON true
    WHERE f.sorted_at IS NULL), '[]'::jsonb));
END $fn$;
REVOKE ALL ON FUNCTION public.get_pdc_stock_take_found_724() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_stock_take_found_724() TO authenticated;

-- The change marker also moves when someone adds or sorts a found car.
DO $edit724$
DECLARE v_old text; v_def text;
  a4 text := $a$    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_x_723), '') || '|' ||$a$;
  b4 text := $b$    coalesce((SELECT max(acted_at)::text FROM public.pdc_stock_take_x_723), '') || '|' ||
    coalesce((SELECT max(greatest(added_at, coalesce(sorted_at, added_at)))::text FROM public.pdc_stock_take_found_724), '') || '|' ||$b$;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.get_pdc_stock_take_rev_720()'::regprocedure;
  IF (length(v_old) - length(replace(v_old, a4, ''))) / length(a4) <> 1 THEN RAISE EXCEPTION 'r724: rev anchor not found once'; END IF;
  v_def := regexp_replace(pg_get_functiondef('public.get_pdc_stock_take_rev_720()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(v_old, a4, b4) || substring(v_def from '\$[a-zA-Z_]*\$$');
END $edit724$;

DO $check724$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('stock_take_found_724', 'F334', 'Stock take "found, not on the list": controller writes, staff reads, no anon, RLS on, in the change marker.',
    $chk$
SELECT NOT has_function_privilege('anon', 'public.set_pdc_stock_take_found_724(text,text,text,uuid)', 'execute')
  AND NOT has_function_privilege('anon', 'public.get_pdc_stock_take_found_724()', 'execute')
  AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.pdc_stock_take_found_724'::regclass)
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.get_pdc_stock_take_rev_720()')), 'pdc_stock_take_found_724') > 0
 AS ok, 'stock take found list in place' AS detail
$chk$, true, 474, 'r724');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'stock_take_found_724') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r724: check red: %', detail; END IF;
END $check724$;
