-- Additive conditional transport for the existing board snapshot. No business data is changed.
-- Only the working staging project is authorised. Apply the r545 access guard first.
-- Rollback: tools/performance/board-snapshot-conditional.down.sql
SET LOCAL lock_timeout = '2s';
DO $guard$
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'conditional board transport: staging only';
  END IF;
  IF to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'conditional board transport: endpoint already exists';
  END IF;
  IF to_regclass('pdc_ops.vehicle_board_snapshot_cache_545') IS NULL
     OR to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()') IS NULL THEN
    RAISE EXCEPTION 'conditional board transport: r545 cache required';
  END IF;
END
$guard$;

CREATE FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(p_snapshot_token text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
SET statement_timeout TO '30s'
SET lock_timeout TO '8s'
AS $function$
DECLARE
  v_role text;
  v_revision bigint;
  v_base jsonb;
  v_token text;
BEGIN
  -- Recheck current staff access on every request, including the not-modified path.
  v_role := public.current_pdc_user_role()::text;
  IF v_role IS NULL OR v_role NOT IN ('viewer','operator','importer','administrator') THEN
    RETURN public.navision_backend_response(false, 'unauthorized');
  END IF;
  SELECT coalesce(r.revision, 0) INTO v_revision
  FROM public.pdc_email_vehicle_revision r WHERE r.singleton;
  v_revision := coalesce(v_revision, 0);
  -- A matching request reads only small metadata; it never fetches/detoasts the
  -- large cached snapshot merely to decide that the browser already has it.
  SELECT c.email_revision::text || ':' || extract(epoch FROM c.computed_at)::text
  INTO v_token
  FROM pdc_ops.vehicle_board_snapshot_cache_545 c
  WHERE c.singleton AND c.email_revision = v_revision
    AND c.computed_at > clock_timestamp() - interval '15 seconds';
  IF v_token IS NOT NULL THEN
    IF p_snapshot_token IS NOT NULL AND p_snapshot_token = v_token THEN
      RETURN jsonb_build_object('ok',true,'code','not_modified','not_modified',true,'snapshot_token',v_token);
    END IF;
    SELECT c.snapshot INTO v_base
    FROM pdc_ops.vehicle_board_snapshot_cache_545 c
    WHERE c.singleton AND c.email_revision = v_revision
      AND c.email_revision::text || ':' || extract(epoch FROM c.computed_at)::text = v_token
      AND c.computed_at > clock_timestamp() - interval '15 seconds';
    IF v_base IS NOT NULL THEN
      RETURN v_base || jsonb_build_object('snapshot_token',v_token);
    END IF;
  END IF;
  -- The original reader owns rebuild locking and freshness. Preserve all fields,
  -- order, error codes, permissions, original hours and scheduling behaviour.
  v_base := public.get_pdc_email_vehicle_board_snapshot();
  IF NOT coalesce((v_base->>'ok')::boolean,false)
     OR jsonb_typeof(v_base#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN
    RETURN v_base;
  END IF;
  -- Another caller may have rebuilt between these statements. Issue a token
  -- only for a cache entry whose COMPLETE payload equals this response.
  -- A nonmatching/missing entry yields a full response without a reusable token.
  SELECT c.email_revision::text || ':' || extract(epoch FROM c.computed_at)::text
  INTO v_token
  FROM pdc_ops.vehicle_board_snapshot_cache_545 c
  WHERE c.singleton AND c.snapshot = v_base
    AND c.computed_at > clock_timestamp() - interval '15 seconds';
  RETURN v_base || jsonb_build_object('snapshot_token',v_token);
END
$function$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(text) TO authenticated, service_role;
COMMENT ON FUNCTION public.get_pdc_email_vehicle_board_snapshot_conditional(text) IS
 'Lossless conditional board read. Role checked on every request. Client reuse requires exact revision and cache generation within existing 15-second lifetime. No customer/job mutation.';
NOTIFY pgrst, 'reload schema';
