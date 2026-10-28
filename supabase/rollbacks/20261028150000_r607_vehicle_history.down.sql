-- Undo r607 (F221): remove the vehicle history reads. Staging cdsmnqxtyyoeoznmbidd only. No data changes.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'vehicle_history_607' AND added_in = 'r607';
DROP FUNCTION IF EXISTS public.get_pdc_vehicle_history_detail_607(uuid);
DROP FUNCTION IF EXISTS public.get_pdc_vehicle_history_607();
DO $$ BEGIN
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r607 undo: pin count'; END IF;
END $$;
