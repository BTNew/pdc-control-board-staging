-- r768 (F430) / sort 560. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 06:09: "add the Navision Uploads to both Broome and Karratha. Broome can upload the Broome navision files,
-- Karratha can upload the Pilbara one. This way its done more often when salespeople are logged in."
-- One RPC for the Sales site. The server picks the upload from the caller's own Sales branch (pdc_sales_private.context):
-- Broome Toyota 37047 -> Broome Upload, Karratha Toyota 14450 -> Pilbara Upload. Nobody can choose the other one.
-- It runs the existing PMB Navision Uploads functions unchanged (preview_navision_upload_profile / apply_navision_upload_profile),
-- so every existing guard still applies: partial or tiny files, wrong dealer, stale preview, duplicate identities.
-- A salesperson is not an importer, so their upload runs as the system actor (first approved administrator, as the cron
-- sweeps do) and the real person is written to pdc_sales_private.navision_uploads_768. Administrators and importers run as themselves.
-- A blocked preview (e.g. a partial export) cannot be applied here; it still needs an administrator on PMB Navision Uploads.
-- Rollback: supabase/rollbacks/20261031070000_r768_sales_navision_uploads.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard768$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r768: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 560 OR fault_id = 'F430' OR added_in = 'r768') THEN RAISE EXCEPTION 'r768: sort 560 or F430 is taken'; END IF;
  IF to_regprocedure('public.preview_navision_upload_profile(text,jsonb,text,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint)') IS NULL
     OR to_regprocedure('pdc_sales_private.context()') IS NULL THEN RAISE EXCEPTION 'r768: upload profile functions missing'; END IF;
END $guard768$;

