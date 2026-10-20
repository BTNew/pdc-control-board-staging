-- Restore the operation-line cache invalidation trigger from before the
-- pg_safeupdate repair. The three full-cache wipes lose their WHERE clause.
-- Rollback for supabase/migrations/20261020075300_fix_375_safeupdate.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
DECLARE
  src text;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  SELECT prosrc INTO src
  FROM pg_proc
  WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM '2ca1e202c59e8238d75f5ebac52dced8' THEN
    RAISE EXCEPTION 'qc_cache_safeupdate_rollback_incomplete';
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

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
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache;
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
        DELETE FROM pdc_work_categories_private.qc_operation_lines_cache;
      END IF;
    ELSIF EXISTS (
      SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.operation_id = op_id
    ) THEN
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id IN (
        SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o WHERE o.operation_id = op_id
      );
    ELSE
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache;
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


DO $check$
DECLARE
  src text;
BEGIN
  SELECT prosrc INTO src
  FROM pg_proc
  WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM '446f28dc70b7a0e5e3ff13462ea29226' THEN
    RAISE EXCEPTION 'qc_cache_safeupdate_rollback_incomplete';
  END IF;
END
$check$;
