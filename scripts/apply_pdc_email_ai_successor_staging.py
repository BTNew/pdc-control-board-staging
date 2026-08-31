#!/usr/bin/env python3
"""Apply and read back only the isolated successor migration in STAGING."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831300000_pdc_email_ai_transaction_successor.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260831290000", "863_exact_retry_after_storage_repair")
TARGET = ("20260831300000", "pdc_email_ai_transaction_successor")


def _row(cursor, query: str):
    cursor.execute(query)
    return cursor.fetchone()


def _secure_bundle() -> dict:
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
    expected_approval = f"apply migration 860 pdc email ai transaction successor source {source_hash}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_860") != expected_approval:
        raise RuntimeError("PDC_SUCCESSOR_STAGING_APPROVAL_MISSING_OR_HASH_MISMATCH")
    bundle = _secure_bundle()
    import psycopg2

    connection = psycopg2.connect(
        bundle["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=bundle["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-transaction-successor-staging-controller",
    )
    connection.autocommit = False
    try:
        cursor = connection.cursor()
        head = tuple(_row(cursor, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != PREDECESSOR:
            raise RuntimeError(f"PDC_SUCCESSOR_UNEXPECTED_LIVE_HEAD:{head}")
        if _row(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_SUCCESSOR_PRODUCTION_SENTINEL_PRESENT")
        cursor.execute(MIGRATION.read_text(encoding="utf-8"))
        connection.commit()
        cursor = connection.cursor()
        ledger = tuple(_row(cursor, "select version,name from supabase_migrations.schema_migrations where version='20260831300000'") or ())
        function = _row(cursor, "select to_regprocedure('public.apply_pdc_email_ai_transaction_successor(jsonb)') is not null")[0]
        health = _row(cursor, "select to_regprocedure('public.get_pdc_email_ai_successor_health()') is not null")[0]
        production = _row(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]
        receipt = {
            "ok": ledger == TARGET and function and health and production is False,
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": source_hash,
            "ledger_head": ledger,
            "command_rpc_present": function,
            "health_rpc_present": health,
            "production_sentinel_present": production,
            "mailbox_contacted": False,
            "outbound_email": False,
            "task_enabled": False,
            "uid514_processed": False,
        }
        if not receipt["ok"]:
            raise RuntimeError("PDC_SUCCESSOR_POST_APPLY_READBACK_FAILED")
        connection.commit()
        print(json.dumps(receipt, sort_keys=True))
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({
            "ok": False,
            "error": str(exc),
            "environment": "staging",
            "mailbox_contacted": False,
            "outbound_email": False,
            "production_contacted": False,
        }, sort_keys=True))
        raise SystemExit(1)
