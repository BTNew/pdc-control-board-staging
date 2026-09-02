#!/usr/bin/env python3
from __future__ import annotations
import hashlib, importlib.util, json, os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902266000_pdc_email_ai_v2_job_card_replay_validation_order_20260902.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PRE = ("20260902265000", "pdc_email_ai_v2_job_card_deployed_function_repair_20260902")
TARGET = ("20260902266000", "pdc_email_ai_v2_job_card_replay_validation_order_20260902")
ENV = "PDC_APPROVE_STAGING_MIGRATION_20260902266000"
FUNC = "public.apply_pdc_email_ai_v2_job_card_source_bound_20260902(uuid,uuid,text,text,text,text,text,text)"


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260902266000 pdc email ai v2 job card replay validation order source {digest}"
    if os.environ.get(ENV) != expected: raise RuntimeError("PDC_JOB_CARD_REPLAY_ORDER_APPROVAL_MISSING_OR_HASH_MISMATCH")
    spec = importlib.util.spec_from_file_location("bootstrap", BOOTSTRAP)
    if not spec or not spec.loader: raise RuntimeError("PDC_JOB_CARD_REPLAY_ORDER_BOOTSTRAP_UNAVAILABLE")
    bootstrap = importlib.util.module_from_spec(spec); spec.loader.exec_module(bootstrap)
    credentials = json.loads(bootstrap.unprotect(SECRETS.read_bytes()).decode()); bootstrap.validate(credentials)
    if REF not in credentials["PDC_STAGING_DATABASE_URL"] or "vjdtsswhroyguxyfjdkt" in credentials["PDC_STAGING_DATABASE_URL"]: raise RuntimeError("PDC_JOB_CARD_REPLAY_ORDER_NON_STAGING_TARGET")
    import psycopg2
    connection = psycopg2.connect(credentials["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-v2-job-card-replay-order-controller")
    connection.autocommit = False
    try:
        cursor = connection.cursor(); cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1"); head = tuple(cursor.fetchone() or ())
        if head not in {PRE, TARGET}: raise RuntimeError(f"PDC_JOB_CARD_REPLAY_ORDER_UNEXPECTED_HEAD:{head}")
        cursor.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
        if cursor.fetchone()[0]: raise RuntimeError("PDC_JOB_CARD_REPLAY_ORDER_PRODUCTION_SENTINEL_PRESENT")
        already = head == TARGET
        if not already: cursor.execute(MIGRATION.read_text(encoding="utf-8"))
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]+$' order by version::numeric desc limit 1"); head = tuple(cursor.fetchone() or ())
        cursor.execute("select count(*) from public.pdc_email_ai_v2_job_card_replay_validation_history_20260902"); history = cursor.fetchone()[0]
        cursor.execute("select pg_get_functiondef(%s::regprocedure)", (FUNC,)); source = cursor.fetchone()[0] or ""
        proof = {"ok": head == TARGET and history == 1 and "conflicting retries fail closed" in source and "v_existing.request_hash<>v_request_hash" in source, "environment": "staging", "project_ref": REF, "migration_sha256": digest, "migration_identity": TARGET, "already_applied": already, "ledger_head": head, "history_rows": history, "replay_validation_order": "conflicting retries fail closed" in source, "production_writes": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}
        if not proof["ok"]: raise RuntimeError("PDC_JOB_CARD_REPLAY_ORDER_POSTCHECK_FAILED")
        connection.commit(); output = ROOT / "review-evidence/v2-controlled/job-card-replay-validation-order-apply-proof.json"; output.parent.mkdir(parents=True, exist_ok=True); output.write_text(json.dumps(proof, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"ok": True, "proof": str(output), "migration": TARGET, "migration_sha256": digest, "ledger_head": head, "production_writes": False, "mailbox_contacted": False, "outbound_email": False, "action_rpc_invoked": False}, sort_keys=True))
    except Exception:
        connection.rollback(); raise
    finally: connection.close()


if __name__ == "__main__": main()
