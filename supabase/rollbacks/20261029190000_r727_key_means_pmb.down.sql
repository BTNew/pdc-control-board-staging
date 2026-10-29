-- Roll back r727 (F337). Cars already moved to PMB stay at PMB (their movement rows say r727).
DROP TRIGGER IF EXISTS zzzz_pdc_key_means_pmb_727 ON public.vehicles;
DROP TRIGGER IF EXISTS zzzz_pdc_key_means_pmb_727_log ON public.vehicles;
DROP FUNCTION IF EXISTS public.pdc_key_means_pmb_727();
DROP FUNCTION IF EXISTS public.pdc_key_means_pmb_727_log();
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'key_means_pmb_727';
