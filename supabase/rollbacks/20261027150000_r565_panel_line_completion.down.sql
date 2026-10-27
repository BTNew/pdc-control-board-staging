-- Undo r565 (F179). Staging only. Drops the side-panel line completion tick.
-- Does not change vehicles, bookings, categories, or QC sign-off.
-- Pin count stays 241. Run between :02 and :45.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r565 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r565 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' AND fault_id='F179' AND sort_order=337 AND added_in='r565')<>1 THEN RAISE EXCEPTION 'r565 undo: F179 check is not the r565 row'; END IF;
END $g$;

DROP TRIGGER IF EXISTS pdc_panel_line_completion_history_565_guard ON public.pdc_panel_line_completion_history_565;
DROP FUNCTION IF EXISTS public.set_panel_line_completion_565(uuid, text, boolean);
DROP FUNCTION IF EXISTS public.get_panel_line_completions_565(uuid);
DROP FUNCTION IF EXISTS public.pdc_panel_line_completion_history_guard_565();
DROP TABLE IF EXISTS public.pdc_panel_line_completion_565;
DROP TABLE IF EXISTS public.pdc_panel_line_completion_history_565;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='panel_line_completion_565' AND fault_id='F179' AND sort_order=337 AND added_in='r565';

DO $post$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' OR fault_id='F179' OR added_in='r565' OR sort_order=337) THEN RAISE EXCEPTION 'r565 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_panel_line_completion_565') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_panel_line_completion_history_565') IS NOT NULL THEN RAISE EXCEPTION 'r565 undo: table remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r565 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r565') THEN RAISE EXCEPTION 'r565 undo: a pin remains'; END IF;
END $post$;
