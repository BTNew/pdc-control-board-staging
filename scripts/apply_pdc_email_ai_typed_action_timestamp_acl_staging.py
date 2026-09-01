#!/usr/bin/env python3
"""Apply and prove the append-only v2 timestamp/ACL correction in STAGING only."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901090000_pdc_email_ai_typed_action_timestamp_acl_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901080000", "pdc_email_ai_typed_action_identity_contract_20260901")
TARGET = ("20260901090000", "pdc_email_ai_typed_action_timestamp_acl_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901090000"


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()


def bundle():
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_TYPED_ACTION_TIMESTAMP_ACL_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_TYPED_ACTION_TIMESTAMP_ACL_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_TYPED_ACTION_TIMESTAMP_ACL_NON_STAGING_TARGET")
    return data


def probe_plan(vehicle):
    vehicle_id = str(vehicle[3])
    identity = {"vehicle_id": vehicle_id, "stock_number": vehicle[0], "vin": vehicle[1], "backend_record_id": str(vehicle[2]).lower() if vehicle[2] else None}
    versions = {
        "transport_release_version": "probe-transport-v1", "planner_version": "probe-planner-v1",
        "model_version": "probe-model-v1", "prompt_version": "probe-prompt-v1",
        "business_rule_version": "probe-rules-v1", "ruleset_version": "probe-rules-v1",
        "taxonomy_version": "pdc-operation-taxonomy-proposed/v1",
        "supabase_action_contract_version": "pdc-email-ai-action-request-v1",
        "source_digest": "a" * 64, "evidence_digest": "b" * 64,
    }
    item = {
        "instruction_id": "probe-0001", "vehicle_id": vehicle_id, "identity": identity,
        "expected_state": {"vehicle_version": 1, "backend_revision": 0}, "action_type": "note_append",
        "payload": {"text": "read-only timestamp contract probe", "event_at": "2026-09-01T00:00:00+00:00"},
        "evidence_refs": [{"kind": "message", "ref": "probe-message", "required_for_action": True}],
        "required_evidence": ["authoritative_identity"], "decision_disposition": "planned",
        "provenance": versions.copy(), "audit_event_ref": "probe-audit-0001", "reason": "read-only timestamp contract probe",
    }
    return {
        "schema_version": "pdc-email-ai-plan-v1", "plan_id": "11111111-1111-4111-8111-111111111111",
        "environment": "staging", "source_receipt_id": "22222222-2222-4222-8222-222222222222",
        "source_digest": "a" * 64, "evidence_digest": "b" * 64, "source_thread_id": "probe-thread",
        "source_message_id": "probe-message", "attachment_digests": ["c" * 64], "versions": versions,
        "instructions": [item], "aggregate_disposition": "planned", "planner_status": "available",
        "planner_failure_reason": None, "created_at": "2026-09-01T00:00:00+00:00",
    }


def validation_probes(cur, plan):
    def check(candidate):
        cur.execute("select public.pdc_email_ai_successor_validate_v2_plan_20260901(%s::jsonb)", (json.dumps(candidate),))
        return bool(cur.fetchone()[0])

    valid = check(plan)
    malformed = {}
    for action_type, payload in (
        ("parts_eta_set", {"eta": "2026-99-99"}),
        ("booking_set", {"stage_code": "QC", "bay_number": 1, "scheduled_start_at": "2026-99-99Tbad", "duration_minutes": 60, "technician_id": None}),
        ("booking_move", {"booking_id": "44444444-4444-4444-8444-444444444444", "expected_booking_version": 1, "stage_code": "QC", "bay_number": 1, "scheduled_start_at": "2026-99-99Tbad", "duration_minutes": 60, "override_reason": None}),
        ("work_complete", {"booking_id": "44444444-4444-4444-8444-444444444444", "expected_booking_version": 1, "work_key": "FITTING", "completed_at": "2026-99-99Tbad"}),
        ("note_append", {"text": "malformed timestamp", "event_at": "2026-99-99Tbad"}),
    ):
        candidate = copy.deepcopy(plan)
        candidate["instructions"][0]["action_type"] = action_type
        candidate["instructions"][0]["payload"] = payload
        malformed[action_type] = not check(candidate)
    return valid, malformed


def acl(cur, signature):
    return tuple(one(cur, "select has_function_privilege('authenticated',%s,'execute'), has_function_privilege('service_role',%s,'execute'), has_function_privilege('public',%s,'execute'), has_function_privilege('anon',%s,'execute')", (signature,) * 4))


def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901090000 pdc email ai typed action timestamp acl source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_TYPED_ACTION_TIMESTAMP_ACL_APPROVAL_MISSING_OR_HASH_MISMATCH")
    data = bundle()
    import psycopg2

    conn = psycopg2.connect(data["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=data["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-typed-action-timestamp-acl-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        already_applied = head == TARGET
        if head not in {PREDECESSOR, TARGET}:
            raise RuntimeError(f"PDC_TYPED_ACTION_TIMESTAMP_ACL_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_TYPED_ACTION_TIMESTAMP_ACL_PRODUCTION_SENTINEL_PRESENT")
        before_counts = tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)"))
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
            conn.commit()
        cur = conn.cursor()
        ledger = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901090000'") or ())
        strict_acl = acl(cur, "public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)")
        low_level_acl = acl(cur, "public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)")
        alias_acl = acl(cur, "public.apply_pdc_email_ai_transaction_successor_v2(jsonb)")
        vehicle = one(cur, "select stock_number_normalized,vin_normalized,source_record_id_normalized,id from public.vehicles where deleted_at is null and stock_number_normalized is not null order by id limit 1")
        if not vehicle:
            raise RuntimeError("PDC_TYPED_ACTION_TIMESTAMP_ACL_NO_PROBE_VEHICLE")
        valid, malformed = validation_probes(cur, probe_plan(vehicle))
        validator = one(cur, "select pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)'::regprocedure)")[0] or ""
        helper_presence = tuple(one(cur, "select to_regprocedure('public.pdc_email_ai_successor_iso_date_20260901(text)') is not null, to_regprocedure('public.pdc_email_ai_successor_iso_timestamptz_20260901(text)') is not null"))
        after_counts = tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)"))
        production = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET and strict_acl == (True, False, False, False) and low_level_acl == (False, False, False, False) and alias_acl == (False, False, False, False) and valid and all(malformed.values()) and helper_presence == (True, True) and "pdc_email_ai_successor_iso_timestamptz_20260901" in validator and before_counts == after_counts and not production,
            "environment": "staging", "project_ref": STAGING_REF, "migration_sha256": digest, "ledger_head": ledger,
            "typed_action_acl": {"authenticated": strict_acl[0], "service_role": strict_acl[1], "public": strict_acl[2], "anon": strict_acl[3]},
            "legacy_low_level_acl": low_level_acl, "compatibility_alias_acl": alias_acl,
            "probes": {"valid_plan": valid, "malformed_rejected": malformed, "iso_helpers_present": helper_presence == (True, True)},
            "receipt_counts_before": before_counts, "receipt_counts_after": after_counts,
            "production_sentinel_present": production, "action_rpc_invoked": False, "business_mutation": False, "mailbox_contacted": False, "outbound_email": False,
        }
        print(json.dumps(proof, sort_keys=True))
        if not proof["ok"]:
            raise RuntimeError("PDC_TYPED_ACTION_TIMESTAMP_ACL_POST_APPLY_READBACK_FAILED")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "action_rpc_invoked": False}, sort_keys=True))
        raise SystemExit(1)
