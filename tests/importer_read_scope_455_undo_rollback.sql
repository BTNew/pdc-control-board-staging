-- r455 (F68) rolled-back test B: apply -> undo (byte-identical restore) -> re-apply; everything is rolled back (R455_RB_B).
-- Rolled-back release test window (F15, r405). Paste at the very top of every rolled-back test
-- that calls board write functions, and replace R455 with the release tag (e.g. R405).
--
-- Why: board write functions take the top-level change lock
-- (pg_advisory_xact_lock('pdc:workshop:top-level-mutation')) and keep it until the test's
-- ROLLBACK. The live clock tick runs every minute at :00 and waits only 3 s for that lock
-- (lock_timeout), so a test that holds it across a minute boundary makes the real tick fail
-- (21:25, 21:28 and 21:30 AWST on 20 Oct 2026, r404 tests).
--
-- Rule: 1) wait until this minute's tick has finished, 2) start between :02 and :15,
-- 3) never wait long for a live lock (lock_timeout 2 s), 4) stop and roll back before :50
-- (each statement's statement_timeout is cut to the time left; call pg_temp.deadline() before
-- each step). Locks are only taken after step 1, so waiting holds nothing.

-- 1+2. Wait for the tick (holds no locks; reads cron history only).
DO $window_wait$
DECLARE i integer := 0;
BEGIN
  LOOP
    EXIT WHEN extract(second FROM clock_timestamp()) BETWEEN 2 AND 15
      AND EXISTS (SELECT 1 FROM cron.job_run_details d JOIN cron.job j USING (jobid)
                  WHERE j.jobname = 'staging-workshop-clock-cascade'
                    AND d.start_time >= date_trunc('minute', clock_timestamp())
                    AND d.end_time IS NOT NULL);
    i := i + 1;
    IF i > 75 THEN RAISE EXCEPTION 'R455_WINDOW: clock tick not seen; test not started'; END IF;
    PERFORM pg_sleep(1);
  END LOOP;
