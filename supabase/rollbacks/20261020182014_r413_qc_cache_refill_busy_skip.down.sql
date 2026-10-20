-- r413 undo: puts back the exact pre-r413 refill body (md5 c9bad5fb2c6ce6f549539fc06647a215), restores its baseline pin and removes the r413 check.
-- Run between :02 and :45 with lock_timeout 2s. Staging only. The cron job, clock tick and every other function are untouched.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r413 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r413 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r413 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r413 undo: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_work_categories_private.invalidate_qc_operation_lines_cache()','00f532fdd214dcd242c267616f43bc7f'),
  ('pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(uuid[],boolean)','419a39c1561d20516289bbb1666928b2'),
  ('public.pdc_qc_operation_lines_379_uncached(uuid)','97fc4caaf7b462163d35b4a3511bc487'),
  ('public.pdc_qc_operation_lines_379(uuid)','b7f90bff12643229ff80f8ca552663a2')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>4 THEN RAISE EXCEPTION 'r413 undo: a QC cache function this release keeps unchanged is not the expected version'; END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)') AND l.lanname='plpgsql'
     AND p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')='{postgres=X/postgres}truev|statement_timeout=4s|lock_timeout=250ms|search_path=pg_catalog'
     AND p.proowner='postgres'::regrole AND NOT p.proisstrict AND p.proparallel='u' AND p.prorettype='integer'::regtype AND p.procost=100)<>1 THEN RAISE EXCEPTION 'r413 undo: refill owner, grants, security, volatility, settings, strictness or return type changed'; END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobname='staging-qc-operation-lines-cache-refill' AND active AND schedule='20 seconds' AND command='SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(40);')<>1 THEN RAISE EXCEPTION 'r413 undo: refill cron job changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)'::regprocedure)<>'7b59047dbeab8613738c5c530eb25705' THEN RAISE EXCEPTION 'r413 undo: refill is not the r413 version; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)' AND prosrc_md5='7b59047dbeab8613738c5c530eb25705' AND release='r413')<>1 THEN RAISE EXCEPTION 'r413 undo: refill pin is not the r413 pin'; END IF;
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
  RETURN filled;
END
$function$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='qc_cache_refill_busy_not_error' AND added_in='r413';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='c9bad5fb2c6ce6f549539fc06647a215',release='baseline',note=NULL,updated_at=now()
 WHERE signature='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)' AND prosrc_md5='7b59047dbeab8613738c5c530eb25705' AND release='r413';

DO $p$ DECLARE r record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)'::regprocedure)<>'c9bad5fb2c6ce6f549539fc06647a215' THEN RAISE EXCEPTION 'r413 undo: restore md5'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE signature='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)' AND prosrc_md5='c9bad5fb2c6ce6f549539fc06647a215' AND release='baseline' AND note IS NULL)<>1 THEN RAISE EXCEPTION 'r413 undo: pin'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r413' OR check_name='qc_cache_refill_busy_not_error') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r413') THEN RAISE EXCEPTION 'r413 undo: r413 rows left'; END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)') AND l.lanname='plpgsql'
     AND p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')='{postgres=X/postgres}truev|statement_timeout=4s|lock_timeout=250ms|search_path=pg_catalog'
     AND p.proowner='postgres'::regrole AND NOT p.proisstrict AND p.proparallel='u' AND p.prorettype='integer'::regtype AND p.procost=100)<>1 THEN RAISE EXCEPTION 'r413 undo: refill attributes changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('pdc_work_categories_private.invalidate_qc_operation_lines_cache()','00f532fdd214dcd242c267616f43bc7f'),
  ('pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(uuid[],boolean)','419a39c1561d20516289bbb1666928b2'),
  ('public.pdc_qc_operation_lines_379_uncached(uuid)','97fc4caaf7b462163d35b4a3511bc487'),
  ('public.pdc_qc_operation_lines_379(uuid)','b7f90bff12643229ff80f8ca552663a2')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>4 THEN RAISE EXCEPTION 'r413 undo: a kept function changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r413 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r413 undo: fault_regression_check changed'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='protected_function_md5s') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r413 undo: protected_function_md5s not ok: %', r.detail; END IF;
END $p$;
