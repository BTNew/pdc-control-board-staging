-- r600 (F214) undo. Staging cdsmnqxtyyoeoznmbidd only.
-- Removes the two r600 checks and the resume push helper.
-- Restoring the previous clock and resume bodies is the reverse of
-- supabase/migrations/20261028120000_r600_clock_resume.sql.
-- It does not rewrite booking rows and it does not turn the cross-bay guard on.

SET LOCAL lock_timeout = '8s';

DO $undo600$
DECLARE n integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN
    RAISE EXCEPTION 'r600 undo: staging only';
  END IF;
  DELETE FROM pdc_ops.regression_checks
  WHERE check_name IN ('no_overlapping_active_bookings_600', 'resume_cascade_600')
    AND added_in = 'r600';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 2 THEN
    RAISE EXCEPTION 'r600 undo: checks not removed';
  END IF;
  DROP FUNCTION IF EXISTS pdc_ops.push_later_planned_in_bay_600(uuid, uuid, timestamptz, timestamptz, jsonb);
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
    RAISE EXCEPTION 'r600 undo: pin count';
  END IF;
END $undo600$;