END $window_wait$;
BEGIN;
SET LOCAL lock_timeout='2s';
CREATE TEMP TABLE t_res(k text, v jsonb) ON COMMIT DROP;
-- r455 (F68, Craig 22 Oct, decision 3): importers can open a vehicle's drop-down read-only. Before, the Workshop detail and
-- booking search read scope (workshop_read_actor_scope_20261013) had no rule for the importer role: an importer without a
-- dealer-scope row fell through to pdc_auditor_actor_scope(), which allows viewer/operator/administrator only, and the
-- drop-down failed (pdc_auditor_unauthorized).
-- Fix: workshop_importer_read_scope_455 gives an approved, active importer with no dealer-scope row the shared board's
-- dealer 14450 as a VIEWER scope (actor_role importer, read_only true). Only get_vehicle_workshop_detail_scoped and
-- get_workshop_booking_search_scoped use workshop_read_actor_scope_20261013 (the check proves it). pdc_auditor_actor_scope()
-- and every write function are unchanged, so an importer gains no write right. New check importer_read_scope_455 (sort 254).
-- Not touched: workshop_clock_tick, any data row, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r455: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r455: staging only'; END IF;
 PERFORM set_config('pdc.r455_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r455_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r455_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r455: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r455') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455' OR added_in='r455') THEN RAISE EXCEPTION 'r455: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=254) THEN RAISE EXCEPTION 'r455: sort_order 254 taken'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()') IS NOT NULL THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() already exists'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '40bf35bd9a5d0986a298f900ffcb941d' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.workshop_read_actor_scope_20261013()') IS DISTINCT FROM '40bf35bd9a5d0986a298f900ffcb941d|r423' THEN RAISE EXCEPTION 'r455: pin of pdc_codex_intake_private.workshop_read_actor_scope_20261013() not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_auditor_actor_scope()'::regprocedure) IS DISTINCT FROM '79ddabb0a8fef13fad26e82151fcbc44' THEN RAISE EXCEPTION 'r455: pdc_auditor_actor_scope changed'; END IF;
 PERFORM set_config('pdc.r455_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_importer_read_scope_455()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 -- r455 (F68): read scope for an approved, active importer who has NO dealer-scope row (active or not): the shared board's
 -- dealer 14450, as a viewer, so the importer can open a vehicle's drop-down read-only. Only the two Workshop read functions
 -- (get_vehicle_workshop_detail_scoped, get_workshop_booking_search_scoped) use this scope; every write function keeps its own
 -- role check, so an importer gains no write. The AI Auditor still uses pdc_auditor_actor_scope() only.
 SELECT CASE WHEN count(*)=1 THEN jsonb_build_object(
   'user_id',auth.uid(),'email',lower(btrim(coalesce(auth.jwt()->>'email',''))),'role','viewer','actor_role','importer',
   'dealer_code','14450','environment','staging','scope_source','importer_read_455','read_only',true) ELSE NULL END
 FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE public.pdc_monitor_staging_guard()
   AND auth.uid() IS NOT NULL AND u.id=auth.uid()
   AND lower(coalesce(u.email,''))=lower(btrim(coalesce(auth.jwt()->>'email','')))
   AND lower(r.email)=lower(coalesce(u.email,''))
   AND r.active AND r.account_status='approved' AND r.role::text='importer'
   AND (u.banned_until IS NULL OR u.banned_until<=now())
   AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s
     WHERE s.auth_user_id=auth.uid() OR s.normalized_email=lower(coalesce(u.email,'')))
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_importer_read_scope_455() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_actor_scope_20261013()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ DECLARE s jsonb; BEGIN
 s:=public.pdc_workshop_controller_scope_423();
 IF s IS NOT NULL THEN RETURN s; END IF;
 s:=pdc_codex_intake_private.workshop_delegated138_identity_20261013(auth.uid(),auth.jwt()->>'email');
 IF s IS NOT NULL THEN RETURN s; END IF;
 -- r455 (F68): an approved importer with no dealer-scope row reads the shared board's dealer 14450, read only.
 s:=pdc_codex_intake_private.workshop_importer_read_scope_455();
 IF s IS NOT NULL THEN RETURN s; END IF;
 RETURN public.pdc_auditor_actor_scope();
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f7dedb862bdc1d85afd7d2392141c946',release='r455',note='r455: importer read scope after controller and delegated (F68); r423 controller scope first',updated_at=clock_timestamp() WHERE signature='pdc_codex_intake_private.workshop_read_actor_scope_20261013()';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_codex_intake_private.workshop_importer_read_scope_455()','93ac42208534e22089c70e025db9cf84','r455','r455: importer read-only scope (board dealer 14450, viewer) (F68)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('importer_read_scope_455','F68','Importers open vehicle drop-downs read-only; the importer read scope reaches only the two Workshop read functions (r455)',$chk$WITH pins AS (
  SELECT count(*) n, count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) ok
  FROM pdc_ops.expected_function_md5 e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature) WHERE e.release='r455'),
scope_users AS (
  SELECT count(*) FILTER (WHERE p.oid NOT IN (pg_catalog.to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)'),
     pg_catalog.to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)'))) other
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname<>'karratha135_pdc' AND strpos(p.prosrc,'workshop_read_actor_scope_20261013(')>0),
importer_users AS (
  SELECT count(*) FILTER (WHERE p.oid<>pg_catalog.to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) other
  FROM pg_catalog.pg_proc p WHERE strpos(p.prosrc,'workshop_importer_read_scope_455(')>0),
