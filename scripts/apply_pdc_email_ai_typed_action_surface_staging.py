#!/usr/bin/env python3
"""Apply/read back the typed action surface in STAGING only.

This controller is deliberately approval/hash gated and never invokes the
mutating action RPC. It installs the append-only DDL, then reads back catalog,
ACL, RLS and function-source controls.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901020000_pdc_email_ai_typed_action_surface.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901010000", "latest100_attachment_work_receipt_successor")
TARGET = ("20260901020000", "pdc_email_ai_typed_action_surface_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901020000"


def one(cursor, query: str, params=()):
    cursor.execute(query, params)
    return cursor.fetchone()


def secure_bundle() -> dict:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_TYPED_ACTION_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_TYPED_ACTION_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    bundle = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(bundle)
    url = bundle.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_TYPED_ACTION_NON_STAGING_TARGET")
    return bundle


def main() -> None:
    source_hash = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901020000 pdc email ai typed action surface source {source_hash}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_TYPED_ACTION_STAGING_APPROVAL_MISSING_OR_HASH_MISMATCH")
    bundle = secure_bundle()
    import psycopg2

    conn = psycopg2.connect(bundle["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=bundle["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-typed-action-surface-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != PREDECESSOR:
            raise RuntimeError(f"PDC_TYPED_ACTION_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_TYPED_ACTION_PRODUCTION_SENTINEL_PRESENT")
        cur.execute(MIGRATION.read_text(encoding="utf-8"))
        conn.commit()
        cur = conn.cursor()
        ledger = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901020000'") or ())
        source = one(cur, "select pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)'::regprocedure)")[0] or ""
        acl = one(cur, "select has_function_privilege('authenticated','public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)','execute'), has_function_privilege('service_role','public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)','execute')")
        trigger = bool(one(cur, "select exists(select 1 from pg_trigger where tgrelid='public.pdc_email_ai_successor_action_rules_20260901'::regclass and tgname='pdc_email_ai_successor_action_rules_20260901_immutable' and not tgisinternal and tgenabled<>'D')")[0])
        receipt_triggers = bool(one(cur, "select exists(select 1 from pg_trigger where tgrelid='public.pdc_email_ai_successor_transaction_receipts'::regclass and tgname='pdc_email_ai_successor_transaction_receipt_immutable' and not tgisinternal and tgenabled<>'D') and exists(select 1 from pg_trigger where tgrelid='public.pdc_email_ai_successor_action_receipts'::regclass and tgname='pdc_email_ai_successor_action_receipt_immutable' and not tgisinternal and tgenabled<>'D')")[0])
        tables = []
        for table in ("pdc_email_ai_successor_action_rules_20260901", "pdc_email_ai_successor_transaction_receipts", "pdc_email_ai_successor_action_receipts"):
            row = one(cur, "select relrowsecurity,relforcerowsecurity from pg_class where oid=to_regclass(%s)", (f"public.{table}",))
            tables.append({"table": table, "rls": bool(row[0]) if row else False, "force_rls": bool(row[1]) if row else False})
        production = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET and bool(acl[0]) and not bool(acl[1]) and trigger and receipt_triggers and all(x["rls"] and x["force_rls"] for x in tables) and "authoritative_readback_field_parity_failed" in source and "pdc_email_ai_successor_taxonomy_disposition_20260901" in source and "EXECUTE " not in source and "..." not in source and not production,
            "environment": "staging", "project_ref": STAGING_REF, "migration_sha256": source_hash,
            "ledger_head": ledger, "authenticated_execute": bool(acl[0]), "service_role_execute": bool(acl[1]),
            "rules_immutable_trigger": trigger, "receipt_immutable_triggers": receipt_triggers, "tables": tables, "field_level_readback": "authoritative_readback_field_parity_failed" in source,
            "static_canonical_dispatch": "EXECUTE " not in source and "..." not in source,
            "taxonomy_gate": "pdc_email_ai_successor_taxonomy_disposition_20260901" in source,
            "action_rpc_source_bytes": len(source), "production_sentinel_present": production,
            "action_rpc_invoked": False, "mailbox_contacted": False, "outbound_email": False, "business_mutation": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_TYPED_ACTION_POST_APPLY_READBACK_FAILED")
        print(json.dumps(proof, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "action_rpc_invoked": False}, sort_keys=True))
        raise SystemExit(1)
