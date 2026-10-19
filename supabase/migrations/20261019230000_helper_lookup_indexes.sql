-- Index the two single-vehicle lookups in the QC operation helper that still
-- scan the table. A deleted vehicle with no active booking was planned on
-- staging cdsmnqxtyyoeoznmbidd:
--   pdc_tune_operation_change_reviews filtered by vehicle, status and
--   change_kind is a sequential scan (91,878,161 scans, 241 rows). The pending
--   unique index and the approved source index do not cover that predicate.
--   pdc_authenticated_email_operation_lines filtered by vehicle_id is a
--   sequential scan. Completions, rejections, Pilbara classification current
--   and history, Pilbara operation history, Pilbara operations and ai_routing
--   already use an index. pdc_standard_operation_hours_20260910 is a function.
-- No function body, schedule or receipt authority changes.
-- Rollback: supabase/rollbacks/20261019230000_helper_lookup_indexes.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF (
    SELECT count(*)
    FROM (VALUES
      ('pdc_tune_operation_change_reviews', 'vehicle_id', 'uuid'),
      ('pdc_tune_operation_change_reviews', 'status', 'text'),
      ('pdc_tune_operation_change_reviews', 'change_kind', 'text'),
      ('pdc_authenticated_email_operation_lines', 'vehicle_id', 'uuid')
    ) expected(rel, col, typ)
    JOIN pg_class c ON c.relname = expected.rel AND c.relkind = 'r'
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = expected.col
      AND a.attnum > 0 AND NOT a.attisdropped
      AND format_type(a.atttypid, a.atttypmod) = expected.typ
  ) IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'reviewed_helper_lookup_columns_changed';
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

CREATE INDEX IF NOT EXISTS pdc_tune_op_change_reviews_vehicle_idx
  ON public.pdc_tune_operation_change_reviews (vehicle_id, status, change_kind);

CREATE INDEX IF NOT EXISTS pdc_authenticated_email_operation_lines_vehicle_idx
  ON public.pdc_authenticated_email_operation_lines (vehicle_id);
