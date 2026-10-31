-- r777 (F380, F381, F382). Staging cdsmnqxtyyoeoznmbidd only. Applied to staging as r763c, r777, r777b.
-- F380: the same file sent again was refused by the snapshot recorder ("a line of snapshot ... was already recorded with
--       different values") because board-derived identity columns had moved. revolution_upload_snapshot_763 now reuses a
--       complete snapshot for the same sha instead of re-recording it (see the r763 migration file for the function body).
-- F381: Craig 10:33 "for the ones leaving the board, can it put into catagories of why?" The dry run splits leaving into
--       Completing (no Navision record) and Staying, tagged (still on Navision, any dealer) via revolution_upload_navision_777.
-- F382: a refusal after begin left a 'loading' job that blocked the next upload for 30 minutes; the edge function now
--       abandons it (revolution_upload_abandon_777).
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

CREATE OR REPLACE FUNCTION public.revolution_upload_navision_777(p_stocks jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
SET statement_timeout TO '30s'
AS $function$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, '')));
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  IF jsonb_typeof(p_stocks) <> 'array' OR jsonb_array_length(p_stocks) > 2000 THEN RETURN jsonb_build_object('ok', false, 'error', 'bad_stocks'); END IF;
  RETURN jsonb_build_object('ok', true, 'on_navision', (
    SELECT coalesce(jsonb_agg(jsonb_build_object('stock', s.stock, 'dealer', s.dealer) ORDER BY s.stock), '[]'::jsonb)
    FROM (
      SELECT DISTINCT ON (x.stock) upper(btrim(x.stock)) stock, n.dealer_code dealer
      FROM jsonb_array_elements_text(p_stocks) x(stock)
      LEFT JOIN public.vehicles v ON upper(btrim(v.stock_number)) = upper(btrim(x.stock)) AND v.deleted_at IS NULL
      JOIN public.navision_backend_records n ON n.source_system = 'microsoft_navision' AND n.is_current AND n.record_status::text = 'current'
        AND (n.canonical_vehicle_id = v.id OR public.normalize_vehicle_stock_number(coalesce(n.normalized_data->>'batch', n.normalized_data->>'stock')) = public.normalize_vehicle_stock_number(x.stock))
      ORDER BY x.stock, n.updated_at DESC) s));
END $function$;
REVOKE ALL ON FUNCTION public.revolution_upload_navision_777(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revolution_upload_navision_777(jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.revolution_upload_abandon_777(p_upload uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
SET statement_timeout TO '30s'
AS $function$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); u pdc_import_620.web_uploads_728; v_n integer;
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  SELECT * INTO u FROM pdc_import_620.web_uploads_728 WHERE upload_id = p_upload AND auth_user_id = auth.uid();
  IF NOT FOUND OR u.job_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'upload_not_found'); END IF;
  UPDATE pdc_import_620.jobs SET status = 'failed', error = 'abandoned before rows were sent: ' || left(coalesce(p_reason, ''), 200), finished_at = clock_timestamp()
  WHERE job_id = u.job_id AND status = 'loading' AND coalesce(rows_loaded, 0) = 0;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'abandoned', v_n = 1);
END $function$;
REVOKE ALL ON FUNCTION public.revolution_upload_abandon_777(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revolution_upload_abandon_777(uuid, text) TO authenticated, service_role;
