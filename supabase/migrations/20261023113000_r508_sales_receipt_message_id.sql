-- r508 (F121): widen the sales-accessory receipt message-id CHECK so an Outlook internet_message_id can be stored.
-- Staging cdsmnqxtyyoeoznmbidd only. PREVIEW / NOT applied. Never touch production.
-- Kajel 23 Oct 01:29Z: BT Allocation Deal Items insert failed
--   sales_accessory_receipts_gmail_message_id_check CHECK (gmail_message_id ~ '^[A-Za-z0-9_-]{6,128}$')
-- on pdc_sales_private.sales_accessory_receipts.
-- Failing id <01dd628d$Blat.v3.2.22$f9cc539a$17dcc6c7327e@10.255.11.20> (length 58, has <>$.@).
-- Held file sha 7fe8b0bd543cb461e4ec228cc6e5cc4de568dd72f97d7bfbfaecdb3b3ff35c19, 1259 rows, 104 stocks.
-- Nothing written. r506 widened management_email_manifests only.
-- Live staging read before this file was written: 12 stored receipt ids, all pass the r506 shape
-- (11 hex length 16, one manual-chat-upload-01M5C2FJ6HM3QGXXQXKVHG8G5C length 45).
-- The old charset is not OR-ed in. A 6-character non-hex id would fail the new CHECK; none is stored.
-- New def, as written:
--   CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'))
-- Mailbox and sender CHECKs on this table are length bounds and already accept pdc@pmgwa.com.au and
-- noreply@revolutionsoftware.com.au. import_sales_accessories_20261020 is unchanged (r505 already
-- coalesces internet_message_id|outlook_message_id|microsoft_message_id into gmail_message_id).
-- Craig 10:14 AWST: pmbcontroller@gmail.com is no longer scanned. Revolution files come from
-- pdc@pmgwa.com.au only. This release does not remove pmbcontroller from checks that already allow it:
-- 259 service-manifest rows still store that mailbox, and tightening that CHECK would fail those rows
-- and outlook_manifest_mailbox_507. Parts receipts have no message-id CHECK (an Outlook id is already
-- stored). Karratha 135, the one-row authorizations pin, person parts-completion and the old Gmail
-- monitor controls are not this import path and are left unchanged. See release_log/r508/NOTES.
-- No function body change. Pin count stays 212. Check outlook_sales_receipt_message_id_508 sort 293 F121.
-- Re-runs outlook_manifest_message_id_506, outlook_manifest_mailbox_507 and outlook_pdc_auth_505.
-- check_sql filters def with WHERE (not count(*) AND column FROM cte).
-- No app.js / pdc-qc-rework.js.
-- Undo: supabase/rollbacks/20261023113000_r508_sales_receipt_message_id.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r508: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r508: staging only'; END IF;
 PERFORM set_config('pdc.r508_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r508_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r508_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
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
 PERFORM set_config('pdc.r508_salesmb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='sales_accessory_receipts_mailbox_check'
     AND c.conrelid='pdc_sales_private.sales_accessory_receipts'::regclass),true);
 PERFORM set_config('pdc.r508_authzid',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='authorizations_gmail_message_id_check'
     AND c.conrelid='pdc_codex_intake_private.authorizations'::regclass),true);
 PERFORM set_config('pdc.r508_authzmb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='authorizations_mailbox_check'
     AND c.conrelid='pdc_codex_intake_private.authorizations'::regclass),true);
 PERFORM set_config('pdc.r508_partsid',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
     AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass),true);
 PERFORM set_config('pdc.r508_partsmb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
     AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass),true);
 IF current_setting('pdc.r508_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r508: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r508_pins')::int IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r508: expected 212 pins at tip, got %', current_setting('pdc.r508_pins'); END IF;
 IF current_setting('pdc.r508_sales') IS DISTINCT FROM '46d4b464c5c1800c8ada245fb2d33bd3' THEN RAISE EXCEPTION 'r508: sales import must stay the r505 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r508: service manifest must stay the r479/r505 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r508: auth is not the r505 body'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' AND added_in='r507' AND sort_order=292 AND fault_id='F120') THEN RAISE EXCEPTION 'r508: r507 mailbox check is not applied'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' AND added_in='r506' AND sort_order=291 AND fault_id='F119') THEN RAISE EXCEPTION 'r508: r506 message-id check is not applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508' OR added_in='r508') THEN RAISE EXCEPTION 'r508: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=293 OR fault_id='F121') THEN RAISE EXCEPTION 'r508: sort_order 293 / F121 taken'; END IF;
 IF to_regclass('pdc_sales_private.sales_accessory_receipts') IS NULL THEN RAISE EXCEPTION 'r508: sales receipt table missing'; END IF;
 IF to_regclass('karratha135_intake.sales_accessory_receipts') IS NOT NULL THEN RAISE EXCEPTION 'r508: unexpected karratha sales receipt table'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='sales_accessory_receipts_gmail_message_id_check'
     AND c.conrelid='pdc_sales_private.sales_accessory_receipts'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%^[A-Za-z0-9_-]{6,128}$%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%BETWEEN 8 AND 512%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%[[:space:]]%'
 ) THEN RAISE EXCEPTION 'r508: live sales receipt CHECK is not the old charset check'; END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_sales_private.sales_accessory_receipts
   WHERE gmail_message_id IS NOT NULL
     AND NOT (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'))
 ) THEN RAISE EXCEPTION 'r508: a stored sales receipt id would fail the widened CHECK'; END IF;
 IF current_setting('pdc.r508_k135id') IS NULL
    OR current_setting('pdc.r508_k135id') NOT LIKE '%^[a-f0-9]+$%'
    OR current_setting('pdc.r508_k135id') LIKE '%BETWEEN 8 AND 512%' THEN RAISE EXCEPTION 'r508: karratha135 manifest CHECK is not the parked hex check'; END IF;
 IF current_setting('pdc.r508_k135mb') IS NULL
    OR current_setting('pdc.r508_k135mb') NOT LIKE '%pmbcontroller@gmail.com%'
    OR current_setting('pdc.r508_k135mb') LIKE '%pdc@pmgwa.com.au%' THEN RAISE EXCEPTION 'r508: karratha135 mailbox CHECK is not the parked pmbcontroller check'; END IF;
 IF current_setting('pdc.r508_manid') IS NULL
    OR current_setting('pdc.r508_manid') NOT LIKE '%^[a-f0-9]+$%'
    OR NOT (
         current_setting('pdc.r508_manid') LIKE '%BETWEEN 8 AND 512%'
      OR (current_setting('pdc.r508_manid') LIKE '%>= 8%' AND current_setting('pdc.r508_manid') LIKE '%<= 512%')
    ) THEN RAISE EXCEPTION 'r508: service manifest message-id CHECK is not the r506 shape'; END IF;
 IF current_setting('pdc.r508_manmb') IS NULL
    OR current_setting('pdc.r508_manmb') NOT LIKE '%pdc@pmgwa.com.au%' THEN RAISE EXCEPTION 'r508: service manifest mailbox CHECK is not the r507 shape'; END IF;
 IF current_setting('pdc.r508_salesmb') IS NULL
    OR current_setting('pdc.r508_salesmb') NOT LIKE '%length(mailbox)%' THEN RAISE EXCEPTION 'r508: sales mailbox CHECK is not the length check'; END IF;
 IF (SELECT count(*) FROM pg_constraint c WHERE c.conrelid='pdc_parts_private.receipts'::regclass AND c.contype='c') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'r508: parts receipts gained a CHECK'; END IF;
