-- Undo r578 (F192). Staging only. Drops the station-icon completion read and the controller override.
-- Does not change vehicles, bookings, panel ticks, QC sign-off, or job cards.
-- Pin count stays 241. Run between :02 and :45.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r578 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r578 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='station_icon_completion_578' AND fault_id='F192' AND sort_order=350 AND added_in='r578')<>1 THEN RAISE EXCEPTION 'r578 undo: F192 check is not the r578 row'; END IF;
END $g$;

DROP TRIGGER IF EXISTS pdc_station_completion_history_578_guard ON public.pdc_station_completion_history_578;
DROP FUNCTION IF EXISTS public.set_station_completion_override_578(uuid, text, boolean);
DROP FUNCTION IF EXISTS public.list_station_icon_completion_578(uuid[]);
DROP FUNCTION IF EXISTS pdc_work_categories_private.station_icon_completion_578(uuid[]);
DROP FUNCTION IF EXISTS public.pdc_station_completion_history_guard_578();
DROP TABLE IF EXISTS public.pdc_station_completion_override_578;
DROP TABLE IF EXISTS public.pdc_station_completion_history_578;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='station_icon_completion_578' AND fault_id='F192' AND sort_order=350 AND added_in='r578';

DO $post$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='station_icon_completion_578' OR fault_id='F192' OR added_in='r578' OR sort_order=350) THEN RAISE EXCEPTION 'r578 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_station_completion_override_578') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_station_completion_history_578') IS NOT NULL THEN RAISE EXCEPTION 'r578 undo: table remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r578 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r578') THEN RAISE EXCEPTION 'r578 undo: a pin remains'; END IF;
END $post$;
