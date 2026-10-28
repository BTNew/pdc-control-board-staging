-- r676 (F285) / sort 424. Staging cdsmnqxtyyoeoznmbidd only.
-- Every board change re-sent the whole Vehicle Locations board (about 16 MB of JSON) to every open screen.
-- New opt-in overload of the conditional reader: when the browser holds a recent snapshot it gets only the
-- vehicles that changed plus the full vehicle order, and rebuilds the same board. Old browsers keep calling
-- the one-argument function, which is unchanged. Tokens are content hashes, so an identical rebuild is not_modified.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard676$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r676: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r676: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r676: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 424 OR fault_id = 'F285' OR added_in = 'r676' OR check_name = 'board_delta_676') THEN RAISE EXCEPTION 'r676: sort 424 or F285 is taken'; END IF;
  IF to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'r676: already applied'; END IF;
END $guard676$;

CREATE TABLE pdc_ops.vehicle_board_snapshot_history_676 (
  token text PRIMARY KEY,
  snapshot jsonb NOT NULL,
  stored_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON pdc_ops.vehicle_board_snapshot_history_676 FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(p_snapshot_token text, p_accept_delta boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_base jsonb; v_token text; v_prev jsonb; v_changed jsonb; v_ids jsonb;
BEGIN
  -- Recheck current staff access on every request, including the not-modified path.
  IF coalesce(public.current_pdc_user_role()::text IN ('viewer','operator','importer','administrator'), false) IS NOT TRUE THEN
    RETURN public.navision_backend_response(false, 'unauthorized');
  END IF;
  -- The original reader owns caching, rebuild locking and freshness.
  v_base := public.get_pdc_email_vehicle_board_snapshot();
  IF NOT coalesce((v_base->>'ok')::boolean, false) OR jsonb_typeof(v_base#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN
    RETURN v_base;
  END IF;
  v_token := 'h676:' || jsonb_hash_extended(v_base, 676)::text;
  IF p_snapshot_token IS NOT NULL AND p_snapshot_token = v_token THEN
    RETURN jsonb_build_object('ok', true, 'code', 'not_modified', 'not_modified', true, 'snapshot_token', v_token);
  END IF;
  IF p_accept_delta IS TRUE AND p_snapshot_token LIKE 'h676:%' THEN
    SELECT h.snapshot INTO v_prev FROM pdc_ops.vehicle_board_snapshot_history_676 h WHERE h.token = p_snapshot_token;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pdc_ops.vehicle_board_snapshot_history_676 h WHERE h.token = v_token) THEN
    INSERT INTO pdc_ops.vehicle_board_snapshot_history_676(token, snapshot) VALUES (v_token, v_base) ON CONFLICT (token) DO NOTHING;
    DELETE FROM pdc_ops.vehicle_board_snapshot_history_676 h
    WHERE h.token NOT IN (SELECT k.token FROM pdc_ops.vehicle_board_snapshot_history_676 k ORDER BY k.stored_at DESC LIMIT 6);
  END IF;
  IF v_prev IS NULL OR jsonb_typeof(v_prev#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN
    RETURN v_base || jsonb_build_object('snapshot_token', v_token);
  END IF;
  SELECT coalesce(jsonb_agg(c.e ORDER BY c.ord) FILTER (WHERE p.e IS NULL OR p.e IS DISTINCT FROM c.e), '[]'::jsonb),
         coalesce(jsonb_agg(c.e->'id' ORDER BY c.ord), '[]'::jsonb)
  INTO v_changed, v_ids
  FROM jsonb_array_elements(v_base#>'{data,vehicles}') WITH ORDINALITY AS c(e, ord)
  LEFT JOIN jsonb_array_elements(v_prev#>'{data,vehicles}') AS p(e) ON p.e->>'id' = c.e->>'id';
  RETURN jsonb_build_object('ok', true, 'code', v_base->'code', 'delta', true, 'snapshot_token', v_token, 'base_token', p_snapshot_token,
    'data', (v_base->'data') - 'vehicles', 'vehicle_ids', v_ids, 'changed', v_changed);
END $fn$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(text, boolean) TO authenticated;

-- r674 file now carries a WHERE on its ON CONFLICT update (safeupdate lint); make the live function match. Same behaviour.
DO $sync674$
DECLARE v_old text; v_def text; c_old text := E'closed_at = NULL, closure_reason = NULL;';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r676: r674 anchor not found once'; END IF;
  v_def := regexp_replace(pg_get_functiondef('pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(v_old, c_old, E'closed_at = NULL, closure_reason = NULL\n        WHERE pdc_new_vehicle_reviews.vehicle_id = excluded.vehicle_id;')
    || substring(v_def from '\$[a-zA-Z_]*\$$');
END $sync674$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_import_620 FROM PUBLIC, anon, authenticated, service_role;

DO $check676$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('board_delta_676', 'F285',
    'Board delta reader exists for authenticated staff only, keeps a small history, and the one-argument reader is untouched.',
    $chk676$
SELECT to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)') IS NOT NULL
  AND to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)') IS NOT NULL
  AND has_function_privilege('authenticated', 'public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.get_pdc_email_vehicle_board_snapshot_conditional(text,boolean)', 'EXECUTE')
  AND (SELECT count(*) FROM pdc_ops.vehicle_board_snapshot_history_676) <= 7
 AS ok, 'board delta reader in place' AS detail
$chk676$, true, 424, 'r676');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'board_delta_676') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r676: check red: %', detail; END IF;
END $check676$;
