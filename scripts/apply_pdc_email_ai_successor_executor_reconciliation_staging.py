#!/usr/bin/env python3
"""Apply the bounded STAGING-only v2 executor reconciliation."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901220000_pdc_email_ai_successor_executor_reconciliation_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901210000", "pdc_email_ai_successor_source_binding_projection_correction_20260901")
TARGET = ("20260901220000", "pdc_email_ai_successor_executor_reconciliation_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901220000"
FUNCTIONS = {
    "executor": "public.pdc_email_ai_successor_execute_v2_20260901(jsonb)",
    "operation_update": "public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)",
    "strict": "public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)",
}
TABLES = (
    "public.pdc_email_ai_successor_runtime_identities",
    "public.pdc_email_ai_successor_transaction_receipts",
    "public.pdc_email_ai_successor_action_receipts",
    "public.pdc_email_ai_successor_executor_reconciliation_history_20260901",
)
ROLES = ("public", "anon", "authenticated", "service_role")


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()


def bundle() -> dict:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_NON_STAGING_TARGET")
    return data


def function_hash(cur, signature: str) -> str:
    return one(cur, "select encode(extensions.digest(convert_to(pg_get_functiondef(%s::regprocedure),'UTF8'),'sha256'),'hex')", (signature,))[0]


def function_source(cur, signature: str) -> str:
    return one(cur, "select pg_get_functiondef(%s::regprocedure)", (signature,))[0] or ""


def state(cur) -> dict:
    existing_tables = [table for table in TABLES if one(cur, "select to_regclass(%s)", (table,))[0] is not None]
    return {
        "ledger_head": tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1") or ()),
        "receipts": tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)")),
        "history_rows": int(one(cur, "select count(*) from public.pdc_email_ai_successor_executor_reconciliation_history_20260901")[0]) if one(cur, "select to_regclass('public.pdc_email_ai_successor_executor_reconciliation_history_20260901') is not null")[0] else 0,
        "rls": {table: tuple(one(cur, "select relrowsecurity,relforcerowsecurity from pg_class where oid=%s::regclass", (table,)) or (False, False)) for table in existing_tables},
        "direct_table_privileges": {table: {role: bool(one(cur, "select has_table_privilege(%s,%s,'select')", (role, table))[0]) for role in ROLES} for table in existing_tables},
        "function_hashes": {name: function_hash(cur, signature) for name, signature in FUNCTIONS.items()},
        "strict_acl": tuple(one(cur, "select has_function_privilege('authenticated',%s,'execute'), has_function_privilege('service_role',%s,'execute'), has_function_privilege('public',%s,'execute'), has_function_privilege('anon',%s,'execute')", (FUNCTIONS["strict"],) * 4)),
        "production_sentinel_present": bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]),
    }


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901220000 pdc email ai successor executor reconciliation source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_APPROVAL_MISSING_OR_HASH_MISMATCH")
    credentials = bundle()
    import psycopg2

    conn = psycopg2.connect(credentials["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-successor-executor-reconciliation-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        before = state(cur)
        if before["ledger_head"] not in {PREDECESSOR, TARGET}:
            raise RuntimeError(f"PDC_EXECUTOR_RECONCILIATION_UNEXPECTED_LIVE_HEAD:{before['ledger_head']}")
        if before["production_sentinel_present"]:
            raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_PRODUCTION_SENTINEL_PRESENT")
        already_applied = before["ledger_head"] == TARGET
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
        after = state(cur)
        executor = function_source(cur, FUNCTIONS["executor"])
        operation = function_source(cur, FUNCTIONS["operation_update"])
        proof = {
            "ok": (
                after["ledger_head"] == TARGET
                and after["history_rows"] == 1
                and before["receipts"] == after["receipts"]
                and after["function_hashes"]["executor"] != before["function_hashes"]["executor"]
                and after["function_hashes"]["operation_update"] != before["function_hashes"]["operation_update"]
                and "SELECT r.source_uid INTO v_source_uid" in executor
                and "pdc_authenticated_email_import_receipts" in executor
                and "import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid" in executor
                and "GET STACKED DIAGNOSTICS" in executor
                and "RETURNED_SQLSTATE" in executor
                and "canonical_error" in executor
                and "SELECT r.source_uid INTO v_source_uid" in operation
                and "source_hash,v_source_uid" in operation
                and after["strict_acl"] == (True, False, False, False)
                and all(all(bool(flag) for flag in values) for values in after["rls"].values())
                and all(not flag for table in after["direct_table_privileges"].values() for flag in table.values())
                and not after["production_sentinel_present"]
            ),
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": digest,
            "migration_identity": TARGET,
            "already_applied": already_applied,
            "before": before,
            "after": after,
            "source_markers": {
                "server_resolved_source_uid": "SELECT r.source_uid INTO v_source_uid" in executor,
                "canonical_operation_add_binding": "import_pdc_authenticated_email_operations_with_hours(source_hash,v_source_uid" in executor,
                "canonical_operation_update_binding": "source_hash,v_source_uid" in operation,
                "canonical_result_error_evidence": "canonical_error" in executor and "RETURNED_SQLSTATE" in executor,
            },
            "production_writes": False,
            "mailbox_contacted": False,
            "outbound_email": False,
            "action_rpc_invoked": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_EXECUTOR_RECONCILIATION_POSTCHECK_FAILED")
        conn.commit()
        out = ROOT / "review-evidence" / "v2-controlled" / "executor-reconciliation-apply-proof.json"
        out.write_text(json.dumps(proof, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"proof": str(out), "migration": TARGET, "migration_sha256": digest, "ledger_head": after["ledger_head"], "receipts_preserved": before["receipts"] == after["receipts"], "production_writes": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
