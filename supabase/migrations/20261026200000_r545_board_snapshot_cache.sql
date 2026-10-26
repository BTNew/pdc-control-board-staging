-- r545 (F159). Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Craig approved go-live 26 Oct 2026 12:30 AWST. Rebased onto main 545b7f89 (r542 / F156).
-- r541 / F155 / sort 319, r543 / F157 / sort 321 and r544 / F158 / sort 322 are open previews.
-- This is the next free id: r545 / F159 / sort 323.
-- The Vehicle Locations board rebuilds one shared JSON on every request.
-- At the start of a shift those rebuilds pile up with station snapshots and Fitting shows
-- Offline / Waiting for the selected station snapshot. One caller builds it. Everyone else
-- reuses that copy for 15 seconds. A change to pdc_email_vehicle_revision drops the copy at once.
-- Re-verified before apply: board body a3a635b978cb6b266ea04f03c876672f (stable invoker),
-- location snapshot e7f77fad301b8a87ef548472a8f790a6, station snapshot 98cc6aafa9cc7627c77eda8b46b389fa,
-- sublet board 7dde7e19d31b269136a93ebecd12217a. None of those bodies changed since the preview.
-- The board function is not pinned. Pin count stays 241. Location snapshot is not edited.
-- The daily check times Fitting's station snapshot and the sublet board under the 8s authenticator timeout,
-- and requires the cache to reread pdc_email_vehicle_revision after waiting.
-- The board maps Pilbara operations from operation_lines. Parts uses the summary and per-job
-- evidence; the per-operation copies repeat that evidence, so the wrapper drops them.
-- Undo: supabase/rollbacks/20261026200000_r545_board_snapshot_cache.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r545: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r545: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r545: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r545: location snapshot changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) IS DISTINCT FROM 'a3a635b978cb6b266ea04f03c876672f' THEN RAISE EXCEPTION 'r545: board snapshot is not the compact body'; END IF;
 IF (SELECT provolatile <> 's' OR prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) THEN RAISE EXCEPTION 'r545: board snapshot is not a stable invoker'; END IF;
 IF to_regclass('pdc_ops.vehicle_board_snapshot_cache_545') IS NOT NULL THEN RAISE EXCEPTION 'r545: cache table already exists'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=323 OR fault_id='F159' OR check_name='vehicle_board_snapshot_cache_545' OR added_in='r545') THEN RAISE EXCEPTION 'r545: sort 323 / F159 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='close_gaps_holds_populated' AND fault_id='F156' AND sort_order=320 AND added_in='r542') THEN RAISE EXCEPTION 'r545: r542 check missing'; END IF;
END $g$;

CREATE TABLE pdc_ops.vehicle_board_snapshot_cache_545 (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  email_revision bigint NOT NULL,
  snapshot jsonb NOT NULL,
  computed_at timestamptz NOT NULL
);
ALTER TABLE pdc_ops.vehicle_board_snapshot_cache_545 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_ops.vehicle_board_snapshot_cache_545 FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON TABLE pdc_ops.vehicle_board_snapshot_cache_545 IS
  'r545 (F159): one Vehicle Locations board payload. No API access. The board function is the only reader and writer.';

DO $own$
DECLARE v_owner name;
BEGIN
  SELECT pg_catalog.pg_get_userbyid(p.proowner) INTO v_owner
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()');
  EXECUTE format('ALTER TABLE pdc_ops.vehicle_board_snapshot_cache_545 OWNER TO %I', v_owner);
END
$own$;

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

REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() TO authenticated, service_role;
COMMENT ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() IS
  'r545 (F159): compact vehicle-board read. One shared copy for 15 seconds, dropped when pdc_email_vehicle_revision changes.';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('vehicle_board_snapshot_cache_545','F159','07:51 Offline / waiting for station snapshot (r545): Fitting station snapshot and the sublet board stay under 8s, and the board cache drops when the email revision changes',
 $chk545$SELECT
  cache.ok
  AND timed.station_ms < 8000
  AND timed.sublet_ms < 8000
  AND timed.station_bytes > 100000
  AND timed.sublet_code = 'sublet_po_board'
  AND timed.sublet_bytes > 5000
 AS ok,
 format('fitting station %s ms / %s bytes; sublet board %s ms / %s bytes; revision reread %s',
   timed.station_ms, timed.station_bytes, timed.sublet_ms, timed.sublet_bytes, cache.ok) AS detail
 FROM (
  SELECT
   to_regclass('pdc_ops.vehicle_board_snapshot_cache_545') IS NOT NULL
   AND (SELECT c.relrowsecurity AND NOT c.relforcerowsecurity FROM pg_class c WHERE c.oid='pdc_ops.vehicle_board_snapshot_cache_545'::regclass)
   AND NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='pdc_ops.vehicle_board_snapshot_cache_545'::regclass)
   AND NOT has_table_privilege('anon','pdc_ops.vehicle_board_snapshot_cache_545','SELECT,INSERT,UPDATE,DELETE')
   AND NOT has_table_privilege('authenticated','pdc_ops.vehicle_board_snapshot_cache_545','SELECT,INSERT,UPDATE,DELETE')
   AND NOT has_table_privilege('service_role','pdc_ops.vehicle_board_snapshot_cache_545','SELECT,INSERT,UPDATE,DELETE')
   AND (SELECT p.provolatile='v' AND p.prosecdef
         AND position('pdc-r545-vehicle-board' IN p.prosrc)>0
         AND position('vehicle_board_snapshot_cache_545' IN p.prosrc)>0
         AND position('interval ''15 seconds''' IN p.prosrc)>0
         AND position('c.email_revision = v_rev' IN p.prosrc)>0
         AND position('email_revision = EXCLUDED.email_revision' IN p.prosrc)>0
         AND (length(p.prosrc)-length(replace(p.prosrc,'FROM public.pdc_email_vehicle_revision','')))/length('FROM public.pdc_email_vehicle_revision')=2
         AND position('pilbara_service_operations' IN p.prosrc)>0
        FROM pg_proc p WHERE p.oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()'))
   AND (SELECT proconfig::text FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) LIKE '%search_path=pg_catalog, public%'
   AND has_function_privilege('authenticated','public.get_pdc_email_vehicle_board_snapshot()','EXECUTE')
   AND has_function_privilege('service_role','public.get_pdc_email_vehicle_board_snapshot()','EXECUTE')
   AND NOT has_function_privilege('anon','public.get_pdc_email_vehicle_board_snapshot()','EXECUTE')
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()'))='e7f77fad301b8a87ef548472a8f790a6'
  AS ok
 ) cache
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
  SELECT public.get_station_workshop_snapshot(
    'FITTING',
    (timezone('Australia/Perth', clock_timestamp()))::date,
    (timezone('Australia/Perth', clock_timestamp()))::date) AS snap
 ) st
 CROSS JOIN LATERAL (SELECT clock_timestamp() AS t1) s1
 CROSS JOIN LATERAL (
  SELECT public.get_pdc_sublet_po_board_439() AS snap
 ) su
 CROSS JOIN LATERAL (
  SELECT round((extract(epoch FROM s1.t1 - s0.t0)*1000)::numeric, 1) AS station_ms,
         octet_length(st.snap::text) AS station_bytes,
         round((extract(epoch FROM clock_timestamp() - s1.t1)*1000)::numeric, 1) AS sublet_ms,
         octet_length(su.snap::text) AS sublet_bytes,
         su.snap->>'code' AS sublet_code,
         set_config('request.jwt.claims', '', true) AS clear_claims,
         set_config('request.jwt.claim.sub', '', true) AS clear_sub,
         set_config('request.jwt.claim.email', '', true) AS clear_email
 ) timed$chk545$,
 true, 323, 'r545');


DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r545: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r545: location snapshot changed'; END IF;
 IF (SELECT provolatile <> 'v' OR NOT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()')) THEN RAISE EXCEPTION 'r545: board snapshot is not a volatile definer'; END IF;
 IF (SELECT position('pdc-r545-vehicle-board' IN prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()'))=0 THEN RAISE EXCEPTION 'r545: board lock key missing'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='vehicle_board_snapshot_cache_545' AND fault_id='F159' AND sort_order=323 AND added_in='r545' AND enabled)<>1 THEN RAISE EXCEPTION 'r545: check missing'; END IF;
 IF (SELECT pg_catalog.pg_get_userbyid(p.proowner) FROM pg_proc p WHERE p.oid=to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()'))
    IS DISTINCT FROM
    (SELECT pg_catalog.pg_get_userbyid(c.relowner) FROM pg_class c WHERE c.oid='pdc_ops.vehicle_board_snapshot_cache_545'::regclass)
 THEN RAISE EXCEPTION 'r545: cache table owner is not the board function owner'; END IF;
 IF NOT (SELECT c.relrowsecurity AND NOT c.relforcerowsecurity FROM pg_class c WHERE c.oid='pdc_ops.vehicle_board_snapshot_cache_545'::regclass) THEN RAISE EXCEPTION 'r545: cache RLS'; END IF;
END $p$;
