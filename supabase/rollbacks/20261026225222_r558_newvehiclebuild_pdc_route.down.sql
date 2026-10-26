-- Undo r558 (F172). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Restores pdc_parts_mailbox_recipient_541 to the r555 body (prosrc md5 f5ccdab2fe3b8bc66cb0ed377493f23e) and removes the r558 check.
-- The person recorder and the importer are not rewritten. Pin count stays 241.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r558 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r558 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r558 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) IS DISTINCT FROM '860a18f2629b1da6a9036a8a2c566f4a' THEN RAISE EXCEPTION 'r558 undo: mailbox recipient is not the r558 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS DISTINCT FROM 'c5314b7bed8a1401b6698319125c2d74' THEN RAISE EXCEPTION 'r558 undo: person recorder changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)')) IS DISTINCT FROM 'e56cd1f5d12205a0d72826d64cb8d1de' THEN RAISE EXCEPTION 'r558 undo: importer changed'; END IF;
END $g$;

-- pdc@ in To, Cc, or a forward. The mailbox flag and the sender proof stay in the recorder.
CREATE OR REPLACE FUNCTION public.pdc_parts_mailbox_recipient_541(p_authentication jsonb, p_subject text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO pg_catalog
AS $mb541$
DECLARE
  auth jsonb := coalesce(p_authentication, '{}'::jsonb);
  pat text := '(^|[^a-z0-9._%+-])pdc@pmgwa[.]com[.]au([^a-z0-9.-]|$)';
  blob text;
  key text;
  elem jsonb;
  subj text;
BEGIN
  blob := lower(concat_ws(' ', auth->>'to_address', auth->>'cc_address', auth->>'cc'));
  IF blob ~ pat THEN RETURN true; END IF;
  FOREACH key IN ARRAY ARRAY['to_addresses', 'cc_addresses', 'recipients']
  LOOP
    IF jsonb_typeof(auth->key) = 'array' THEN
      FOR elem IN SELECT t.value FROM jsonb_array_elements(auth->key) AS t(value)
      LOOP
        IF lower(coalesce(elem #>> '{}', '')) ~ pat THEN RETURN true; END IF;
      END LOOP;
    ELSIF jsonb_typeof(auth->key) = 'string' AND lower(auth->>key) ~ pat THEN
      RETURN true;
    END IF;
  END LOOP;
  IF lower(btrim(coalesce(auth->>'forwarded', ''))) IN ('true', 'yes', '1') THEN
    RETURN true;
  END IF;
  subj := lower(regexp_replace(btrim(coalesce(p_subject, '')), '[[:space:]]+', ' ', 'g'));
  subj := regexp_replace(subj, '^((re):[[:space:]]+)+', '');
  RETURN subj ~ '^(fw|fwd):[[:space:]]';
END
$mb541$;

REVOKE ALL ON FUNCTION public.pdc_parts_mailbox_recipient_541(jsonb, text) FROM PUBLIC, anon, authenticated, service_role;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='newvehiclebuild_pdc_route_558' AND fault_id='F172' AND sort_order=333 AND added_in='r558';

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r558 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) IS DISTINCT FROM 'f5ccdab2fe3b8bc66cb0ed377493f23e' THEN RAISE EXCEPTION 'r558 undo: mailbox recipient md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS DISTINCT FROM 'c5314b7bed8a1401b6698319125c2d74' THEN RAISE EXCEPTION 'r558 undo: person md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_import_job_parts_csv_20260912(jsonb,jsonb)')) IS DISTINCT FROM 'e56cd1f5d12205a0d72826d64cb8d1de' THEN RAISE EXCEPTION 'r558 undo: importer md5'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='newvehiclebuild_pdc_route_558' OR fault_id='F172' OR added_in='r558') THEN RAISE EXCEPTION 'r558 undo: check remains'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_complete_wording_555') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r558 undo: parts_complete_wording_555 not OK: %', x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $p$;