CREATE TABLE pdc_sales_private.navision_uploads_768 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor_id uuid NOT NULL,
  actor_email text NOT NULL,
  sales_role text NOT NULL,
  salesperson_code text,
  dealer_code text NOT NULL,
  profile text NOT NULL CHECK (profile IN ('broome', 'pilbara')),
  mode text NOT NULL CHECK (mode IN ('preview', 'apply')),
  ran_as text NOT NULL CHECK (ran_as IN ('self', 'system')),
  source_name text,
  row_count integer NOT NULL,
  ok boolean NOT NULL,
  code text,
  result_revision bigint
);
ALTER TABLE pdc_sales_private.navision_uploads_768 ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.navision_uploads_768 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_sales_private.navision_uploads_768 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.sales_navision_upload_768(
  p_apply boolean, p_rows jsonb, p_source_name text,
  p_idempotency_key text DEFAULT NULL, p_source_hash text DEFAULT NULL, p_preview_hash text DEFAULT NULL,
  p_expected_revision bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public' SET statement_timeout TO '130s'
AS $fn$
DECLARE
  ctx jsonb; v_dealer text; v_profile text; v_uid uuid := auth.uid(); v_email text := lower(coalesce(auth.jwt()->>'email', ''));
  v_claims text := current_setting('request.jwt.claims', true); v_self boolean; v_sys public.pdc_user_roles;
  v_result jsonb; v_code text; v_ok boolean; v_name text := left(coalesce(nullif(btrim(p_source_name), ''), 'Sales upload'), 255);
BEGIN
  ctx := pdc_sales_private.context();  -- raises unless an approved Sales account (salesperson, linked controller or administrator)
  v_dealer := ctx->>'dealer_code';
  v_profile := CASE v_dealer WHEN '37047' THEN 'broome' WHEN '14450' THEN 'pilbara' END;
  IF v_profile IS NULL THEN RETURN public.navision_backend_response(false, 'branch_upload_not_available'); END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN RETURN public.navision_backend_response(false, 'invalid_input'); END IF;
  IF p_apply AND (nullif(btrim(p_idempotency_key), '') IS NULL OR length(p_idempotency_key) > 150) THEN
    RETURN public.navision_backend_response(false, 'invalid_input'); END IF;
  v_self := EXISTS (SELECT 1 FROM public.pdc_user_roles u WHERE u.auth_user_id = v_uid AND u.email = v_email AND u.active
    AND u.account_status = 'approved' AND u.role::text IN ('importer', 'administrator'));
  IF NOT v_self THEN
    SELECT * INTO v_sys FROM public.pdc_user_roles u WHERE u.active AND u.account_status = 'approved' AND u.role::text = 'administrator'
      AND u.auth_user_id IS NOT NULL ORDER BY u.created_at, u.id LIMIT 1;
    IF v_sys.id IS NULL THEN RETURN public.navision_backend_response(false, 'system_actor_missing'); END IF;
    PERFORM set_config('request.jwt.claims', (coalesce(nullif(v_claims, '')::jsonb, '{}'::jsonb)
      || jsonb_build_object('sub', v_sys.auth_user_id, 'email', v_sys.email, 'role', 'authenticated'))::text, true);
  END IF;
  BEGIN
    IF p_apply THEN
      v_result := public.apply_navision_upload_profile(v_profile, 'sales768:' || v_uid::text || ':' || p_idempotency_key, p_rows,
        v_name, NULL, p_source_hash, p_preview_hash, p_expected_revision);
    ELSE
      v_result := public.preview_navision_upload_profile(v_profile, p_rows, v_name, NULL);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_result := public.navision_backend_response(false, 'upload_failed', jsonb_build_object('message', left(SQLERRM, 300), 'sqlstate', SQLSTATE));
  END;
  PERFORM set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  v_ok := v_result->>'ok' = 'true';
  v_code := coalesce(v_result->>'code', v_result->>'error');
  INSERT INTO pdc_sales_private.navision_uploads_768(actor_id, actor_email, sales_role, salesperson_code, dealer_code, profile, mode,
    ran_as, source_name, row_count, ok, code, result_revision)
  VALUES (v_uid, v_email, coalesce(ctx->>'account_role', ctx->>'role'), ctx->>'salesperson_code', v_dealer, v_profile,
    CASE WHEN p_apply THEN 'apply' ELSE 'preview' END, CASE WHEN v_self THEN 'self' ELSE 'system' END, v_name,
    jsonb_array_length(p_rows), v_ok, v_code, nullif(v_result#>>'{data,result_revision}', '')::bigint);
  RETURN jsonb_build_object('profile', v_profile, 'dealer_code', v_dealer, 'branch', ctx->>'division', 'result', v_result);
END $fn$;
REVOKE ALL ON FUNCTION public.sales_navision_upload_768(boolean, jsonb, text, text, text, text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sales_navision_upload_768(boolean, jsonb, text, text, text, text, bigint) TO authenticated;

-- Last Sales upload per branch, for the page header ("Last upload 30 Oct 14:55 by BG").
CREATE FUNCTION public.sales_navision_last_upload_768()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE ctx jsonb := pdc_sales_private.context(); v_dealer text := ctx->>'dealer_code'; v jsonb;
BEGIN
  SELECT jsonb_build_object('applied_at', max((to_jsonb(b)->>'applied_at')::timestamptz)) INTO v
    FROM public.navision_import_batches b
   WHERE to_jsonb(b)->>'dealer_code' = v_dealer AND (to_jsonb(b)->>'applied_at') IS NOT NULL;
  RETURN coalesce(v, '{}'::jsonb) || jsonb_build_object('dealer_code', v_dealer, 'branch', ctx->>'division',
    'profile', CASE v_dealer WHEN '37047' THEN 'broome' WHEN '14450' THEN 'pilbara' END);
END $fn$;
REVOKE ALL ON FUNCTION public.sales_navision_last_upload_768() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sales_navision_last_upload_768() TO authenticated;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('sales_navision_upload_768', 'F430',
  'Sales Navision Uploads (r768): the Sales RPC exists, anon cannot run it, it calls the unchanged PMB profile functions and its log table is private.',
  $chk$
SELECT to_regprocedure('public.sales_navision_upload_768(boolean,jsonb,text,text,text,text,bigint)') IS NOT NULL
   AND NOT has_function_privilege('anon', 'public.sales_navision_upload_768(boolean,jsonb,text,text,text,text,bigint)', 'EXECUTE')
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.sales_navision_upload_768(boolean,jsonb,text,text,text,text,bigint)')), 'public.apply_navision_upload_profile(') > 0
   AND NOT has_table_privilege('authenticated', 'pdc_sales_private.navision_uploads_768', 'SELECT')
 AS ok, 'Sales Navision upload RPC present and locked down' AS detail
$chk$, true, 560, 'r768');
