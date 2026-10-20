-- Unschedule the QC operation-line cache refill and drop its function.
-- Restore the invalidation trigger to the body from before the epoch, then
-- drop the epoch table. The cache table, the uncached body, and the workshop
-- clock job stay.
-- Rollback for supabase/migrations/20261020082000_qc_operation_lines_cache_refill.sql
-- The restored trigger keeps WHERE true on every full-cache wipe. Rolling
-- this refill back must not bring back the bare DELETE pg_safeupdate rejects.
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

CREATE OR REPLACE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $invalidate$
DECLARE
  op_id uuid;
BEGIN
  IF TG_OP = 'TRUNCATE' OR TG_TABLE_NAME IN ('ai_routing_20261019', 'import_rules_139_20261018', 'import_rules_20261017', 'navision_backend_records', 'pdc_pilbara_service_import_batches', 'workshop_stage_aliases', 'workshop_stages') THEN
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE true;
    RETURN NULL;
  END IF;
  IF TG_TABLE_NAME = 'vehicles' THEN
    IF TG_OP = 'INSERT' THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = NEW.id;
    ELSIF TG_OP = 'UPDATE' THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id IN (OLD.id, NEW.id);
    ELSE
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = OLD.id;
    END IF;
    RETURN NULL;
  END IF;
  IF TG_TABLE_NAME IN ('operation_routing_history_20261015', 'pdc_pilbara_service_classification_current', 'pdc_pilbara_service_classification_history', 'pdc_pilbara_service_operation_history') THEN
    IF TG_OP = 'DELETE' THEN op_id := OLD.operation_id; ELSE op_id := NEW.operation_id; END IF;
    IF TG_OP = 'UPDATE' AND OLD.operation_id IS DISTINCT FROM NEW.operation_id THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id IN (
        SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o
        WHERE o.operation_id IN (OLD.operation_id, NEW.operation_id)
      );
      IF NOT EXISTS (
        SELECT 1 FROM public.pdc_pilbara_service_operations o
        WHERE o.operation_id IN (OLD.operation_id, NEW.operation_id)
      ) THEN
        DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE true;
      END IF;
    ELSIF EXISTS (
      SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.operation_id = op_id
    ) THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id IN (
        SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o WHERE o.operation_id = op_id
      );
    ELSE
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE true;
    END IF;
    RETURN NULL;
  END IF;
  IF TG_OP = 'INSERT' THEN
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = NEW.vehicle_id;
  ELSIF TG_OP = 'UPDATE' THEN
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id IN (OLD.vehicle_id, NEW.vehicle_id);
  ELSE
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = OLD.vehicle_id;
  END IF;
  RETURN NULL;
END
$invalidate$;

DROP FUNCTION IF EXISTS pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(uuid[], boolean);
DROP TABLE IF EXISTS pdc_work_categories_private.qc_operation_lines_cache_epoch;

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
  IF to_regclass('pdc_work_categories_private.qc_operation_lines_cache_epoch') IS NOT NULL
     OR to_regprocedure('pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(uuid[],boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_rollback_incomplete';
  END IF;
  IF position(
    'qc_operation_lines_cache_epoch' IN (
      SELECT prosrc
      FROM pg_proc
      WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure
    )
  ) > 0 THEN
    RAISE EXCEPTION 'qc_cache_refill_rollback_incomplete';
  END IF;
END
$check$;
