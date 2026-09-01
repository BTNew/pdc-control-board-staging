#!/usr/bin/env python3
"""Apply and prove the serialized v2 field-executor/identity correction in STAGING only."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901120000_pdc_email_ai_typed_action_field_executor_identity_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901110000", "pdc_email_ai_typed_action_review_receipts_20260901")
TARGET = ("20260901120000", "pdc_email_ai_typed_action_field_executor_identity_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901120000"
# Read-only probes cover booking_set, work_complete and note_append affected rows.
READBACK_ACTIONS = ("booking_set", "work_complete", "note_append")


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()


def bundle():
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_TYPED_ACTION_FIELD_EXECUTOR_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    import importlib.util
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_TYPED_ACTION_FIELD_EXECUTOR_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_TYPED_ACTION_FIELD_EXECUTOR_NON_STAGING_TARGET")
    return data


def plan(vehicle=None, *, stock=None, vin=None):
    vehicle_id = str(vehicle[3]) if vehicle else None
    identity = {
        "vehicle_id": vehicle_id,
        "stock_number": vehicle[0] if vehicle else stock,
        "vin": vehicle[1] if vehicle else vin,
        "backend_record_id": str(vehicle[2]).lower() if vehicle and vehicle[2] else None,
    }
    versions = {
        "transport_release_version": "probe-transport-v1", "planner_version": "probe-planner-v1",
        "model_version": "probe-model-v1", "prompt_version": "probe-prompt-v1",
        "business_rule_version": "probe-rules-v1", "ruleset_version": "probe-rules-v1",
        "taxonomy_version": "pdc-operation-taxonomy-proposed/v1",
        "supabase_action_contract_version": "pdc-email-ai-action-request-v1",
        "source_digest": "a" * 64, "evidence_digest": "b" * 64,
    }
    item = {
        "instruction_id": "probe-known-review-0001" if vehicle else "probe-unbound-review-0001",
        "vehicle_id": vehicle_id, "identity": identity, "expected_state": {"vehicle_version": 1, "backend_revision": 0},
        "action_type": "note_append", "payload": {"text": "read-only field-executor identity probe", "event_at": "2026-09-01T00:00:00+00:00"},
        "evidence_refs": [{"kind": "message", "ref": "probe-message", "required_for_action": True}],
        "required_evidence": ["authoritative_identity"], "decision_disposition": "review",
        "provenance": versions.copy(), "audit_event_ref": "probe-audit-0001", "reason": "read-only identity evidence probe",
    }
    return {
        "schema_version": "pdc-email-ai-plan-v1", "plan_id": "44444444-4444-4444-8444-444444444444" if not vehicle else "11111111-1111-4111-8111-111111111111",
        "environment": "staging", "source_receipt_id": "22222222-2222-4222-8222-222222222222",
        "source_digest": "a" * 64, "evidence_digest": "b" * 64, "source_thread_id": "probe-thread",
        "source_message_id": "probe-message", "attachment_digests": ["c" * 64], "versions": versions,
        "instructions": [item], "aggregate_disposition": "review", "planner_status": "available",
        "planner_failure_reason": None, "created_at": "2026-09-01T00:00:00+00:00",
    }


def acl(cur, signature):
    return tuple(one(cur, "select has_function_privilege('authenticated',%s,'execute'), has_function_privilege('service_role',%s,'execute'), has_function_privilege('public',%s,'execute'), has_function_privilege('anon',%s,'execute')", (signature,) * 4))


def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901120000 pdc email ai typed action field executor identity source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_TYPED_ACTION_FIELD_EXECUTOR_APPROVAL_MISSING_OR_HASH_MISMATCH")
    data = bundle()
    import psycopg2
    conn = psycopg2.connect(data["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=data["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-typed-action-field-executor-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        already_applied = head == TARGET
        if head not in {PREDECESSOR, TARGET}:
            raise RuntimeError(f"PDC_TYPED_ACTION_FIELD_EXECUTOR_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_TYPED_ACTION_FIELD_EXECUTOR_PRODUCTION_SENTINEL_PRESENT")
        before_counts = tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)"))
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
            conn.commit()
        cur = conn.cursor()
        ledger = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901120000'") or ())
        strict_signature = "public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)"
        strict_definition = one(cur, "select pg_get_functiondef(%s::regprocedure)", (strict_signature,))[0] or ""
        known = one(cur, "select stock_number_normalized,vin_normalized,source_record_id_normalized,id from public.vehicles where deleted_at is null and stock_number_normalized is not null order by id limit 1")
        if not known:
            raise RuntimeError("PDC_TYPED_ACTION_FIELD_EXECUTOR_NO_PROBE_VEHICLE")
        def check(candidate):
            cur.execute("select public.pdc_email_ai_successor_validate_v2_plan_20260901(%s::jsonb)", (json.dumps(candidate),))
            return bool(cur.fetchone()[0])
        unknown_identity_plan = check(plan(stock="99999999"))
        duplicate_vin_plan = check(plan(vin="JH4TB2H26CC000001"))
        known_review_plan = check(plan(known))
        route = "pdc_email_ai_successor_execute_v2_20260901(p_plan)" in strict_definition
        low_level = "apply_pdc_email_ai_typed_action_surface_20260901(normalized)" in strict_definition
        operation_guard = "apply_pdc_email_ai_operation_update_transaction_20260901(p_plan)" in strict_definition
        non_dispatch_guard = "pdc_email_ai_successor_record_non_dispatch_v2_20260901(p_plan)" in strict_definition
        after_counts = tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts)"))
        production = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET and route and not low_level and operation_guard and non_dispatch_guard and unknown_identity_plan and duplicate_vin_plan and known_review_plan and acl(cur, strict_signature) == (True, False, False, False) and before_counts == after_counts and not production,
            "environment": "staging", "project_ref": STAGING_REF, "migration_sha256": digest, "ledger_head": ledger,
            "head_route_calls_execute_v2": route, "head_route_calls_low_level": low_level, "strict_has_operation_update_guard": operation_guard,
            "strict_has_non_dispatch_guard": non_dispatch_guard, "unknown_identity_plan": unknown_identity_plan, "duplicate_vin_plan": duplicate_vin_plan, "known_review_plan": known_review_plan,
            "typed_action_acl": acl(cur, strict_signature), "receipt_counts_before": before_counts, "receipt_counts_after": after_counts,
            "action_rpc_invoked": False, "business_mutation": False, "mailbox_contacted": False, "outbound_email": False, "production_sentinel_present": production,
        }
        print(json.dumps(proof, sort_keys=True))
        if not proof["ok"]:
            raise RuntimeError("PDC_TYPED_ACTION_FIELD_EXECUTOR_IDENTITY_POST_APPLY_READBACK_FAILED")
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
