#!/usr/bin/env python3
"""Apply the source-bound Job Card parity migration to STAGING only."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902264000_pdc_email_ai_v2_job_card_parity_correction_20260902.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRE = ("20260902263200", "pdc_email_ai_v2_scoped_navision_activation_readback_repair_20260902")
TARGET = ("20260902264000", "pdc_email_ai_v2_job_card_parity_correction_20260902")
ENV = "PDC_APPROVE_STAGING_MIGRATION_20260902264000"
EXECUTOR = "public.pdc_email_ai_successor_execute_v2_20260901(jsonb)"


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260902264000 pdc email ai v2 job card parity correction source {digest}"
    if os.environ.get(ENV) != expected:
        raise RuntimeError("PDC_JOB_CARD_APPROVAL_MISSING_OR_HASH_MISMATCH")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if not spec or not spec.loader:
        raise RuntimeError("PDC_JOB_CARD_BOOTSTRAP_UNAVAILABLE")
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)
    credentials = json.loads(bootstrap.unprotect(SECRETS.read_bytes()).decode())
    bootstrap.validate(credentials)
    database_url = credentials["PDC_STAGING_DATABASE_URL"]
    if STAGING_REF not in database_url or "vjdtsswhroyguxyfjdkt" in database_url:
        raise RuntimeError("PDC_JOB_CARD_NON_STAGING_TARGET")
    import psycopg2

    connection = psycopg2.connect(
        database_url,
        sslmode="verify-full",
        sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-v2-job-card-parity-staging-controller",
    )
    connection.autocommit = False
    try:
        cursor = connection.cursor()
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1")
        head = tuple(cursor.fetchone() or ())
        if head not in {PRE, TARGET}:
            raise RuntimeError(f"PDC_JOB_CARD_UNEXPECTED_HEAD:{head}")
        cursor.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
        if cursor.fetchone()[0]:
            raise RuntimeError("PDC_JOB_CARD_PRODUCTION_SENTINEL_PRESENT")
        already_applied = head == TARGET
        if not already_applied:
            cursor.execute(MIGRATION.read_text(encoding="utf-8"))
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1")
        head = tuple(cursor.fetchone() or ())
        cursor.execute("select count(*) from public.pdc_email_ai_v2_job_card_parity_correction_history_20260902")
        history_rows = cursor.fetchone()[0]
        cursor.execute("select pg_get_functiondef(%s::regprocedure)", (EXECUTOR,))
        executor_source = cursor.fetchone()[0] or ""
        cursor.execute("select has_function_privilege('service_role',%s,'EXECUTE'), has_function_privilege('public',%s,'EXECUTE'), has_function_privilege('anon',%s,'EXECUTE')", ("public.reconcile_pdc_email_ai_v2_job_card_parity_20260902(uuid,uuid,text,text,text,text,text,text)",) * 3)
        service_acl, public_acl, anon_acl = cursor.fetchone()
        proof = {
            "ok": head == TARGET and history_rows == 1 and "job_card_set" in executor_source and not service_acl and not public_acl and not anon_acl,
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": digest,
            "migration_identity": TARGET,
            "already_applied": already_applied,
            "ledger_head": head,
            "history_rows": history_rows,
            "executor_job_card_marker": "job_card_set" in executor_source,
            "direct_reconcile_acl": {"service_role": service_acl, "public": public_acl, "anon": anon_acl, "authenticated": True},
            "production_writes": False,
            "mailbox_contacted": False,
            "outbound_email": False,
            "action_rpc_invoked": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_JOB_CARD_POSTCHECK_FAILED")
        connection.commit()
        output = ROOT / "review-evidence/v2-controlled/job-card-parity-correction-apply-proof.json"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(proof, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"ok": True, "proof": str(output), "migration": TARGET, "migration_sha256": digest, "ledger_head": head, "production_writes": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}, sort_keys=True))
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    main()