END $g$;

ALTER TABLE pdc_sales_private.sales_accessory_receipts
 DROP CONSTRAINT sales_accessory_receipts_gmail_message_id_check;

ALTER TABLE pdc_sales_private.sales_accessory_receipts
 ADD CONSTRAINT sales_accessory_receipts_gmail_message_id_check
 CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'));

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('outlook_sales_receipt_message_id_508','F121','Sales receipt gmail_message_id (r508): hex ids of any length still pass; an Outlook internet_message_id and a Graph id (length 8-512, no whitespace) pass; the stored manual upload id passes; a 6-character non-hex id fails because the old charset is not OR-ed (live rows already pass the r506 shape); whitespace and a 513-character non-hex id fail; the column CHECK on pdc_sales_private.sales_accessory_receipts matches; every stored id still passes; the sales import function is unchanged',
  $chk508$WITH ids(label, id, want) AS (
  VALUES
   ('hex short','abc',true),
   ('hex gmail','1a158481917b7196',true),
   ('outlook internet','<01dd628d$Blat.v3.2.22$f9cc539a$17dcc6c7327e@10.255.11.20>',true),
   ('outlook graph','AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE9bAAA',true),
   ('stored manual','manual-chat-upload-01M5C2FJ6HM3QGXXQXKVHG8G5C',true),
   ('old pattern short nonhex','Abcdef',false),
   ('whitespace','<id with space@10.255.11.20>',false),
   ('too long',repeat('x',513),false)
), ev AS (
  SELECT label, want,
    (id ~ '^[a-f0-9]+$' OR (length(id) BETWEEN 8 AND 512 AND id !~ '[[:space:]]')) AS got
  FROM ids
), def AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='sales_accessory_receipts_gmail_message_id_check'
    AND c.conrelid='pdc_sales_private.sales_accessory_receipts'::regclass
)
SELECT (SELECT count(*)=8 AND bool_and(got IS NOT DISTINCT FROM want) FROM ev)
   AND (SELECT count(*)=1 FROM def WHERE d LIKE '%^[a-f0-9]+$%'
            AND (d LIKE '%BETWEEN 8 AND 512%' OR (d LIKE '%>= 8%' AND d LIKE '%<= 512%'))
            AND d LIKE '%[[:space:]]%'
            AND d NOT LIKE '%[A-Za-z0-9_-]{6,128}%')
   AND NOT EXISTS (
     SELECT 1 FROM pdc_sales_private.sales_accessory_receipts m
     WHERE m.gmail_message_id IS NOT NULL
       AND NOT (m.gmail_message_id ~ '^[a-f0-9]+$' OR (length(m.gmail_message_id) BETWEEN 8 AND 512 AND m.gmail_message_id !~ '[[:space:]]'))
   )
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)'))='46d4b464c5c1800c8ada245fb2d33bd3'
 AS ok,
 'cases '||(SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) FROM ev)||'/'||(SELECT count(*) FROM ev)
 ||coalesce(' (WRONG: '||(SELECT string_agg(label||' -> '||coalesce(got::text,'null'),'; ') FROM ev WHERE got IS DISTINCT FROM want)||')','')
 ||'; def '||coalesce((SELECT d FROM def),'missing')
 AS detail$chk508$,true,293,'r508');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM current_setting('pdc.r508_pins')::int THEN RAISE EXCEPTION 'r508: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.import_sales_accessories_20261020(text,jsonb,jsonb,text)')) IS DISTINCT FROM current_setting('pdc.r508_sales') THEN RAISE EXCEPTION 'r508: sales import changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r508: service manifest changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r508: auth changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r508_tick') THEN RAISE EXCEPTION 'r508: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r508_frc') THEN RAISE EXCEPTION 'r508: fault_regression_check changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_gmail_message_id_check'
       AND c.conrelid='karratha135_intake.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_k135id') THEN RAISE EXCEPTION 'r508: karratha135 manifest CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_mailbox_check'
       AND c.conrelid='karratha135_intake.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_k135mb') THEN RAISE EXCEPTION 'r508: karratha135 mailbox CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_gmail_message_id_check'
       AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_manid') THEN RAISE EXCEPTION 'r508: service manifest message-id CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_mailbox_check'
       AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_manmb') THEN RAISE EXCEPTION 'r508: service manifest mailbox CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='sales_accessory_receipts_mailbox_check'
       AND c.conrelid='pdc_sales_private.sales_accessory_receipts'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_salesmb') THEN RAISE EXCEPTION 'r508: sales mailbox CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='authorizations_gmail_message_id_check'
       AND c.conrelid='pdc_codex_intake_private.authorizations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_authzid') THEN RAISE EXCEPTION 'r508: authorizations message-id CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='authorizations_mailbox_check'
       AND c.conrelid='pdc_codex_intake_private.authorizations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_authzmb') THEN RAISE EXCEPTION 'r508: authorizations mailbox CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
       AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_partsid') THEN RAISE EXCEPTION 'r508: parts completion message-id CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
       AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r508_partsmb') THEN RAISE EXCEPTION 'r508: parts completion mailbox CHECK changed'; END IF;
 IF (SELECT count(*) FROM pg_constraint c WHERE c.conrelid='pdc_parts_private.receipts'::regclass AND c.contype='c') IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'r508: parts receipts CHECK changed'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='sales_accessory_receipts_gmail_message_id_check'
     AND c.conrelid='pdc_sales_private.sales_accessory_receipts'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%^[a-f0-9]+$%'
     AND pg_get_constraintdef(c.oid) LIKE '%[[:space:]]%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%[A-Za-z0-9_-]{6,128}%'
     AND (pg_get_constraintdef(c.oid) LIKE '%BETWEEN 8 AND 512%'
          OR (pg_get_constraintdef(c.oid) LIKE '%>= 8%' AND pg_get_constraintdef(c.oid) LIKE '%<= 512%'))
 ) THEN RAISE EXCEPTION 'r508: widened CHECK did not land'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508' AND added_in='r508' AND sort_order=293 AND fault_id='F121') THEN RAISE EXCEPTION 'r508: check missing'; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_sales_receipt_message_id_508';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r508: outlook_sales_receipt_message_id_508 failed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_message_id_506';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r508: r506 message-id check regressed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_mailbox_507';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r508: r507 mailbox check regressed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_pdc_auth_505';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r508: r505 auth check regressed: %', y; END IF;
END $g$;
