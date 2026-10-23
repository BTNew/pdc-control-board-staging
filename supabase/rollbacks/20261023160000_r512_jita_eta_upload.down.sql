-- r512 undo (F128). Staging cdsmnqxtyyoeoznmbidd only. Only if 20261023160000_r512_jita_eta_upload.sql was applied.
-- Drops the JITA paste tables, functions, pin and check. Does not change set_parts_eta or the email parts ETA rows.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r512 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.jita_eta_parse_512(text)')) IS DISTINCT FROM '492ab29757e9ba25674f67f76b206b1e'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.import_jita_eta_512(text,boolean)')) IS DISTINCT FROM 'daaa7f839a33bf7719d282f749896aa7'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_jita_eta_board()')) IS DISTINCT FROM '2d0930074c9f9372aed02901964bb4e9'
  THEN RAISE EXCEPTION 'r512 undo: functions are not the r512 versions; not undoing over unknown changes'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec'
  THEN RAISE EXCEPTION 'r512 undo: parts ETA functions are not the r436 bodies'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='jita_eta_upload_512' AND added_in='r512' AND fault_id='F128';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r512' AND signature IN (
 'public.jita_eta_parse_512(text)',
 'public.import_jita_eta_512(text,boolean)',
 'public.get_pdc_jita_eta_board()');

DROP FUNCTION public.import_jita_eta_512(text, boolean);
DROP FUNCTION public.jita_eta_parse_512(text);
DROP FUNCTION public.get_pdc_jita_eta_board();
DROP TABLE public.pdc_jita_eta_audit;
DROP TABLE public.pdc_jita_eta;

DO $g$ BEGIN
 IF to_regprocedure('public.jita_eta_parse_512(text)') IS NOT NULL
    OR to_regprocedure('public.import_jita_eta_512(text,boolean)') IS NOT NULL
    OR to_regprocedure('public.get_pdc_jita_eta_board()') IS NOT NULL
    OR to_regclass('public.pdc_jita_eta') IS NOT NULL
    OR to_regclass('public.pdc_jita_eta_audit') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r512')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='jita_eta_upload_512' OR fault_id='F128')
  THEN RAISE EXCEPTION 'r512 undo: JITA objects remain'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec'
  THEN RAISE EXCEPTION 'r512 undo: parts ETA functions changed'; END IF;
END $g$;
