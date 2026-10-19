-- Remove the helper lookup indexes added by
-- supabase/migrations/20261019230000_helper_lookup_indexes.sql.
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

DROP INDEX IF EXISTS public.pdc_tune_op_change_reviews_vehicle_idx;
DROP INDEX IF EXISTS public.pdc_authenticated_email_operation_lines_vehicle_idx;
