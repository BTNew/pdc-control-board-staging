-- r484 undo (F97). Staging cdsmnqxtyyoeoznmbidd only; run between :02 and :45. Restores the exact pre-r484 body of
-- pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text) (functiondef md5 bd378910e0328a5c6bcab980195d73d4, prosrc md5 67d03f901dc6ba475691a9661fff8826,
-- with its original CRLF line ends), drops the r484 pin (the function was unpinned before r484) and check parts_auth_pdc_mailbox_484.
-- The old body is written here with LF line ends and turned back into CRLF with chr(13) in SQL, so it survives any transport.
-- Parts reports addressed To pdc@pmgwa.com.au with Craig on CC are held again after this. Revert the PR as well.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r484 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r484 undo: staging only'; END IF;
 PERFORM set_config('pdc.r484_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r484_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r484_callers',(SELECT string_agg(p.oid::regprocedure::text||'='||md5(p.prosrc),',' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
   WHERE p.prokind='f' AND p.proname<>'revolution_parts_authenticated_20261006' AND p.prosrc LIKE '%revolution_parts_authenticated_20261006%'),true);
 PERFORM set_config('pdc.r484_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r484_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r484 undo: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '6c1a612f6ed82dfcbf5788c17d2e5d87' THEN RAISE EXCEPTION 'r484 undo: function is not the r484 version; not undoing over unknown changes'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r484' AND signature='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')<>1 OR (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r484')<>1
    OR NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_auth_pdc_mailbox_484' AND added_in='r484') THEN RAISE EXCEPTION 'r484 undo: r484 is not applied'; END IF;
END $g$;
DO $u$ DECLARE src text := $old$

 SELECT coalesce(jsonb_typeof(p_auth)='object'
  AND p_message_id ~ '^[a-f0-9]{10,40}$' AND p_auth->>'gmail_message_id'=p_message_id
  AND p_auth->>'from_address'='noreply@revolutionsoftware.com.au'
  AND p_auth->>'mailbox'='pmbcontroller@gmail.com' AND (p_auth->>'to_address'='pmbcontroller@gmail.com' OR (p_auth->>'to_address'='craig.watson@broometoyota.com.au' AND p_auth->'cc_addresses' @> '["pmbcontroller@gmail.com"]'::jsonb))
  AND p_auth->>'verified_by'='gmail_receiving_provider' AND p_auth->>'header_from'='revolutionsoftware.com.au'
  AND coalesce(nullif(p_auth->>'reply_to',''),'noreply@revolutionsoftware.com.au')='noreply@revolutionsoftware.com.au'
  AND p_auth->>'authentication_results' ~* '^mx[.]google[.]com;'
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=noreply@revolutionsoftware[.]com[.]au([;[:space:]]|$)'
  AND p_auth->>'authentication_results' ~* '(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from=revolutionsoftware[.]com[.]au([;[:space:]]|$)',false);
$old$; BEGIN
 -- $old$ ... $old$ holds the old body with LF line ends plus one leading line break added here for readability; drop it, then CRLF.
 src := replace(substr(src, 2), chr(10), chr(13)||chr(10));
 IF md5(src) IS DISTINCT FROM '67d03f901dc6ba475691a9661fff8826' THEN RAISE EXCEPTION 'r484 undo: rebuilt old body md5 % is not 67d03f901dc6ba475691a9661fff8826', md5(src); END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_auth jsonb, p_message_id text)'||chr(10)
   ||' RETURNS boolean'||chr(10)||' LANGUAGE sql'||chr(10)||' IMMUTABLE'||chr(10)||' SET search_path TO ''pg_catalog'''||chr(10)
   ||'AS '||quote_literal(src);
END $u$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='parts_auth_pdc_mailbox_484' AND added_in='r484';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r484' AND signature='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)';
DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'::regprocedure) IS DISTINCT FROM '67d03f901dc6ba475691a9661fff8826'
    OR md5(pg_get_functiondef('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'::regprocedure)) IS DISTINCT FROM 'bd378910e0328a5c6bcab980195d73d4' THEN RAISE EXCEPTION 'r484 undo: old body not restored exactly'; END IF;
 IF (SELECT count(*) FROM pg_proc p WHERE p.oid='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)'::regprocedure AND NOT p.prosecdef AND p.provolatile='i' AND p.proconfig='{search_path=pg_catalog}'
     AND p.proacl::text='{postgres=X/postgres}' AND pg_get_userbyid(p.proowner)='postgres' AND p.prorettype='boolean'::regtype AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='sql'))<>1
   THEN RAISE EXCEPTION 'r484 undo: owner / grants / security / volatility not as before'; END IF;
 IF (SELECT string_agg(p.oid::regprocedure::text||'='||md5(p.prosrc),',' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
   WHERE p.prokind='f' AND p.proname<>'revolution_parts_authenticated_20261006' AND p.prosrc LIKE '%revolution_parts_authenticated_20261006%') IS DISTINCT FROM current_setting('pdc.r484_callers') THEN RAISE EXCEPTION 'r484 undo: a caller changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r484_tick') THEN RAISE EXCEPTION 'r484 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r484_frc') THEN RAISE EXCEPTION 'r484 undo: fault_regression_check changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r484' OR signature='pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r484')
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r484_pins')::int-1 THEN RAISE EXCEPTION 'r484 undo: did not fully undo'; END IF;
END $g$;
