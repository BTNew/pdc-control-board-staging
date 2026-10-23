-- r509 undo (F112). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45.
-- Restores the public sales snapshot wrappers to snapshot_with_autocare / board_snapshot_with_autocare.
-- Drops station_icons, attach_station_icons, sales_snapshot_509, sales_board_snapshot_509,
-- their four pins, and check sales_station_icons_509. Does not change r420 snapshot bodies.
-- Does not undo r507 or the merged r508 (F121) sales receipt check. Does not touch workshop_clock_tick.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r509 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r509 undo: staging only'; END IF;
 PERFORM set_config('pdc.r509_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 IF current_setting('pdc.r509_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r509 undo: clock tick pin mismatch'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 216 THEN RAISE EXCEPTION 'r509 undo: pin count is not 216'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r509') IS DISTINCT FROM 4 THEN RAISE EXCEPTION 'r509 undo: expected 4 r509 pins'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_station_icons_509' AND added_in='r509' AND sort_order=294 AND fault_id='F112') THEN RAISE EXCEPTION 'r509 undo: r509 check is not applied'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')) IS DISTINCT FROM 'e57e0904890225fad39c5e41ee1b14ef' THEN RAISE EXCEPTION 'r509 undo: r420 sales snapshot changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.board_visibility_source_snapshot(boolean)')) IS DISTINCT FROM '37a9d2d92ce5c34e8617a0058cfd3e4f' THEN RAISE EXCEPTION 'r509 undo: r420 board snapshot changed'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_broome_sales_snapshot()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='pg_catalog','pdc_sales_private'
AS $fn$ SELECT pdc_sales_private.snapshot_with_autocare(); $fn$;

CREATE OR REPLACE FUNCTION public.get_broome_sales_board_snapshot()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog
AS $fn$ SELECT pdc_sales_private.board_snapshot_with_autocare(); $fn$;

DROP FUNCTION IF EXISTS pdc_sales_private.sales_snapshot_509();
DROP FUNCTION IF EXISTS pdc_sales_private.sales_board_snapshot_509();
DROP FUNCTION IF EXISTS pdc_sales_private.attach_station_icons(jsonb);
DROP FUNCTION IF EXISTS pdc_sales_private.station_icons(uuid,jsonb,jsonb,jsonb,jsonb,text);

DELETE FROM pdc_ops.expected_function_md5 WHERE release='r509';
DELETE FROM pdc_ops.regression_checks WHERE check_name='sales_station_icons_509' AND added_in='r509';

DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_station_icons_509' OR added_in='r509' OR fault_id='F112') THEN RAISE EXCEPTION 'r509 undo: check still present'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r509') THEN RAISE EXCEPTION 'r509 undo: pins still present'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r509 undo: pin count is not 212'; END IF;
 IF to_regprocedure('pdc_sales_private.station_icons(uuid,jsonb,jsonb,jsonb,jsonb,text)') IS NOT NULL
    OR to_regprocedure('pdc_sales_private.attach_station_icons(jsonb)') IS NOT NULL
    OR to_regprocedure('pdc_sales_private.sales_snapshot_509()') IS NOT NULL
    OR to_regprocedure('pdc_sales_private.sales_board_snapshot_509()') IS NOT NULL THEN RAISE EXCEPTION 'r509 undo: functions still present'; END IF;
 IF (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_snapshot()')) NOT LIKE '%snapshot_with_autocare%'
    OR (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_snapshot()')) LIKE '%sales_snapshot_509%' THEN RAISE EXCEPTION 'r509 undo: sales wrapper not restored'; END IF;
 IF (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_board_snapshot()')) NOT LIKE '%board_snapshot_with_autocare%'
    OR (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_board_snapshot()')) LIKE '%sales_board_snapshot_509%' THEN RAISE EXCEPTION 'r509 undo: board wrapper not restored'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_snapshot()')) IS NOT FALSE THEN RAISE EXCEPTION 'r509 undo: sales wrapper must stay invoker'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_board_snapshot()')) IS NOT FALSE THEN RAISE EXCEPTION 'r509 undo: board wrapper must stay invoker'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r509_tick') THEN RAISE EXCEPTION 'r509 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.visibility_source_snapshot(boolean)')) IS DISTINCT FROM 'e57e0904890225fad39c5e41ee1b14ef' THEN RAISE EXCEPTION 'r509 undo: r420 sales snapshot changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.board_visibility_source_snapshot(boolean)')) IS DISTINCT FROM '37a9d2d92ce5c34e8617a0058cfd3e4f' THEN RAISE EXCEPTION 'r509 undo: r420 board snapshot changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' AND added_in='r507') THEN RAISE EXCEPTION 'r509 undo: r507 check missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508' AND added_in='r508' AND sort_order=293 AND fault_id='F121') THEN RAISE EXCEPTION 'r509 undo: r508 receipt check missing'; END IF;
END $g$;
