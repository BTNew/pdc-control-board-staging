-- r514 undo (F128). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45.
-- Restores the hex {10,40} message-id CHECK and the pmbcontroller-only mailbox CHECK on
-- public.pdc_parts_completion_email_confirmations. Refuses while a stored row would fail those
-- old checks (delete or revoke the Outlook / pdc@ confirmation first).
-- Restores record_pdc_person_parts_complete_20260913 and mark_pdc_parts_complete from the
-- preimage saved by the up migration (md5 77887b5450188a86acf0f0da34193e11 and
-- 82d890802677a2ac93942d3f7b7bcd27). Drops outlook_parts_completion_514 and the preimage table.
-- Does not change is_pdc_role, the wayne recorder, parts flags, Karratha 135, or the pin list.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r514 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r514 undo: staging only'; END IF;
 PERFORM set_config('pdc.r514_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r514_k135id',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
     AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass),true);
 PERFORM set_config('pdc.r514_k135mb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
     AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass),true);
 IF current_setting('pdc.r514_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r514 undo: clock tick pin mismatch'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 225 THEN RAISE EXCEPTION 'r514 undo: pin count is not 225'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_pdc_role(public.pdc_role)'::regprocedure) IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r514 undo: is_pdc_role changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND sort_order=301 AND fault_id='F128') THEN RAISE EXCEPTION 'r514 undo: r514 check is not applied'; END IF;
 IF to_regclass('pdc_ops.r514_parts_completion_prev') IS NULL THEN RAISE EXCEPTION 'r514 undo: preimage table missing'; END IF;
 IF (SELECT md5(prosrc) FROM pdc_ops.r514_parts_completion_prev WHERE signature='person') IS DISTINCT FROM '77887b5450188a86acf0f0da34193e11' THEN RAISE EXCEPTION 'r514 undo: person preimage is not the r514 tip'; END IF;
 IF (SELECT md5(prosrc) FROM pdc_ops.r514_parts_completion_prev WHERE signature='mark') IS DISTINCT FROM '82d890802677a2ac93942d3f7b7bcd27' THEN RAISE EXCEPTION 'r514 undo: mark preimage is not the r514 tip'; END IF;
 IF EXISTS (
   SELECT 1 FROM public.pdc_parts_completion_email_confirmations
   WHERE gmail_message_id !~ '^[a-f0-9]{10,40}$' OR mailbox IS DISTINCT FROM 'pmbcontroller@gmail.com'
 ) THEN RAISE EXCEPTION 'r514 undo: a stored confirmation is outside the old checks; remove those rows before restoring them'; END IF;
 IF current_setting('pdc.r514_k135id') IS NULL OR current_setting('pdc.r514_k135id') NOT LIKE '%^[a-f0-9]{10,40}$%' THEN RAISE EXCEPTION 'r514 undo: karratha message-id CHECK missing'; END IF;
 IF current_setting('pdc.r514_k135mb') IS NULL OR current_setting('pdc.r514_k135mb') NOT LIKE '%pmbcontroller@gmail.com%' THEN RAISE EXCEPTION 'r514 undo: karratha mailbox CHECK missing'; END IF;
END $g$;

ALTER TABLE public.pdc_parts_completion_email_confirmations
 DROP CONSTRAINT pdc_parts_completion_email_confirmations_gmail_message_id_check;
ALTER TABLE public.pdc_parts_completion_email_confirmations
 ADD CONSTRAINT pdc_parts_completion_email_confirmations_gmail_message_id_check
 CHECK (gmail_message_id ~ '^[a-f0-9]{10,40}$');

ALTER TABLE public.pdc_parts_completion_email_confirmations
 DROP CONSTRAINT pdc_parts_completion_email_confirmations_mailbox_check;
ALTER TABLE public.pdc_parts_completion_email_confirmations
 ADD CONSTRAINT pdc_parts_completion_email_confirmations_mailbox_check
 CHECK (mailbox = 'pmbcontroller@gmail.com');

DO $u$ DECLARE src text; sec boolean; cfg text[]; BEGIN
 SELECT prosrc, prosecdef, proconfig INTO STRICT src, sec, cfg FROM pdc_ops.r514_parts_completion_prev WHERE signature='person';
 IF md5(src) IS DISTINCT FROM '77887b5450188a86acf0f0da34193e11' OR sec IS TRUE THEN RAISE EXCEPTION 'r514 undo: person preimage rejected'; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.record_pdc_person_parts_complete_20260913(p_stock text, p_gmail_message_id text, p_received_at timestamp with time zone, p_subject text, p_confirmation_text text, p_evidence_sha256 text, p_authentication jsonb)'
  || ' RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''pg_catalog'', ''public'', ''pdc_codex_intake_private'' AS ' || quote_literal(src);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM '77887b5450188a86acf0f0da34193e11' THEN RAISE EXCEPTION 'r514 undo: person body did not restore'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS TRUE THEN RAISE EXCEPTION 'r514 undo: person became security definer'; END IF;
 IF (SELECT proconfig FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM cfg THEN RAISE EXCEPTION 'r514 undo: person search_path did not restore'; END IF;

 SELECT prosrc, prosecdef, proconfig INTO STRICT src, sec, cfg FROM pdc_ops.r514_parts_completion_prev WHERE signature='mark';
 IF md5(src) IS DISTINCT FROM '82d890802677a2ac93942d3f7b7bcd27' OR sec IS NOT TRUE THEN RAISE EXCEPTION 'r514 undo: mark preimage rejected'; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.mark_pdc_parts_complete(p_vehicle_id uuid, p_expected_version integer)'
  || ' RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS ' || quote_literal(src);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS DISTINCT FROM '82d890802677a2ac93942d3f7b7bcd27' THEN RAISE EXCEPTION 'r514 undo: mark body did not restore'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS NOT TRUE THEN RAISE EXCEPTION 'r514 undo: mark lost security definer'; END IF;
 IF (SELECT proconfig FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS DISTINCT FROM cfg THEN RAISE EXCEPTION 'r514 undo: mark search_path did not restore'; END IF;
END $u$;

REVOKE ALL ON FUNCTION public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.mark_pdc_parts_complete(uuid,integer) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_pdc_parts_complete(uuid,integer) TO authenticated;

DELETE FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128';
DROP TABLE pdc_ops.r514_parts_completion_prev;

DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' OR added_in='r514' OR fault_id='F128') THEN RAISE EXCEPTION 'r514 undo: check still present'; END IF;
 IF to_regclass('pdc_ops.r514_parts_completion_prev') IS NOT NULL THEN RAISE EXCEPTION 'r514 undo: preimage table still present'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
     AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%^[a-f0-9]{10,40}$%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%BETWEEN 8 AND 512%'
 ) THEN RAISE EXCEPTION 'r514 undo: old message-id CHECK did not return'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
     AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%pmbcontroller@gmail.com%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%pdc@pmgwa.com.au%'
 ) THEN RAISE EXCEPTION 'r514 undo: old mailbox CHECK did not return'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
       AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r514_k135id') THEN RAISE EXCEPTION 'r514 undo: karratha message-id CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
       AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r514_k135mb') THEN RAISE EXCEPTION 'r514 undo: karratha mailbox CHECK changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 225 THEN RAISE EXCEPTION 'r514 undo: pin count changed'; END IF;
 IF has_function_privilege('service_role','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE') THEN RAISE EXCEPTION 'r514 undo: mark grants changed'; END IF;
END $g$;
