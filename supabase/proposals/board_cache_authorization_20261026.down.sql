-- SECURITY WARNING: rollback restores the original cache-hit authorization gap.
-- Prefer keeping this isolated guard when reverting unrelated performance changes.
-- Staging cdsmnqxtyyoeoznmbidd only. No business data, cache rows, grants or pins are edited.
-- Apply transactionally using the migration mechanism. This file is a reviewed proposal.
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '10s';
DO $board_auth$
DECLARE
  v_oid oid := to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()');
  v_before pg_proc%ROWTYPE;
  v_after pg_proc%ROWTYPE;
  v_body text;
  v_definition text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'board_cache_authorization: staging only';
  END IF;
  SELECT * INTO STRICT v_before FROM pg_proc WHERE oid=v_oid;
  IF md5(v_before.prosrc) IS DISTINCT FROM 'ae706516b88574c1162e2c5889e4b4a9' THEN
    RAISE EXCEPTION 'board_cache_authorization: down source changed; inspect before proceeding';
  END IF;
  IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_board_snapshot()') THEN
    RAISE EXCEPTION 'board_cache_authorization: function is newly pinned; review pin rather than bypassing it';
  END IF;
  IF NOT v_before.prosecdef OR v_before.provolatile <> 'v'
     OR has_function_privilege('anon',v_oid,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'board_cache_authorization: unexpected function security metadata';
  END IF;
  v_body := replace(v_before.prosrc, $old$BEGIN
  -- performance-20261026: authorize every caller before a shared cache hit.
  -- Keep the same allowed roles as get_pdc_email_vehicle_location_snapshot_pre168.
  IF coalesce(public.current_pdc_user_role()::text IN ('viewer','operator','importer','administrator'), false) IS NOT TRUE THEN
    RETURN public.navision_backend_response(false, 'unauthorized');
  END IF;
$old$, $new$BEGIN
$new$);
  IF md5(v_body) IS DISTINCT FROM 'd30bb1f22c63097ae7983f2adbcb2a94' THEN
    RAISE EXCEPTION 'board_cache_authorization: transformed body mismatch';
  END IF;
  v_definition := pg_get_functiondef(v_oid);
  EXECUTE replace(v_definition,v_before.prosrc,v_body);
  SELECT * INTO STRICT v_after FROM pg_proc WHERE oid=v_oid;
  IF md5(v_after.prosrc) IS DISTINCT FROM 'd30bb1f22c63097ae7983f2adbcb2a94'
     OR v_after.proacl IS DISTINCT FROM v_before.proacl
     OR v_after.proowner IS DISTINCT FROM v_before.proowner
     OR v_after.proconfig IS DISTINCT FROM v_before.proconfig
     OR v_after.prosecdef IS DISTINCT FROM v_before.prosecdef
     OR v_after.provolatile IS DISTINCT FROM v_before.provolatile THEN
    RAISE EXCEPTION 'board_cache_authorization: definition or metadata verification failed';
  END IF;
END
$board_auth$;
