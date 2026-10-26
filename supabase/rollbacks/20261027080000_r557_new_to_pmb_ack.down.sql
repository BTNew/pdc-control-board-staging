-- Undo r557 (F171). Staging only. Drops the New to PMB acknowledgement and the
-- User Management station assignments. Does not change vehicles.current_location.
-- Pin count stays 241. Run between :02 and :45.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r557 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r557 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_557' AND fault_id='F171' AND sort_order=332 AND added_in='r557')<>1 THEN RAISE EXCEPTION 'r557 undo: F171 check is not the r557 row'; END IF;
END $g$;

DROP TRIGGER IF EXISTS zz_pdc_pmb_arrival_557 ON public.vehicles;
DROP FUNCTION IF EXISTS public.acknowledge_pmb_arrival_557(uuid, text);
DROP FUNCTION IF EXISTS public.list_pmb_arrival_ack_557();
DROP FUNCTION IF EXISTS public.list_user_station_departments_557();
DROP FUNCTION IF EXISTS public.admin_set_user_station_departments_557(text, text[]);
DROP TABLE IF EXISTS public.pdc_pmb_arrival_dept_ack_557;
DROP TABLE IF EXISTS public.pdc_pmb_arrival_557;
DROP TABLE IF EXISTS public.pdc_user_station_departments_557;
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.state_557(uuid, uuid, boolean, uuid, boolean);
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.relevant_stations_557(uuid);
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.capture_557();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.drop_read_caches_557();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.dept_guard_557();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.arrival_guard_557();
DROP SCHEMA IF EXISTS pdc_pmb_ack_private;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='new_to_pmb_ack_557' AND fault_id='F171' AND sort_order=332 AND added_in='r557';

DO $post$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_557' OR fault_id='F171' OR added_in='r557' OR sort_order=332) THEN RAISE EXCEPTION 'r557 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_pmb_arrival_557') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_pmb_arrival_dept_ack_557') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_user_station_departments_557') IS NOT NULL THEN RAISE EXCEPTION 'r557 undo: table remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r557 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r557') THEN RAISE EXCEPTION 'r557 undo: a pin remains'; END IF;
END $post$;
