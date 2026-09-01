from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831461000_latest100_force_rls_successor.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260831460000", "latest100_resume_repair")
TARGET = ("20260831461000", "latest100_force_rls_successor")


def staging_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    dsn = data["PDC_STAGING_DATABASE_URL"]
    if REF not in dsn or PROD in dsn:
        raise RuntimeError("PDC_461_NON_STAGING_TARGET")
    return data


def scalar(cur, sql: str):
    cur.execute(sql)
    row = cur.fetchone()
    return row[0] if row else None


def row(cur, sql: str):
    cur.execute(sql)
    return cur.fetchone()


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 461 latest100 force rls source {digest}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_461") != expected:
        raise RuntimeError("PDC_461_APPROVAL_MISSING_OR_HASH_MISMATCH")
    values = staging_values()
    conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], connect_timeout=20, application_name="pdc-latest100-force-rls-staging")
    conn.autocommit = False
    tables = (
        "ai_email_intake",
        "ai_email_attachments",
        "pdc_monitor_exact_sender_enrollments",
        "pdc_jobcard_attachment_import_receipts",
        "pdc_jobcard_attachment_source_row_receipts",
    )
    try:
        with conn.cursor() as cur:
            head = tuple(row(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
            if head not in (PREDECESSOR, TARGET):
                raise RuntimeError(f"PDC_461_UNEXPECTED_HEAD:{head}")
            if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                raise RuntimeError("PDC_461_PRODUCTION_SENTINEL_PRESENT")
            if head == PREDECESSOR:
                cur.execute(MIGRATION.read_text(encoding="utf-8"))
                conn.commit()
            current = tuple(row(cur, "select version,name from supabase_migrations.schema_migrations where version='20260831461000'") or ())
            if current != TARGET:
                raise RuntimeError(f"PDC_461_LEDGER_READBACK_FAILED:{current}")
            checks = {
                "environment": "staging",
                "project_ref": REF,
                "migration_sha256": digest,
                "ledger_head": current,
                "production_sentinel_present": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
                "forced_rls": {table: scalar(cur, f"select relrowsecurity and relforcerowsecurity from pg_class where oid='public.{table}'::regclass") for table in tables},
                "authenticated_intake_select": scalar(cur, "select has_table_privilege('authenticated','public.ai_email_intake','select')"),
                "authenticated_attachment_select": scalar(cur, "select has_table_privilege('authenticated','public.ai_email_attachments','select')"),
                "mailbox_contacted": False,
                "mailbox_flags_changed": False,
                "outbound_email_sent": False,
                "production_writes": False,
            }
            if (checks["production_sentinel_present"] is not False
                    or not all(checks["forced_rls"].values())
                    or checks["authenticated_intake_select"] is not False
                    or checks["authenticated_attachment_select"] is not False):
                raise RuntimeError("PDC_461_POST_APPLY_READBACK_FAILED:" + json.dumps(checks, sort_keys=True, default=str))
            conn.commit()
            print(json.dumps(checks, sort_keys=True, default=str))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
