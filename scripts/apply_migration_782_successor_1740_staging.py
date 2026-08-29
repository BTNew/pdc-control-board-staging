from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830174000_782_historical_reconciliation_atomic_wrapper_successor.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
EXPECTED_HEAD = "(20260830173000,782_historical_reconciliation_current_head_security_successor)"


def staging_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(values)
    database_url = values["PDC_STAGING_DATABASE_URL"]
    if REF not in database_url or PROD in database_url:
        raise RuntimeError("PDC_782_1740_NON_STAGING_TARGET")
    return values


def scalar(cur, sql: str):
    cur.execute(sql)
    row = cur.fetchone()
    return row[0] if row else None


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    approval = f"apply migration 782 successor 1740 source {digest}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_782") != approval:
        raise RuntimeError("staging migration approval missing or hash-mismatched")
    if os.environ.get("PDC_782_SECURITY_REVIEW_VERDICT") != "ready_for_apply":
        raise RuntimeError("PDC_782_SECURITY_REVIEW_NOT_READY")

    import psycopg2

    values = staging_values()
    conn = psycopg2.connect(
        values["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=values["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-782-1740-staging-controller",
    )
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = scalar(cur, "select (version,name)::text from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        if head != EXPECTED_HEAD:
            raise RuntimeError(f"PDC_782_1740_UNEXPECTED_LIVE_HEAD:{head}")
        if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
            raise RuntimeError("PDC_782_1740_PRODUCTION_SENTINEL_PRESENT")
        cur.execute(MIGRATION.read_text(encoding="utf-8"))
        conn.commit()
        result = {
            "environment": "staging",
            "project_ref": REF,
            "migration_sha256": digest,
            "ledger_head": scalar(cur, "select (version,name)::text from supabase_migrations.schema_migrations where version='20260830174000'"),
            "wrapper_exists": scalar(cur, "select to_regprocedure('public.submit_pdc_historical_reconciliation_778(jsonb)') is not null"),
            "private_base_exists": scalar(cur, "select to_regprocedure('public.submit_pdc_historical_reconciliation_782_base(jsonb)') is not null"),
            "wrapper_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')"),
            "wrapper_anon": scalar(cur, "select has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')"),
            "wrapper_service_role": scalar(cur, "select has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')"),
            "base_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_782_base(jsonb)','execute')"),
            "binding_rows": scalar(cur, "select count(*) from public.pdc_historical_job_card_attachments_782"),
            "observations": scalar(cur, "select count(*) from public.pdc_historical_provider_observations_778"),
            "receipts": scalar(cur, "select count(*) from public.pdc_historical_reconciliation_778_receipts"),
            "binding_rls_forced": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_job_card_attachments_782'::regclass"),
            "production_sentinel_present": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
            "mailbox_contacted": False,
            "valid_historical_writer_called": False,
            "production_contacted": False,
        }
        if not result["ledger_head"] or result["wrapper_exists"] is not True or result["private_base_exists"] is not True or result["wrapper_authenticated"] is not True or result["wrapper_anon"] is not False or result["wrapper_service_role"] is not False or result["base_authenticated"] is not False or result["binding_rows"] != 3 or result["observations"] != 0 or result["receipts"] != 0 or result["binding_rls_forced"] is not True or result["production_sentinel_present"] is not False:
            raise RuntimeError("PDC_782_1740_POST_APPLY_READBACK_FAILED:" + json.dumps(result, sort_keys=True, default=str))
        print(json.dumps(result, sort_keys=True, default=str))
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "environment": "staging", "mailbox_contacted": False, "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
