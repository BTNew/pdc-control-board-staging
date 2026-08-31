#!/usr/bin/env python3
"""Apply/read back only the successor inbox projection in STAGING."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831330000_pdc_email_ai_successor_inbox_read_projection.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260831320000", "pdc_email_ai_transaction_successor_contract_repair")
TARGET = ("20260831330000", "pdc_email_ai_successor_inbox_read_projection")


def one(cursor, query: str):
    cursor.execute(query)
    return cursor.fetchone()


def secure_bundle() -> dict:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_SUCCESSOR_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SUCCESSOR_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    bundle = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(bundle)
    url = bundle.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_SUCCESSOR_NON_STAGING_TARGET")
    return bundle


def main() -> None:
    source_hash = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 863 pdc email ai successor inbox projection source {source_hash}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_863") != expected:
        raise RuntimeError("PDC_SUCCESSOR_INBOX_STAGING_APPROVAL_MISSING_OR_HASH_MISMATCH")
    bundle = secure_bundle()
    import psycopg2

    connection = psycopg2.connect(
        bundle["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=bundle["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-successor-inbox-staging-controller",
    )
    connection.autocommit = False
    try:
        cursor = connection.cursor()
        head = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != PREDECESSOR:
            raise RuntimeError(f"PDC_SUCCESSOR_INBOX_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_SUCCESSOR_INBOX_PRODUCTION_SENTINEL_PRESENT")
        cursor.execute(MIGRATION.read_text(encoding="utf-8"))
        connection.commit()
        cursor = connection.cursor()
        ledger = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version='20260831330000'") or ())
        rpc_present = bool(one(cursor, "select to_regprocedure('public.get_pdc_email_ai_transaction_successor_inbox(timestamptz,integer)') is not null")[0])
        revision_present = bool(one(cursor, "select to_regclass('public.pdc_email_ai_successor_ui_revision') is not null")[0])
        typed_plan_present = bool(one(cursor, "select exists(select 1 from information_schema.columns where table_schema='public' and table_name='pdc_email_ai_successor_transaction_receipts' and column_name='typed_plan')")[0])
        realtime_present = bool(one(cursor, "select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_email_ai_successor_ui_revision')")[0])
        execute_authenticated = bool(one(cursor, "select has_function_privilege('authenticated','public.get_pdc_email_ai_transaction_successor(timestamp with time zone,integer)','execute')")[0])
        execute_service = bool(one(cursor, "select has_function_privilege('service_role','public.get_pdc_email_ai_transaction_successor(timestamp with time zone,integer)','execute')")[0])
        force_rls = bool(one(cursor, "select relforcerowsecurity from pg_class where oid='public.pdc_email_ai_successor_ui_revision'::regclass")[0])
        production_present = bool(one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET and rpc_present and revision_present and typed_plan_present and realtime_present and execute_authenticated and not execute_service and force_rls and not production_present,
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": source_hash,
            "ledger_head": ledger,
            "inbox_rpc_present": rpc_present,
            "revision_table_present": revision_present,
            "typed_plan_column_present": typed_plan_present,
            "realtime_revision_published": realtime_present,
            "authenticated_execute": execute_authenticated,
            "service_role_execute": execute_service,
            "revision_force_rls": force_rls,
            "production_sentinel_present": production_present,
            "mailbox_contacted": False,
            "outbound_email": False,
            "business_mutations": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_SUCCESSOR_INBOX_POST_APPLY_READBACK_FAILED")
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
