-- Prove the refill job restores missing cache rows and leaves the clock job alone.
-- The cron schema here is a stub. CI Postgres does not install pg_cron.

CREATE FUNCTION public.pdc_monitor_staging_guard()
 RETURNS boolean
 LANGUAGE sql
AS $guard$
  SELECT true
$guard$;

CREATE SCHEMA pdc_work_categories_private;

CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY
);

CREATE TABLE pdc_work_categories_private.qc_operation_lines_cache (
  vehicle_id uuid PRIMARY KEY,
  lines jsonb NOT NULL,
  computed_at timestamptz NOT NULL
);

CREATE FUNCTION public.pdc_qc_operation_lines_379_uncached(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $stub$
  SELECT jsonb_build_object('id', p_vehicle_id::text);
$stub$;

CREATE SCHEMA cron;

CREATE TABLE cron.job (
  jobid bigserial PRIMARY KEY,
  schedule text NOT NULL,
  command text NOT NULL,
  jobname text UNIQUE,
  active boolean NOT NULL DEFAULT true
);

CREATE FUNCTION cron.schedule(job_name text, schedule text, command text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $cron$
DECLARE
  new_id bigint;
BEGIN
  INSERT INTO cron.job (schedule, command, jobname, active)
  VALUES (schedule, command, job_name, true)
  RETURNING jobid INTO new_id;
  RETURN new_id;
END
$cron$;

CREATE FUNCTION cron.unschedule(job_name text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $cron$
DECLARE
  removed integer;
BEGIN
  DELETE FROM cron.job WHERE jobname = job_name;
  GET DIAGNOSTICS removed = ROW_COUNT;
  IF removed = 0 THEN
    RAISE EXCEPTION 'job not found';
  END IF;
  RETURN true;
END
$cron$;

INSERT INTO cron.job (schedule, command, jobname, active)
VALUES (
  '* * * * *',
  'SELECT public.workshop_clock_tick(true,clock_timestamp());',
  'staging-workshop-clock-cascade',
  true
);

BEGIN;
\ir ../supabase/migrations/20261019233000_qc_operation_lines_cache_refill.sql
COMMIT;

DO $proof$
DECLARE
  filled integer;
  kept integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-qc-operation-lines-cache-refill'
      AND schedule = '* * * * *'
      AND command = 'SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20);'
      AND active IS TRUE
  ) THEN
    RAISE EXCEPTION 'refill job was not scheduled';
  END IF;
  IF (
    SELECT command
    FROM cron.job
    WHERE jobname = 'staging-workshop-clock-cascade'
  ) IS DISTINCT FROM 'SELECT public.workshop_clock_tick(true,clock_timestamp());' THEN
    RAISE EXCEPTION 'workshop_clock_job_changed';
  END IF;

  INSERT INTO public.vehicles (id) VALUES
    ('00000000-0000-4000-8000-000000000001'),
    ('00000000-0000-4000-8000-000000000002'),
    ('00000000-0000-4000-8000-000000000003'),
    ('00000000-0000-4000-8000-000000000004'),
    ('00000000-0000-4000-8000-000000000005');

  IF pdc_work_categories_private.refill_qc_operation_lines_cache(2) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'first batch';
  END IF;
  IF pdc_work_categories_private.refill_qc_operation_lines_cache(2) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'second batch';
  END IF;
  IF pdc_work_categories_private.refill_qc_operation_lines_cache(2) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'third batch';
  END IF;
  IF (SELECT count(*) FROM pdc_work_categories_private.qc_operation_lines_cache) IS DISTINCT FROM 5 THEN
    RAISE EXCEPTION 'cache was not filled';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pdc_work_categories_private.qc_operation_lines_cache c
    WHERE c.lines IS DISTINCT FROM public.pdc_qc_operation_lines_379_uncached(c.vehicle_id)
  ) THEN
    RAISE EXCEPTION 'cached lines differ from uncached';
  END IF;

  UPDATE pdc_work_categories_private.qc_operation_lines_cache
  SET lines = '{"kept":true}'::jsonb
  WHERE vehicle_id = '00000000-0000-4000-8000-000000000001';
  IF pdc_work_categories_private.refill_qc_operation_lines_cache(20) IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'present row was refilled';
  END IF;
  IF (
    SELECT lines
    FROM pdc_work_categories_private.qc_operation_lines_cache
    WHERE vehicle_id = '00000000-0000-4000-8000-000000000001'
  ) IS DISTINCT FROM '{"kept":true}'::jsonb THEN
    RAISE EXCEPTION 'present row was rewritten';
  END IF;

  DELETE FROM pdc_work_categories_private.qc_operation_lines_cache
  WHERE vehicle_id = '00000000-0000-4000-8000-000000000003';
  IF pdc_work_categories_private.refill_qc_operation_lines_cache(1) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'deleted row was not refilled';
  END IF;
  IF (
    SELECT lines
    FROM pdc_work_categories_private.qc_operation_lines_cache
    WHERE vehicle_id = '00000000-0000-4000-8000-000000000003'
  ) IS DISTINCT FROM public.pdc_qc_operation_lines_379_uncached('00000000-0000-4000-8000-000000000003') THEN
    RAISE EXCEPTION 'refilled lines differ from uncached';
  END IF;
  IF (
    SELECT lines
    FROM pdc_work_categories_private.qc_operation_lines_cache
    WHERE vehicle_id = '00000000-0000-4000-8000-000000000001'
  ) IS DISTINCT FROM '{"kept":true}'::jsonb THEN
    RAISE EXCEPTION 'refill rewrote a row that was still present';
  END IF;

  SELECT count(*) INTO kept FROM pdc_work_categories_private.qc_operation_lines_cache;
  BEGIN
    PERFORM pdc_work_categories_private.refill_qc_operation_lines_cache(0);
    RAISE EXCEPTION 'zero batch was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM IS DISTINCT FROM 'qc_cache_refill_batch_out_of_range' THEN
        RAISE;
      END IF;
  END;
  BEGIN
    PERFORM pdc_work_categories_private.refill_qc_operation_lines_cache(41);
    RAISE EXCEPTION 'oversized batch was accepted';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM IS DISTINCT FROM 'qc_cache_refill_batch_out_of_range' THEN
        RAISE;
      END IF;
  END;
  IF (SELECT count(*) FROM pdc_work_categories_private.qc_operation_lines_cache) IS DISTINCT FROM kept THEN
    RAISE EXCEPTION 'rejected batch changed the cache';
  END IF;
END
$proof$;
