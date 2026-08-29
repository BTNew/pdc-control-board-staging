from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830172000_778_historical_reconciliation_receipt_and_occurrence_repair.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
EXPECTED_HEAD = "(20260830171000,778_historical_reconciliation_security_successor)"


def values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_1710_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap unavailable")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    data = json.loads(mod.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    mod.validate(data)
    if REF not in data["PDC_STAGING_DATABASE_URL"] or PROD in data["PDC_STAGING_DATABASE_URL"]:
        raise RuntimeError("PDC_778_1710_NON_STAGING_DATABASE_TARGET")
    return data


def scalar(cur, sql: str, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 778 successor 1720 source {digest}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_778") != expected:
        raise RuntimeError("staging migration approval missing or hash-mismatched")
    v = values()
    import psycopg2
    conn = psycopg2.connect(v["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=v["PDC_STAGING_SSLROOTCERT"], application_name="pdc-website-development-778-1710-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = scalar(cur, "select (version,name)::text from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        if head != EXPECTED_HEAD:
            raise RuntimeError("PDC_778_1720_UNEXPECTED_LIVE_HEAD:" + head)
        if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
            raise RuntimeError("PDC_778_1720_PRODUCTION_SENTINEL_PRESENT")
        cur.execute(MIGRATION.read_text(encoding="utf-8"))
        conn.commit()
        result = {
            "ok": scalar(cur, "select count(*)=1 from supabase_migrations.schema_migrations where version='20260830172000' and name='778_historical_reconciliation_receipt_and_occurrence_repair'"),
            "environment": "staging", "project_ref": REF, "migration_sha256": digest,
            "ledger_head": scalar(cur, "select (version,name)::text from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1"),
            "provider_observation_rows": scalar(cur, "select count(*) from public.pdc_historical_provider_observations_778"),
            "reconciliation_receipt_rows": scalar(cur, "select count(*) from public.pdc_historical_reconciliation_778_receipts"),
            "reference_stock_rows": scalar(cur, "select count(*) from public.pdc_historical_reconciliation_writer_authorizations_773 where provider_uid='1:197' or stock_number='13056899'"),
            "auth_rls_forced": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_provider_observations_778'::regclass"),
            "receipt_rls_forced": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_reconciliation_778_receipts'::regclass"),
            "rpc_exists": scalar(cur, "select to_regprocedure('public.submit_pdc_historical_reconciliation_778(jsonb)') is not null"),
            "production_sentinel_present": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
            "mailbox_contacted": False, "valid_historical_writer_called": False, "production_contacted": False,
        }
        if not result["ok"] or result["provider_observation_rows"] != 0 or result["reconciliation_receipt_rows"] != 0 or result["reference_stock_rows"] != 0 or result["auth_rls_forced"] is not True or result["receipt_rls_forced"] is not True or result["rpc_exists"] is not True or result["production_sentinel_present"] is not False:
            raise RuntimeError("PDC_778_1720_POST_APPLY_READBACK_FAILED:" + json.dumps(result, sort_keys=True, default=str))
        print(json.dumps(result, sort_keys=True, default=str))
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "environment": "staging", "mailbox_contacted": False, "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