auditor AS (
  SELECT strpos(p.prosrc,'r.role::text in (''viewer'',''operator'',''administrator'')')>0 ok
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_auditor_actor_scope()'))
SELECT (SELECT n FROM pins)=2 AND (SELECT ok FROM pins)=2 AND (SELECT other FROM scope_users)=0 AND (SELECT other FROM importer_users)=0
  AND coalesce((SELECT ok FROM auditor),false) AS ok,
 'Importer read scope (r455): r455 pins matching '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)
 ||'; other functions using the Workshop read scope: '||(SELECT other FROM scope_users)||' (must be 0: read paths only)'
 ||'; other functions using the importer scope: '||(SELECT other FROM importer_users)
 ||'; AI Auditor scope still viewer/operator/administrator only: '||CASE WHEN coalesce((SELECT ok FROM auditor),false) THEN 'yes' ELSE 'NO' END AS detail$chk$,true,254,'r455');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM 'f7dedb862bdc1d85afd7d2392141c946' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()')) IS DISTINCT FROM '93ac42208534e22089c70e025db9cf84' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() owner/ACL/settings not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r455')<>2 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r455_pins')::int+1 THEN RAISE EXCEPTION 'r455: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455' AND added_in='r455' AND sort_order=254) IS DISTINCT FROM 'fc188cad04093d1c7f4172e80bc4421f' THEN RAISE EXCEPTION 'r455: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR x IN SELECT r.check_name, r.check_sql FROM pdc_ops.regression_checks r WHERE r.check_name IN ('importer_read_scope_455') LOOP
  DECLARE y record; BEGIN EXECUTE x.check_sql INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r455: check % not OK: %',x.check_name,y.detail; END IF; END;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r455_tick') THEN RAISE EXCEPTION 'r455: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r455_frc') THEN RAISE EXCEPTION 'r455: fault_regression_check changed'; END IF;
END $g$;

INSERT INTO t_res SELECT 'applied', jsonb_build_object('pins',(SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r455'));
-- r455 undo (F68): restores workshop_read_actor_scope_20261013 byte for byte (md5 40bf35bd9a5d0986a298f900ffcb941d) and its r423
-- pin, drops workshop_importer_read_scope_455, its pin and check importer_read_scope_455. Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r455 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r455 undo: staging only'; END IF;
 PERFORM set_config('pdc.r455_undo_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r455_undo_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r455_undo_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r455 undo: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM 'f7dedb862bdc1d85afd7d2392141c946' THEN RAISE EXCEPTION 'r455 undo: pdc_codex_intake_private.workshop_read_actor_scope_20261013() is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()')) IS DISTINCT FROM '93ac42208534e22089c70e025db9cf84' THEN RAISE EXCEPTION 'r455 undo: pdc_codex_intake_private.workshop_importer_read_scope_455() is not the expected version'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455' AND added_in='r455') THEN RAISE EXCEPTION 'r455 undo: r455 is not applied'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_actor_scope_20261013()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ DECLARE s jsonb; BEGIN
 s:=public.pdc_workshop_controller_scope_423();
 IF s IS NOT NULL THEN RETURN s; END IF;
 s:=pdc_codex_intake_private.workshop_delegated138_identity_20261013(auth.uid(),auth.jwt()->>'email');
 IF s IS NOT NULL THEN RETURN s; END IF;
 RETURN public.pdc_auditor_actor_scope();
END $function$;

DROP FUNCTION pdc_codex_intake_private.workshop_importer_read_scope_455();
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='40bf35bd9a5d0986a298f900ffcb941d',release='r423',note='controller scope first (was ce8d10d6c6d7076cbc58d7d3c65a03e8)',updated_at=clock_timestamp() WHERE signature='pdc_codex_intake_private.workshop_read_actor_scope_20261013()';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r455';
DELETE FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455' AND added_in='r455';

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '40bf35bd9a5d0986a298f900ffcb941d' THEN RAISE EXCEPTION 'r455 undo: pdc_codex_intake_private.workshop_read_actor_scope_20261013() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455 undo: pdc_codex_intake_private.workshop_read_actor_scope_20261013() owner/ACL/settings not as expected'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()') IS NOT NULL THEN RAISE EXCEPTION 'r455 undo: pdc_codex_intake_private.workshop_importer_read_scope_455() still exists'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r455') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r455') THEN RAISE EXCEPTION 'r455 undo: leftovers'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r455_undo_tick') THEN RAISE EXCEPTION 'r455 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r455_undo_frc') THEN RAISE EXCEPTION 'r455 undo: fault_regression_check changed'; END IF;
END $g$;

