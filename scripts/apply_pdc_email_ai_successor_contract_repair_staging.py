#!/usr/bin/env python3
"""Apply/read back only the successor contract repair in STAGING."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831320000_pdc_email_ai_transaction_successor_contract_repair.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260831310000", "pdc_checklist_completion_history_preservation")
TARGET = ("20260831320000", "pdc_email_ai_transaction_successor_contract_repair")


def one(cursor, query: str):
    cursor.execute(query)
    return cursor.fetchone()


def secure_bundle() -> dict:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_SUCCESSOR_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SUCCESSOR_STAGING_CONNECTOR_INVALID")
    spec.loader.exec_module(module)
    bundle = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(bundle)
    url = bundle.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_SUCCESSOR_NON_STAGING_TARGET")
    return bundle


def main() -> None:
    source_hash = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 862 pdc email ai successor contract repair source {source_hash}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_862") != expected:
        raise RuntimeError("PDC_SUCCESSOR_STAGING_REPAIR_APPROVAL_MISSING_OR_HASH_MISMATCH")
    bundle = secure_bundle()
    import psycopg2

    connection = psycopg2.connect(
        bundle["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=bundle["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-transaction-successor-contract-repair-staging-controller",
    )
    connection.autocommit = False
    try:
        cursor = connection.cursor()
        head = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != PREDECESSOR:
            raise RuntimeError(f"PDC_SUCCESSOR_REPAIR_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_SUCCESSOR_REPAIR_PRODUCTION_SENTINEL_PRESENT")
        cursor.execute(MIGRATION.read_text(encoding="utf-8"))
        connection.commit()
        cursor = connection.cursor()
        ledger = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version='20260831320000'") or ())
        function_present = bool(one(cursor, "select to_regprocedure('public.apply_pdc_email_ai_transaction_successor(jsonb)') is not null")[0])
        function_source = one(cursor, "select pg_get_functiondef('public.apply_pdc_email_ai_transaction_successor(jsonb)'::regprocedure)")[0] or ""
        proof = {
            "ok": ledger == TARGET and function_present and "'expected'" in function_source and "v_initial_vehicle_versions" in function_source,
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": source_hash,
            "ledger_head": ledger,
            "command_rpc_present": function_present,
            "expected_actual_response_fields": "'expected'" in function_source and "'actual'" in function_source,
            "multi_action_vehicle_preflight": "v_initial_vehicle_versions" in function_source,
            "source_graph_binding": "attachment_digests" in function_source and "graph_thread_id" in function_source,
            "production_sentinel_present": bool(one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]),
            "mailbox_contacted": False,
            "outbound_email": False,
            "task_enabled": False,
            "uid514_processed": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_SUCCESSOR_REPAIR_POST_APPLY_READBACK_FAILED")
        connection.commit()
        print(json.dumps(proof, sort_keys=True))
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "mailbox_contacted": False, "outbound_email": False, "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
