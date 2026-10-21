-- r437 undo (F48). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Deletes the r437 regression check row only
-- (r437 changed no function, table or row). Revert the PR as well to bring back the old card-open guard.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r437 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r437 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r437 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r437 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='board_vehicle_dealer_code_card_openable' AND added_in='r437') IS DISTINCT FROM '10e06e3bf42cbc0a4e4b390fb1b2245d' THEN RAISE EXCEPTION 'r437 undo: check is not the r437 version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE added_in='r437')<>1 THEN RAISE EXCEPTION 'r437 undo: expected exactly one r437 check'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='board_vehicle_dealer_code_card_openable' AND added_in='r437';
DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r437' OR check_name='board_vehicle_dealer_code_card_openable') THEN RAISE EXCEPTION 'r437 undo: did not fully undo'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r437 undo: fault_regression_check changed'; END IF;
END $g$;