INSERT INTO t_res SELECT 'undone', jsonb_build_object('md5',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.workshop_read_actor_scope_20261013()'::regprocedure),'helper_gone',to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()') IS NULL,'pin',(SELECT release||':'||prosrc_md5||':'||coalesce(note,'NULL') FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.workshop_read_actor_scope_20261013()'),'check_gone',NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455'));
-- r455 (F68, Craig 22 Oct, decision 3): importers can open a vehicle's drop-down read-only. Before, the Workshop detail and
-- booking search read scope (workshop_read_actor_scope_20261013) had no rule for the importer role: an importer without a
-- dealer-scope row fell through to pdc_auditor_actor_scope(), which allows viewer/operator/administrator only, and the
-- drop-down failed (pdc_auditor_unauthorized).
-- Fix: workshop_importer_read_scope_455 gives an approved, active importer with no dealer-scope row the shared board's
-- dealer 14450 as a VIEWER scope (actor_role importer, read_only true). Only get_vehicle_workshop_detail_scoped and
-- get_workshop_booking_search_scoped use workshop_read_actor_scope_20261013 (the check proves it). pdc_auditor_actor_scope()
-- and every write function are unchanged, so an importer gains no write right. New check importer_read_scope_455 (sort 254).
-- Not touched: workshop_clock_tick, any data row, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r455: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r455: staging only'; END IF;
 PERFORM set_config('pdc.r455_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r455_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r455_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r455: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r455') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455' OR added_in='r455') THEN RAISE EXCEPTION 'r455: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=254) THEN RAISE EXCEPTION 'r455: sort_order 254 taken'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()') IS NOT NULL THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() already exists'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '40bf35bd9a5d0986a298f900ffcb941d' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.workshop_read_actor_scope_20261013()') IS DISTINCT FROM '40bf35bd9a5d0986a298f900ffcb941d|r423' THEN RAISE EXCEPTION 'r455: pin of pdc_codex_intake_private.workshop_read_actor_scope_20261013() not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_auditor_actor_scope()'::regprocedure) IS DISTINCT FROM '79ddabb0a8fef13fad26e82151fcbc44' THEN RAISE EXCEPTION 'r455: pdc_auditor_actor_scope changed'; END IF;
 PERFORM set_config('pdc.r455_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_importer_read_scope_455()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 -- r455 (F68): read scope for an approved, active importer who has NO dealer-scope row (active or not): the shared board's
 -- dealer 14450, as a viewer, so the importer can open a vehicle's drop-down read-only. Only the two Workshop read functions
 -- (get_vehicle_workshop_detail_scoped, get_workshop_booking_search_scoped) use this scope; every write function keeps its own
 -- role check, so an importer gains no write. The AI Auditor still uses pdc_auditor_actor_scope() only.
 SELECT CASE WHEN count(*)=1 THEN jsonb_build_object(
   'user_id',auth.uid(),'email',lower(btrim(coalesce(auth.jwt()->>'email',''))),'role','viewer','actor_role','importer',
   'dealer_code','14450','environment','staging','scope_source','importer_read_455','read_only',true) ELSE NULL END
 FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE public.pdc_monitor_staging_guard()
   AND auth.uid() IS NOT NULL AND u.id=auth.uid()
   AND lower(coalesce(u.email,''))=lower(btrim(coalesce(auth.jwt()->>'email','')))
   AND lower(r.email)=lower(coalesce(u.email,''))
   AND r.active AND r.account_status='approved' AND r.role::text='importer'
   AND (u.banned_until IS NULL OR u.banned_until<=now())
   AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s
     WHERE s.auth_user_id=auth.uid() OR s.normalized_email=lower(coalesce(u.email,'')))
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_importer_read_scope_455() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_actor_scope_20261013()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ DECLARE s jsonb; BEGIN
 s:=public.pdc_workshop_controller_scope_423();
 IF s IS NOT NULL THEN RETURN s; END IF;
 s:=pdc_codex_intake_private.workshop_delegated138_identity_20261013(auth.uid(),auth.jwt()->>'email');
 IF s IS NOT NULL THEN RETURN s; END IF;
 -- r455 (F68): an approved importer with no dealer-scope row reads the shared board's dealer 14450, read only.
 s:=pdc_codex_intake_private.workshop_importer_read_scope_455();
 IF s IS NOT NULL THEN RETURN s; END IF;
 RETURN public.pdc_auditor_actor_scope();
