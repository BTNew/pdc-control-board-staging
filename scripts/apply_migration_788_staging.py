from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830185000_788_canonical_historical_digest_contract.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_HEAD = "(20260830184000,787_cycle7_contract_version_repair)"
TARGET_HEAD = "(20260830185000,788_canonical_historical_digest_contract)"


def staging_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(values)
    database_url = values["PDC_STAGING_DATABASE_URL"]
    if REF not in database_url or "vjdtsswhroyguxyfjdkt" in database_url:
        raise RuntimeError("PDC_788_NON_STAGING_TARGET")
    return values


def scalar(cur, sql: str):
    cur.execute(sql)
    row = cur.fetchone()
    return row[0] if row else None


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    approval = f"apply migration 788 canonical digest source {digest}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_788") != approval:
        raise RuntimeError("staging migration approval missing or hash-mismatched")
    if os.environ.get("PDC_788_SECURITY_REVIEW_VERDICT") != "ready_for_apply":
        raise RuntimeError("PDC_788_SECURITY_REVIEW_NOT_READY")

    import psycopg2

    values = staging_values()
    conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc-788-canonical-digest-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = scalar(cur, "select (version,name)::text from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
        already_applied = head == TARGET_HEAD
        if head not in (EXPECTED_HEAD, TARGET_HEAD):
            raise RuntimeError(f"PDC_788_UNEXPECTED_LIVE_HEAD:{head}")
        if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
            raise RuntimeError("PDC_788_PRODUCTION_SENTINEL_PRESENT")
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
            conn.commit()
            cur = conn.cursor()
        base_def = scalar(cur, "select pg_get_functiondef('public.submit_pdc_historical_reconciliation_782_base(jsonb)'::regprocedure)") or ""
        wrapper_def = scalar(cur, "select pg_get_functiondef('public.submit_pdc_historical_reconciliation_778(jsonb)'::regprocedure)") or ""
        boundary_def = scalar(cur, "select pg_get_functiondef('public.pdc_historical_782_boundary_snapshot()'::regprocedure)") or ""
        result = {
            "ok": scalar(cur, "select (version,name)::text from supabase_migrations.schema_migrations where version='20260830185000'") == TARGET_HEAD,
            "environment": "staging",
            "project_ref": REF,
            "migration_sha256": digest,
            "ledger_head": scalar(cur, "select (version,name)::text from supabase_migrations.schema_migrations where version='20260830185000'"),
            "wrapper_exists": scalar(cur, "select to_regprocedure('public.submit_pdc_historical_reconciliation_778(jsonb)') is not null"),
            "private_base_exists": scalar(cur, "select to_regprocedure('public.submit_pdc_historical_reconciliation_782_base(jsonb)') is not null"),
            "canonical_request_helper_exists": scalar(cur, "select to_regprocedure('public.pdc_historical_canonical_request_788(jsonb,uuid,text,jsonb)') is not null"),
            "canonical_observation_helper_exists": scalar(cur, "select to_regprocedure('public.pdc_historical_canonical_observation_788(jsonb,jsonb,uuid,uuid,uuid,integer,text,text,text)') is not null"),
            "wrapper_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')"),
            "wrapper_anon": scalar(cur, "select has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')"),
            "wrapper_service_role": scalar(cur, "select has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')"),
            "base_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_782_base(jsonb)','execute')"),
            "observations": scalar(cur, "select count(*) from public.pdc_historical_provider_observations_778"),
            "receipts": scalar(cur, "select count(*) from public.pdc_historical_reconciliation_778_receipts"),
            "observation_rls_forced": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_provider_observations_778'::regclass"),
            "receipt_rls_forced": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_reconciliation_778_receipts'::regclass"),
            "production_sentinel_present": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
            "mailbox_contacted": False,
            "production_contacted": False,
            "historical_writer_called": False,
            "base_has_old_contract_tag": "'782.1'" in base_def,
            "base_recomputes_request": "pdc_historical_canonical_request_788" in base_def,
            "base_recomputes_observation": "pdc_historical_canonical_observation_788" in base_def,
            "base_checks_request_digest": "h.request_sha256=v_request_hash" in base_def,
            "base_checks_observation_digest": "h.observation_sha256=v_observation_sha" in base_def,
            "base_checks_complete_boundary": "PDC_788_PROTECTED_BOUNDARY_DRIFT" in base_def and "v_boundary_after IS DISTINCT FROM v_boundary_before" in base_def,
            "wrapper_recomputes_request": "pdc_historical_canonical_request_788" in wrapper_def,
            "wrapper_checks_complete_boundary": "PDC_788_PROTECTED_BOUNDARY_DRIFT" in wrapper_def and "v_after IS DISTINCT FROM v_before" in wrapper_def,
            "protected_snapshot_complete": all(marker in boundary_def for marker in ("pdc_sublet_bookings", "pdc_sublet_booking_instances", "pdc_pmb_stoppage_receipts_422", "monitored_mailboxes", "pdc_email_monitor_status", "pdc_qc_salesperson_update_outbox_399", "pdc_rft_transport_email_outbox_734", "pdc_sublet_email_update_receipts")),
            "observation_unique_occurrence": scalar(cur, "select exists(select 1 from pg_index i where i.indrelid='public.pdc_historical_provider_observations_778'::regclass and i.indisunique and pg_get_indexdef(i.indexrelid) like '%(intake_id, attachment_id)%')"),
            "observation_unique_digest": scalar(cur, "select exists(select 1 from pg_index i where i.indrelid='public.pdc_historical_provider_observations_778'::regclass and i.indisunique and pg_get_indexdef(i.indexrelid) like '%(observation_sha256)%')"),
        }
        required = ["ok", "wrapper_exists", "private_base_exists", "canonical_request_helper_exists", "canonical_observation_helper_exists", "wrapper_authenticated", "observation_rls_forced", "receipt_rls_forced"]
        if any(result[k] is not True for k in required) or result["wrapper_anon"] is not False or result["wrapper_service_role"] is not False or result["base_authenticated"] is not False or result["observations"] != 0 or result["receipts"] != 0 or result["production_sentinel_present"] is not False or result["base_has_old_contract_tag"] or not all(result[k] for k in ("base_recomputes_request", "base_recomputes_observation", "base_checks_request_digest", "base_checks_observation_digest", "base_checks_complete_boundary", "wrapper_recomputes_request", "wrapper_checks_complete_boundary", "protected_snapshot_complete", "observation_unique_occurrence", "observation_unique_digest")):
            raise RuntimeError("PDC_788_POST_APPLY_READBACK_FAILED:" + json.dumps(result, sort_keys=True, default=str))
        print(json.dumps(result, sort_keys=True, default=str))
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "environment": "staging", "mailbox_contacted": False, "production_contacted": False, "historical_writer_called": False}, sort_keys=True))
        raise SystemExit(1)
