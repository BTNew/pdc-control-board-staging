#!/usr/bin/env python3
"""Apply and prove the final v2 typed action identity contract in STAGING only."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901080000_pdc_email_ai_typed_action_identity_contract_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901070000", "pdc_email_ai_typed_action_execution_readback_20260901")
TARGET = ("20260901080000", "pdc_email_ai_typed_action_identity_contract_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901080000"


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()


def bundle():
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_TYPED_ACTION_IDENTITY_CONTRACT_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_TYPED_ACTION_IDENTITY_CONTRACT_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_TYPED_ACTION_IDENTITY_CONTRACT_NON_STAGING_TARGET")
    return data


def probe_plan(vehicle):
    stock = vehicle[0]
    vin = vehicle[1]
    source_record = vehicle[2]
    vehicle_id = str(vehicle[3])
    backend_record_id = str(source_record).lower() if source_record and re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", str(source_record), re.I) else None
    identity = {"vehicle_id": vehicle_id, "stock_number": stock, "vin": vin, "backend_record_id": backend_record_id}
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
        "payload": {"text": "read-only contract probe", "event_at": "2026-09-01T00:00:00+00:00"},
        "evidence_refs": [{"kind": "message", "ref": "probe-message", "required_for_action": True}],
        "required_evidence": ["authoritative_identity"], "decision_disposition": "planned",
        "provenance": versions.copy(), "audit_event_ref": "probe-audit-0001", "reason": "read-only contract probe",
    }
    return {
        "schema_version": "pdc-email-ai-plan-v1", "plan_id": "11111111-1111-4111-8111-111111111111",
        "environment": "staging", "source_receipt_id": "22222222-2222-4222-8222-222222222222",
        "source_digest": "a" * 64, "evidence_digest": "b" * 64, "source_thread_id": "probe-thread",
        "source_message_id": "probe-message", "attachment_digests": ["c" * 64], "versions": versions,
        "instructions": [item], "aggregate_disposition": "planned", "planner_status": "available",
        "planner_failure_reason": None, "created_at": "2026-09-01T00:00:00+00:00",
    }


def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901080000 pdc email ai typed action identity contract source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_TYPED_ACTION_IDENTITY_CONTRACT_APPROVAL_MISSING_OR_HASH_MISMATCH")
    data = bundle()
    import psycopg2

    conn = psycopg2.connect(data["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=data["PDC_STAGING_SSLROOTCERT"], application_name="pdc-email-ai-typed-action-identity-contract-staging-controller")
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        already_applied = head == TARGET
        if head not in {PREDECESSOR, TARGET}:
            raise RuntimeError(f"PDC_TYPED_ACTION_IDENTITY_CONTRACT_UNEXPECTED_LIVE_HEAD:{head}")
        if one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError("PDC_TYPED_ACTION_IDENTITY_CONTRACT_PRODUCTION_SENTINEL_PRESENT")
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
            conn.commit()
        cur = conn.cursor()
        ledger = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901080000'") or ())
        acl = tuple(one(cur, "select has_function_privilege('authenticated','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('service_role','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('public','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('anon','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute')"))
        vehicle = one(cur, "select stock_number_normalized,vin_normalized,source_record_id_normalized,id from public.vehicles where deleted_at is null and stock_number_normalized is not null order by id limit 1")
        if not vehicle:
            raise RuntimeError("PDC_TYPED_ACTION_IDENTITY_CONTRACT_NO_PROBE_VEHICLE")
        plan = probe_plan(vehicle)
        cur.execute("select public.pdc_email_ai_successor_validate_v2_plan_20260901(%s::jsonb)", (json.dumps(plan),))
        valid = bool(cur.fetchone()[0])
        forged = json.loads(json.dumps(plan))
        forged["instructions"][0]["identity"]["stock_number"] = "99999999"
        cur.execute("select public.pdc_email_ai_successor_validate_v2_plan_20260901(%s::jsonb)", (json.dumps(forged),))
        forged_rejected = not bool(cur.fetchone()[0])
        malformed = json.loads(json.dumps(plan)); malformed["attachment_digests"] = ["not-a-digest"]
        cur.execute("select public.pdc_email_ai_successor_validate_v2_plan_20260901(%s::jsonb)", (json.dumps(malformed),))
        malformed_rejected = not bool(cur.fetchone()[0])
        conflict = json.loads(json.dumps(plan)); conflict["instructions"][0]["decision_disposition"] = "conflict"; conflict["instructions"][0]["action_type"] = "operation_add"; conflict["instructions"][0]["payload"] = {"operation_no":"OP1","source_row_no":1,"work_key":"PARTS","description":"identity conflict retained as evidence","estimated_hours":None,"taxonomy_version":"pdc-operation-taxonomy-proposed/v1","taxonomy_disposition":"conflict","source_uid":"probe-message:c"*1}
        cur.execute("select public.pdc_email_ai_successor_validate_v2_plan_20260901(%s::jsonb)", (json.dumps(conflict),))
        conflict_valid = bool(cur.fetchone()[0])
        unresolved = json.loads(json.dumps(plan)); unresolved["instructions"][0]["vehicle_id"] = "33333333-3333-4333-8333-333333333333"; unresolved["instructions"][0]["identity"] = {"vehicle_id":"33333333-3333-4333-8333-333333333333","stock_number":None,"vin":None,"backend_record_id":None}; unresolved["instructions"][0]["decision_disposition"] = "review"
        cur.execute("select public.pdc_email_ai_successor_validate_v2_plan_20260901(%s::jsonb)", (json.dumps(unresolved),))
        unresolved_valid = bool(cur.fetchone()[0])
        validator = one(cur, "select pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)'::regprocedure)")[0] or ""
        executor = one(cur, "select pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure)")[0] or ""
        nullable = bool(one(cur, "select not attnotnull from pg_attribute where attrelid='public.pdc_email_ai_successor_action_receipts'::regclass and attname='vehicle_id'")[0])
        check = bool(one(cur, "select exists(select 1 from pg_constraint where conname='pdc_email_ai_successor_action_receipt_vehicle_scope')")[0])
        production = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {
            "ok": ledger == TARGET and acl == (True, False, False, False) and valid and forged_rejected and malformed_rejected and conflict_valid and unresolved_valid and nullable and check and "source_record_id_normalized" in validator and "vehicle_not_found" not in executor and not production,
            "environment": "staging", "project_ref": STAGING_REF, "migration_sha256": digest, "ledger_head": ledger,
            "typed_action_acl": {"authenticated": acl[0], "service_role": acl[1], "public": acl[2], "anon": acl[3]},
            "probes": {"valid_plan": valid, "forged_identity_rejected": forged_rejected, "malformed_attachment_rejected": malformed_rejected, "identity_conflict_valid": conflict_valid, "unresolved_review_valid": unresolved_valid, "nullable_review_receipt_vehicle": nullable, "review_receipt_scope_check": check},
            "production_sentinel_present": production, "action_rpc_invoked": False, "business_mutation": False, "mailbox_contacted": False, "outbound_email": False,
        }
        print(json.dumps(proof, sort_keys=True))
        if not proof["ok"]:
            raise RuntimeError("PDC_TYPED_ACTION_IDENTITY_CONTRACT_POST_APPLY_READBACK_FAILED")
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
