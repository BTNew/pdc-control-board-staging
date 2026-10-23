-- r506 (F119): widen the service-manifest message-id CHECK so an Outlook internet_message_id can be stored.
-- Staging cdsmnqxtyyoeoznmbidd only. PREVIEW / NOT applied. Never touch production.
-- Kajel 23 Oct 09:38 AWST: Service As-a-Whole insert failed
--   management_email_manifests_gmail_message_id_check CHECK (gmail_message_id ~ '^[a-f0-9]+$')
-- on pdc_codex_intake_private.management_email_manifests. Parts receipt 5e14b8d1 had already succeeded.
-- r505 auth already accepts that id as p_message_id (length 8-512, no whitespace, equal to
-- internet_message_id|outlook_message_id|microsoft_message_id). A hex surrogate makes auth false.
-- The column CHECK was not widened in r505. This release only drops and re-adds that one CHECK.
-- New def, as written:
--   CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'))
-- Hex Gmail ids of any length still pass. management_manifest_revolution_authentication is unchanged:
-- it still calls revolution_service_manifest_20261006(provenance, gmail_message_id, filename), which
-- passes p_message_id through to the r505 auth helper.
-- karratha135_intake.management_email_manifests has the same hex CHECK but is not this path.
-- The service importer writes pdc_codex_intake_private only. The Karratha copy is the parked Dept 135
-- table and its mailbox CHECK is still pmbcontroller@gmail.com, so an Outlook pdc@ service row cannot
-- land there. That CHECK is left hex-only. No other gmail_message_id CHECK is changed.
-- No function body change. Pin count stays 212. Check outlook_manifest_message_id_506 sort 291 F119.
-- No app.js / pdc-qc-rework.js.
-- Undo: supabase/rollbacks/20261023094500_r506_outlook_manifest_message_id.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r506: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r506: staging only'; END IF;
 PERFORM set_config('pdc.r506_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r506_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r506_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r506_manifest',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')),true);
 PERFORM set_config('pdc.r506_k135def',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='management_email_manifests_gmail_message_id_check'
     AND c.conrelid='karratha135_intake.management_email_manifests'::regclass),true);
 IF current_setting('pdc.r506_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r506: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r506_pins')::int IS DISTINCT FROM 212 THEN RAISE EXCEPTION 'r506: expected 212 pins at tip, got %', current_setting('pdc.r506_pins'); END IF;
 IF current_setting('pdc.r506_manifest') IS DISTINCT FROM '63ff5dabf94abcdf7c278fb3afa9bd96' THEN RAISE EXCEPTION 'r506: service manifest must stay the r479/r505 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r506: auth is not the r505 body'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' OR added_in='r506') THEN RAISE EXCEPTION 'r506: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=291 OR fault_id='F119') THEN RAISE EXCEPTION 'r506: sort_order 291 / F119 taken'; END IF;
 IF to_regclass('pdc_codex_intake_private.management_email_manifests') IS NULL THEN RAISE EXCEPTION 'r506: service manifest table missing'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='management_email_manifests_gmail_message_id_check'
     AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%^[a-f0-9]+$%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%BETWEEN 8 AND 512%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%>= 8%'
 ) THEN RAISE EXCEPTION 'r506: live service manifest CHECK is not the hex-only check'; END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_codex_intake_private.management_email_manifests
   WHERE gmail_message_id IS NOT NULL AND gmail_message_id !~ '^[a-f0-9]+$'
 ) THEN RAISE EXCEPTION 'r506: a stored manifest id is already non-hex'; END IF;
 IF current_setting('pdc.r506_k135def') IS NULL
    OR current_setting('pdc.r506_k135def') NOT LIKE '%^[a-f0-9]+$%'
    OR current_setting('pdc.r506_k135def') LIKE '%BETWEEN 8 AND 512%' THEN RAISE EXCEPTION 'r506: karratha135 manifest CHECK is not the parked hex check'; END IF;
END $g$;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 DROP CONSTRAINT management_email_manifests_gmail_message_id_check;

