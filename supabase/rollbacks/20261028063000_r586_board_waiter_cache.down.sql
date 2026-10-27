-- r586 (F200) undo. Restores the blocking board lock and the r554 checksum.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Puts public.get_pdc_email_vehicle_board_snapshot() back to ae706516b88574c1162e2c5889e4b4a9.
-- Puts read_once_snapshots_554 back to that checksum. Removes board_snapshot_waiter_586.
-- Does not release a pin. Pin count stays 241. Department 135, Kajel, the clock tick,
-- the conditional read, and the QC line bodies are not rewritten.
SET LOCAL lock_timeout = '8s';
DO $g$
DECLARE awst time;
BEGIN
 awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
 IF awst BETWEEN time '06:50' AND time '07:30'
    OR awst BETWEEN time '12:20' AND time '12:40'
    OR awst BETWEEN time '17:50' AND time '18:10' THEN
  RAISE EXCEPTION 'r586 undo: Kajel import window';
 END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r586 undo: staging only'; END IF;
 IF (SELECT position('board_busy' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()'))=0 THEN RAISE EXCEPTION 'r586 undo: board body is not r586'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='board_snapshot_waiter_586' AND fault_id='F200' AND sort_order=358 AND added_in='r586')<>1 THEN RAISE EXCEPTION 'r586 undo: check missing'; END IF;
END $g$;

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
  (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')),
  'ae706516b88574c1162e2c5889e4b4a9')
WHERE check_name='read_once_snapshots_554'
  AND fault_id='F168'
  AND sort_order=329
  AND added_in='r554'
  AND position((SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IN check_sql)>0;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_board_snapshot()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_base jsonb;
  v_rows jsonb;
  v_rev bigint;
  v_cached jsonb;
  v_lock boolean;
BEGIN
  -- performance-20261026: authorize every caller before a shared cache hit.
  -- Keep the same allowed roles as get_pdc_email_vehicle_location_snapshot_pre168.
  IF coalesce(public.current_pdc_user_role()::text IN ('viewer','operator','importer','administrator'), false) IS NOT TRUE THEN
    RETURN public.navision_backend_response(false, 'unauthorized');
  END IF;
  -- r545 (F159): one shared Vehicle Locations board for 15 seconds.
  -- The payload does not depend on who is signed in. Parallel refreshes were
  -- each rebuilding it and timing the workshop out.
  SELECT r.revision INTO v_rev
  FROM public.pdc_email_vehicle_revision r
  WHERE r.singleton;
  v_rev := coalesce(v_rev, 0);

  SELECT c.snapshot INTO v_cached
  FROM pdc_ops.vehicle_board_snapshot_cache_545 c
  WHERE c.singleton
    AND c.email_revision = v_rev
    AND c.computed_at > clock_timestamp() - interval '15 seconds';
  IF v_cached IS NOT NULL THEN
    RETURN v_cached;
  END IF;

  v_lock := pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r545-vehicle-board', 0));
  IF NOT v_lock THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r545-vehicle-board', 0));
    SELECT r.revision INTO v_rev
    FROM public.pdc_email_vehicle_revision r
    WHERE r.singleton;
    v_rev := coalesce(v_rev, 0);
    SELECT c.snapshot INTO v_cached
    FROM pdc_ops.vehicle_board_snapshot_cache_545 c
    WHERE c.singleton
      AND c.email_revision = v_rev
      AND c.computed_at > clock_timestamp() - interval '15 seconds';
    IF v_cached IS NOT NULL THEN
      RETURN v_cached;
    END IF;
  END IF;

  v_base := public.get_pdc_email_vehicle_location_snapshot();
  IF NOT coalesce((v_base->>'ok')::boolean, false)
     OR jsonb_typeof(v_base#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN
    RETURN v_base;
  END IF;
  SELECT coalesce(jsonb_agg(
    CASE WHEN jsonb_typeof(row_value) = 'object' THEN
      CASE WHEN jsonb_typeof(row_value->'parts_flags') = 'object'
        THEN (row_value - 'pilbara_service_operations') #- '{parts_flags,operations}'
        ELSE row_value - 'pilbara_service_operations'
      END
    ELSE row_value END ORDER BY ordinal), '[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(v_base#>'{data,vehicles}') WITH ORDINALITY AS x(row_value, ordinal);
  v_base := jsonb_set(v_base, '{data,vehicles}', v_rows, false);
  INSERT INTO pdc_ops.vehicle_board_snapshot_cache_545 (singleton, email_revision, snapshot, computed_at)
  VALUES (true, v_rev, v_base, clock_timestamp())
  ON CONFLICT (singleton) DO UPDATE
    SET email_revision = EXCLUDED.email_revision,
        snapshot = EXCLUDED.snapshot,
        computed_at = EXCLUDED.computed_at
    WHERE vehicle_board_snapshot_cache_545.singleton;
  RETURN v_base;
END
$function$;

COMMENT ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() IS
  'r545 (F159): compact vehicle-board read. One shared copy for 15 seconds, dropped when pdc_email_vehicle_revision changes.';

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() TO authenticated, service_role;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='board_snapshot_waiter_586'
  AND fault_id='F200'
  AND sort_order=358
  AND added_in='r586';

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM 'ae706516b88574c1162e2c5889e4b4a9' THEN RAISE EXCEPTION 'r586 undo: board md5'; END IF;
 IF (SELECT provolatile <> 'v' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) THEN RAISE EXCEPTION 'r586 undo: volatility'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='board_snapshot_waiter_586')<>0 THEN RAISE EXCEPTION 'r586 undo: check remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554' AND (length(check_sql)-length(replace(check_sql,'ae706516b88574c1162e2c5889e4b4a9','')))/32=1)<>1 THEN RAISE EXCEPTION 'r586 undo: r554 check not restored'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r586 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r586 undo: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r586 undo: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r586 undo: Kajel apply changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r586 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)')) IS DISTINCT FROM '5b50acbf467ad4f38d3a8f9a062cc12e' THEN RAISE EXCEPTION 'r586 undo: conditional body changed'; END IF;
END $p$;
