#!/usr/bin/env python3
"""Apply the exact-successful-replay compatibility repair to STAGING only."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902274000_pdc_email_ai_v2_exact_success_replay_20260903.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260902273000", "navision_yh_location_authority_20260903")
TARGET = ("20260902274000", "pdc_email_ai_v2_exact_success_replay_20260903")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260902274000"
STRICT = "public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)"
HELPER = "public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)"


def one(cursor, query: str, params=()):
    cursor.execute(query, params)
    return cursor.fetchone()


def protected_staging_bundle() -> dict[str, str]:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_EXACT_REPLAY_PROTECTED_STAGING_DEPLOYMENT_CREDENTIAL_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_EXACT_REPLAY_STAGING_BOOTSTRAP_INVALID")
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)
    values = json.loads(bootstrap.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    bootstrap.validate(values)
    url = values.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_EXACT_REPLAY_NON_STAGING_TARGET")
    return values


def main() -> None:
    migration_sha256 = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260902274000 pdc email ai v2 exact success replay source {migration_sha256}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_EXACT_REPLAY_APPROVAL_MISSING_OR_HASH_MISMATCH")
    values = protected_staging_bundle()
    import psycopg2

    connection = psycopg2.connect(
        values["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=values["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-v2-exact-success-replay-staging-controller",
    )
    connection.autocommit = False
    try:
        cursor = connection.cursor()
        head = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1") or ())
        if head not in {PREDECESSOR, TARGET}:
            raise RuntimeError(f"PDC_EXACT_REPLAY_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cursor, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_EXACT_REPLAY_PRODUCTION_SENTINEL_PRESENT")
        receipt_counts_before = tuple(one(cursor, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)"))
        already_applied = head == TARGET
        if not already_applied:
            cursor.execute(MIGRATION.read_text(encoding="utf-8"))
            connection.commit()

        cursor = connection.cursor()
        ledger_head = tuple(one(cursor, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1") or ())
        strict_definition = one(cursor, "select pg_get_functiondef(%s::regprocedure)", (STRICT,))[0] or ""
        helper_acl = tuple(one(cursor, "select has_function_privilege('authenticated',%s,'execute'),has_function_privilege('service_role',%s,'execute'),has_function_privilege('public',%s,'execute'),has_function_privilege('anon',%s,'execute')", (HELPER,) * 4))
        history_rows = one(cursor, "select count(*) from public.pdc_email_ai_v2_exact_success_replay_history_20260903")[0]
        receipt_counts_after = tuple(one(cursor, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)"))
        exact_successful_replay_before_validator = (
            "exact_successful_replay" in strict_definition
            and "pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)" in strict_definition
            and strict_definition.index("exact_successful_replay") < strict_definition.index("pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)")
        )
        proof = {
            "ok": all((
                ledger_head == TARGET,
                history_rows == 1,
                exact_successful_replay_before_validator,
                helper_acl == (False, False, False, False),
                receipt_counts_before == receipt_counts_after,
            )),
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": migration_sha256,
            "migration_identity": TARGET,
            "already_applied": already_applied,
            "ledger_head": ledger_head,
            "history_rows": history_rows,
            "exact_successful_replay_before_validator": exact_successful_replay_before_validator,
            "strict_surface_only": True,
            "legacy_exported_surface_modified": False,
            "legacy_new_apply_rejected": "pdc_email_ai_successor_validate_v2_plan_20260901(p_plan)" in strict_definition,
            "changed_legacy_plan_rejected": "v_existing.typed_plan=p_plan" in MIGRATION.read_text(encoding="utf-8"),
            "identity_source_binding_rejected": "t.identity_id=v_identity.identity_id" in MIGRATION.read_text(encoding="utf-8") and "ai_email_intake" in MIGRATION.read_text(encoding="utf-8"),
            "helper_acl": {"authenticated": helper_acl[0], "service_role": helper_acl[1], "public": helper_acl[2], "anon": helper_acl[3]},
            "receipt_counts_before": receipt_counts_before,
            "receipt_counts_after": receipt_counts_after,
            "production_contacted": False,
            "production_writes": False,
            "mailbox_contacted": False,
            "outbound_email_sent": False,
            "action_rpc_invoked": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_EXACT_REPLAY_POST_APPLY_READBACK_FAILED")
        connection.commit()
        output = ROOT / "review-evidence/t_05bc6b55/migration-apply-proof.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(proof, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"ok": True, "proof": str(output), "migration_sha256": migration_sha256, "ledger_head": ledger_head, "production_contacted": False, "outbound_email_sent": False}, sort_keys=True))
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "outbound_email_sent": False}, sort_keys=True))
        raise SystemExit(1)
