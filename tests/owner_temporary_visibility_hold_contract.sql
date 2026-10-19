-- Pure contract assertions. Actual owner-scoped preservation/refresh rehearsal is private evidence.
BEGIN;
DO $checks$ BEGIN
IF pdc_codex_intake_private.owner_board_hold_active_20261019(NULL,'unmatched-contract-identity',NULL) THEN RAISE EXCEPTION 'unmatched_hidden';END IF;
IF has_function_privilege('authenticated','pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid)','execute') OR has_function_privilege('anon','pdc_codex_intake_private.enforce_owner_board_hold_20261019()','execute') OR has_table_privilege('service_role','pdc_codex_intake_private.owner_board_visibility_holds_20261019','update') THEN RAISE EXCEPTION 'hold_contract_exposed';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='pdc_codex_intake_private' AND c.relname='owner_board_visibility_holds_20261019' AND c.relrowsecurity) THEN RAISE EXCEPTION 'rls_missing';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='z_owner_board_hold_20261019' AND NOT tgisinternal) THEN RAISE EXCEPTION 'future_visibility_guard_missing';END IF;
END $checks$;
SELECT 'PASS: unmatched isolation, private execution/data permissions, RLS and future refresh guard' result;
ROLLBACK;
