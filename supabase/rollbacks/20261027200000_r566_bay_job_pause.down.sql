-- Undo r569 (F183) / sort 340. Staging cdsmnqxtyyoeoznmbidd only.
-- Drops pause_bay_job_for_other_566 and the bay_job_pause_569 check.
-- Does not rewrite workshop_bookings, vehicles, or any pinned function.
-- Pin count stays 241. Clock tick and workshop_move_booking stay on the r559 bodies.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r569 down: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r569 down: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r569 down: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '83a2c8d5ff85b5a295343e5f3ef66ded' THEN RAISE EXCEPTION 'r569 down: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM 'f15067e423da1ce70957e5190c922d50' THEN RAISE EXCEPTION 'r569 down: move body changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.pause_bay_job_for_other_566(uuid,integer,uuid,integer)')) IS DISTINCT FROM '36be5d0f4bc13546911a95adbbf41456' THEN RAISE EXCEPTION 'r569 down: pause body is not the preview'; END IF;
END $g$;

DROP FUNCTION public.pause_bay_job_for_other_566(uuid, integer, uuid, integer);

DELETE FROM pdc_ops.regression_checks
 WHERE check_name = 'bay_job_pause_569'
   AND fault_id = 'F183'
   AND sort_order = 340
   AND added_in = 'r569';

DO $post$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r569 down: pin count changed'; END IF;
 IF pg_catalog.to_regprocedure('public.pause_bay_job_for_other_566(uuid,integer,uuid,integer)') IS NOT NULL THEN RAISE EXCEPTION 'r569 down: function still present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_job_pause_569' OR fault_id='F183' OR added_in='r569') THEN RAISE EXCEPTION 'r569 down: check still present'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '83a2c8d5ff85b5a295343e5f3ef66ded' THEN RAISE EXCEPTION 'r569 down: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM 'f15067e423da1ce70957e5190c922d50' THEN RAISE EXCEPTION 'r569 down: move body changed'; END IF;
END $post$;
