-- r413 (F29): the QC cache refill returns -1 (busy) when a writer holds a lock it needs, instead of failing the cron run.
-- Staging cdsmnqxtyyoeoznmbidd only. One function body changes: pdc_work_categories_private.refill_qc_operation_lines_cache(integer).
-- Cause (20 Oct, 6 failures of staging-qc-operation-lines-cache-refill, 08:17-15:18 AWST): every write to a QC input table
-- bumps the vehicle's (or the global) row in qc_operation_lines_cache_epoch from a trigger and keeps it locked until the
-- writer commits; a Pilbara service import holds the global row for seconds (10:05, 15:10 and 15:18 were import batches).
-- The refill's FOR SHARE re-check of the generations (and once, 09:01, the cache unique check) waited its 250 ms
-- lock_timeout and the run failed. Once the writer commits the generation has moved, so the batch is skipped anyway.
-- Fix: the INSERT runs in a block that catches lock_not_available (55P03) only, logs qc_cache_refill_busy and returns -1.
-- Same 250 ms wait, same FOR SHARE re-check, same 3 s budget, same batch limits, same SECURITY DEFINER, owner, grants,
-- settings and signature; every other error still fails the run. Nothing is stored on busy, exactly as when it failed.
-- Health: check qc_cache_refill_busy_not_error (F29) adds the refill's 24 h failure count (the clock check covers only the clock).
-- Not touched: workshop_clock_tick, the cron job, the epoch trigger and bump functions, QC line functions, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r413: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r413: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r413: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r413: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_work_categories_private.invalidate_qc_operation_lines_cache()','00f532fdd214dcd242c267616f43bc7f'),
  ('pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(uuid[],boolean)','419a39c1561d20516289bbb1666928b2'),
  ('public.pdc_qc_operation_lines_379_uncached(uuid)','97fc4caaf7b462163d35b4a3511bc487'),
  ('public.pdc_qc_operation_lines_379(uuid)','b7f90bff12643229ff80f8ca552663a2')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>4 THEN RAISE EXCEPTION 'r413: a QC cache function this release keeps unchanged is not the expected version'; END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)') AND l.lanname='plpgsql'
     AND p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')='{postgres=X/postgres}truev|statement_timeout=4s|lock_timeout=250ms|search_path=pg_catalog'
     AND p.proowner='postgres'::regrole AND NOT p.proisstrict AND p.proparallel='u' AND p.prorettype='integer'::regtype AND p.procost=100)<>1 THEN RAISE EXCEPTION 'r413: refill owner, grants, security, volatility, settings, strictness or return type changed'; END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobname='staging-qc-operation-lines-cache-refill' AND active AND schedule='20 seconds' AND command='SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(40);')<>1 THEN RAISE EXCEPTION 'r413: refill cron job changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)'::regprocedure)<>'c9bad5fb2c6ce6f549539fc06647a215' THEN RAISE EXCEPTION 'r413: refill is not the expected version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)' AND prosrc_md5='c9bad5fb2c6ce6f549539fc06647a215' AND release='baseline')<>1 THEN RAISE EXCEPTION 'r413: refill pin is not the baseline pin'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='qc_cache_refill_busy_not_error' OR added_in='r413') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r413') THEN RAISE EXCEPTION 'r413: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=210) THEN RAISE EXCEPTION 'r413: sort_order 210 taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(p_batch integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET statement_timeout TO '4s'
 SET lock_timeout TO '250ms'
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  ids uuid[] := ARRAY[]::uuid[];
  payloads jsonb[] := ARRAY[]::jsonb[];
  vehicle_gens bigint[] := ARRAY[]::bigint[];
  global_gens bigint[] := ARRAY[]::bigint[];
  v_started timestamptz := clock_timestamp();
  global_id constant uuid := '00000000-0000-0000-0000-000000000000';
  vehicle uuid;
  v_gen bigint;
  g_gen bigint;
  filled integer;
