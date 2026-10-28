-- Undo r614 (F229): remove tick-all. Staging cdsmnqxtyyoeoznmbidd only. Ticks already made stay (untick per line).
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'qc_override_ticks_614' AND added_in = 'r614';
DROP TRIGGER IF EXISTS vehicles_qc_override_ticks_614 ON public.vehicles;
DROP FUNCTION IF EXISTS public.vehicles_qc_override_ticks_614();
DROP FUNCTION IF EXISTS public.complete_all_panel_lines_614(uuid);
