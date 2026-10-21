-- r446 (F59) undo: removes approve_pdc_new_vehicle_review_446, the r446 check and its 3 pins (165 pins after).
-- Categories already recorded through it stay: they are ordinary line_overrides, the same as choices made in the vehicle
-- drop-down, and they are listed by audit_events metadata source 'r446_new_vehicle_review_approval'. BEFORE running, export
-- that list to release_log/r446_dept138_review_stations/ if wanted. Revert the PR as well (or the review page's Approve
-- returns an RPC-not-found error); approvals themselves are never reverted.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r446 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r446 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r446 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r446 undo: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r446' AND md5(p.prosrc)=e.prosrc_md5)<>3 THEN RAISE EXCEPTION 'r446 undo: r446 functions are not the pinned versions; not undoing over unknown changes'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='dept138_review_categories_446' AND added_in='r446') THEN RAISE EXCEPTION 'r446 undo: check missing (not applied?)'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>168 THEN RAISE EXCEPTION 'r446 undo: expected 168 pins'; END IF;
END $g$;
DROP FUNCTION public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid);
DELETE FROM pdc_ops.regression_checks WHERE check_name='dept138_review_categories_446' AND added_in='r446';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r446';
DO $g$ BEGIN
 IF to_regprocedure('public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r446 undo: function left behind'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r446') OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>165
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r446') THEN RAISE EXCEPTION 'r446 undo: pins / check not restored'; END IF;
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'f099baf746f35b500389749ac844bc2f' THEN RAISE EXCEPTION 'r446 undo: approve changed'; END IF;
END $g$;
