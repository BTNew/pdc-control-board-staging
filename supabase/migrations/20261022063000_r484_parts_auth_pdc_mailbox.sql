-- r484 (F97, change request; Craig approved in chat 22 Oct 2026 14:18 AWST, "Yes, widen the parts check"): accept Revolution's
-- Pilbara parts report now addressed To pdc@pmgwa.com.au with Craig on CC. Staging cdsmnqxtyyoeoznmbidd only.
-- Changes only pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text): one more To/CC case,
--   to_address = 'pdc@pmgwa.com.au' AND cc_addresses (jsonb array) contains 'craig.watson@broometoyota.com.au'.
-- Everything it accepted before is unchanged (To pmbcontroller@gmail.com; To Craig with pmbcontroller on CC), and every other
-- test is unchanged: message id format and match, sender noreply@revolutionsoftware.com.au, mailbox pmbcontroller@gmail.com,
-- verified_by gmail_receiving_provider, header from, reply-to, mx.google.com, SPF pass and DMARC pass for revolutionsoftware.com.au.
-- Exact matching as before (no case folding or trimming). To pdc@ without Craig on CC, any other domain, or any other address fails.
-- The attachment sha256, subject, file name, envelope sender and mailbox checks stay in the callers, which are not changed:
--   public.pdc_import_job_parts_csv_20260912 (parts), pdc_codex_intake_private.revolution_service_manifest_20261006 (service),
--   karratha135_intake.revolution_csv_contract_20261007 (Karratha 135). All three call this function, so the new To/CC case
--   applies to each of them; their own subject / file / department rules are unchanged.
-- Same signature, LANGUAGE sql IMMUTABLE, SET search_path pg_catalog, not security definer, owner postgres, EXECUTE postgres only.
-- The function had no pin; adds one (pins +1). Check parts_auth_pdc_mailbox_484 (sort 284, F97).
-- Body is LF only (the old body had CRLF line ends; r479's apply failed because CRLF did not survive the MCP transport).
-- Old: functiondef md5 bd378910e0328a5c6bcab980195d73d4, prosrc md5 67d03f901dc6ba475691a9661fff8826. New: functiondef md5 abbb00e85839a85c47df7de16c9895bd, prosrc md5 6c1a612f6ed82dfcbf5788c17d2e5d87.
-- Undo: supabase/rollbacks/20261022063000_r484_parts_auth_pdc_mailbox.down.sql.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r484: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r484: staging only'; END IF;
 PERFORM set_config('pdc.r484_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r484_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r484_callers',(SELECT string_agg(p.oid::regprocedure::text||'='||md5(p.prosrc),',' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
   WHERE p.prokind='f' AND p.proname<>'revolution_parts_authenticated_20261006' AND p.prosrc LIKE '%revolution_parts_authenticated_20261006%'),true);
 PERFORM set_config('pdc.r484_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r484_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r484: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p WHERE p.oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM 'bd378910e0328a5c6bcab980195d73d4'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '67d03f901dc6ba475691a9661fff8826' THEN RAISE EXCEPTION 'r484: parts sign-in check is not the version this release was prepared on'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)' OR release='r484')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_auth_pdc_mailbox_484' OR added_in='r484') THEN RAISE EXCEPTION 'r484: already applied (or pinned since prepared)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=284 OR fault_id='F97') THEN RAISE EXCEPTION 'r484: sort_order 284 / F97 taken'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_auth jsonb, p_message_id text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT coalesce(jsonb_typeof(p_auth)='object'
  AND p_message_id ~ '^[a-f0-9]{10,40}$' AND p_auth->>'gmail_message_id'=p_message_id
  AND p_auth->>'from_address'='noreply@revolutionsoftware.com.au'
  AND p_auth->>'mailbox'='pmbcontroller@gmail.com' AND (p_auth->>'to_address'='pmbcontroller@gmail.com' OR (p_auth->>'to_address'='craig.watson@broometoyota.com.au' AND p_auth->'cc_addresses' @> '["pmbcontroller@gmail.com"]'::jsonb)
   -- r484 (F97): Revolution's Pilbara parts report, To pdc@pmgwa.com.au with Craig on CC (still delivered to the pmbcontroller mailbox)
   OR (p_auth->>'to_address'='pdc@pmgwa.com.au' AND p_auth->'cc_addresses' @> '["craig.watson@broometoyota.com.au"]'::jsonb))
  AND p_auth->>'verified_by'='gmail_receiving_provider' AND p_auth->>'header_from'='revolutionsoftware.com.au'
  AND coalesce(nullif(p_auth->>'reply_to',''),'noreply@revolutionsoftware.com.au')='noreply@revolutionsoftware.com.au'
  AND p_auth->>'authentication_results' ~* '^mx[.]google[.]com;'
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=noreply@revolutionsoftware[.]com[.]au([;[:space:]]|$)'
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from=revolutionsoftware[.]com[.]au([;[:space:]]|$)',false);
$function$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at) VALUES
 ('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)','6c1a612f6ed82dfcbf5788c17d2e5d87','r484','r484 (F97): + To pdc@pmgwa.com.au with Craig on CC (was 67d03f901dc6ba475691a9661fff8826, unpinned)',now());

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('parts_auth_pdc_mailbox_484','F97','Revolution report sign-in check (r484): pinned, same settings (sql, immutable, search_path pg_catalog, not security definer, owner postgres, EXECUTE postgres only); 26 synthetic headers: both old To/CC cases and To pdc@pmgwa.com.au with Craig on CC pass; To pdc@ without Craig on CC, another CC, another To address or domain, case or space changes, wrong sender / header from / reply-to / mailbox / verifier, SPF fail, DMARC fail, not mx.google.com and a message id mismatch all fail',
  $chk$WITH f AS (
  SELECT p.oid, md5(p.prosrc) m, p.prosecdef, p.provolatile, p.proconfig, p.proacl::text acl, pg_catalog.pg_get_userbyid(p.proowner) own
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')
), pin AS (
  SELECT count(*) n, count(*) FILTER (WHERE e.prosrc_md5=(SELECT m FROM f)) ok FROM pdc_ops.expected_function_md5 e
  WHERE e.signature='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'
), base AS (
  SELECT jsonb_build_object('gmail_message_id','a484a484a484a484','from_address','noreply@revolutionsoftware.com.au','mailbox','pmbcontroller@gmail.com',
   'to_address','pdc@pmgwa.com.au','cc_addresses',jsonb_build_array('craig.watson@broometoyota.com.au'),'verified_by','gmail_receiving_provider',
   'header_from','revolutionsoftware.com.au','reply_to','noreply@revolutionsoftware.com.au',
   'authentication_results','mx.google.com;       spf=pass (google.com: domain of noreply@revolutionsoftware.com.au designates 192.0.2.10 as permitted sender) smtp.mailfrom=noreply@revolutionsoftware.com.au;       dmarc=pass (p=QUARANTINE sp=QUARANTINE dis=NONE) header.from=revolutionsoftware.com.au') a
), cases(name, want, a) AS (
  SELECT 'old: To pmbcontroller', true, (SELECT a FROM base)||'{"to_address":"pmbcontroller@gmail.com","cc_addresses":[]}' UNION ALL
  SELECT 'old: To Craig, CC pmbcontroller', true, (SELECT a FROM base)||'{"to_address":"craig.watson@broometoyota.com.au","cc_addresses":["pmbcontroller@gmail.com"]}' UNION ALL
  SELECT 'new: To pdc, CC Craig', true, (SELECT a FROM base) UNION ALL
  SELECT 'new: To pdc, CC Craig + another', true, (SELECT a FROM base)||'{"cc_addresses":["someone@pmgwa.com.au","craig.watson@broometoyota.com.au"]}' UNION ALL
  SELECT 'To pdc, no CC', false, (SELECT a FROM base)-'cc_addresses' UNION ALL
  SELECT 'To pdc, empty CC', false, (SELECT a FROM base)||'{"cc_addresses":[]}' UNION ALL
  SELECT 'To pdc, CC someone else', false, (SELECT a FROM base)||'{"cc_addresses":["someone@pmgwa.com.au"]}' UNION ALL
  SELECT 'To pdc, CC pmbcontroller only', false, (SELECT a FROM base)||'{"cc_addresses":["pmbcontroller@gmail.com"]}' UNION ALL
  SELECT 'To pdc, CC Craig as text', false, (SELECT a FROM base)||'{"cc_addresses":"craig.watson@broometoyota.com.au"}' UNION ALL
  SELECT 'To pdc, CC Craig other domain', false, (SELECT a FROM base)||'{"cc_addresses":["craig.watson@pmgwa.com.au"]}' UNION ALL
  SELECT 'To pdc other domain', false, (SELECT a FROM base)||'{"to_address":"pdc@pmgwa.com"}' UNION ALL
  SELECT 'To pdc lookalike domain', false, (SELECT a FROM base)||'{"to_address":"pdc@pmgwa.com.au.example.net"}' UNION ALL
  SELECT 'To someone else @pmgwa', false, (SELECT a FROM base)||'{"to_address":"parts@pmgwa.com.au"}' UNION ALL
  SELECT 'To pdc upper case', false, (SELECT a FROM base)||'{"to_address":"PDC@PMGWA.COM.AU"}' UNION ALL
  SELECT 'To pdc with spaces', false, (SELECT a FROM base)||'{"to_address":" pdc@pmgwa.com.au "}' UNION ALL
  SELECT 'To Craig, CC Craig', false, (SELECT a FROM base)||'{"to_address":"craig.watson@broometoyota.com.au"}' UNION ALL
  SELECT 'wrong sender', false, (SELECT a FROM base)||'{"from_address":"noreply@revolutionsoftware.com"}' UNION ALL
  SELECT 'wrong header from', false, (SELECT a FROM base)||'{"header_from":"example.com"}' UNION ALL
  SELECT 'wrong reply-to', false, (SELECT a FROM base)||'{"reply_to":"someone@example.com"}' UNION ALL
  SELECT 'wrong mailbox', false, (SELECT a FROM base)||'{"mailbox":"pdc@pmgwa.com.au"}' UNION ALL
  SELECT 'not verified by gmail', false, (SELECT a FROM base)||'{"verified_by":"self"}' UNION ALL
  SELECT 'SPF fail', false, (SELECT a FROM base)||jsonb_build_object('authentication_results',replace((SELECT a->>'authentication_results' FROM base),'spf=pass','spf=fail')) UNION ALL
  SELECT 'DMARC fail', false, (SELECT a FROM base)||jsonb_build_object('authentication_results',replace((SELECT a->>'authentication_results' FROM base),'dmarc=pass','dmarc=fail')) UNION ALL
  SELECT 'not mx.google.com', false, (SELECT a FROM base)||jsonb_build_object('authentication_results',replace((SELECT a->>'authentication_results' FROM base),'mx.google.com;','mx.example.com;')) UNION ALL
  SELECT 'message id mismatch', false, (SELECT a FROM base)||'{"gmail_message_id":"b484b484b484b484"}' UNION ALL
  SELECT 'not an object', false, '["x"]'::jsonb
), r AS (
  SELECT name, want, pdc_codex_intake_private.revolution_parts_authenticated_20261006(a,'a484a484a484a484') got FROM cases
)
SELECT (SELECT count(*)=1 FROM f) AND (SELECT NOT prosecdef AND provolatile='i' AND proconfig='{search_path=pg_catalog}' AND acl='{postgres=X/postgres}' AND own='postgres' FROM f)
   AND (SELECT n=1 AND ok=1 FROM pin)
   AND (SELECT count(*)=26 AND bool_and(got IS NOT DISTINCT FROM want) FROM r) AS ok,
 'parts auth pin '||(SELECT ok FROM pin)||'/'||(SELECT n FROM pin)||'; settings '||coalesce((SELECT (NOT prosecdef AND provolatile='i' AND proconfig='{search_path=pg_catalog}' AND acl='{postgres=X/postgres}' AND own='postgres')::text FROM f),'missing')
 ||'; cases right '||(SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) FROM r)||'/'||(SELECT count(*) FROM r)
 ||coalesce(' (WRONG: '||(SELECT string_agg(name||' -> '||coalesce(got::text,'null'),'; ') FROM r WHERE got IS DISTINCT FROM want)||')','') AS detail$chk$,true,284,'r484');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'::regprocedure) IS DISTINCT FROM '6c1a612f6ed82dfcbf5788c17d2e5d87'
    OR (SELECT md5(pg_get_functiondef('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'::regprocedure))) IS DISTINCT FROM 'abbb00e85839a85c47df7de16c9895bd'
    OR (SELECT position(chr(13) IN prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'::regprocedure)<>0 THEN RAISE EXCEPTION 'r484: function did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'::regprocedure AND NOT p.prosecdef AND p.provolatile='i' AND p.proconfig='{search_path=pg_catalog}'
     AND p.proacl::text='{postgres=X/postgres}' AND pg_get_userbyid(p.proowner)='postgres' AND p.prorettype='boolean'::regtype AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='sql'))<>1
   THEN RAISE EXCEPTION 'r484: owner / grants / security / volatility not as before'; END IF;
 IF (SELECT string_agg(p.oid::regprocedure::text||'='||md5(p.prosrc),',' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
   WHERE p.prokind='f' AND p.proname<>'revolution_parts_authenticated_20261006' AND p.prosrc LIKE '%revolution_parts_authenticated_20261006%') IS DISTINCT FROM current_setting('pdc.r484_callers') THEN RAISE EXCEPTION 'r484: a caller changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r484_tick') THEN RAISE EXCEPTION 'r484: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r484_frc') THEN RAISE EXCEPTION 'r484: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r484')<>1 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r484_pins')::int+1 THEN RAISE EXCEPTION 'r484: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='parts_auth_pdc_mailbox_484' AND added_in='r484' AND sort_order=284) IS DISTINCT FROM '92a3df8531f68e6eaf83d6438c059d59' THEN RAISE EXCEPTION 'r484: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_auth_pdc_mailbox_484') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r484: check not OK: %',y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