BEGIN
  IF p_batch IS NULL OR p_batch < 1 OR p_batch > 40 THEN
    RAISE EXCEPTION 'qc_cache_refill_batch_out_of_range';
  END IF;
  -- The CI proof sets this so it can commit an input change after compute
  -- and before insert. Production leaves it unset and takes no advisory lock.
  -- The key is not the workshop clock lock.
  IF coalesce(current_setting('pdc.qc_cache_refill_after_compute', true), '') = 'wait' THEN
    PERFORM set_config('lock_timeout', '30s', true);
    PERFORM set_config('statement_timeout', '30s', true);
  END IF;
  -- Missing rows are the refill set. Read both generations before computing.
  -- Calling the wrapper would just miss again.
  FOR vehicle IN
    SELECT v.id
    FROM public.vehicles v
    WHERE NOT EXISTS (
      SELECT 1
      FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id = v.id
    )
    ORDER BY v.id
    LIMIT p_batch
  LOOP
    EXIT WHEN clock_timestamp() > v_started + interval '3 seconds';
    SELECT e.gen INTO v_gen
    FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
    WHERE e.vehicle_id = vehicle;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;
    SELECT e.gen INTO g_gen
    FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
    WHERE e.vehicle_id = global_id;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;
    ids := ids || ARRAY[vehicle];
    vehicle_gens := vehicle_gens || ARRAY[v_gen];
    global_gens := global_gens || ARRAY[g_gen];
    payloads := payloads || ARRAY[public.pdc_qc_operation_lines_379_uncached(vehicle)];
  END LOOP;
  IF cardinality(ids) = 0 THEN
    RETURN 0;
  END IF;
  IF coalesce(current_setting('pdc.qc_cache_refill_after_compute', true), '') = 'wait' THEN
    PERFORM pg_advisory_lock(hashtextextended('pdc:qc-cache-refill:test-gate', 0));
    PERFORM pg_advisory_unlock(hashtextextended('pdc:qc-cache-refill:test-gate', 0));
  END IF;
  -- r413 (F29): a writer that changes a vehicle's QC inputs (or a global input: a Pilbara service import holds the
  -- global row for seconds) keeps the epoch row it bumped locked until it commits; the cache unique check can wait on an
  -- in-flight transaction the same way. Once it commits the generation has moved, so this batch would be skipped anyway.
  -- After the same 250 ms lock wait as before, the batch is skipped and the refill returns -1 (busy) instead of failing
  -- the cron run. Nothing is stored, exactly as when the statement failed; the next run (20 s later) retries.
  BEGIN
    INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
    SELECT batch.id, batch.lines, statement_timestamp()
    FROM unnest(ids, payloads, vehicle_gens, global_gens) AS batch(id, lines, vehicle_gen, global_gen)
    WHERE (
      SELECT e.gen
      FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
      WHERE e.vehicle_id = batch.id
      FOR SHARE OF e
    ) IS NOT DISTINCT FROM batch.vehicle_gen
    AND (
      SELECT e.gen
      FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
      WHERE e.vehicle_id = global_id
      FOR SHARE OF e
    ) IS NOT DISTINCT FROM batch.global_gen
    ON CONFLICT (vehicle_id) DO NOTHING;
    GET DIAGNOSTICS filled = ROW_COUNT;
  EXCEPTION WHEN lock_not_available THEN
    RAISE LOG 'qc_cache_refill_busy: %', SQLERRM;
    RETURN -1;
  END;
  RETURN filled;
