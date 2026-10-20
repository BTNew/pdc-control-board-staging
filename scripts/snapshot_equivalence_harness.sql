-- Snapshot equivalence harness (r410, stage 0 of SNAPSHOT_PLAN.md). Paste after the release-test window prelude
-- (scripts/rolled_back_test_window.sql) inside the rolled-back test. Nothing here writes outside temp tables.
-- Usage: SELECT pg_temp.snap('<run label>','location'|'board');  ...change functions...  SELECT pg_temp.snap(...);
--        SELECT pg_temp.compare('<run a>','<run b>');  -> overall, per-department and per-vehicle md5s; any
--        difference names the vehicle and the top-level keys that differ.
-- The login is set by the caller (request.jwt.claims built from auth.users by id; no email in files).
CREATE TEMP TABLE t_res(step serial, k text, v jsonb) ON COMMIT DROP;
CREATE TEMP TABLE t_veh(run text, ord bigint, id text, depts text[], m text, v jsonb) ON COMMIT DROP;
CREATE FUNCTION pg_temp.snap(p_run text, p_which text) RETURNS jsonb LANGUAGE plpgsql AS $h$
DECLARE t0 timestamptz; s jsonb; ms integer; r jsonb;
BEGIN
  PERFORM pg_temp.deadline();
  t0 := clock_timestamp();
  IF p_which = 'board' THEN s := public.get_pdc_email_vehicle_board_snapshot();
  ELSIF p_which = 'location' THEN s := public.get_pdc_email_vehicle_location_snapshot();
  ELSE RAISE EXCEPTION 'harness: unknown snapshot %', p_which; END IF;
  ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  INSERT INTO t_veh(run, ord, id, depts, m, v)
  SELECT p_run, e.ord, e.x->>'id',
         coalesce((SELECT array_agg(d ORDER BY d) FROM jsonb_array_elements_text(
           CASE WHEN jsonb_typeof(e.x->'department_codes') = 'array' THEN e.x->'department_codes' ELSE '[]'::jsonb END) d), '{}'),
         md5(e.x::text), e.x
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(s#>'{data,vehicles}') = 'array' THEN s#>'{data,vehicles}' ELSE '[]'::jsonb END)
       WITH ORDINALITY e(x, ord);
  r := jsonb_build_object('which', p_which, 'ms', ms, 'md5', md5(s::text), 'bytes', octet_length(s::text),
         'ok', s->'ok', 'n', jsonb_array_length(coalesce(s#>'{data,vehicles}', '[]'::jsonb)),
         'envelope_md5', md5((s #- '{data,vehicles}')::text),
         'depts', (SELECT jsonb_object_agg(dept, jsonb_build_object('n', n, 'md5', dm)) FROM (
             SELECT coalesce(d, 'none') dept, count(*) n, md5(string_agg(t.m, ',' ORDER BY t.ord)) dm
             FROM t_veh t LEFT JOIN LATERAL unnest(nullif(t.depts, '{}')) d ON true
             WHERE t.run = p_run GROUP BY 1) z),
         'vehicles_md5', (SELECT md5(string_agg(id || ':' || m, ',' ORDER BY id)) FROM t_veh WHERE run = p_run),
         'order_md5', (SELECT md5(string_agg(id, ',' ORDER BY ord)) FROM t_veh WHERE run = p_run));
  INSERT INTO t_res(k, v) VALUES (p_run, r);
  RETURN r;
END $h$;
CREATE FUNCTION pg_temp.compare(a text, b text) RETURNS jsonb LANGUAGE plpgsql AS $h$
DECLARE ra jsonb; rb jsonb; diff jsonb; nd integer;
BEGIN
  SELECT v INTO ra FROM t_res WHERE k = a; SELECT v INTO rb FROM t_res WHERE k = b;
  SELECT count(*), coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'in_a', x.m IS NOT NULL, 'in_b', y.m IS NOT NULL,
           'ord_a', x.ord, 'ord_b', y.ord,
           'keys', (SELECT jsonb_agg(k ORDER BY k) FROM (
              SELECT k FROM jsonb_object_keys(coalesce(x.v, '{}'::jsonb)) k
              UNION SELECT k FROM jsonb_object_keys(coalesce(y.v, '{}'::jsonb)) k) kk
              WHERE x.v->kk.k IS DISTINCT FROM y.v->kk.k))) FILTER (WHERE rn <= 8), '[]'::jsonb)
    INTO nd, diff
  FROM (SELECT coalesce(x.id, y.id) id, x.m xm, y.m ym, row_number() OVER (ORDER BY coalesce(x.id, y.id)) rn, x.id xid, y.id yid
        FROM (SELECT * FROM t_veh WHERE run = a) x FULL JOIN (SELECT * FROM t_veh WHERE run = b) y ON x.id = y.id
        WHERE x.m IS DISTINCT FROM y.m OR x.ord IS DISTINCT FROM y.ord) q
  LEFT JOIN t_veh x ON x.run = a AND x.id = q.xid
  LEFT JOIN t_veh y ON y.run = b AND y.id = q.yid;
  RETURN jsonb_build_object('a', a, 'b', b,
    'identical', ra->>'md5' = rb->>'md5' AND ra->'depts' = rb->'depts' AND ra->>'vehicles_md5' = rb->>'vehicles_md5'
                 AND ra->>'order_md5' = rb->>'order_md5' AND ra->>'envelope_md5' = rb->>'envelope_md5' AND nd = 0,
    'md5_equal', ra->>'md5' = rb->>'md5', 'envelope_equal', ra->>'envelope_md5' = rb->>'envelope_md5',
    'depts_equal', ra->'depts' = rb->'depts', 'vehicles_equal', ra->>'vehicles_md5' = rb->>'vehicles_md5',
    'order_equal', ra->>'order_md5' = rb->>'order_md5', 'vehicles_differing', nd, 'first_differences', diff);
END $h$;
