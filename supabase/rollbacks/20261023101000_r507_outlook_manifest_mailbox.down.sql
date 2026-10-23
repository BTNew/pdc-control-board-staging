-- r507 undo (F120). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45.
-- Restores the pmbcontroller-only mailbox CHECK on pdc_codex_intake_private.management_email_manifests.
-- Refuses while a non-pmbcontroller mailbox is stored (remove those Outlook manifests first).
-- Drops check outlook_manifest_mailbox_507. Does not change function bodies or the pin list.
-- Does not touch karratha135_intake.management_email_manifests. Does not undo r506.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r507 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r507 undo: staging only'; END IF;
 PERFORM set_config('pdc.r507_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r507_manifest',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')),true);
 PERFORM set_config('pdc.r507_k135def',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='management_email_manifests_mailbox_check'
     AND c.conrelid='karratha135_intake.management_email_manifests'::regclass),true);
 IF current_setting('pdc.r507_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r507 undo: clock tick pin mismatch'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r507 undo: pin count is not 212'; END IF;
 IF current_setting('pdc.r507_manifest') IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r507 undo: service manifest changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r507 undo: auth is not the r505 body'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' AND added_in='r507' AND sort_order=292 AND fault_id='F120') THEN RAISE EXCEPTION 'r507 undo: r507 check is not applied'; END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_codex_intake_private.management_email_manifests
   WHERE mailbox IS NOT NULL AND mailbox IS DISTINCT FROM 'pmbcontroller@gmail.com'
 ) THEN RAISE EXCEPTION 'r507 undo: a non-pmbcontroller mailbox is stored; remove those rows before restoring the mailbox CHECK'; END IF;
 IF current_setting('pdc.r507_k135def') IS NULL
    OR current_setting('pdc.r507_k135def') NOT LIKE '%pmbcontroller@gmail.com%' THEN RAISE EXCEPTION 'r507 undo: karratha135 mailbox CHECK missing'; END IF;
END $g$;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 DROP CONSTRAINT management_email_manifests_mailbox_check;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 ADD CONSTRAINT management_email_manifests_mailbox_check
 CHECK (mailbox = 'pmbcontroller@gmail.com');

DELETE FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' AND added_in='r507';

DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' OR added_in='r507' OR fault_id='F120') THEN RAISE EXCEPTION 'r507 undo: check still present'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='management_email_manifests_mailbox_check'
     AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%pmbcontroller@gmail.com%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%pdc@pmgwa.com.au%'
 ) THEN RAISE EXCEPTION 'r507 undo: pmbcontroller-only CHECK did not return'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_mailbox_check'
       AND c.conrelid='karratha135_intake.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r507_k135def') THEN RAISE EXCEPTION 'r507 undo: karratha135 mailbox CHECK changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r507 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r507 undo: service manifest changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' AND added_in='r506') THEN RAISE EXCEPTION 'r507 undo: r506 check missing'; END IF;
END $g$;
