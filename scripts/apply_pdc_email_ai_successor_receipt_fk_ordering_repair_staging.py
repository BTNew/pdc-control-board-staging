#!/usr/bin/env python3
"""Apply and prove the narrow STAGING receipt FK ordering repair."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901170000_pdc_email_ai_successor_receipt_fk_ordering_repair_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901160000", "pdc_email_ai_typed_action_source_hash_ambiguity_repair_20260901")
TARGET = ("20260901170000", "pdc_email_ai_successor_receipt_fk_ordering_repair_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901170000"
FK_NAME = "pdc_email_ai_successor_action_receipts_transaction_id_fkey"
RECEIPT_ID = "205f0c13-ef4b-4ac0-8128-3563a4d8d61a"
FUNCTIONS = {
    "execute": "public.pdc_email_ai_successor_execute_v2_20260901(jsonb)",
    "non_dispatch": "public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)",
    "operation_update": "public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)",
}
TABLES = (
    "public.pdc_email_ai_successor_runtime_identities",
    "public.pdc_email_ai_successor_transaction_receipts",
    "public.pdc_email_ai_successor_action_receipts",
)
ROLES = ("public", "anon", "authenticated", "service_role")


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()


def bundle() -> dict:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_RECEIPT_FK_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_RECEIPT_FK_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_RECEIPT_FK_NON_STAGING_TARGET")
    return data


def function_hash(cur, signature: str) -> str:
    return one(
        cur,
        "select encode(extensions.digest(convert_to(pg_get_functiondef(%s::regprocedure),'UTF8'),'sha256'),'hex')",
        (signature,),
    )[0]


def function_acls(cur, signature: str) -> tuple[bool, bool, bool, bool]:
    return tuple(
        one(
            cur,
            "select has_function_privilege('authenticated',%s,'execute'), has_function_privilege('service_role',%s,'execute'), has_function_privilege('public',%s,'execute'), has_function_privilege('anon',%s,'execute')",
            (signature,) * 4,
        )
    )


def constraint_state(cur) -> dict:
    row = one(
        cur,
        "select condeferrable,condeferred,convalidated,pg_get_constraintdef(oid) from pg_constraint where conrelid='public.pdc_email_ai_successor_action_receipts'::regclass and conname=%s and contype='f'",
        (FK_NAME,),
    )
    if not row:
        return {"present": False}
    return {
        "present": True,
        "deferrable": bool(row[0]),
        "initially_deferred": bool(row[1]),
        "validated": bool(row[2]),
        "definition": row[3],
    }


def rls_state(cur) -> dict:
    return {
        table: tuple(
            one(
                cur,
                "select relrowsecurity,relforcerowsecurity from pg_class where oid=%s::regclass",
                (table,),
            )
            or (False, False)
        )
        for table in TABLES
    }


def direct_table_denial(cur) -> dict:
    return {
        table: {
            role: bool(one(cur, "select has_table_privilege(%s,%s,'select')", (role, table))[0])
            for role in ROLES
        }
        for table in TABLES
    }


def state(cur) -> dict:
    return {
        "ledger_head": tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ()),
        "constraint": constraint_state(cur),
        "receipts": tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)")),
        "retained_receipt": int(one(cur, "select count(*) from public.pdc_email_ai_successor_transaction_receipts where transaction_id=%s", (RECEIPT_ID,))[0]),
        "rls": rls_state(cur),
        "direct_table_denial": direct_table_denial(cur),
        "strict_acl": function_acls(cur, "public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)"),
        "function_hashes": {name: function_hash(cur, sig) for name, sig in FUNCTIONS.items()},
        "production_sentinel_present": bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]),
    }


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901170000 pdc email ai successor receipt fk ordering repair source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_RECEIPT_FK_APPROVAL_MISSING_OR_HASH_MISMATCH")
    credentials = bundle()
    import psycopg2

    conn = psycopg2.connect(
        credentials["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-receipt-fk-ordering-staging-controller",
    )
    conn.autocommit = False
    try:
        cur = conn.cursor()
        before = state(cur)
        if before["ledger_head"] not in {PREDECESSOR, TARGET}:
            raise RuntimeError(f"PDC_RECEIPT_FK_UNEXPECTED_LIVE_HEAD:{before['ledger_head']}")
        if before["production_sentinel_present"]:
            raise RuntimeError("PDC_RECEIPT_FK_PRODUCTION_SENTINEL_PRESENT")
        if before["retained_receipt"] != 1:
            raise RuntimeError("PDC_RECEIPT_FK_RETAINED_RECEIPT_MISSING")
        already_applied = before["ledger_head"] == TARGET
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
        after = state(cur)
        proof = {
            "ok": (
                after["ledger_head"] == TARGET
                and after["constraint"].get("present") is True
                and after["constraint"].get("deferrable") is True
                and after["constraint"].get("initially_deferred") is True
                and after["constraint"].get("validated") is True
                and "FOREIGN KEY (transaction_id)" in after["constraint"].get("definition", "")
                and "REFERENCES pdc_email_ai_successor_transaction_receipts(transaction_id)" in after["constraint"].get("definition", "")
                and before["receipts"] == after["receipts"]
                and before["function_hashes"] == after["function_hashes"]
                and after["retained_receipt"] == 1
                and after["strict_acl"] == (True, False, False, False)
                and all(all(bool(flag) for flag in values) for values in after["rls"].values())
                and all(not flag for table in after["direct_table_denial"].values() for flag in table.values())
                and not after["production_sentinel_present"]
            ),
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": digest,
            "migration_identity": TARGET,
            "already_applied": already_applied,
            "before": before,
            "after": after,
            "preserved_receipt_id": RECEIPT_ID,
            "production_writes": False,
            "mailbox_contacted": False,
            "outbound_email": False,
            "action_rpc_invoked": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_RECEIPT_FK_POST_APPLY_READBACK_FAILED")
        conn.commit()
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
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}, sort_keys=True))
        raise SystemExit(1)
