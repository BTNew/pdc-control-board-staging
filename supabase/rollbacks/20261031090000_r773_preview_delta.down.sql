-- Undo r773 (F375): drop the two read-only delta RPCs and check 488. The edge function falls back to the board compare when they are missing.
DROP FUNCTION IF EXISTS public.revolution_upload_delta_773(jsonb);
DROP FUNCTION IF EXISTS public.revolution_upload_delta_compare_773(jsonb);
DELETE FROM pdc_ops.regression_checks WHERE added_in = 'r773';
