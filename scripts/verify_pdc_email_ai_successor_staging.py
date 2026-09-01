#!/usr/bin/env python3
"""Read-only live STAGING proof for the isolated successor."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
TARGET = ("20260901090000", "pdc_email_ai_typed_action_timestamp_acl_20260901")


def one(cursor, query: str):
    cursor.execute(query)
    return cursor.fetchone()[0]


def main() -> None:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    if spec is None or spec.loader is None or not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_SUCCESSOR_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec.loader.exec_module(module)
    bundle = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(bundle)
    url = bundle.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or "vjdtsswhroyguxyfjdkt" in url:
        raise RuntimeError("PDC_SUCCESSOR_NON_STAGING_TARGET")
    import psycopg2

    connection = psycopg2.connect(url, sslmode="verify-full", sslrootcert=bundle["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-transaction-successor-readonly-verifier")
    try:
        cursor = connection.cursor()
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        head = tuple(cursor.fetchone() or ())
        tables = []
        for table in ("pdc_email_ai_successor_runtime_identities", "pdc_email_ai_successor_transaction_receipts", "pdc_email_ai_successor_action_receipts"):
            cursor.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid=%s::regclass", (f"public.{table}",))
            row = cursor.fetchone()
            tables.append({"table": table, "rls": bool(row[0]) if row else False, "force_rls": bool(row[1]) if row else False})
        result = {
            "ok": head == TARGET and all(item["rls"] and item["force_rls"] for item in tables),
            "environment": "staging",
            "project_ref": STAGING_REF,
            "ledger_head": head,
            "command_rpc_present": bool(one(cursor, "select to_regprocedure('public.apply_pdc_email_ai_transaction_successor(jsonb)') is not null")),
            "health_rpc_present": bool(one(cursor, "select to_regprocedure('public.get_pdc_email_ai_successor_health()') is not null")),
            "typed_action_surface_present": bool(one(cursor, "select to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)') is not null")),
            "typed_action_contract_present": bool(one(cursor, "select to_regprocedure('public.get_pdc_email_ai_successor_action_contract_20260901()') is not null")),
            "authenticated_command_execute": bool(one(cursor, "select has_function_privilege('authenticated','public.apply_pdc_email_ai_transaction_successor(jsonb)','EXECUTE')")),
            "service_role_command_execute": bool(one(cursor, "select has_function_privilege('service_role','public.apply_pdc_email_ai_transaction_successor(jsonb)','EXECUTE')")),
            "runtime_identity_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_runtime_identities")),
            "transaction_receipt_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_transaction_receipts")),
            "action_receipt_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_action_receipts")),
            "tables": tables,
            "production_sentinel_present": bool(one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")),
            "mailbox_contacted": False,
            "outbound_email": False,
            "task_enabled": False,
            "uid514_processed": False,
        }
        result["ok"] = result["ok"] and result["command_rpc_present"] and result["health_rpc_present"] and result["typed_action_surface_present"] and result["typed_action_contract_present"] and result["authenticated_command_execute"] and not result["service_role_command_execute"] and not result["production_sentinel_present"]
        print(json.dumps(result, sort_keys=True))
        if not result["ok"]:
            raise RuntimeError("PDC_SUCCESSOR_READONLY_STAGING_PROOF_FAILED")
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "mailbox_contacted": False, "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
