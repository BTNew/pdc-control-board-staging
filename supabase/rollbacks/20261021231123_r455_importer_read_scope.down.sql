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
