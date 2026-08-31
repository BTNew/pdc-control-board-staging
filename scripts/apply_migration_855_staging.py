from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831210000_855_deterministic_inbound_sender_eligibility_successor.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260831200000", "854_exact_claim_839_845_compatibility_successor")
TARGET = ("20260831210000", "855_deterministic_inbound_sender_eligibility_successor")


def staging_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    dsn = data["PDC_STAGING_DATABASE_URL"]
    if REF not in dsn or PROD in dsn:
        raise RuntimeError("PDC_855_NON_STAGING_TARGET")
    return data


def scalar(cur, sql: str):
    cur.execute(sql)
    row = cur.fetchone()
    return row[0] if row else None


def row_value(cur, sql: str):
    cur.execute(sql)
    return cur.fetchone()


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    approval = f"apply migration 855 deterministic inbound sender eligibility source {digest}"
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_855") != approval:
        raise RuntimeError("staging migration approval missing or hash-mismatched")
    values = staging_values()
    import psycopg2
    conn = psycopg2.connect(values["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc-855-inbound-eligibility-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(row_value(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head not in (PREDECESSOR, TARGET):
            raise RuntimeError(f"PDC_855_UNEXPECTED_LIVE_HEAD:{head}")
        if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
            raise RuntimeError("PDC_855_PRODUCTION_SENTINEL_PRESENT")
        if head != TARGET:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
            conn.commit()
            cur = conn.cursor()
        result = {
            "ok": tuple(row_value(cur, "select version,name from supabase_migrations.schema_migrations where version='20260831210000'") or ()) == TARGET,
            "environment": "staging", "project_ref": REF, "migration_sha256": digest,
            "ledger_head": tuple(row_value(cur, "select version,name from supabase_migrations.schema_migrations where version='20260831210000'") or ()),
            "receipt_table": scalar(cur, "select to_regclass('public.pdc_monitor_inbound_eligibility_receipts_855') is not null"),
            "receipt_table_rls_forced": scalar(cur, "select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_monitor_inbound_eligibility_receipts_855'::regclass"),
            "receipt_rows": scalar(cur, "select count(*) from public.pdc_monitor_inbound_eligibility_receipts_855"),
            "enqueue_source": (scalar(cur, "select pg_get_functiondef('public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure)") or ""),
            "production_sentinel_present": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
            "mailbox_contacted": False, "uid514_processed": False, "outbound_email_enabled": False,
        }
        source = result["enqueue_source"].lower()
        result["non_enrolled_review_receipt"] = "pdc_monitor_sender_not_enrolled" in source and "review_queued" in source
        result["deterministic_conflict_skip"] = "on conflict(receipt_key) do nothing" in source
        result["board_mutation_guard"] = "board_mutations,mailbox_flags_changed,outbound_email_sent,production_writes" in source
        result["approved_adapter_preserved"] = "pdc_monitor_authenticated_active_scope_839" in source and "v_sender_enrolled" in source
        result["authenticated_execute"] = scalar(cur, "select has_function_privilege('authenticated','public.enqueue_pdc_email_intake(jsonb,jsonb)','execute')")
        result["anon_execute"] = scalar(cur, "select has_function_privilege('anon','public.enqueue_pdc_email_intake(jsonb,jsonb)','execute')")
        result["service_role_execute"] = scalar(cur, "select has_function_privilege('service_role','public.enqueue_pdc_email_intake(jsonb,jsonb)','execute')")
        if not (result["ok"] and result["receipt_table"] and result["receipt_table_rls_forced"] and result["non_enrolled_review_receipt"] and result["deterministic_conflict_skip"] and result["board_mutation_guard"] and result["approved_adapter_preserved"] and result["production_sentinel_present"] is False and result["authenticated_execute"] is True and result["anon_execute"] is False and result["service_role_execute"] is False):
            raise RuntimeError("PDC_855_POST_APPLY_READBACK_FAILED:" + json.dumps({k:v for k,v in result.items() if k != "enqueue_source"}, sort_keys=True, default=str))
        conn.commit()
        result.pop("enqueue_source")
        print(json.dumps(result, sort_keys=True, default=str))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "environment": "staging", "mailbox_contacted": False, "uid514_processed": False, "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
