-- r436 undo (F47). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Drops the r436 check, the 3 pins, the 3 functions and the
-- 3 new tables (pdc_parts_eta, pdc_parts_eta_sender_domains, pdc_parts_eta_audit). Any parts ETAs recorded since are lost with them
-- (PMB Email keeps the source emails and can re-import after a re-apply; set_parts_eta is idempotent on the message id).
-- r436 changed no other function, table or row. Revert the PR as well so the board stops asking for parts ETAs.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r436 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r436 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r436 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT count(*) FROM (VALUES ('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)','88d31cbd6ca5ddd372e3143d5f8c013f'),('public.get_pdc_parts_eta_board()','decd9053241b3fe8ede99bd231ad98ec'),('public.set_pdc_parts_eta_sender_domain(text,boolean,text)','eb44898f34bca89afc1ee5e129a04928')) e(s,m)
     JOIN pg_proc p ON p.oid=to_regprocedure(e.s) WHERE md5(p.prosrc)=e.m)<>3 THEN RAISE EXCEPTION 'r436 undo: functions are not the r436 versions; not undoing over unknown changes'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_eta_rpc_contract' AND added_in='r436') IS DISTINCT FROM '0854a63912b8bbf0ed50635e535e4a0e' THEN RAISE EXCEPTION 'r436 undo: check is not the r436 version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r436')<>3 THEN RAISE EXCEPTION 'r436 undo: expected exactly three r436 pins'; END IF;
 IF EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid IN (to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)'),to_regprocedure('public.get_pdc_parts_eta_board()'),to_regprocedure('public.set_pdc_parts_eta_sender_domain(text,boolean,text)')) AND d.deptype='n')
    OR EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid IN (to_regclass('public.pdc_parts_eta'),to_regclass('public.pdc_parts_eta_sender_domains'),to_regclass('public.pdc_parts_eta_audit'))
      AND d.deptype='n' AND d.classid='pg_rewrite'::regclass) THEN RAISE EXCEPTION 'r436 undo: something else depends on r436 objects'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='parts_eta_rpc_contract' AND added_in='r436';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r436';
DROP FUNCTION public.set_pdc_parts_eta_sender_domain(text,boolean,text);
DROP FUNCTION public.get_pdc_parts_eta_board();
DROP FUNCTION public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamptz);
DROP TABLE public.pdc_parts_eta_audit;
DROP TABLE public.pdc_parts_eta;
DROP TABLE public.pdc_parts_eta_sender_domains;
DO $g$ BEGIN
 IF to_regclass('public.pdc_parts_eta') IS NOT NULL OR to_regclass('public.pdc_parts_eta_sender_domains') IS NOT NULL OR to_regclass('public.pdc_parts_eta_audit') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc WHERE proname IN ('set_parts_eta','get_pdc_parts_eta_board','set_pdc_parts_eta_sender_domain'))
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r436') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r436')
 THEN RAISE EXCEPTION 'r436 undo: did not fully undo'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r436 undo: clock tick changed'; END IF;
END $g$;
