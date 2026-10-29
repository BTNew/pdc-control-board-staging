-- Roll back r728 (F338): website Service as a Whole upload.
-- Restore the five edited functions and the manifest constraint from the definitions saved before apply
-- (pdc_ops.release_backups 'r728' if present), then:
DROP FUNCTION IF EXISTS public.revolution_upload_begin_728(text, text, text);
DROP FUNCTION IF EXISTS public.revolution_upload_rows_728(uuid, jsonb);
DROP FUNCTION IF EXISTS public.revolution_upload_finish_728(uuid);
DROP FUNCTION IF EXISTS public.revolution_upload_status_728(uuid);
DROP FUNCTION IF EXISTS public.revolution_prior_decisions_728();
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'website_service_upload_728';
-- The receipt table and helper functions stay until the edited functions no longer call them.
