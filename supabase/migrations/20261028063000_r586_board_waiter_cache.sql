-- r586 (F200) / sort 358. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Burt, 28 Oct 2026 06:19 AWST: get_pdc_email_vehicle_board_snapshot_conditional convoyed on the
-- r545 rebuild lock. One PostgREST call held it while rebuilding and the others waited on
-- Lock/advisory until the authenticator gave up. Lifetime of that RPC: 696 calls, mean 5454.6 ms, max 29812.3 ms.
-- The conditional read calls public.get_pdc_email_vehicle_board_snapshot(). That function already
-- tries the lock, then blocks with pg_advisory_xact_lock until the holder finishes.
-- Waiters now return the last stored snapshot at once, even when it is a few seconds stale.
-- Only the lock holder rebuilds. A cold cache (no row yet) polls for 1.5 seconds and then
-- returns board_busy. It does not take the blocking lock.
-- The rebuild strip is unchanged, so a holder's JSON stays byte-identical.
-- PR #498 keeps r584 / F198 / sort 356. This does not take those numbers.
-- The board function is not pinned. Pin count stays 241.
-- read_once_snapshots_554 names the old board body ae706516b88574c1162e2c5889e4b4a9. This release
-- retargets that one checksum to the new body. The r554 calculations are not edited.
-- Undo: supabase/rollbacks/20261028063000_r586_board_waiter_cache.down.sql
SET LOCAL lock_timeout = '8s';
DO $g$
DECLARE awst time;
BEGIN
 awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
 IF awst BETWEEN time '06:50' AND time '07:30'
    OR awst BETWEEN time '12:20' AND time '12:40'
    OR awst BETWEEN time '17:50' AND time '18:10' THEN
  RAISE EXCEPTION 'r586: Kajel import window';
 END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r586: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r586: pin count is not 241'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_board_snapshot()') THEN RAISE EXCEPTION 'r586: board function is pinned'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=358 OR fault_id='F200' OR check_name='board_snapshot_waiter_586' OR added_in='r586') THEN RAISE EXCEPTION 'r586: sort 358 / F200 is taken'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=356 OR fault_id='F198' OR added_in='r584') THEN RAISE EXCEPTION 'r586: r584 preview is in the ledger'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM 'ae706516b88574c1162e2c5889e4b4a9' THEN RAISE EXCEPTION 'r586: board body changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)')) IS DISTINCT FROM '5b50acbf467ad4f38d3a8f9a062cc12e' THEN RAISE EXCEPTION 'r586: conditional body changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r586: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r586: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r586: Kajel apply changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r586: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r586: QC wrapper changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379_uncached(uuid)')) IS DISTINCT FROM '97fc4caaf7b462163d35b4a3511bc487' THEN RAISE EXCEPTION 'r586: QC uncached changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.base_pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'a93005010cf96ab6eb804ef879039861' THEN RAISE EXCEPTION 'r586: QC base changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554' AND fault_id='F168' AND sort_order=329 AND added_in='r554' AND (length(check_sql)-length(replace(check_sql,'ae706516b88574c1162e2c5889e4b4a9','')))/32=1)<>1 THEN RAISE EXCEPTION 'r586: r554 check does not name the old board body once'; END IF;
