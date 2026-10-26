-- Undo r544 (F158). Staging only. Drops the New to PMB acknowledgement.
-- Does not change vehicles.current_location. Pin count stays 241.
-- Run between :02 and :45. Craig gives the go-live; this file is the undo.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r544 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r544 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_544' AND fault_id='F158' AND sort_order=322 AND added_in='r544')<>1 THEN RAISE EXCEPTION 'r544 undo: F158 check is not the r544 row'; END IF;
END $g$;

DROP TRIGGER IF EXISTS zz_pdc_pmb_arrival_ack_544 ON public.vehicles;
DROP FUNCTION IF EXISTS public.acknowledge_pmb_arrival_544(uuid);
DROP FUNCTION IF EXISTS public.list_pmb_arrival_ack_544();
DROP TABLE IF EXISTS public.pdc_pmb_arrival_ack_544;
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.capture_544();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.append_only_544();
DROP SCHEMA IF EXISTS pdc_pmb_ack_private;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='new_to_pmb_ack_544' AND fault_id='F158' AND sort_order=322 AND added_in='r544';

DO $post$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_544' OR fault_id='F158' OR added_in='r544' OR sort_order=322) THEN RAISE EXCEPTION 'r544 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_pmb_arrival_ack_544') IS NOT NULL THEN RAISE EXCEPTION 'r544 undo: table remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r544 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r544') THEN RAISE EXCEPTION 'r544 undo: a pin remains'; END IF;
END $post$;
