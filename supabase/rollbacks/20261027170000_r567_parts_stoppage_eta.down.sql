-- r567 (F181) undo. Staging cdsmnqxtyyoeoznmbidd only. Run between :02 and :45.
-- Drops the manual parts ETA, its audit, and check parts_stoppage_manual_567.
-- Email parts ETA rows and JITA ETA rows stay. No vehicle row is rewritten.
-- Manual dates typed since this release are removed with the two new tables.
-- Object names stay _564. The check identity is r567 / F181 / sort 338.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r567 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r567 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r567 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)')) IS DISTINCT FROM 'fa275b45be296e9021f9f4dc570f5751' THEN RAISE EXCEPTION 'r567 undo: set is not the r564 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_stoppage_board_564()')) IS DISTINCT FROM '89a8b409650f95c59f459c8b2ff31e60' THEN RAISE EXCEPTION 'r567 undo: board read is not the r564 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_stoppage_history_564(uuid)')) IS DISTINCT FROM 'db31f96870cb5478e5f25426249a7e3e' THEN RAISE EXCEPTION 'r567 undo: history is not the r564 body'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_stoppage_manual_567' AND fault_id='F181' AND sort_order=338 AND added_in='r567') IS DISTINCT FROM 'a4fdf46d7a6f6dbc6ff158e0d138e6f2' THEN RAISE EXCEPTION 'r567 undo: check is not the r567 check'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r567 undo: set_parts_eta changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_jita_eta_board()')) IS DISTINCT FROM '29dcb35956acd61b6a8aa2ca07a80182' THEN RAISE EXCEPTION 'r567 undo: JITA board read changed'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='parts_stoppage_manual_567' AND fault_id='F181' AND sort_order=338 AND added_in='r567';
DROP FUNCTION public.get_pdc_parts_stoppage_history_564(uuid);
DROP FUNCTION public.get_pdc_parts_stoppage_board_564();
DROP FUNCTION public.set_pdc_parts_stoppage_564(uuid, date, text, boolean, boolean);
DROP TABLE public.pdc_parts_stoppage_audit_564;
DROP TABLE public.pdc_parts_stoppage_564;

DO $g$ BEGIN
 IF to_regclass('public.pdc_parts_stoppage_564') IS NOT NULL
    OR to_regclass('public.pdc_parts_stoppage_audit_564') IS NOT NULL
    OR to_regprocedure('public.set_pdc_parts_stoppage_564(uuid,date,text,boolean,boolean)') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r567') THEN RAISE EXCEPTION 'r567 undo: did not fully undo'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r567 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r567 undo: set_parts_eta changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec' THEN RAISE EXCEPTION 'r567 undo: parts ETA board read changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board_v2()')) IS DISTINCT FROM '6a0046123aeb862667dce68884318850' THEN RAISE EXCEPTION 'r567 undo: parts ETA board v2 changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_jita_eta_board()')) IS DISTINCT FROM '29dcb35956acd61b6a8aa2ca07a80182' THEN RAISE EXCEPTION 'r567 undo: JITA board read changed'; END IF;
END $g$;
