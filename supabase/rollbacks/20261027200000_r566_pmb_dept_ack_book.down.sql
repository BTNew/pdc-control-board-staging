-- Undo r574 (F188) / sort 345. Staging only. Removes the regression check.
-- Does not match service_whole_archive_570 (F184, sort 341, release r570).
-- Leaves the r557 acknowledgement rows, the r562 key gate, and every booking
-- function where they are. Does not change vehicles.current_location.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r574 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r574 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='pmb_dept_ack_book_574' AND fault_id='F188' AND sort_order=345 AND added_in='r574')<>1 THEN RAISE EXCEPTION 'r574 undo: F188 check is not the r574 row'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='pmb_dept_ack_book_574' AND fault_id='F188' AND sort_order=345 AND added_in='r574';

DO $post$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_dept_ack_book_574' OR fault_id='F188' OR added_in='r574' OR sort_order=345) THEN RAISE EXCEPTION 'r574 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_pmb_arrival_dept_ack_557') IS NULL THEN RAISE EXCEPTION 'r574 undo: acknowledgement table was removed'; END IF;
 IF pg_catalog.to_regclass('public.pdc_vehicle_key_assigned_562') IS NULL THEN RAISE EXCEPTION 'r574 undo: key table was removed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r574 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r574') THEN RAISE EXCEPTION 'r574 undo: a pin remains'; END IF;
END $post$;