END $function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f7dedb862bdc1d85afd7d2392141c946',release='r455',note='r455: importer read scope after controller and delegated (F68); r423 controller scope first',updated_at=clock_timestamp() WHERE signature='pdc_codex_intake_private.workshop_read_actor_scope_20261013()';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_codex_intake_private.workshop_importer_read_scope_455()','93ac42208534e22089c70e025db9cf84','r455','r455: importer read-only scope (board dealer 14450, viewer) (F68)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('importer_read_scope_455','F68','Importers open vehicle drop-downs read-only; the importer read scope reaches only the two Workshop read functions (r455)',$chk$WITH pins AS (
  SELECT count(*) n, count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) ok
  FROM pdc_ops.expected_function_md5 e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature) WHERE e.release='r455'),
scope_users AS (
  SELECT count(*) FILTER (WHERE p.oid NOT IN (pg_catalog.to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)'),
     pg_catalog.to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)'))) other
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname<>'karratha135_pdc' AND strpos(p.prosrc,'workshop_read_actor_scope_20261013(')>0),
importer_users AS (
  SELECT count(*) FILTER (WHERE p.oid<>pg_catalog.to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) other
  FROM pg_catalog.pg_proc p WHERE strpos(p.prosrc,'workshop_importer_read_scope_455(')>0),
auditor AS (
  SELECT strpos(p.prosrc,'r.role::text in (''viewer'',''operator'',''administrator'')')>0 ok
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_auditor_actor_scope()'))
SELECT (SELECT n FROM pins)=2 AND (SELECT ok FROM pins)=2 AND (SELECT other FROM scope_users)=0 AND (SELECT other FROM importer_users)=0
  AND coalesce((SELECT ok FROM auditor),false) AS ok,
 'Importer read scope (r455): r455 pins matching '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)
 ||'; other functions using the Workshop read scope: '||(SELECT other FROM scope_users)||' (must be 0: read paths only)'
 ||'; other functions using the importer scope: '||(SELECT other FROM importer_users)
 ||'; AI Auditor scope still viewer/operator/administrator only: '||CASE WHEN coalesce((SELECT ok FROM auditor),false) THEN 'yes' ELSE 'NO' END AS detail$chk$,true,254,'r455');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM 'f7dedb862bdc1d85afd7d2392141c946' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_actor_scope_20261013()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_read_actor_scope_20261013() owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()')) IS DISTINCT FROM '93ac42208534e22089c70e025db9cf84' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_importer_read_scope_455()')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r455: pdc_codex_intake_private.workshop_importer_read_scope_455() owner/ACL/settings not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r455')<>2 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r455_pins')::int+1 THEN RAISE EXCEPTION 'r455: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='importer_read_scope_455' AND added_in='r455' AND sort_order=254) IS DISTINCT FROM 'fc188cad04093d1c7f4172e80bc4421f' THEN RAISE EXCEPTION 'r455: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR x IN SELECT r.check_name, r.check_sql FROM pdc_ops.regression_checks r WHERE r.check_name IN ('importer_read_scope_455') LOOP
  DECLARE y record; BEGIN EXECUTE x.check_sql INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r455: check % not OK: %',x.check_name,y.detail; END IF; END;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r455_tick') THEN RAISE EXCEPTION 'r455: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r455_frc') THEN RAISE EXCEPTION 'r455: fault_regression_check changed'; END IF;
END $g$;

INSERT INTO t_res SELECT 'reapplied', to_jsonb((SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r455'));
DO $f$ BEGIN RAISE EXCEPTION 'R455_RB_B %', (SELECT jsonb_object_agg(k,v) FROM t_res); END $f$;