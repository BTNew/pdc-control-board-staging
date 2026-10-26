-- Revert only this exact reviewed endpoint; never drop a later replacement.
-- The client falls back only on PostgREST PGRST202. Retain the separate cache
-- access guard when reverting performance changes.
-- Body fingerprint is computed after normalising CRLF to LF, preserving all
-- other source bytes. This permits equivalent Windows/Unix deployment files.
DO $guard$
DECLARE
  v_proc pg_catalog.pg_proc%ROWTYPE;
  v_legacy_owner oid;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'conditional board transport rollback: staging only';
  END IF;
  SELECT * INTO v_proc FROM pg_catalog.pg_proc
  WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)');
  IF NOT FOUND THEN RETURN; END IF; -- idempotent once the endpoint is absent
  IF md5(replace(v_proc.prosrc,chr(13)||chr(10),chr(10))) IS DISTINCT FROM '5b50acbf467ad4f38d3a8f9a062cc12e' THEN
    RAISE EXCEPTION USING ERRCODE='PDC01',MESSAGE='conditional board transport rollback: endpoint body changed; review the newer release before removing it';
  END IF;
  SELECT proowner INTO v_legacy_owner FROM pg_catalog.pg_proc
  WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()');
  IF v_proc.proowner IS DISTINCT FROM v_legacy_owner
     OR NOT v_proc.prosecdef OR v_proc.provolatile <> 'v'
     OR v_proc.prorettype <> 'jsonb'::regtype
     OR v_proc.prolang <> (SELECT oid FROM pg_catalog.pg_language WHERE lanname='plpgsql')
     OR v_proc.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public','statement_timeout=30s','lock_timeout=8s']::text[]
     OR NOT has_function_privilege('authenticated',v_proc.oid,'EXECUTE')
     OR NOT has_function_privilege('service_role',v_proc.oid,'EXECUTE')
     OR EXISTS (
       SELECT 1 FROM pg_catalog.aclexplode(coalesce(v_proc.proacl,pg_catalog.acldefault('f',v_proc.proowner))) a
       WHERE a.grantor <> v_proc.proowner OR a.privilege_type <> 'EXECUTE'
         OR a.grantee NOT IN (v_proc.proowner,'authenticated'::regrole::oid,'service_role'::regrole::oid)
     ) THEN
    RAISE EXCEPTION USING ERRCODE='PDC02',MESSAGE='conditional board transport rollback: endpoint security metadata changed; review before removing it';
  END IF;
  -- Guard and removal are one statement: a client configured to continue after
  -- SQL errors cannot accidentally execute an unguarded DROP afterwards.
  EXECUTE 'DROP FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(text)';
  PERFORM pg_catalog.pg_notify('pgrst','reload schema');
END
$guard$;
