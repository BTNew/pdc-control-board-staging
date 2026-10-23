-- r515 undo (F129). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45.
-- Restores record_pdc_person_parts_complete_20260913 from the preimage (md5 eb02f76ec94cd0b6c824a18660432afa).
-- Restores the r514 regression check text (md5 cd2ee86341370cb6b214456ed7da5640) and drops outlook_internal_parts_auth_515.
-- Does not change mark_pdc_parts_complete (f5bdb212b439fd37adb73860c5e5d4d3), the confirmation CHECKs, Karratha, is_pdc_role,
-- the wayne recorder, parts flags, or the pin list. Stored pdc@ confirmations are left in place.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r515 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r515 undo: staging only'; END IF;
 PERFORM set_config('pdc.r515_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r515_k135id',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
     AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass),true);
 PERFORM set_config('pdc.r515_k135mb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
     AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass),true);
 IF current_setting('pdc.r515_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r515 undo: clock tick pin mismatch'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 225 THEN RAISE EXCEPTION 'r515 undo: pin count is not 225'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_pdc_role(public.pdc_role)'::regprocedure) IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r515 undo: is_pdc_role changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM '8ddb1477beeb94c7879c4021cccf1d40' THEN RAISE EXCEPTION 'r515 undo: person body is not r515'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS DISTINCT FROM 'f5bdb212b439fd37adb73860c5e5d4d3' THEN RAISE EXCEPTION 'r515 undo: mark body is not the r514 body'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' AND added_in='r515' AND sort_order=302 AND fault_id='F129') IS DISTINCT FROM 'ece98352be4126d5fd4ad2707157cae2' THEN RAISE EXCEPTION 'r515 undo: r515 check is not the preview text'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301) IS DISTINCT FROM 'd876e9bd42a929e659c811c0c9e6c2ec' THEN RAISE EXCEPTION 'r515 undo: r514 check is not the re-pinned text'; END IF;
 IF to_regclass('pdc_ops.r515_person_parts_prev') IS NULL THEN RAISE EXCEPTION 'r515 undo: preimage table missing'; END IF;
 IF (SELECT md5(body) FROM pdc_ops.r515_person_parts_prev WHERE signature='person') IS DISTINCT FROM 'eb02f76ec94cd0b6c824a18660432afa' THEN RAISE EXCEPTION 'r515 undo: person preimage is not r514'; END IF;
 IF (SELECT md5(body) FROM pdc_ops.r515_person_parts_prev WHERE signature='check514') IS DISTINCT FROM 'cd2ee86341370cb6b214456ed7da5640' THEN RAISE EXCEPTION 'r515 undo: r514 check preimage is not the live text'; END IF;
 IF (SELECT prosecdef FROM pdc_ops.r515_person_parts_prev WHERE signature='person') IS TRUE THEN RAISE EXCEPTION 'r515 undo: person preimage is security definer'; END IF;
 IF current_setting('pdc.r515_k135id') IS NULL OR current_setting('pdc.r515_k135id') NOT LIKE '%^[a-f0-9]{10,40}$%' THEN RAISE EXCEPTION 'r515 undo: karratha message-id CHECK missing'; END IF;
 IF current_setting('pdc.r515_k135mb') IS NULL OR current_setting('pdc.r515_k135mb') NOT LIKE '%pmbcontroller@gmail.com%' OR current_setting('pdc.r515_k135mb') LIKE '%pdc@pmgwa.com.au%' THEN RAISE EXCEPTION 'r515 undo: karratha mailbox CHECK changed'; END IF;
END $g$;

DO $u$ DECLARE src text; sec boolean; cfg text[]; BEGIN
 SELECT body, prosecdef, proconfig INTO STRICT src, sec, cfg FROM pdc_ops.r515_person_parts_prev WHERE signature='person';
 IF md5(src) IS DISTINCT FROM 'eb02f76ec94cd0b6c824a18660432afa' OR sec IS TRUE THEN RAISE EXCEPTION 'r515 undo: person preimage rejected'; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.record_pdc_person_parts_complete_20260913(p_stock text, p_gmail_message_id text, p_received_at timestamp with time zone, p_subject text, p_confirmation_text text, p_evidence_sha256 text, p_authentication jsonb)'
  || ' RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''pg_catalog'', ''public'', ''pdc_codex_intake_private'' AS ' || quote_literal(src);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM 'eb02f76ec94cd0b6c824a18660432afa' THEN RAISE EXCEPTION 'r515 undo: person body did not restore'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS TRUE THEN RAISE EXCEPTION 'r515 undo: person became security definer'; END IF;
 IF (SELECT proconfig FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM cfg THEN RAISE EXCEPTION 'r515 undo: person search_path did not restore'; END IF;
END $u$;

REVOKE ALL ON FUNCTION public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;

UPDATE pdc_ops.regression_checks AS c
SET check_sql = p.body
FROM pdc_ops.r515_person_parts_prev AS p
WHERE c.check_name='outlook_parts_completion_514'
  AND c.added_in='r514'
  AND c.fault_id='F128'
  AND c.sort_order=301
  AND p.signature='check514'
  AND md5(p.body)='cd2ee86341370cb6b214456ed7da5640';

DELETE FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' AND added_in='r515' AND fault_id='F129' AND sort_order=302;
DROP TABLE pdc_ops.r515_person_parts_prev;

DO $g$ DECLARE y record; BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' OR added_in='r515' OR fault_id='F129') THEN RAISE EXCEPTION 'r515 undo: r515 check still present'; END IF;
 IF to_regclass('pdc_ops.r515_person_parts_prev') IS NOT NULL THEN RAISE EXCEPTION 'r515 undo: preimage table still present'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301) IS DISTINCT FROM 'cd2ee86341370cb6b214456ed7da5640' THEN RAISE EXCEPTION 'r515 undo: r514 check text did not return'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM 'eb02f76ec94cd0b6c824a18660432afa' THEN RAISE EXCEPTION 'r515 undo: person md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS DISTINCT FROM 'f5bdb212b439fd37adb73860c5e5d4d3' THEN RAISE EXCEPTION 'r515 undo: mark md5 changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
       AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r515_k135id') THEN RAISE EXCEPTION 'r515 undo: karratha message-id CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
       AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r515_k135mb') THEN RAISE EXCEPTION 'r515 undo: karratha mailbox CHECK changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 225 THEN RAISE EXCEPTION 'r515 undo: pin count changed'; END IF;
 IF has_function_privilege('service_role','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE') THEN RAISE EXCEPTION 'r515 undo: mark grants changed'; END IF;
 IF has_function_privilege('service_role','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
    OR has_function_privilege('anon','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'r515 undo: person grants changed'; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_parts_completion_514';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r515 undo: r514 check failed: %', y; END IF;
END $g$;
