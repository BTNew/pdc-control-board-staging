-- pg_safeupdate rejects a DELETE or UPDATE that has no WHERE clause.
-- Authenticator sessions preload that library, so the three full-cache
-- wipes in invalidate_qc_operation_lines_cache failed the Navision import
-- with SQLSTATE 21000. Those three statements now end in WHERE true.
-- Rollback: supabase/rollbacks/20261020075300_fix_375_safeupdate.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
DECLARE
  src text;
  definer boolean;
  config text[];
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF to_regprocedure('pdc_work_categories_private.invalidate_qc_operation_lines_cache()') IS NULL THEN
    RAISE EXCEPTION 'reviewed_qc_cache_invalidate_changed';
  END IF;
  SELECT p.prosrc, p.prosecdef, p.proconfig
    INTO src, definer, config
  FROM pg_proc p
  WHERE p.oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM '446f28dc70b7a0e5e3ff13462ea29226'
     OR definer IS DISTINCT FROM true
     OR config IS DISTINCT FROM ARRAY['search_path=pg_catalog'] THEN
    RAISE EXCEPTION 'reviewed_qc_cache_invalidate_changed';
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

REVOKE ALL ON FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache() FROM PUBLIC;

DO $check$
DECLARE
  src text;
BEGIN
  SELECT prosrc INTO src
  FROM pg_proc
  WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM '2ca1e202c59e8238d75f5ebac52dced8' THEN
    RAISE EXCEPTION 'qc_cache_safeupdate_rewrite_mismatch';
  END IF;
  IF position('DELETE FROM pdc_work_categories_private.qc_operation_lines_cache;' IN src) > 0 THEN
    RAISE EXCEPTION 'qc_cache_safeupdate_rewrite_mismatch';
  END IF;
END
$check$;
