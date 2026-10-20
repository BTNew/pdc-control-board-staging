-- Prove the three full-cache wipes survive pg_safeupdate.
-- The library is what the authenticator role preloads.

CREATE FUNCTION public.pdc_monitor_staging_guard()
 RETURNS boolean
 LANGUAGE sql
AS $guard$
  SELECT true
$guard$;

CREATE SCHEMA pdc_work_categories_private;

CREATE TABLE pdc_work_categories_private.qc_operation_lines_cache (
  vehicle_id uuid PRIMARY KEY,
  lines jsonb NOT NULL,
  computed_at timestamptz NOT NULL
);

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


CREATE TABLE public.navision_backend_records (
  id integer PRIMARY KEY
);
CREATE TRIGGER qc_operation_lines_cache_row
  AFTER INSERT OR UPDATE OR DELETE ON public.navision_backend_records
  FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate
  AFTER TRUNCATE ON public.navision_backend_records
  FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TABLE public.safeupdate_probe (
  id integer
);
GRANT USAGE ON SCHEMA public TO qc_cache_safeupdate_writer;
GRANT USAGE ON SCHEMA pdc_work_categories_private TO qc_cache_safeupdate_writer;
GRANT INSERT, TRUNCATE ON public.navision_backend_records TO qc_cache_safeupdate_writer;
GRANT INSERT, DELETE ON public.safeupdate_probe TO qc_cache_safeupdate_writer;

-- The unpatched trigger must fail in a session where safeupdate is loaded.
LOAD 'safeupdate';
INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
VALUES ('00000000-0000-4000-8000-0000000000f1', '[]'::jsonb, statement_timestamp());
INSERT INTO public.safeupdate_probe (id) VALUES (1);
SET ROLE qc_cache_safeupdate_writer;
DO $before$
BEGIN
  INSERT INTO public.navision_backend_records (id) VALUES (1);
  RAISE EXCEPTION 'unpatched shared wipe was accepted';
EXCEPTION
  WHEN cardinality_violation THEN
    IF SQLERRM NOT LIKE '%WHERE clause%' THEN
      RAISE;
    END IF;
END
$before$;
RESET ROLE;

BEGIN;
\ir ../supabase/migrations/20261020075300_fix_375_safeupdate.sql
COMMIT;

INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
VALUES ('00000000-0000-4000-8000-0000000000f1', '[]'::jsonb, statement_timestamp())
ON CONFLICT (vehicle_id) DO NOTHING;
SET ROLE qc_cache_safeupdate_writer;
INSERT INTO public.navision_backend_records (id) VALUES (1);
RESET ROLE;

DO $shared_write$
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_work_categories_private.qc_operation_lines_cache) THEN
    RAISE EXCEPTION 'shared input left a cache row';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.navision_backend_records WHERE id = 1) THEN
    RAISE EXCEPTION 'shared input row was not written';
  END IF;
END
$shared_write$;

INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
VALUES ('00000000-0000-4000-8000-0000000000f1', '[]'::jsonb, statement_timestamp());
SET ROLE qc_cache_safeupdate_writer;
TRUNCATE public.navision_backend_records;
RESET ROLE;

DO $shared_truncate$
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_work_categories_private.qc_operation_lines_cache) THEN
    RAISE EXCEPTION 'truncate left a cache row';
  END IF;
  IF EXISTS (SELECT 1 FROM public.navision_backend_records) THEN
    RAISE EXCEPTION 'truncate left a navision row';
  END IF;
END
$shared_truncate$;