END
$function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='7b59047dbeab8613738c5c530eb25705',release='r413',note='QC cache refill returns -1 (busy) on a writer lock instead of failing the run (r413, F29)',updated_at=now()
 WHERE signature='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)' AND prosrc_md5='c9bad5fb2c6ce6f549539fc06647a215' AND release='baseline';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('qc_cache_refill_busy_not_error','F29','The QC cache refill (every 20 s) returns -1 (busy) when a writer holds an epoch or cache row lock instead of failing (lock_not_available caught after the same 250 ms wait, FOR SHARE re-check kept), its cron job runs, and no refill run failed in the last 24 hours (the six 20 Oct lock timeouts fixed by r413 are reported, not counted) (r413).',$c413$WITH f AS (
  SELECT p.prosrc, l.lanname, p.prosecdef, coalesce(array_to_string(p.proconfig, '|'), '') AS cfg
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_language l ON l.oid = p.prolang
  WHERE p.oid = to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)')
), j AS (
  SELECT jobid, schedule, command, active FROM cron.job WHERE jobname = 'staging-qc-operation-lines-cache-refill'
), d AS (
  SELECT d.status, d.start_time, d.return_message FROM cron.job_run_details d JOIN j ON j.jobid = d.jobid
  WHERE d.start_time > now() - interval '24 hours'
), s AS (
  SELECT
    (SELECT count(*) FROM f WHERE lanname = 'plpgsql' AND prosecdef
       AND cfg LIKE '%lock_timeout=250ms%' AND cfg LIKE '%statement_timeout=4s%'
       AND prosrc LIKE '%FOR SHARE OF e%'
       AND prosrc ~ 'ON CONFLICT \(vehicle_id\) DO NOTHING;\s+GET DIAGNOSTICS filled = ROW_COUNT;\s+EXCEPTION WHEN lock_not_available THEN\s+RAISE LOG ''qc_cache_refill_busy: %'', SQLERRM;\s+RETURN -1;\s+END;\s+RETURN filled;') AS fn_ok,
    (SELECT count(*) FROM j WHERE active AND schedule = '20 seconds'
       AND command = 'SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(40);') AS job_ok,
    (SELECT count(*) FROM d) AS runs_24h,
    (SELECT count(*) FROM d WHERE start_time > now() - interval '30 minutes') AS runs_30m,
    (SELECT count(*) FROM d WHERE status <> 'succeeded') AS failed_24h,
    -- The six lock timeouts of 20 Oct (08:17-15:18 AWST) are what r413 fixed; they leave the 24 h window by 15:18 AWST 21 Oct.
    (SELECT count(*) FROM d WHERE status <> 'succeeded' AND start_time < timestamptz '2026-10-20 15:18:10+08'
       AND return_message LIKE '%canceling statement due to lock timeout%') AS pre_r413_lock_timeouts,
    (SELECT max(start_time) FROM d WHERE status <> 'succeeded') AS last_failure
)
SELECT s.fn_ok = 1 AND s.job_ok = 1 AND s.runs_30m >= 45 AND s.failed_24h - s.pre_r413_lock_timeouts = 0 AS ok,
  'refill ' || CASE WHEN s.fn_ok = 1 THEN 'returns -1 (busy) on a writer lock' ELSE 'NOT as r413 left it (busy handler, timeouts or FOR SHARE missing)' END
  || '; job ' || CASE WHEN s.job_ok = 1 THEN 'every 20 s' ELSE 'missing, paused or changed' END
  || '; last 30 min: ' || s.runs_30m || ' runs; last 24 h: ' || s.runs_24h || ' runs, ' || s.failed_24h || ' failed'
  || CASE WHEN s.pre_r413_lock_timeouts > 0 THEN ' (' || s.pre_r413_lock_timeouts || ' pre-r413 lock timeouts, 20 Oct)' ELSE '' END
  || coalesce(', last failure ' || to_char(s.last_failure AT TIME ZONE 'Australia/Perth', 'DD Mon HH24:MI') || ' AWST', '') AS detail
FROM s$c413$,true,210,'r413');

DO $p$ DECLARE r record; BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r413: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)'::regprocedure)<>'7b59047dbeab8613738c5c530eb25705' THEN RAISE EXCEPTION 'r413: refill md5 after apply'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r413' AND e.signature='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)' AND md5(p.prosrc)=e.prosrc_md5)<>1
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r413')<>1 THEN RAISE EXCEPTION 'r413: pin'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='qc_cache_refill_busy_not_error' AND added_in='r413' AND fault_id='F29' AND enabled AND sort_order=210)<>'2510b3c1e00f25c6df67b07448d55b7b' THEN RAISE EXCEPTION 'r413: check md5'; END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)') AND l.lanname='plpgsql'
     AND p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')='{postgres=X/postgres}truev|statement_timeout=4s|lock_timeout=250ms|search_path=pg_catalog'
     AND p.proowner='postgres'::regrole AND NOT p.proisstrict AND p.proparallel='u' AND p.prorettype='integer'::regtype AND p.procost=100)<>1 THEN RAISE EXCEPTION 'r413: refill attributes changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_work_categories_private.invalidate_qc_operation_lines_cache()','00f532fdd214dcd242c267616f43bc7f'),
  ('pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(uuid[],boolean)','419a39c1561d20516289bbb1666928b2'),
  ('public.pdc_qc_operation_lines_379_uncached(uuid)','97fc4caaf7b462163d35b4a3511bc487'),
  ('public.pdc_qc_operation_lines_379(uuid)','b7f90bff12643229ff80f8ca552663a2')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>4 THEN RAISE EXCEPTION 'r413: a kept function changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r413: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r413: fault_regression_check changed'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r413: protected_function_md5s not ok: %', r.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='qc_cache_refill_busy_not_error') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r413: check not ok: %', r.detail; END IF;
END $p$;
