-- r507 (F120): widen the service-manifest mailbox CHECK so pdc@pmgwa.com.au can be stored.
-- Staging cdsmnqxtyyoeoznmbidd only. PREVIEW / NOT applied. Never touch production.
-- After r506 the held 08:52 Service As-a-Whole preview cleared the message-id CHECK and failed on
--   management_email_manifests_mailbox_check CHECK (mailbox = 'pmbcontroller@gmail.com')
-- on pdc_codex_intake_private.management_email_manifests. The row mailbox is pdc@pmgwa.com.au,
-- which is the Outlook envelope r505 auth already requires. A pmbcontroller value would fail auth.
-- This release only drops and re-adds that one CHECK. New def, as written:
--   CHECK (mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text]))
-- management_manifest_revolution_authentication is unchanged.
-- karratha135_intake.management_email_manifests has the same pmbcontroller-only mailbox CHECK but is
-- not this path. The service importer writes pdc_codex_intake_private only. That parked Dept 135
-- CHECK stays pmbcontroller-only. No other mailbox CHECK is changed.
-- No function body change. Pin count stays 212. Check outlook_manifest_mailbox_507 sort 292 F120.
-- check_sql filters def and k135 with WHERE (not count(*) AND column FROM cte).
-- SQL only. No frontend files.
-- Undo: supabase/rollbacks/20261023101000_r507_outlook_manifest_mailbox.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r507: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r507: staging only'; END IF;
 PERFORM set_config('pdc.r507_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r507_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r507_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r507_manifest',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')),true);
 PERFORM set_config('pdc.r507_k135def',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='management_email_manifests_mailbox_check'
     AND c.conrelid='karratha135_intake.management_email_manifests'::regclass),true);
 IF current_setting('pdc.r507_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r507: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r507_pins')::int IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r507: expected 212 pins at tip, got %', current_setting('pdc.r507_pins'); END IF;
 IF current_setting('pdc.r507_manifest') IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r507: service manifest must stay the r479/r505 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r507: auth is not the r505 body'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' AND added_in='r506' AND sort_order=291 AND fault_id='F119') THEN RAISE EXCEPTION 'r507: r506 message-id check is not applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' OR added_in='r507') THEN RAISE EXCEPTION 'r507: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=292 OR fault_id='F120') THEN RAISE EXCEPTION 'r507: sort_order 292 / F120 taken'; END IF;
 IF to_regclass('pdc_codex_intake_private.management_email_manifests') IS NULL THEN RAISE EXCEPTION 'r507: service manifest table missing'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='management_email_manifests_mailbox_check'
     AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%pmbcontroller@gmail.com%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%pdc@pmgwa.com.au%'
 ) THEN RAISE EXCEPTION 'r507: live service manifest mailbox CHECK is not pmbcontroller-only'; END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_codex_intake_private.management_email_manifests
   WHERE mailbox IS NOT NULL AND mailbox IS DISTINCT FROM 'pmbcontroller@gmail.com'
 ) THEN RAISE EXCEPTION 'r507: a stored manifest mailbox is not pmbcontroller@gmail.com'; END IF;
 IF current_setting('pdc.r507_k135def') IS NULL
    OR current_setting('pdc.r507_k135def') NOT LIKE '%pmbcontroller@gmail.com%'
    OR current_setting('pdc.r507_k135def') LIKE '%pdc@pmgwa.com.au%' THEN RAISE EXCEPTION 'r507: karratha135 mailbox CHECK is not the parked pmbcontroller check'; END IF;
END $g$;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 DROP CONSTRAINT management_email_manifests_mailbox_check;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 ADD CONSTRAINT management_email_manifests_mailbox_check
 CHECK (mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text]));

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('outlook_manifest_mailbox_507','F120','Service manifest mailbox (r507): pmbcontroller@gmail.com and pdc@pmgwa.com.au pass; a third mailbox fails; the column CHECK on pdc_codex_intake_private.management_email_manifests matches; every stored mailbox still passes; the Karratha 135 copy stays pmbcontroller-only',
  $chk507$WITH boxes(label, mailbox, want) AS (
  VALUES
   ('gmail','pmbcontroller@gmail.com',true),
   ('outlook','pdc@pmgwa.com.au',true),
   ('other','someone@example.com',false)
), ev AS (
  SELECT label, want,
    (mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text])) AS got
  FROM boxes
), def AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='management_email_manifests_mailbox_check'
    AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass
), k135 AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='management_email_manifests_mailbox_check'
    AND c.conrelid='karratha135_intake.management_email_manifests'::regclass
)
SELECT (SELECT count(*)=3 AND bool_and(got IS NOT DISTINCT FROM want) FROM ev)
   AND (SELECT count(*)=1 FROM def WHERE d LIKE '%pmbcontroller@gmail.com%'
            AND d LIKE '%pdc@pmgwa.com.au%')
   AND NOT EXISTS (
     SELECT 1 FROM pdc_codex_intake_private.management_email_manifests m
     WHERE m.mailbox IS NOT NULL
       AND NOT (m.mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text]))
   )
   AND (SELECT count(*)=1 FROM k135 WHERE d LIKE '%pmbcontroller@gmail.com%'
            AND d NOT LIKE '%pdc@pmgwa.com.au%')
 AS ok,
 'cases '||(SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) FROM ev)||'/'||(SELECT count(*) FROM ev)
 ||coalesce(' (WRONG: '||(SELECT string_agg(label||' -> '||coalesce(got::text,'null'),'; ') FROM ev WHERE got IS DISTINCT FROM want)||')','')
 ||'; def '||coalesce((SELECT d FROM def),'missing')
 ||'; k135 '||coalesce((SELECT d FROM k135),'missing')
 AS detail$chk507$,true,292,'r507');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM current_setting('pdc.r507_pins')::int THEN RAISE EXCEPTION 'r507: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) IS DISTINCT FROM current_setting('pdc.r507_manifest') THEN RAISE EXCEPTION 'r507: service manifest changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r507: auth changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r507_tick') THEN RAISE EXCEPTION 'r507: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r507_frc') THEN RAISE EXCEPTION 'r507: fault_regression_check changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_mailbox_check'
       AND c.conrelid='karratha135_intake.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r507_k135def') THEN RAISE EXCEPTION 'r507: karratha135 mailbox CHECK changed'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='management_email_manifests_mailbox_check'
     AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%pmbcontroller@gmail.com%'
     AND pg_get_constraintdef(c.oid) LIKE '%pdc@pmgwa.com.au%'
 ) THEN RAISE EXCEPTION 'r507: widened mailbox CHECK did not land'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_mailbox_507' AND added_in='r507' AND sort_order=292 AND fault_id='F120') THEN RAISE EXCEPTION 'r507: check missing'; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_mailbox_507';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r507: outlook_manifest_mailbox_507 failed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_message_id_506';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r507: r506 message-id check regressed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_pdc_auth_505';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r507: r505 auth check regressed: %', y; END IF;
END $g$;
