-- r558 (F172). Approved go-live 27 Oct 2026 06:48 AWST.
-- Staging cdsmnqxtyyoeoznmbidd only. Production is not touched.
-- Next free after r557 / F171 / sort 332. This is r558 / F172 / sort 333.
-- Kajel: two parts-complete ticks failed unverified_or_ambiguous_confirmation.
-- pdc@ was not in To or Cc. The mail reached pdc@ through the Newvehiclebuild@ distribution list.
-- 1IRU519 / J138000880 was from parts.malaga@pmgwa.com.au.
-- 13102818 was from Talin Parker, subject RE: New vehicle order for 13102818 - PMG Build.
-- The raw envelopes were not at /workspace/pmb-live/work/review-20261027-525-526.
-- The check uses those facts on the address fields this function already reads.
-- A Newvehiclebuild@pmgwa.com.au header counts as the pdc@ route only when
-- verified_by is exactly microsoft_receiving_provider. A direct pdc@ header, a Cc,
-- a forward flag, and an FW subject stay accepted. An unverified Newvehiclebuild@
-- delivery and any other list stay refused.
-- The person recorder stays c5314b7bed8a1401b6698319125c2d74.
-- The importer stays e56cd1f5d12205a0d72826d64cb8d1de. Pin count stays 241.
-- Recipient prosrc md5 was f5ccdab2fe3b8bc66cb0ed377493f23e and becomes 860a18f2629b1da6a9036a8a2c566f4a.
-- Undo: supabase/rollbacks/20261026225222_r558_newvehiclebuild_pdc_route.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r558: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r558: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r558: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) IS DISTINCT FROM 'f5ccdab2fe3b8bc66cb0ed377493f23e' THEN RAISE EXCEPTION 'r558: mailbox recipient is not the r555 body'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) IS TRUE THEN RAISE EXCEPTION 'r558: mailbox recipient is security definer'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS DISTINCT FROM 'c5314b7bed8a1401b6698319125c2d74' THEN RAISE EXCEPTION 'r558: person recorder changed'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS TRUE THEN RAISE EXCEPTION 'r558: person recorder is security definer'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)')) IS DISTINCT FROM 'e56cd1f5d12205a0d72826d64cb8d1de' THEN RAISE EXCEPTION 'r558: importer changed'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_557' AND fault_id='F171' AND sort_order=332 AND added_in='r557') THEN RAISE EXCEPTION 'r558: r557 / F171 sort 332 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_complete_wording_555' AND fault_id='F169' AND sort_order=330 AND added_in='r555') THEN RAISE EXCEPTION 'r558: r555 / F169 sort 330 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=333 OR fault_id='F172' OR check_name='newvehiclebuild_pdc_route_558' OR added_in='r558') THEN RAISE EXCEPTION 'r558: sort 333 or F172 is taken'; END IF;
END $g$;