ALTER TABLE pdc_codex_intake_private.management_email_manifests
 ADD CONSTRAINT management_email_manifests_gmail_message_id_check
 CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'));

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('outlook_manifest_message_id_506','F119','Service manifest gmail_message_id (r506): hex ids of any length still pass; an Outlook internet_message_id and a Graph id (length 8-512, no whitespace) pass; whitespace and a 513-character id fail; the column CHECK on pdc_codex_intake_private.management_email_manifests matches; every stored id still passes; the service manifest function is unchanged; the Karratha 135 copy stays hex-only',
  $chk506$WITH ids(label, id, want) AS (
  VALUES
   ('hex short','abc',true),
   ('hex gmail','5e14b8d15e14b8d1',true),
   ('outlook internet','<01dd6288$Blat.v3.2.22$d55355b9$b9010b3753@10.255.11.20>',true),
   ('outlook graph','AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE7dQAA',true),
   ('whitespace','<id with space@10.255.11.20>',false),
   ('too long',repeat('x',513),false)
), ev AS (
  SELECT label, want,
    (id ~ '^[a-f0-9]+$' OR (length(id) BETWEEN 8 AND 512 AND id !~ '[[:space:]]')) AS got
  FROM ids
), def AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='management_email_manifests_gmail_message_id_check'
    AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass
), k135 AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='management_email_manifests_gmail_message_id_check'
    AND c.conrelid='karratha135_intake.management_email_manifests'::regclass
)
SELECT (SELECT count(*)=6 AND bool_and(got IS NOT DISTINCT FROM want) FROM ev)
   AND (SELECT count(*)=1 AND d LIKE '%^[a-f0-9]+$%'
            AND (d LIKE '%BETWEEN 8 AND 512%' OR (d LIKE '%>= 8%' AND d LIKE '%<= 512%'))
            AND d LIKE '%[[:space:]]%' FROM def)
   AND NOT EXISTS (
     SELECT 1 FROM pdc_codex_intake_private.management_email_manifests m
     WHERE m.gmail_message_id IS NOT NULL
       AND NOT (m.gmail_message_id ~ '^[a-f0-9]+$' OR (length(m.gmail_message_id) BETWEEN 8 AND 512 AND m.gmail_message_id !~ '[[:space:]]'))
   )
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'))='63ff5dabf94abcdf7c278fb3afa9bd96'
   AND (SELECT count(*)=1 AND d LIKE '%^[a-f0-9]+$%' AND d NOT LIKE '%BETWEEN 8 AND 512%' AND d NOT LIKE '%>= 8%' FROM k135)
 AS ok,
 'cases '||(SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) FROM ev)||'/'||(SELECT count(*) FROM ev)
 ||coalesce(' (WRONG: '||(SELECT string_agg(label||' -> '||coalesce(got::text,'null'),'; ') FROM ev WHERE got IS DISTINCT FROM want)||')','')
 ||'; def '||coalesce((SELECT d FROM def),'missing')
 ||'; k135 '||coalesce((SELECT d FROM k135),'missing')
 AS detail$chk506$,true,291,'r506');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 212
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM current_setting('pdc.r506_pins')::int THEN RAISE EXCEPTION 'r506: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) IS DISTINCT FROM current_setting('pdc.r506_manifest') THEN RAISE EXCEPTION 'r506: service manifest changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r506: auth changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r506_tick') THEN RAISE EXCEPTION 'r506: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r506_frc') THEN RAISE EXCEPTION 'r506: fault_regression_check changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='management_email_manifests_gmail_message_id_check'
       AND c.conrelid='karratha135_intake.management_email_manifests'::regclass)
    IS DISTINCT FROM current_setting('pdc.r506_k135def') THEN RAISE EXCEPTION 'r506: karratha135 manifest CHECK changed'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='management_email_manifests_gmail_message_id_check'
     AND c.conrelid='pdc_codex_intake_private.management_email_manifests'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%^[a-f0-9]+$%'
     AND pg_get_constraintdef(c.oid) LIKE '%[[:space:]]%'
     AND (pg_get_constraintdef(c.oid) LIKE '%BETWEEN 8 AND 512%'
          OR (pg_get_constraintdef(c.oid) LIKE '%>= 8%' AND pg_get_constraintdef(c.oid) LIKE '%<= 512%'))
 ) THEN RAISE EXCEPTION 'r506: widened CHECK did not land'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_manifest_message_id_506' AND added_in='r506' AND sort_order=291 AND fault_id='F119') THEN RAISE EXCEPTION 'r506: check missing'; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_message_id_506';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r506: outlook_manifest_message_id_506 failed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_pdc_auth_505';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r506: r505 auth check regressed: %', y; END IF;
END $g$;
