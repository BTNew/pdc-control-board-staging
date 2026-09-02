#!/usr/bin/env python3
"""Apply and verify the exact Karratha Toyota sender enrollment in STAGING."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902261000_pdc_email_ai_v2_karratha_toyota_sender_enrollment_20260902.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PRE = ("20260902260000", "pdc_email_ai_v2_pd_replay_correction_binding_20260902")
TARGET = ("20260902261000", "pdc_email_ai_v2_karratha_toyota_sender_enrollment_20260902")
TARGET_HASH = "ba17511f3cd912553d2f31744dde2b1be8d916d7dd2c1b94b6d2ce861600f2ae"
NEGATIVE_HASH = hashlib.sha256(b"unapproved@karrathatoyota.com.au").hexdigest()
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260902261000"
HISTORY = "public.pdc_email_ai_v2_sender_enrollment_history_20260902"
ENROLLMENTS = "public.pdc_monitor_exact_sender_enrollments"


def load_staging_database() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SENDER_BOOTSTRAP_UNAVAILABLE")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode())
    module.validate(data)
    url = data["PDC_STAGING_DATABASE_URL"]
    if REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_SENDER_NON_STAGING_TARGET")
    return data


def main() -> None:
    migration_hash = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected_approval = (
        f"apply migration 20260902261000 pdc email ai v2 karratha toyota sender enrollment source {migration_hash}"
    )
    if os.environ.get(APPROVAL_ENV) != expected_approval:
        raise RuntimeError("PDC_SENDER_APPROVAL_MISSING_OR_HASH_MISMATCH")

    data = load_staging_database()
    import psycopg2

    connection = psycopg2.connect(
        data["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=data["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-v2-karratha-sender-staging-controller",
    )
    connection.autocommit = False
    proof: dict[str, object]
    try:
        cursor = connection.cursor()
        cursor.execute(
            "select version,name from supabase_migrations.schema_migrations "
            "where version~'^[0-9]+$' order by version::numeric desc limit 1"
        )
        head = tuple(cursor.fetchone() or ())
        if head not in {PRE, TARGET}:
            raise RuntimeError(f"PDC_SENDER_UNEXPECTED_HEAD:{head}")

        cursor.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
        if cursor.fetchone()[0]:
            raise RuntimeError("PDC_SENDER_PRODUCTION_SENTINEL_PRESENT")

        already_applied = head == TARGET
        if not already_applied:
            cursor.execute(MIGRATION.read_text(encoding="utf-8"))

        cursor.execute(
            "select version,name from supabase_migrations.schema_migrations "
            "where version~'^[0-9]+$' order by version::numeric desc limit 1"
        )
        final_head = tuple(cursor.fetchone() or ())
        cursor.execute(
            "select count(*) from public.pdc_monitor_exact_sender_enrollments "
            "where sender_sha256=%s and active",
            (TARGET_HASH,),
        )
        target_active_count = cursor.fetchone()[0]
        cursor.execute(
            "select count(*) from public.pdc_monitor_exact_sender_enrollments "
            "where sender_sha256=%s and active",
            (NEGATIVE_HASH,),
        )
        negative_active_count = cursor.fetchone()[0]
        cursor.execute(f"select count(*) from {HISTORY}")
        history_rows = cursor.fetchone()[0]
        cursor.execute(
            "select relrowsecurity,relforcerowsecurity from pg_class where oid=%s::regclass",
            (HISTORY,),
        )
        history_rls = tuple(cursor.fetchone() or ())
        cursor.execute(
            "select relrowsecurity,relforcerowsecurity from pg_class where oid=%s::regclass",
            (ENROLLMENTS,),
        )
        enrollment_rls = tuple(cursor.fetchone() or ())

        roles = ("public", "anon", "authenticated", "service_role", "pdc_email_monitor")
        history_select_acl: dict[str, bool] = {}
        enrollment_select_acl: dict[str, bool] = {}
        for role in roles:
            cursor.execute(
                "select has_table_privilege(%s,%s,'SELECT'), has_table_privilege(%s,%s,'SELECT')",
                (role, HISTORY, role, ENROLLMENTS),
            )
            history_select_acl[role], enrollment_select_acl[role] = cursor.fetchone()

        rollback_probe: dict[str, object]
        cursor.execute("BEGIN")
        cursor.execute("SAVEPOINT sender_enrollment_rollback_probe")
        try:
            cursor.execute(f"UPDATE {HISTORY} SET contract=contract")
        except psycopg2.Error as error:
            cursor.execute("ROLLBACK TO SAVEPOINT sender_enrollment_rollback_probe")
            rollback_probe = {
                "blocked": True,
                "sqlstate": error.pgcode,
                "error_prefix": str(error).splitlines()[0][:120],
            }
        else:
            cursor.execute("ROLLBACK TO SAVEPOINT sender_enrollment_rollback_probe")
            raise RuntimeError("PDC_SENDER_ROLLBACK_MUTATION_NOT_BLOCKED")

        proof = {
            "ok": (
                final_head == TARGET
                and target_active_count == 1
                and negative_active_count == 0
                and history_rows == 1
                and history_rls == (True, True)
                and enrollment_rls[0] is True
                and not any(history_select_acl.values())
                and not any(enrollment_select_acl.values())
                and rollback_probe["blocked"] is True
                and rollback_probe["error_prefix"] == "PDC_20260902261000_HISTORY_IMMUTABLE"
            ),
            "environment": "staging",
            "project_ref": REF,
            "migration_sha256": migration_hash,
            "migration_identity": TARGET,
            "already_applied": already_applied,
            "predecessor_identity": PRE,
            "ledger_head": final_head,
            "exact_sender_hash": TARGET_HASH,
            "exact_sender_active_count": target_active_count,
            "unapproved_negative_hash": NEGATIVE_HASH,
            "unapproved_negative_active_count": negative_active_count,
            "history_rows": history_rows,
            "history_rls_force": history_rls,
            "enrollment_rls": enrollment_rls,
            "history_select_acl": history_select_acl,
            "enrollment_select_acl": enrollment_select_acl,
            "rollback_probe": rollback_probe,
            "production_sentinel_present": False,
            "production_writes": False,
            "mailbox_contacted": False,
            "outbound_email": False,
            "action_rpc_invoked": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_SENDER_POSTCHECK_FAILED")
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    output = ROOT / "review-evidence/v2-controlled/karratha-toyota-sender-enrollment-apply-proof.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(proof, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "ok": proof["ok"],
                "proof": str(output),
                "migration": TARGET,
                "migration_sha256": migration_hash,
                "ledger_head": final_head,
                "exact_sender_hash": TARGET_HASH,
                "exact_sender_active_count": proof["exact_sender_active_count"],
                "unapproved_negative_active_count": proof["unapproved_negative_active_count"],
                "rollback_blocked": proof["rollback_probe"]["blocked"],
                "production_writes": False,
                "mailbox_contacted": False,
                "outbound_email": False,
                "action_rpc_invoked": False,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
