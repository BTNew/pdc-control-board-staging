#!/usr/bin/env python3
"""Apply and prove the narrow STAGING source_hash ambiguity repair."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901160000_pdc_email_ai_typed_action_source_hash_ambiguity_repair_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901140000", "pdc_email_ai_successor_inbox_digest_canonicalization_20260901")
TARGET = ("20260901160000", "pdc_email_ai_typed_action_source_hash_ambiguity_repair_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901160000"
FUNCTIONS = {
    "execute": "public.pdc_email_ai_successor_execute_v2_20260901(jsonb)",
    "non_dispatch": "public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)",
    "operation_update": "public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)",
}
EXPECTED_PREDECESSOR_HASHES = {
    "execute": "14fa8e912732e8d21f3bf56d00b953a9a3f9f60753d3348a6bebf86449ac465c",
    "non_dispatch": "3df2bff20c151221f782e969a88604e833fd182dff228b536ff600ed55f2daf6",
    "operation_update": "d84cca9a4e0fb7868aadc4657eedc6e870e52e8cb4b13740ccd7bf1a428b3ba6",
}


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()


def bundle() -> dict:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_NON_STAGING_TARGET")
    return data


def function_hash(cur, signature: str) -> str:
    return one(cur, "select encode(extensions.digest(convert_to(pg_get_functiondef(%s::regprocedure),'UTF8'),'sha256'),'hex')", (signature,))[0]


def acl(cur, signature: str) -> tuple[bool, bool, bool, bool]:
    return tuple(one(cur, "select has_function_privilege('authenticated',%s,'execute'), has_function_privilege('service_role',%s,'execute'), has_function_privilege('public',%s,'execute'), has_function_privilege('anon',%s,'execute')", (signature,) * 4))


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901160000 pdc email ai typed action source hash ambiguity repair source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_APPROVAL_MISSING_OR_HASH_MISMATCH")
    credentials = bundle()
    import psycopg2

    conn = psycopg2.connect(credentials["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-source-hash-ambiguity-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        already_applied = head == TARGET
        if head not in {PREDECESSOR, TARGET}:
            raise RuntimeError(f"PDC_SOURCE_HASH_AMBIGUITY_UNEXPECTED_LIVE_HEAD:{head}")
        if bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]):
            raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_PRODUCTION_SENTINEL_PRESENT")
        before_counts = tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)"))
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
        ledger = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901160000'") or ())
        definitions = {name: one(cur, "select pg_get_functiondef(%s::regprocedure)", (signature,))[0] or "" for name, signature in FUNCTIONS.items()}
        hashes = {name: function_hash(cur, signature) for name, signature in FUNCTIONS.items()}
        predicate_checks = {
            name: {
                "old_ambiguous_predicate_absent": "lower(coalesce(i.source_hash,''))=source_hash" not in definition,
                "qualified_source_column_present": "lower(coalesce(i.source_hash,''))=v_source_hash_key" in definition,
            }
            for name, definition in definitions.items()
        }
        after_counts = tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)"))
        history = one(cur, "select count(*),min(predecessor_head),max(successor_head),bool_and(not production_writes and not mailbox_contacted and not outbound_email and not action_rpc_invoked) from public.pdc_email_ai_typed_action_source_hash_ambiguity_history_20260901")
        production = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET
            and all(EXPECTED_PREDECESSOR_HASHES[name] != hashes[name] for name in FUNCTIONS)
            and all(checks["old_ambiguous_predicate_absent"] and checks["qualified_source_column_present"] for checks in predicate_checks.values())
            and history == (1, "20260901140000", "20260901160000", True)
            and acl(cur, "public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)") == (True, False, False, False)
            and before_counts == after_counts
            and not production,
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": digest,
            "ledger_head": ledger,
            "predecessor_function_sha256": hashes,
            "predicate_checks": predicate_checks,
            "history": {"rows": history[0], "predecessor_head": history[1], "successor_head": history[2], "zero_side_effect_flags": history[3]},
            "strict_typed_action_acl": acl(cur, "public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)"),
            "receipt_counts_before": before_counts,
            "receipt_counts_after": after_counts,
            "action_rpc_invoked": False,
            "production_sentinel_present": production,
            "mailbox_contacted": False,
            "outbound_email": False,
            "business_mutation": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_SOURCE_HASH_AMBIGUITY_POST_APPLY_READBACK_FAILED")
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
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "action_rpc_invoked": False}, sort_keys=True))
        raise SystemExit(1)
