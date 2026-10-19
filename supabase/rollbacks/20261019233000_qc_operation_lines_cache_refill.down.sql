-- Unschedule the QC operation-line cache refill and drop its function.
-- The cache table, the uncached body, and the workshop clock job stay.
-- Rollback for supabase/migrations/20261019233000_qc_operation_lines_cache_refill.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
DECLARE
  clock_command text := 'SELECT public.workshop_clock_tick(true,clock_timestamp());';
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF to_regclass('cron.job') IS NULL
     OR to_regprocedure('cron.unschedule(text)') IS NULL THEN
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
    PERFORM cron.unschedule('staging-qc-operation-lines-cache-refill');
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS pdc_work_categories_private.refill_qc_operation_lines_cache(integer);

DO $check$
DECLARE
  clock_command text := 'SELECT public.workshop_clock_tick(true,clock_timestamp());';
BEGIN
  IF to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_rollback_incomplete';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-qc-operation-lines-cache-refill'
  ) THEN
    RAISE EXCEPTION 'qc_cache_refill_rollback_incomplete';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-workshop-clock-cascade'
      AND command IS DISTINCT FROM clock_command
  ) THEN
    RAISE EXCEPTION 'workshop_clock_job_changed';
  END IF;
END
$check$;
