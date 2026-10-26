-- Undo r545 (F159). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Restores the compact stable invoker board snapshot (prosrc md5 a3a635b978cb6b266ea04f03c876672f).
-- Drops the private board cache. Leaves the location snapshot and the 241 pins alone.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r545 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r545 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r545 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r545 undo: location snapshot changed'; END IF;
 IF (SELECT position('pdc-r545-vehicle-board' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()'))=0 THEN RAISE EXCEPTION 'r545 undo: board snapshot is not the r545 body'; END IF;
 IF (SELECT provolatile <> 'v' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) THEN RAISE EXCEPTION 'r545 undo: board snapshot is not the r545 volatile definer'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_board_snapshot()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_base jsonb;
  v_rows jsonb;
BEGIN
  v_base := public.get_pdc_email_vehicle_location_snapshot();
  IF NOT coalesce((v_base->>'ok')::boolean, false)
     OR jsonb_typeof(v_base#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN
    RETURN v_base;
  END IF;
  -- The board maps Pilbara operations from operation_lines. Parts uses the
  -- summary and per-job evidence; the per-operation copies repeat that evidence.
  SELECT coalesce(jsonb_agg(
    CASE WHEN jsonb_typeof(row_value) = 'object' THEN
      CASE WHEN jsonb_typeof(row_value->'parts_flags') = 'object'
        THEN (row_value - 'pilbara_service_operations') #- '{parts_flags,operations}'
        ELSE row_value - 'pilbara_service_operations'
      END
    ELSE row_value END ORDER BY ordinal), '[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(v_base#>'{data,vehicles}') WITH ORDINALITY AS x(row_value, ordinal);
  RETURN jsonb_set(v_base, '{data,vehicles}', v_rows, false);
END
$function$;

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() TO authenticated, service_role;
COMMENT ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() IS
  'Compact authenticated vehicle-board read; preserves the original snapshot authority and compatibility endpoint.';

DROP TABLE IF EXISTS pdc_ops.vehicle_board_snapshot_cache_545;

DELETE FROM pdc_ops.regression_checks
 WHERE check_name='vehicle_board_snapshot_cache_545' AND fault_id='F159' AND sort_order=323 AND added_in='r545';

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r545 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r545 undo: location snapshot changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM 'a3a635b978cb6b266ea04f03c876672f' THEN RAISE EXCEPTION 'r545 undo: restored board body md5'; END IF;
 IF (SELECT provolatile <> 's' OR prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) THEN RAISE EXCEPTION 'r545 undo: board snapshot is not a stable invoker'; END IF;
 IF to_regclass('pdc_ops.vehicle_board_snapshot_cache_545') IS NOT NULL THEN RAISE EXCEPTION 'r545 undo: cache table still exists'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='vehicle_board_snapshot_cache_545' OR fault_id='F159' OR sort_order=323 OR added_in='r545') THEN RAISE EXCEPTION 'r545 undo: check still present'; END IF;
END $p$;