-- pdc@ in To, Cc, or a forward. Newvehiclebuild@ counts only when Microsoft verified the delivery.
-- The mailbox flag and the sender proof stay in the recorder.
CREATE OR REPLACE FUNCTION public.pdc_parts_mailbox_recipient_541(p_authentication jsonb, p_subject text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO pg_catalog
AS $mb541$
DECLARE
  auth jsonb := coalesce(p_authentication, '{}'::jsonb);
  pat text := '(^|[^a-z0-9._%+-])pdc@pmgwa[.]com[.]au([^a-z0-9.-]|$)';
  list_pat text := '(^|[^a-z0-9._%+-])newvehiclebuild@pmgwa[.]com[.]au([^a-z0-9.-]|$)';
  blob text;
  key text;
  elem jsonb;
  subj text;
  list_hit boolean := false;
BEGIN
  blob := lower(concat_ws(' ', auth->>'to_address', auth->>'cc_address', auth->>'cc'));
  IF blob ~ pat THEN RETURN true; END IF;
  IF blob ~ list_pat THEN list_hit := true; END IF;
  FOREACH key IN ARRAY ARRAY['to_addresses', 'cc_addresses', 'recipients']
  LOOP
    IF jsonb_typeof(auth->key) = 'array' THEN
      FOR elem IN SELECT t.value FROM jsonb_array_elements(auth->key) AS t(value)
      LOOP
        IF lower(coalesce(elem #>> '{}', '')) ~ pat THEN RETURN true; END IF;
        IF lower(coalesce(elem #>> '{}', '')) ~ list_pat THEN list_hit := true; END IF;
      END LOOP;
    ELSIF jsonb_typeof(auth->key) = 'string' THEN
      IF lower(auth->>key) ~ pat THEN
        RETURN true;
      ELSIF lower(auth->>key) ~ list_pat THEN
        list_hit := true;
      END IF;
    END IF;
  END LOOP;
  IF list_hit AND auth->>'verified_by' = 'microsoft_receiving_provider' THEN
    RETURN true;
  END IF;
  IF lower(btrim(coalesce(auth->>'forwarded', ''))) IN ('true', 'yes', '1') THEN
    RETURN true;
  END IF;
  subj := lower(regexp_replace(btrim(coalesce(p_subject, '')), '[[:space:]]+', ' ', 'g'));
  subj := regexp_replace(subj, '^((re):[[:space:]]+)+', '');
  RETURN subj ~ '^(fw|fwd):[[:space:]]';
END
$mb541$;

REVOKE ALL ON FUNCTION public.pdc_parts_mailbox_recipient_541(jsonb, text) FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('newvehiclebuild_pdc_route_558', 'F172',
 'Newvehiclebuild list route (r558): pdc@ via Newvehiclebuild@pmgwa.com.au counts only when verified_by is microsoft_receiving_provider. The parts.malaga 1IRU519/J138000880 envelope and the Talin 13102818 envelope pass. A direct pdc@ header passes. An unverified Newvehiclebuild@ delivery and any other list fail. A forward and an FW subject stay accepted. The importer and the 241 pins stay.',
 $chk558$
SELECT
 (
  pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)') IS NOT NULL
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)'))
      = '860a18f2629b1da6a9036a8a2c566f4a'
  AND (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) IS NOT TRUE
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) LIKE '%cc_addresses%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) LIKE '%forwarded%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) LIKE '%newvehiclebuild@pmgwa%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) LIKE '%microsoft_receiving_provider%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) LIKE '%list_hit%'
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'))
      = 'c5314b7bed8a1401b6698319125c2d74'
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)'))
      = 'e56cd1f5d12205a0d72826d64cb8d1de'
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"pdc@pmgwa.com.au"}'::pg_catalog.jsonb, 'Parts complete') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"mailbox":"pdc@pmgwa.com.au","from_address":"parts.malaga@pmgwa.com.au","to_address":"Newvehiclebuild | Pilbara Motor Group <Newvehiclebuild@pmgwa.com.au>","cc_addresses":[],"verified_by":"microsoft_receiving_provider"}'::pg_catalog.jsonb, '1IRU519 J138000880 EPT') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"mailbox":"pdc@pmgwa.com.au","from_address":"talin.parker@pmgwa.com.au","to_addresses":["Newvehiclebuild@pmgwa.com.au"],"cc_address":"","verified_by":"microsoft_receiving_provider"}'::pg_catalog.jsonb, 'RE: New vehicle order for 13102818 - PMG Build') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"parts.malaga@pmgwa.com.au","cc_addresses":["Newvehiclebuild@pmgwa.com.au"],"verified_by":"microsoft_receiving_provider"}'::pg_catalog.jsonb, '1IRU519 J138000880 EPT') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"mailbox":"pdc@pmgwa.com.au","from_address":"parts.malaga@pmgwa.com.au","to_address":"Newvehiclebuild | Pilbara Motor Group <Newvehiclebuild@pmgwa.com.au>","cc_addresses":[]}'::pg_catalog.jsonb, '1IRU519 J138000880 EPT') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"mailbox":"pdc@pmgwa.com.au","from_address":"talin.parker@pmgwa.com.au","to_addresses":["Newvehiclebuild@pmgwa.com.au"],"verified_by":"gmail_receiving_provider"}'::pg_catalog.jsonb, 'RE: New vehicle order for 13102818 - PMG Build') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"mailbox":"pdc@pmgwa.com.au","to_address":"Workshop updates <workshopupdates@pmgwa.com.au>","cc_addresses":[],"verified_by":"microsoft_receiving_provider"}'::pg_catalog.jsonb, 'Parts complete') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"newvehiclebuild@pmgwa.com.au.example.net","verified_by":"microsoft_receiving_provider"}'::pg_catalog.jsonb, 'Parts complete') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au","verified_by":"microsoft_receiving_provider"}'::pg_catalog.jsonb, 'Newvehiclebuild@pmgwa.com.au') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"Newvehiclebuild@pmgwa.com.au","verified_by":"Microsoft_receiving_provider"}'::pg_catalog.jsonb, 'Parts complete') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au","cc_addresses":["sales@pmgwa.com.au"],"verified_by":"microsoft_receiving_provider"}'::pg_catalog.jsonb, 'Parts complete') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"parts.malaga@pmgwa.com.au","cc_addresses":["pdc@pmgwa.com.au"]}'::pg_catalog.jsonb, '1IRU519 J138000880 EPT') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"parts.malaga@pmgwa.com.au","cc_address":"Workshop <pdc@pmgwa.com.au>"}'::pg_catalog.jsonb, '1IRU519 J138000880 EPT') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au"}'::pg_catalog.jsonb, 'FW: 1IRU519 J138000880 EPT') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au","forwarded":"true"}'::pg_catalog.jsonb, '1IRU519 J138000880') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au"}'::pg_catalog.jsonb, 'RE: New vehicle order for 13102818 - PMG Build') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au","cc_addresses":[]}'::pg_catalog.jsonb, 'Parts complete') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"pdc@pmgwa.com.au.example.net"}'::pg_catalog.jsonb, 'Parts complete') IS FALSE
  AND (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='newvehiclebuild_pdc_route_558' AND fault_id='F172' AND sort_order=333 AND added_in='r558' AND enabled) = 1
 ) AS ok,
 '1IRU519/J138000880 and 13102818 reach pdc@ through verified Newvehiclebuild@; an unverified list and any other list do not' AS detail
$chk558$, true, 333, 'r558');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r558: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) IS DISTINCT FROM '860a18f2629b1da6a9036a8a2c566f4a' THEN RAISE EXCEPTION 'r558: mailbox recipient md5'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) IS TRUE THEN RAISE EXCEPTION 'r558: mailbox recipient became security definer'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS DISTINCT FROM 'c5314b7bed8a1401b6698319125c2d74' THEN RAISE EXCEPTION 'r558: person md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)')) IS DISTINCT FROM 'e56cd1f5d12205a0d72826d64cb8d1de' THEN RAISE EXCEPTION 'r558: importer md5'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='newvehiclebuild_pdc_route_558') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r558: newvehiclebuild_pdc_route_558 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_complete_wording_555') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r558: parts_complete_wording_555 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r558: regression_checks_self_test not OK: %', x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $p$;
