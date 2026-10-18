-- Disposable restore only; never run this on the working board.
BEGIN;
CREATE TEMP TABLE perf_before ON COMMIT DROP AS
 SELECT id,public.pdc_qc_operation_lines_379(id) lines FROM public.vehicles WHERE deleted_at IS NULL;
CREATE TEMP TABLE eligible_before ON COMMIT DROP AS
 SELECT e.* FROM public.workshop_stages s CROSS JOIN LATERAL public.workshop_station_eligibility(s.code) e
 WHERE s.active AND s.planner_enabled AND s.code=e.stage_code;
\ir ../supabase/migrations/20261018095200_overview_operation_projection_performance.sql
DO $verify$
BEGIN
 IF EXISTS(
  (SELECT * FROM eligible_before EXCEPT ALL SELECT * FROM pdc_work_categories_private.all_station_eligibility_20261018())
  UNION ALL
  (SELECT * FROM pdc_work_categories_private.all_station_eligibility_20261018() EXCEPT ALL SELECT * FROM eligible_before)
 ) THEN RAISE EXCEPTION 'eligibility_changed'; END IF;
 IF EXISTS(SELECT 1 FROM perf_before b WHERE b.lines IS DISTINCT FROM public.pdc_qc_operation_lines_379(b.id))
 THEN RAISE EXCEPTION 'canonical_output_changed'; END IF;
END $verify$;
ROLLBACK;
