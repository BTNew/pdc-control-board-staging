-- Undo r604 (F218): remove pit bookings. This deletes every pit booking and its history.
-- Staging cdsmnqxtyyoeoznmbidd only. Nothing else depends on these objects.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'pit_bookings_604' AND added_in = 'r604';
DROP FUNCTION IF EXISTS public.set_pdc_pit_booking_604(uuid, date, text, boolean, integer);
DROP FUNCTION IF EXISTS public.get_pdc_pit_board_604();
DROP SCHEMA IF EXISTS pdc_pit_private CASCADE;
DO $$ BEGIN
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r604 undo: pin count'; END IF;
END $$;
