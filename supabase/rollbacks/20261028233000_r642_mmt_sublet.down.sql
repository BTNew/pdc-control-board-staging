-- Undo r642 (F257): remove the MMT sublet page objects. Built ticks and their history are deleted.
-- Complete ticks stay on the board (they are ordinary sublet done ticks). Any tick recorded with
-- changed_role 'sublet_provider' is relabelled 'operator' first so the original CHECK can come back.
-- Staging cdsmnqxtyyoeoznmbidd only.
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'mmt_sublet_642' AND added_in = 'r642';
DROP FUNCTION IF EXISTS public.set_pdc_mmt_sublet_tick_642(uuid, text, text, boolean, integer);
DROP FUNCTION IF EXISTS public.get_pdc_mmt_sublet_board_642();
UPDATE public.pdc_sublet_line_ticks_439 SET changed_role = 'operator' WHERE changed_role = 'sublet_provider';
UPDATE public.pdc_sublet_line_ticks_439 SET ticked_role = 'operator' WHERE ticked_role = 'sublet_provider';
ALTER TABLE public.pdc_sublet_line_ticks_439 DROP CONSTRAINT pdc_sublet_line_ticks_439_changed_role_check;
ALTER TABLE public.pdc_sublet_line_ticks_439 ADD CONSTRAINT pdc_sublet_line_ticks_439_changed_role_check
  CHECK (changed_role = ANY (ARRAY['operator'::text, 'administrator'::text, 'fitter'::text]));
DROP SCHEMA IF EXISTS pdc_mmt_private CASCADE;
DO $$ BEGIN
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r642 undo: pin count'; END IF;
END $$;
