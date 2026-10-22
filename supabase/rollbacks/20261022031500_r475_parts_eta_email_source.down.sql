-- r475 undo (F88). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Drops check parts_eta_email_source_475, the 2 r475 pins,
-- public.set_parts_eta_from_email and public.get_pdc_parts_eta_board_v2, the 5 source columns on public.pdc_parts_eta and restores the
-- r436 audit action check. Parts ETAs recorded through r475 stay (they are ordinary r436 rows); only their source text (from name,
-- subject, quote, previous stock) is lost. Audit rows written by the r475 wrapper keep their content and are relabelled
-- action 'set_parts_eta' with result.via = 'set_parts_eta_from_email' so the r436 check constraint can come back. Revert the PR as
-- well (the board falls back to get_pdc_parts_eta_board by itself when v2 is missing).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r475 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r475 undo: staging only'; END IF;
 PERFORM set_config('pdc.r475_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r475_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r475_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r475 undo: clock tick does not match its pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)')) IS DISTINCT FROM 'a81b786bfc7868c3217d827933299678'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board_v2()')) IS DISTINCT FROM '6a0046123aeb862667dce68884318850' THEN RAISE EXCEPTION 'r475 undo: functions are not the r475 versions; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r475')<>2
    OR NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_eta_email_source_475' AND added_in='r475') THEN RAISE EXCEPTION 'r475 undo: r475 is not applied'; END IF;
 IF EXISTS(SELECT 1 FROM pg_depend d WHERE d.refobjid IN (to_regprocedure('public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)'),to_regprocedure('public.get_pdc_parts_eta_board_v2()'))
      AND d.deptype='n') THEN RAISE EXCEPTION 'r475 undo: something else depends on r475 functions'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='parts_eta_email_source_475' AND added_in='r475';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r475';
DROP FUNCTION public.get_pdc_parts_eta_board_v2();
DROP FUNCTION public.set_parts_eta_from_email(text,date,text,text,timestamptz,text,text,text,text,integer,text,text,text,text,boolean);
UPDATE public.pdc_parts_eta_audit SET action='set_parts_eta', result=result||jsonb_build_object('via','set_parts_eta_from_email') WHERE action='set_parts_eta_from_email';
ALTER TABLE public.pdc_parts_eta_audit DROP CONSTRAINT pdc_parts_eta_audit_action_check,
  ADD CONSTRAINT pdc_parts_eta_audit_action_check CHECK (action IN ('set_parts_eta','sender_domain_set'));
ALTER TABLE public.pdc_parts_eta DROP COLUMN previous_stock, DROP COLUMN source_quote, DROP COLUMN source_subject, DROP COLUMN source_from_name, DROP COLUMN source_kind;
DO $g$ BEGIN
 IF to_regprocedure('public.get_pdc_parts_eta_board_v2()') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_proc WHERE proname='set_parts_eta_from_email')
    OR EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='pdc_parts_eta' AND column_name IN ('source_kind','source_from_name','source_subject','source_quote','previous_stock'))
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r475') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r475')
 THEN RAISE EXCEPTION 'r475 undo: did not fully undo'; END IF;
 IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.pdc_parts_eta_audit'::regclass AND conname='pdc_parts_eta_audit_action_check')
    IS DISTINCT FROM 'CHECK ((action = ANY (ARRAY[''set_parts_eta''::text, ''sender_domain_set''::text])))' THEN RAISE EXCEPTION 'r475 undo: audit action check not restored'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r475_pins')::int-2 THEN RAISE EXCEPTION 'r475 undo: pin count'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_parts_eta_board()')) IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec' THEN RAISE EXCEPTION 'r475 undo: r436 functions changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r475_tick') THEN RAISE EXCEPTION 'r475 undo: clock tick changed'; END IF;
END $g$;
