-- r506 undo (F119). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45.
-- Restores the hex-only CHECK on pdc_codex_intake_private.management_email_manifests.
-- Refuses while a non-hex message id is stored (delete or revoke those Outlook manifests first).
-- Drops check outlook_manifest_message_id_506. Does not change function bodies or the pin list.
-- Does not touch karratha135_intake.management_email_manifests.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r506 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r506 undo: staging only'; END IF;
 PERFORM set_config('pdc.r506_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r506_manifest',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')),true);
 PERFORM set_config('pdc.r506_k135def',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='management_email_manifests_gmail_message_id_check'
     AND c.conrelid='karratha135_intake.management_email_manifests'::regclass),true);
 IF current_setting('pdc.r506_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r506 undo: clock tick pin mismatch'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r506 undo: pin count is not 212'; END IF;
 IF current_setting('pdc.r506_manifest') IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r506 undo: service manifest changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r506 undo: auth is not the r505 body'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' AND added_in='r506' AND sort_order=291 AND fault_id='F119') THEN RAISE EXCEPTION 'r506 undo: r506 check is not applied'; END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_codex_intake_private.management_email_manifests
   WHERE gmail_message_id IS NOT NULL AND gmail_message_id !~ '^[a-f0-9]+$'
 ) THEN RAISE EXCEPTION 'r506 undo: Outlook (non-hex) manifest ids are stored; remove those rows before restoring the hex CHECK'; END IF;
 IF current_setting('pdc.r506_k135def') IS NULL
    OR current_setting('pdc.r506_k135def') NOT LIKE '%^[a-f0-9]+$%' THEN RAISE EXCEPTION 'r506 undo: karratha135 manifest CHECK missing'; END IF;
END $g$;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 DROP CONSTRAINT management_email_manifests_gmail_message_id_check;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 ADD CONSTRAINT management_email_manifests_gmail_message_id_check
 CHECK (gmail_message_id ~ '^[a-f0-9]+$');

DELETE FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' AND added_in='r506';

DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' OR added_in='r506' OR fault_id='F119') THEN RAISE EXCEPTION 'r506 undo: check still present'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='management_email_manifests_gmail_message_id_check'
     AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%^[a-f0-9]+$%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%BETWEEN 8 AND 512%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%>= 8%'
 ) THEN RAISE EXCEPTION 'r506 undo: hex CHECK did not return'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_gmail_message_id_check'
       AND c.conrelid='karratha135_intake.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r506_k135def') THEN RAISE EXCEPTION 'r506 undo: karratha135 manifest CHECK changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r506 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r506 undo: service manifest changed'; END IF;
END $g$;
