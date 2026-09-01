#!/usr/bin/env python3
"""Read-only catalog/RLS/publication proof for the successor inbox projection."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
TARGET = ("20260901010000", "latest100_attachment_work_receipt_successor")


def one(cursor, sql: str):
    cursor.execute(sql)
    return cursor.fetchone()


def main() -> None:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_SUCCESSOR_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SUCCESSOR_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    bundle = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(bundle)
    if STAGING_REF not in bundle.get("PDC_STAGING_DATABASE_URL", ""):
        raise RuntimeError("PDC_SUCCESSOR_NON_STAGING_TARGET")
    import psycopg2

    connection = psycopg2.connect(
        bundle["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=bundle["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-successor-inbox-readonly-verifier",
    )
    try:
        cursor = connection.cursor()
        ledger = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version='20260901010000'") or ())
        rpc = bool(one(cursor, "select to_regprocedure('public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)') is not null")[0])
        revision = bool(one(cursor, "select to_regclass('public.pdc_email_ai_successor_ui_revision') is not null")[0])
        typed_plan = bool(one(cursor, "select exists(select 1 from information_schema.columns where table_schema='public' and table_name='pdc_email_ai_successor_transaction_receipts' and column_name='typed_plan')")[0])
        publication = bool(one(cursor, "select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_email_ai_successor_ui_revision')")[0])
        rls = tuple(one(cursor, "select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_email_ai_successor_ui_revision'::regclass") or ())
        authenticated_execute = bool(one(cursor, "select has_function_privilege('authenticated','public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)','execute')")[0])
        service_execute = bool(one(cursor, "select has_function_privilege('service_role','public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)','execute')")[0])
        command_source = (one(cursor, "select pg_get_functiondef('public.apply_pdc_email_ai_transaction_successor(jsonb)'::regprocedure)")[0] or "") + (one(cursor, "select pg_get_functiondef('public.apply_pdc_email_ai_transaction_successor__pre_hostile_gate(jsonb)'::regprocedure)")[0] or "")
        inbox_source = one(cursor, "select pg_get_functiondef('public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)'::regprocedure)")[0] or ""
        command_identity_binding = "identity_vehicle_mismatch" in command_source
        confirmed_true_guard = "IS DISTINCT FROM 'true'" in command_source
        composite_cursor = "v_cursor_created_at" in inbox_source and "v_cursor_id" in inbox_source
        waiting_status = "RECEIVED_WAITING" in inbox_source
        production = bool(one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET and rpc and revision and typed_plan and publication and rls == (True, True) and authenticated_execute and not service_execute and command_identity_binding and confirmed_true_guard and composite_cursor and waiting_status and not production,
            "environment": "staging",
            "project_ref": STAGING_REF,
            "ledger": ledger,
            "inbox_rpc_present": rpc,
            "revision_table_present": revision,
            "typed_plan_column_present": typed_plan,
            "realtime_publication_present": publication,
            "revision_rls_force": rls,
            "authenticated_execute": authenticated_execute,
            "service_role_execute": service_execute,
            "command_identity_binding": command_identity_binding,
            "confirmed_true_guard": confirmed_true_guard,
            "composite_cursor": composite_cursor,
            "legacy_status_waiting": waiting_status,
            "production_sentinel_present": production,
            "runtime_identity_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_runtime_identities")[0]),
            "transaction_receipt_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_transaction_receipts")[0]),
            "action_receipt_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_action_receipts")[0]),
            "mailbox_contacted": False,
            "outbound_email": False,
            "business_mutation": False,
        }
        print(json.dumps(proof, sort_keys=True))
        raise SystemExit(0 if proof["ok"] else 1)
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "outbound_email": False}, sort_keys=True))
        raise SystemExit(1)
