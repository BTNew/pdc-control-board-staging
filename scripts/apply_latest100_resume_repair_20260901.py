from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831460000_latest100_resume_repair.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260831450000", "pdc_email_monitor_viewer_receipt_read_successor")
TARGET = ("20260831460000", "latest100_resume_repair")


def staging_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    dsn = data["PDC_STAGING_DATABASE_URL"]
    if REF not in dsn or PROD in dsn:
        raise RuntimeError("PDC_460_NON_STAGING_TARGET")
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
    expected = f"apply migration 460 latest100 resume repair source {digest}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_460") != expected:
        raise RuntimeError("PDC_460_APPROVAL_MISSING_OR_HASH_MISMATCH")
    values = staging_values()
    conn = psycopg2.connect(
        values["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=values["PDC_STAGING_SSLROOTCERT"],
        connect_timeout=20,
        application_name="pdc-latest100-resume-repair-staging",
    )
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            if scalar(cur, "select current_user") != "postgres":
                raise RuntimeError("PDC_460_OWNER_REQUIRED")
            head = tuple(row(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
            if head not in (PREDECESSOR, TARGET):
                raise RuntimeError(f"PDC_460_UNEXPECTED_HEAD:{head}")
            if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                raise RuntimeError("PDC_460_PRODUCTION_SENTINEL_PRESENT")
            if head == PREDECESSOR:
                cur.execute(MIGRATION.read_text(encoding="utf-8"))
                conn.commit()
            cur = conn.cursor()
            current = tuple(row(cur, "select version,name from supabase_migrations.schema_migrations where version='20260831460000'") or ())
            if current != TARGET:
                raise RuntimeError(f"PDC_460_LEDGER_READBACK_FAILED:{current}")
            checks = {
                "environment": "staging",
                "project_ref": REF,
                "migration_sha256": digest,
                "ledger_head": current,
                "production_sentinel_present": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
                "viewer_capability": scalar(cur, "select count(*)=1 from public.pdc_monitor_canonical_import_capabilities_20260831 where singleton and auth_user_id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid and capability='canonical_attachment_import_only' and active"),
                "viewer_writer_rows": scalar(cur, "select count(*) from public.pdc_monitor_stage_activation_writers where user_id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid and active and revoked_at is null"),
                "known_sender_hash_rows": scalar(cur, "select count(*) from public.pdc_monitor_exact_sender_enrollments where active and sender_sha256 in ('0f371e0126fe46f11550b6fd8893f61e8976f8b94d181fe2729c0f32c0a76ebd','ff43f3ac9154a06df493ba77605120e7c06205da4001ae0259f94d6d163b7543','c8f1287687794e3d9a835f1cba02f856fdb8cc5188661a2d7728d952cacc455f','201f02404dd79de8ae556d4d033246e24ba51648ce72f7ae776d9d82357865f5')"),
                "parent_audit_function": scalar(cur, "select to_regprocedure('public.read_pdc_email_intake_parent_audit_20260901(text)') is not null"),
                "parent_audit_authenticated_execute": scalar(cur, "select has_function_privilege('authenticated','public.read_pdc_email_intake_parent_audit_20260901(text)','execute')"),
                "parent_audit_anon_execute": scalar(cur, "select has_function_privilege('anon','public.read_pdc_email_intake_parent_audit_20260901(text)','execute')"),
                "parent_audit_service_execute": scalar(cur, "select has_function_privilege('service_role','public.read_pdc_email_intake_parent_audit_20260901(text)','execute')"),
                "intake_table_select_denied_authenticated": scalar(cur, "select not has_table_privilege('authenticated','public.ai_email_intake','select')"),
                "attachment_table_select_denied_authenticated": scalar(cur, "select not has_table_privilege('authenticated','public.ai_email_attachments','select')"),
                "child_receipts_forced_rls": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_jobcard_attachment_import_receipts'::regclass"),
                "source_receipts_forced_rls": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_jobcard_attachment_source_row_receipts'::regclass"),
                "pre310_capability_marker": "pdc_canonical_import_capability_context_20260831" in (scalar(cur, "select pg_get_functiondef('public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)'::regprocedure)") or ""),
                "generic_deprecated_flag_marker": "pdc_resume_460_deprecated_derived_authentication_flag" in (scalar(cur, "select pg_get_functiondef('public.pdc_submit_generic_current_navision_enrichment_312(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)'::regprocedure)") or ""),
                "mailbox_contacted": False,
                "mailbox_flags_changed": False,
                "outbound_email_sent": False,
                "production_writes": False,
            }
            required = [
                checks["production_sentinel_present"] is False,
                checks["viewer_capability"] is True,
                checks["viewer_writer_rows"] == 0,
                checks["known_sender_hash_rows"] == 4,
                checks["parent_audit_function"] is True,
                checks["parent_audit_authenticated_execute"] is True,
                checks["parent_audit_anon_execute"] is False,
                checks["parent_audit_service_execute"] is False,
                checks["intake_table_select_denied_authenticated"] is True,
                checks["attachment_table_select_denied_authenticated"] is True,
                checks["child_receipts_forced_rls"] is True,
                checks["source_receipts_forced_rls"] is True,
                checks["pre310_capability_marker"],
                checks["generic_deprecated_flag_marker"],
            ]
            if not all(required):
                raise RuntimeError("PDC_460_POST_APPLY_READBACK_FAILED:" + json.dumps(checks, sort_keys=True, default=str))
            conn.commit()
            print(json.dumps(checks, sort_keys=True, default=str))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
