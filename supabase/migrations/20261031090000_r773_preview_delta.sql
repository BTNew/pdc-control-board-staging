-- r773 (F375) / sort 488. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 2026 08:38: "i uploaded the same file we did before and showing me this, shouldnt it only show me the changes?"
-- The website dry run compared the file with the board snapshot only: every car already on the board counted as updated and
-- every car imported but still waiting on the New Vehicles page counted as new. The server already knows the real delta
-- (r771 content hashes against the last OK apply). Two read-only RPCs let the dry run use it:
--   revolution_upload_delta_773(rows)      -> {stock: [content hashes]} for the prepared rows (chunked by the edge function)
--   revolution_upload_delta_compare_773(h) -> {unchanged, changed, held_before (in an earlier apply, never applied OK), first_time} per stock
-- Administrator only. Nothing is written.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

CREATE OR REPLACE FUNCTION public.revolution_upload_delta_773(p_rows jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
SET statement_timeout TO '60s'
AS $function$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, '')));
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  IF jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 5000 THEN RETURN jsonb_build_object('ok', false, 'error', 'bad_rows'); END IF;
  RETURN jsonb_build_object('ok', true, 'hashes', (
    SELECT coalesce(jsonb_object_agg(s.stock, s.hashes), '{}'::jsonb)
    FROM (SELECT upper(btrim(r->>'stock_number')) stock, jsonb_agg(pdc_import_620.row_content_hash_771(r)) hashes
          FROM jsonb_array_elements(p_rows) r WHERE coalesce(btrim(r->>'stock_number'), '') <> '' GROUP BY 1) s));
END $function$;

CREATE OR REPLACE FUNCTION public.revolution_upload_delta_compare_773(p_hashes jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
SET statement_timeout TO '60s'
AS $function$
DECLARE v_role text := lower(btrim(coalesce(public.current_pdc_user_role()::text, ''))); v_out jsonb;
BEGIN
  IF v_role <> 'administrator' THEN RETURN jsonb_build_object('ok', false, 'error', 'administrator_required'); END IF;
  IF jsonb_typeof(p_hashes) <> 'object' THEN RETURN jsonb_build_object('ok', false, 'error', 'bad_hashes'); END IF;
  WITH cur AS (
    SELECT upper(btrim(e.key)) stock, (SELECT array_agg(x ORDER BY x) FROM jsonb_array_elements_text(e.value) x) hashes FROM jsonb_each(p_hashes) e
  ), prior AS (
    SELECT DISTINCT ON (c.stock) c.stock, j.job_id, r.part
    FROM cur c
    JOIN pdc_import_620.job_rows r ON upper(btrim(r.stock_number)) = c.stock AND r.held_reason IS NULL
    JOIN pdc_import_620.jobs j ON j.job_id = r.job_id AND j.mode = 'apply' AND j.status = 'done' AND j.report = 'service_whole'
      AND (j.parts->r.part->'apply'->>'ok') = 'true' AND coalesce(j.parts->r.part->'apply'->>'skipped', '') = ''
    ORDER BY c.stock, j.created_at DESC
  ), prev AS (
    SELECT p.stock, array_agg(pdc_import_620.row_content_hash_771(r.row) ORDER BY pdc_import_620.row_content_hash_771(r.row)) hashes
    FROM prior p JOIN pdc_import_620.job_rows r ON r.job_id = p.job_id AND r.part = p.part AND upper(btrim(r.stock_number)) = p.stock AND r.held_reason IS NULL
    GROUP BY p.stock
  )
  , seen AS (
    -- r773b: stocks that were in an earlier apply but never applied OK (held every time)
    SELECT DISTINCT upper(btrim(r.stock_number)) stock FROM pdc_import_620.job_rows r JOIN pdc_import_620.jobs j ON j.job_id = r.job_id
    WHERE j.mode = 'apply' AND j.report = 'service_whole' AND upper(btrim(r.stock_number)) IN (SELECT stock FROM cur)
  )
  SELECT jsonb_build_object(
    'unchanged', coalesce(jsonb_agg(c.stock ORDER BY c.stock) FILTER (WHERE pv.hashes = c.hashes), '[]'::jsonb),
    'changed', coalesce(jsonb_agg(c.stock ORDER BY c.stock) FILTER (WHERE pv.hashes IS NOT NULL AND pv.hashes <> c.hashes), '[]'::jsonb),
    'held_before', coalesce(jsonb_agg(c.stock ORDER BY c.stock) FILTER (WHERE pv.hashes IS NULL AND sn.stock IS NOT NULL), '[]'::jsonb),
    'first_time', coalesce(jsonb_agg(c.stock ORDER BY c.stock) FILTER (WHERE pv.hashes IS NULL AND sn.stock IS NULL), '[]'::jsonb))
    INTO v_out
  FROM cur c LEFT JOIN prev pv ON pv.stock = c.stock LEFT JOIN seen sn ON sn.stock = c.stock;
  RETURN jsonb_build_object('ok', true) || coalesce(v_out, '{}'::jsonb);
END $function$;

REVOKE ALL ON FUNCTION public.revolution_upload_delta_773(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revolution_upload_delta_compare_773(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revolution_upload_delta_773(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revolution_upload_delta_compare_773(jsonb) TO authenticated, service_role;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('preview_delta_773', 'F375',
  'Upload (r773): the dry run can ask the server which stocks are unchanged since the last OK apply (delta RPCs exist, administrator only, read-only, same hash as r771).',
  $chk$
SELECT to_regprocedure('public.revolution_upload_delta_773(jsonb)') IS NOT NULL
   AND to_regprocedure('public.revolution_upload_delta_compare_773(jsonb)') IS NOT NULL
   AND (SELECT provolatile FROM pg_proc WHERE oid = to_regprocedure('public.revolution_upload_delta_compare_773(jsonb)')) = 's'
   AND NOT has_function_privilege('anon', 'public.revolution_upload_delta_773(jsonb)', 'EXECUTE')
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.revolution_upload_delta_773(jsonb)')), 'row_content_hash_771') > 0
 AS ok, 'preview delta uses the r771 content hash' AS detail
$chk$, true, 488, 'r773');
