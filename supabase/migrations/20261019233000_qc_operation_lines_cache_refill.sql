-- Refill QC operation-line cache rows that triggers have deleted.
-- A read still falls through to the uncached body when the row is missing,
-- and nothing was putting those rows back.
-- This adds a separate pg_cron job, every minute, that recomputes a bounded
-- batch of missing vehicle rows.
-- It is not called from workshop_clock_tick and it is not appended to the
-- clock job. The clock holds its advisory transaction lock and its booking
-- and assignment row locks until it returns. Extending that transaction with
-- the recompute would make the next clock wait on this work.
-- The refill never takes that advisory lock or those booking locks. It
-- computes the batch first, then inserts once, so cache row locks exist only
-- for the insert. lock_timeout makes this job give up if the clock is already
-- deleting one of those rows.
-- Rollback: supabase/rollbacks/20261019233000_qc_operation_lines_cache_refill.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
DECLARE
  clock_command text := 'SELECT public.workshop_clock_tick(true,clock_timestamp());';
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF to_regclass('pdc_work_categories_private.qc_operation_lines_cache') IS NULL
     OR to_regclass('public.vehicles') IS NULL
     OR to_regprocedure('public.pdc_qc_operation_lines_379_uncached(uuid)') IS NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_cache_missing';
  END IF;
  IF (
    SELECT count(*)
    FROM (VALUES ('vehicle_id'), ('lines'), ('computed_at')) AS expected(col)
    JOIN pg_attribute a
      ON a.attrelid = 'pdc_work_categories_private.qc_operation_lines_cache'::regclass
     AND a.attname = expected.col
     AND a.attnum > 0
     AND NOT a.attisdropped
  ) IS DISTINCT FROM 3
  OR NOT EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'public.vehicles'::regclass
      AND attname = 'id'
      AND NOT attisdropped
      AND atttypid = 'uuid'::regtype
  )
  OR NOT EXISTS (
    SELECT 1
    FROM pg_proc
    WHERE oid = 'public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure
      AND prosecdef
      AND provolatile = 's'
  ) THEN
    RAISE EXCEPTION 'qc_cache_refill_cache_missing';
  END IF;
  IF to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_already_installed';
  END IF;
  IF to_regprocedure('cron.schedule(text,text,text)') IS NULL
     OR to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_cron_missing';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-workshop-clock-cascade'
      AND command IS DISTINCT FROM clock_command
  ) THEN
    RAISE EXCEPTION 'workshop_clock_job_changed';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-qc-operation-lines-cache-refill'
  ) THEN
    RAISE EXCEPTION 'qc_cache_refill_job_exists';
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

CREATE FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(p_batch integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET statement_timeout TO '4s'
 SET lock_timeout TO '250ms'
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  ids uuid[] := ARRAY[]::uuid[];
  payloads jsonb[] := ARRAY[]::jsonb[];
  v_started timestamptz := clock_timestamp();
  vehicle uuid;
  filled integer;
BEGIN
  IF p_batch IS NULL OR p_batch < 1 OR p_batch > 40 THEN
    RAISE EXCEPTION 'qc_cache_refill_batch_out_of_range';
  END IF;
  -- Read the missing ids, then compute, then insert. Invalidated rows are
  -- deletes, so a missing row is the whole refill set. The uncached body is
  -- the slow path; calling the wrapper would just miss again.
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
    ids := ids || ARRAY[vehicle];
    payloads := payloads || ARRAY[public.pdc_qc_operation_lines_379_uncached(vehicle)];
  END LOOP;
  IF cardinality(ids) = 0 THEN
    RETURN 0;
  END IF;
  INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
  SELECT batch.id, batch.lines, statement_timestamp()
  FROM unnest(ids, payloads) AS batch(id, lines)
  ON CONFLICT (vehicle_id) DO NOTHING;
  GET DIAGNOSTICS filled = ROW_COUNT;
  RETURN filled;
END
$function$;

REVOKE ALL ON FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(integer) FROM PUBLIC;
DO $revoke_refill$
DECLARE role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE 'REVOKE ALL ON FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(integer) FROM ' || quote_ident(role_name);
    END IF;
  END LOOP;
END
$revoke_refill$;

COMMENT ON FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(integer) IS
  'Recompute missing QC operation-line cache rows in a bounded batch. Separate from the workshop clock.';

DO $schedule$
DECLARE
  refill_command text := 'SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20);';
  clock_command text := 'SELECT public.workshop_clock_tick(true,clock_timestamp());';
BEGIN
  PERFORM cron.schedule(
    'staging-qc-operation-lines-cache-refill',
    '* * * * *',
    refill_command
  );
  IF NOT EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-qc-operation-lines-cache-refill'
      AND schedule = '* * * * *'
      AND command = refill_command
      AND active IS TRUE
  ) THEN
    RAISE EXCEPTION 'qc_cache_refill_schedule_mismatch';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-workshop-clock-cascade'
      AND command IS DISTINCT FROM clock_command
  ) THEN
    RAISE EXCEPTION 'workshop_clock_job_changed';
  END IF;
  IF (
    SELECT proconfig
    FROM pg_proc
    WHERE oid = 'pdc_work_categories_private.refill_qc_operation_lines_cache(integer)'::regprocedure
  ) IS DISTINCT FROM ARRAY['statement_timeout=4s', 'lock_timeout=250ms', 'search_path=pg_catalog'] THEN
    RAISE EXCEPTION 'qc_cache_refill_schedule_mismatch';
  END IF;
END
$schedule$;
