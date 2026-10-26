-- r549 undo. Drops the visual bay rename. Does not rewrite workshop_bays.
-- Pin count stays 241. No pinned body is restored because none was replaced.
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r549 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r549 undo: pin count is not 241'; END IF;
 IF pg_catalog.to_regprocedure('public.set_workshop_bay_display_name(uuid,integer,text)') IS NULL THEN RAISE EXCEPTION 'r549 undo: rename function missing'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='bay_display_name_visual_only' AND fault_id='F163' AND sort_order=325 AND added_in='r549')<>1 THEN RAISE EXCEPTION 'r549 undo: check missing'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks
 WHERE check_name='bay_display_name_visual_only' AND fault_id='F163' AND sort_order=325 AND added_in='r549';

DROP FUNCTION public.workshop_bay_display_name_probe_549();
DROP FUNCTION public.set_workshop_bay_display_name(pg_catalog.uuid, pg_catalog.int4, pg_catalog.text);
DROP FUNCTION public.workshop_bay_display_label(pg_catalog.uuid);
DROP FUNCTION public.workshop_bay_default_label(pg_catalog.text, pg_catalog.int4);

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r549 undo: pin count changed'; END IF;
 IF pg_catalog.to_regprocedure('public.set_workshop_bay_display_name(uuid,integer,text)') IS NOT NULL THEN RAISE EXCEPTION 'r549 undo: rename function still present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_display_name_visual_only' OR fault_id='F163' OR added_in='r549') THEN RAISE EXCEPTION 'r549 undo: check still present'; END IF;
END $p$;
