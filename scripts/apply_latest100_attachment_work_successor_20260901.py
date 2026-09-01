from __future__ import annotations
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import psycopg2

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901010000_latest100_attachment_work_receipt_successor.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260831461000", "latest100_force_rls_successor")
TARGET = ("20260901010000", "latest100_attachment_work_receipt_successor")


def staging_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    dsn = data["PDC_STAGING_DATABASE_URL"]
    if REF not in dsn or PROD in dsn:
        raise RuntimeError("PDC_100_NON_STAGING_TARGET")
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
    expected = f"apply migration 100 latest100 attachment work successor source {digest}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_100") != expected:
        raise RuntimeError("PDC_100_APPROVAL_MISSING_OR_HASH_MISMATCH")
    values = staging_values()
    conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], connect_timeout=20, application_name="pdc-latest100-attachment-work-successor-staging")
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            head = tuple(row(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
            if head not in (PREDECESSOR, TARGET):
                raise RuntimeError(f"PDC_100_UNEXPECTED_HEAD:{head}")
            if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                raise RuntimeError("PDC_100_PRODUCTION_SENTINEL_PRESENT")
            old_digest = scalar(cur, """select encode(extensions.digest(convert_to(coalesce((select string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)) from public.pdc_email_intake_work_receipts x),''),'UTF8'),'sha256'),'hex')""")
            if head == PREDECESSOR:
                cur.execute(MIGRATION.read_text(encoding="utf-8"))
                conn.commit()
            current = tuple(row(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901010000'") or ())
            if current != TARGET:
                raise RuntimeError(f"PDC_100_LEDGER_READBACK_FAILED:{current}")
            new_old_digest = scalar(cur, """select encode(extensions.digest(convert_to(coalesce((select string_agg(md5(to_jsonb(x)::text),'' order by md5(to_jsonb(x)::text)) from public.pdc_email_intake_work_receipts x),''),'UTF8'),'sha256'),'hex')""")
            checks = {
                "environment": "staging",
                "project_ref": REF,
                "migration_sha256": digest,
                "ledger_head": current,
                "production_sentinel_present": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
                "old_work_receipts_digest_unchanged": old_digest == new_old_digest,
                "old_work_receipt_count": scalar(cur, "select count(*) from public.pdc_email_intake_work_receipts"),
                "successor_table": scalar(cur, "select to_regclass('public.pdc_email_intake_work_receipts_20260901') is not null"),
                "successor_rows_initial": scalar(cur, "select count(*) from public.pdc_email_intake_work_receipts_20260901"),
                "successor_forced_rls": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_email_intake_work_receipts_20260901'::regclass"),
                "successor_select_public": scalar(cur, "select has_table_privilege('public','public.pdc_email_intake_work_receipts_20260901','select')"),
                "successor_select_authenticated": scalar(cur, "select has_table_privilege('authenticated','public.pdc_email_intake_work_receipts_20260901','select')"),
                "successor_select_service": scalar(cur, "select has_table_privilege('service_role','public.pdc_email_intake_work_receipts_20260901','select')"),
                "process_authenticated_execute": scalar(cur, "select has_function_privilege('authenticated','public.process_email_intake_work(uuid,text,text,jsonb,text)','execute')"),
                "process_public_execute": scalar(cur, "select has_function_privilege('public','public.process_email_intake_work(uuid,text,text,jsonb,text)','execute')"),
                "process_anon_execute": scalar(cur, "select has_function_privilege('anon','public.process_email_intake_work(uuid,text,text,jsonb,text)','execute')"),
                "process_service_execute": scalar(cur, "select has_function_privilege('service_role','public.process_email_intake_work(uuid,text,text,jsonb,text)','execute')"),
                "schema_reload_sent": True,
                "mailbox_contacted": False,
                "mailbox_flags_changed": False,
                "outbound_email_sent": False,
                "production_writes": False,
            }
            required = [
                checks["production_sentinel_present"] is False,
                checks["old_work_receipts_digest_unchanged"] is True,
                checks["successor_table"] is True,
                checks["successor_forced_rls"] is True,
                checks["successor_select_public"] is False,
                checks["successor_select_authenticated"] is False,
                checks["successor_select_service"] is False,
                checks["process_authenticated_execute"] is True,
                checks["process_public_execute"] is False,
                checks["process_anon_execute"] is False,
                checks["process_service_execute"] is False,
            ]
            if not all(required):
                raise RuntimeError("PDC_100_POST_APPLY_READBACK_FAILED:" + json.dumps(checks, sort_keys=True, default=str))
            conn.commit()
            print(json.dumps(checks, sort_keys=True, default=str))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
