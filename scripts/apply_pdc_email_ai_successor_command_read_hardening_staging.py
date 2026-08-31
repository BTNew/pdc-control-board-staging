#!/usr/bin/env python3
"""Apply/read back successor command/read hardening in STAGING only."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831340000_pdc_email_ai_successor_command_read_hardening.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260831330000", "pdc_email_ai_successor_inbox_read_projection")
TARGET = ("20260831340000", "pdc_email_ai_successor_command_read_hardening")


def one(cursor, sql: str):
    cursor.execute(sql)
    return cursor.fetchone()


def bundle() -> dict:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_SUCCESSOR_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SUCCESSOR_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(result)
    url = result.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_SUCCESSOR_NON_STAGING_TARGET")
    return result


def main() -> None:
    source_hash = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 864 pdc email ai successor command read hardening source {source_hash}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_864") != expected:
        raise RuntimeError("PDC_SUCCESSOR_3400_STAGING_APPROVAL_MISSING_OR_HASH_MISMATCH")
    credentials = bundle()
    import psycopg2

    connection = psycopg2.connect(
        credentials["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-successor-command-read-hardening-staging-controller",
    )
    connection.autocommit = False
    try:
        cursor = connection.cursor()
        head = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != PREDECESSOR:
            raise RuntimeError(f"PDC_SUCCESSOR_3400_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_SUCCESSOR_3400_PRODUCTION_SENTINEL_PRESENT")
        cursor.execute(MIGRATION.read_text(encoding="utf-8"))
        connection.commit()
        cursor = connection.cursor()
        ledger = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version='20260831340000'") or ())
        apply_source = one(cursor, "select pg_get_functiondef('public.apply_pdc_email_ai_transaction_successor(jsonb)'::regprocedure)")[0] or ""
        v2_present = bool(one(cursor, "select to_regprocedure('public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)') is not null")[0])
        v2_source = one(cursor, "select pg_get_functiondef('public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)'::regprocedure)")[0] or ""
        auth_execute = bool(one(cursor, "select has_function_privilege('authenticated','public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)','execute')")[0])
        service_execute = bool(one(cursor, "select has_function_privilege('service_role','public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)','execute')")[0])
        production = bool(one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET and v2_present and "identity_vehicle_mismatch" in apply_source and "IS DISTINCT FROM 'true'" in apply_source and "v_cursor_id" in v2_source and "RECEIVED_WAITING" in v2_source and auth_execute and not service_execute and not production,
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": source_hash,
            "ledger": ledger,
            "command_identity_binding": "identity_vehicle_mismatch" in apply_source,
            "confirmed_true_guard": "IS DISTINCT FROM 'true'" in apply_source,
            "inbox_v2_present": v2_present,
            "composite_cursor": "v_cursor_created_at" in v2_source and "v_cursor_id" in v2_source,
            "legacy_status_waiting": "RECEIVED_WAITING" in v2_source,
            "authenticated_execute": auth_execute,
            "service_role_execute": service_execute,
            "production_sentinel_present": production,
            "runtime_identity_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_runtime_identities")[0]),
            "transaction_receipt_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_transaction_receipts")[0]),
            "action_receipt_count": int(one(cursor, "select count(*) from public.pdc_email_ai_successor_action_receipts")[0]),
            "mailbox_contacted": False,
            "outbound_email": False,
            "business_mutation": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_SUCCESSOR_3400_POST_APPLY_READBACK_FAILED")
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
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "outbound_email": False}, sort_keys=True))
        raise SystemExit(1)
