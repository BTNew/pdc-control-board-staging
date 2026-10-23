-- r508 undo (F121). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45.
-- Restores CHECK (gmail_message_id ~ '^[A-Za-z0-9_-]{6,128}$') on pdc_sales_private.sales_accessory_receipts.
-- Refuses while a stored id is outside that old pattern (delete or revoke those Outlook receipts first).
-- Drops check outlook_sales_receipt_message_id_508. Does not change function bodies or the pin list.
-- Does not undo r505, r506 or r507. Does not touch Karratha 135, authorizations, parts receipts,
-- parts-completion confirmations, or service manifests.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r508 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r508 undo: staging only'; END IF;
 PERFORM set_config('pdc.r508_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r508_sales',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')),true);
 PERFORM set_config('pdc.r508_k135id',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='management_email_manifests_gmail_message_id_check'
     AND c.conrelid='karratha135_intake.management_email_manifests'::regclass),true);
 PERFORM set_config('pdc.r508_k135mb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='management_email_manifests_mailbox_check'
     AND c.conrelid='karratha135_intake.management_email_manifests'::regclass),true);
 PERFORM set_config('pdc.r508_manid',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='management_email_manifests_gmail_message_id_check'
     AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass),true);
 PERFORM set_config('pdc.r508_manmb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='management_email_manifests_mailbox_check'
     AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass),true);
 IF current_setting('pdc.r508_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r508 undo: clock tick pin mismatch'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r508 undo: pin count is not 212'; END IF;
 IF current_setting('pdc.r508_sales') IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3' THEN RAISE EXCEPTION 'r508 undo: sales import changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r508 undo: service manifest changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r508 undo: auth is not the r505 body'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508' AND added_in='r508' AND sort_order=293 AND fault_id='F121') THEN RAISE EXCEPTION 'r508 undo: r508 check is not applied'; END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_sales_private.sales_accessory_receipts
   WHERE gmail_message_id IS NOT NULL AND gmail_message_id !~ '^[A-Za-z0-9_-]{6,128}$'
 ) THEN RAISE EXCEPTION 'r508 undo: a stored id is outside the old pattern; remove those rows before restoring the charset CHECK'; END IF;
 IF current_setting('pdc.r508_k135id') IS NULL
    OR current_setting('pdc.r508_k135id') NOT LIKE '%^[a-f0-9]+$%' THEN RAISE EXCEPTION 'r508 undo: karratha135 manifest CHECK missing'; END IF;
 IF current_setting('pdc.r508_k135mb') IS NULL
    OR current_setting('pdc.r508_k135mb') NOT LIKE '%pmbcontroller@gmail.com%' THEN RAISE EXCEPTION 'r508 undo: karratha135 mailbox CHECK missing'; END IF;
END $g$;

ALTER TABLE pdc_sales_private.sales_accessory_receipts
 DROP CONSTRAINT sales_accessory_receipts_gmail_message_id_check;

ALTER TABLE pdc_sales_private.sales_accessory_receipts
 ADD CONSTRAINT sales_accessory_receipts_gmail_message_id_check
 CHECK (gmail_message_id ~ '^[A-Za-z0-9_-]{6,128}$');

DELETE FROM pdc_ops.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508' AND added_in='r508';

DO $g$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508' OR added_in='r508' OR fault_id='F121') THEN RAISE EXCEPTION 'r508 undo: check still present'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='sales_accessory_receipts_gmail_message_id_check'
     AND c.conrelid='pdc_sales_private.sales_accessory_receipts'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%^[A-Za-z0-9_-]{6,128}$%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%BETWEEN 8 AND 512%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%[[:space:]]%'
 ) THEN RAISE EXCEPTION 'r508 undo: old charset CHECK did not return'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_gmail_message_id_check'
       AND c.conrelid='karratha135_intake.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_k135id') THEN RAISE EXCEPTION 'r508 undo: karratha135 manifest CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_mailbox_check'
       AND c.conrelid='karratha135_intake.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_k135mb') THEN RAISE EXCEPTION 'r508 undo: karratha135 mailbox CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_gmail_message_id_check'
       AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_manid') THEN RAISE EXCEPTION 'r508 undo: service manifest message-id CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_mailbox_check'
       AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_manmb') THEN RAISE EXCEPTION 'r508 undo: service manifest mailbox CHECK changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r508 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3' THEN RAISE EXCEPTION 'r508 undo: sales import changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' AND added_in='r506') THEN RAISE EXCEPTION 'r508 undo: r506 check missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' AND added_in='r507') THEN RAISE EXCEPTION 'r508 undo: r507 check missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_pdc_auth_505' AND added_in='r505') THEN RAISE EXCEPTION 'r508 undo: r505 check missing'; END IF;
END $g$;
