-- Undo r605 (F219): remove the workshop TV read. Staging cdsmnqxtyyoeoznmbidd only.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'workshop_tv_605' AND added_in = 'r605';
DROP FUNCTION IF EXISTS public.get_pdc_workshop_tv_605();
DO $$ BEGIN
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r605 undo: pin count'; END IF;
END $$;