END $g$;

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
  v_until timestamptz;
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
    -- r586 (F200): a waiter never blocks on the rebuild lock.
    -- Return the last stored snapshot even when the revision moved or the 15 seconds have passed.
    SELECT c.snapshot INTO v_cached
    FROM pdc_ops.vehicle_board_snapshot_cache_545 c
    WHERE c.singleton;
    IF v_cached IS NOT NULL THEN
      RETURN v_cached;
    END IF;
    -- Cold cache: no prior snapshot. Poll until the holder commits a row, or 1.5 seconds.
    v_until := clock_timestamp() + interval '1500 milliseconds';
    WHILE v_cached IS NULL AND clock_timestamp() < v_until LOOP
      PERFORM pg_catalog.pg_sleep(0.05);
      SELECT c.snapshot INTO v_cached
      FROM pdc_ops.vehicle_board_snapshot_cache_545 c
      WHERE c.singleton;
    END LOOP;
    IF v_cached IS NOT NULL THEN
      RETURN v_cached;
    END IF;
    RETURN public.navision_backend_response(false, 'board_busy');
  END IF;

  SELECT r.revision INTO v_rev
  FROM public.pdc_email_vehicle_revision r
  WHERE r.singleton;
  v_rev := coalesce(v_rev, 0);

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
  'r586 (F200): compact vehicle-board read. One holder rebuilds. Waiters return the last stored snapshot at once. A cold cache waits at most 1.5 seconds, then returns board_busy.';

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
  'ae706516b88574c1162e2c5889e4b4a9',
  (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')))
WHERE check_name='read_once_snapshots_554'
  AND fault_id='F168'
  AND sort_order=329
  AND added_in='r554'
  AND position('ae706516b88574c1162e2c5889e4b4a9' IN check_sql)>0;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('board_snapshot_waiter_586','F200','06:19 board RPC convoyed on the rebuild lock (r586): waiters do not take the blocking lock, a second call stays under 2s, and the two payloads match',
 $chk586$SELECT
  structure.ok
  AND timed.second_ms < 2000
  AND timed.same
  AND timed.ok_flag
 AS ok,
 format('first %s ms / second %s ms / %s bytes / md5 %s / same %s',
   timed.first_ms, timed.second_ms, timed.bytes, timed.payload_md5, timed.same) AS detail
 FROM (
  SELECT
   (SELECT p.provolatile='v' AND p.prosecdef
      AND position('current_pdc_user_role' IN p.prosrc) < position('vehicle_board_snapshot_cache_545' IN p.prosrc)
      AND position('pdc-r545-vehicle-board' IN p.prosrc)>0
      AND position('interval ''15 seconds''' IN p.prosrc)>0
      AND position('c.email_revision = v_rev' IN p.prosrc)>0
      AND position('email_revision = EXCLUDED.email_revision' IN p.prosrc)>0
      AND position('interval ''1500 milliseconds''' IN p.prosrc)>0
      AND position('board_busy' IN p.prosrc)>0
      AND position('pg_catalog.pg_sleep' IN p.prosrc)>0
      AND position('pg_catalog.pg_try_advisory_xact_lock' IN p.prosrc)>0
      AND position('pg_catalog.pg_advisory_xact_lock' IN p.prosrc)=0
      AND position('PERFORM pg_catalog.pg_advisory_xact_lock' IN p.prosrc)=0
      AND (length(p.prosrc)-length(replace(p.prosrc,'FROM public.pdc_email_vehicle_revision','')))/length('FROM public.pdc_email_vehicle_revision')=2
     FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()'))
   AND (SELECT proconfig::text FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) LIKE '%search_path=pg_catalog, public%'
   AND has_function_privilege('authenticated','public.get_pdc_email_vehicle_board_snapshot()','EXECUTE')
   AND NOT has_function_privilege('anon','public.get_pdc_email_vehicle_board_snapshot()','EXECUTE')
   AND to_regclass('pdc_ops.vehicle_board_snapshot_cache_545') IS NOT NULL
  AS ok
 ) structure
 CROSS JOIN LATERAL (
  SELECT r.email, r.auth_user_id
  FROM public.pdc_user_roles r
  WHERE r.role::text='administrator' AND r.active AND r.account_status='approved' AND r.auth_user_id IS NOT NULL
  ORDER BY r.auth_user_id
  LIMIT 1
 ) actor
 CROSS JOIN LATERAL (
  SELECT set_config('request.jwt.claims', json_build_object('sub', actor.auth_user_id, 'email', actor.email)::text, true) AS claims,
         set_config('request.jwt.claim.sub', actor.auth_user_id::text, true) AS sub,
         set_config('request.jwt.claim.email', actor.email, true) AS email
 ) primed
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t0) s0
 CROSS JOIN LATERAL (
  SELECT public.get_pdc_email_vehicle_board_snapshot() AS snap
 ) a
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t1) s1
 CROSS JOIN LATERAL (
  SELECT public.get_pdc_email_vehicle_board_snapshot() AS snap
 ) b
 CROSS JOIN LATERAL (
  SELECT round((extract(epoch FROM s1.t1 - s0.t0)*1000)::numeric, 1) AS first_ms,
         round((extract(epoch FROM clock_timestamp() - s1.t1)*1000)::numeric, 1) AS second_ms,
         octet_length(b.snap::text) AS bytes,
         md5(b.snap::text) AS payload_md5,
         a.snap IS NOT DISTINCT FROM b.snap AS same,
         coalesce((b.snap->>'ok')::boolean, false) AS ok_flag,
         set_config('request.jwt.claims', '', true) AS clear_claims,
         set_config('request.jwt.claim.sub', '', true) AS clear_sub,
         set_config('request.jwt.claim.email', '', true) AS clear_email
 ) timed$chk586$,
 true, 358, 'r586');

DO $p$
DECLARE v_md5 text;
BEGIN
 SELECT md5(prosrc) INTO v_md5 FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()');
 IF v_md5 IS NOT DISTINCT FROM 'ae706516b88574c1162e2c5889e4b4a9' THEN RAISE EXCEPTION 'r586: board body did not change'; END IF;
 IF (SELECT position('PERFORM pg_catalog.pg_advisory_xact_lock' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()'))<>0 THEN RAISE EXCEPTION 'r586: blocking lock remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r586: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r586: department 135 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r586: Kajel rows changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r586: Kajel apply changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN RAISE EXCEPTION 'r586: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot_conditional(text)')) IS DISTINCT FROM '5b50acbf467ad4f38d3a8f9a062cc12e' THEN RAISE EXCEPTION 'r586: conditional body changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379(uuid)')) IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r586: QC wrapper changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554' AND (length(check_sql)-length(replace(check_sql,v_md5,'')))/length(v_md5)=1 AND position('ae706516b88574c1162e2c5889e4b4a9' IN check_sql)=0)<>1 THEN RAISE EXCEPTION 'r586: r554 check was not retargeted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='board_snapshot_waiter_586' AND fault_id='F200' AND sort_order=358 AND added_in='r586' AND enabled)<>1 THEN RAISE EXCEPTION 'r586: check missing'; END IF;
END $p$;
