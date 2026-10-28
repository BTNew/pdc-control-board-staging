-- Undo r612 (F226): remove the vehicle history reads. Staging cdsmnqxtyyoeoznmbidd only. No data changes.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'vehicle_history_612' AND added_in = 'r612';
DROP FUNCTION IF EXISTS public.get_pdc_vehicle_history_detail_612(uuid);
DROP FUNCTION IF EXISTS public.get_pdc_vehicle_history_612();
DO $$ BEGIN
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r612 undo: pin count'; END IF;
END $$;
