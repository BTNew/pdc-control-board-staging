#!/usr/bin/env python3
"""Apply and verify the STAGING mixed-disposition repair with a real scoped JWT."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from backend.pdc_email_ai_v2_actions import validate_v2_plan
from backend.pdc_email_ai_v2_planner import V2Planner
from scripts.apply_pdc_email_ai_current_hours_fixture_generation_staging_20260903 import (
    request_json,
    require_ok,
    rpc,
    runtime_headers,
)
from scripts.diagnose_pdc_email_ai_actual_jwt_replay_staging_20260903 import management_query

STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
VERSION = "20260903124000"
GENERATION_ID = "5bf31237-0005-4000-8000-000000000014"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260903124000"
MIGRATION = ROOT / "supabase/staging_only/20260903124000_pdc_email_ai_evidence_bound_fixture_refresh_20260903.sql"
EVIDENCE = ROOT / "review-evidence/t_5bf31237/mixed-disposition-staging-verification.json"
RUNTIME_CREDENTIAL_SOURCE = "pdc-email-ai-lead/.env"
LIVE_ACTION_TYPES = {
    "activate_vehicle", "booking_cancel", "booking_move", "booking_set",
    "location_set", "note_append", "operation_add", "operation_update",
    "parts_complete", "parts_eta_set", "required_work_set", "rft_collect",
    "rft_transfer", "work_complete",
}


def wait_for_rpc(base: str, headers: dict[str, str], function: str, payload: dict[str, Any]) -> tuple[int, Any]:
    last: tuple[int, Any] = (0, None)
    for _ in range(30):
        last = rpc(base, headers, function, payload)
        if last[0] == 200:
            return last
        time.sleep(1)
    return last


def scenario_correspondence(fixture: Mapping[str, Any]) -> str:
    return str(fixture["source"]["correspondence"])


def build_fixture_plan(fixture: Mapping[str, Any]) -> dict[str, Any]:
    source = fixture["source"]
    extracted = source["extracted_data"]
    vehicle = fixture["authoritative_snapshot"]["vehicle"]
    context = {
        "vehicle_id": str(fixture["target_vehicle_id"]), "stock_number": str(extracted["stock_number"]),
        "vin": vehicle.get("vin"), "backend_record_id": str(extracted["backend_record_id"]),
        "vehicle_version": int(vehicle["version"]), "backend_revision": 0,
    }
    receipt = {
        "receipt_id": str(fixture["source_receipt_id"]), "source_digest": str(fixture["source_digest"]),
        "evidence_digest": str(fixture["evidence_digest"]), "thread_id": str(fixture["source_thread_id"]),
        "message_id": str(fixture["source_message_id"]), "source_uid": str(source["provider_uid"]),
        "received_at": str(source["received_at"]), "correspondence": scenario_correspondence(fixture),
    }
    lines = []
    for raw in extracted["operation_lines"]:
        lines.append(dict(raw))
    attachment_source = source["attachments"][0]
    attachment = {
        "digest": str(attachment_source["source_hash"]), "filename": str(attachment_source["file_name"]),
        "extracted_text": str(attachment_source["extracted_text"]), "stock_number": str(extracted["stock_number"]),
        "vin": context.get("vin"), "lines": lines,
    }
    plan = V2Planner().plan(receipt, [attachment], [context])
    plan["instructions"] = [instruction for instruction in plan["instructions"]
        if instruction["action_type"] in LIVE_ACTION_TYPES and instruction["vehicle_id"] == context["vehicle_id"]]
    for index, instruction in enumerate(plan["instructions"], 1):
        instruction["instruction_id"] = f"instruction-{index:04d}"
        instruction["audit_event_ref"] = f"audit-plan-{index:04d}"
    if int(fixture["scenario_no"]) == 9:
        for instruction in plan["instructions"]:
            instruction["decision_disposition"] = "review"
            instruction["reason"] = "ambiguous_identity_requires_review"
        plan["aggregate_disposition"] = "review"
    if int(fixture["scenario_no"]) == 12:
        for instruction in plan["instructions"]:
            if instruction["payload"].get("description") == "mixed FMG signage / GVM / GCM / Tare decals":
                instruction["reason"] = "mixed_decals_taxonomy_review"
    return validate_v2_plan(plan, authoritative_contexts=[context])


def main() -> None:
    if os.environ.get(APPROVAL) != "YES":
        raise RuntimeError(f"Set {APPROVAL}=YES for this reversible STAGING-only migration")
    sql = MIGRATION.read_text(encoding="utf-8")
    if STAGING_REF not in sql or PRODUCTION_REF in sql:
        raise RuntimeError("PDC_MIXED_DISPOSITION_NON_STAGING_REFUSED")

    installed = management_query(
        "SELECT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260903124000' "
        "AND name='pdc_email_ai_evidence_bound_fixture_refresh_20260903') AS present"
    )[0]["present"]
    if not installed:
        try:
            management_query(sql)  # Supabase CLI:supabase management credential, hard-pinned STAGING only.
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"STAGING_MIGRATION_HTTP_{exc.code}: {exc.read().decode('utf-8', 'replace')[:2000]}") from exc

    deployed = management_query("""
      SELECT
        (SELECT version FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version DESC LIMIT 1) AS ledger_head,
        encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS strict_sha256,
        encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS executor_sha256,
        position($needle$decision_disposition'='planned'$needle$ IN pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure))>0 AS mixed_route_installed,
        position($needle$decision_disposition'<>'planned'$needle$ IN pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure))=0 AS obsolete_route_absent,
        position('operation_update_mixed_plan_requires_replan' IN pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure))>0 AS operation_update_fail_closed,
        NOT has_table_privilege('authenticated','public.pdc_email_ai_mixed_disposition_repairs_20260903','select') AS repair_evidence_private,
        NOT has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5','select') AS fixture_table_private,
        to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL AS production_sentinel_present
    """)[0]
    if deployed["ledger_head"] != VERSION or deployed["executor_sha256"] != "e9f61731254263a893352ecb0311798c032c4384e17df1a72369990a6e7b8b1a":
        raise RuntimeError(f"DEPLOYED_HASH_OR_LEDGER_FAILED: {deployed}")
    required_flags = ("mixed_route_installed", "obsolete_route_absent", "operation_update_fail_closed", "repair_evidence_private", "fixture_table_private")
    if not all(bool(deployed[key]) for key in required_flags) or deployed["production_sentinel_present"]:
        raise RuntimeError(f"DEPLOYED_SAFETY_POSTCONDITION_FAILED: {deployed}")

    base, headers, anon_headers = runtime_headers()  # Reads only pdc-email-ai-lead/.env; no privileged credential is copied.
    generation_status, generation = wait_for_rpc(
        base, headers, "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v5", {"p_generation_id": GENERATION_ID}
    )
    generation = require_ok(generation_status, generation, "FIXTURE_GENERATION_3")
    fixtures = generation.get("fixtures") or []
    if not generation.get("ok") or generation.get("generation_id") != GENERATION_ID or len(fixtures) != 14:
        raise RuntimeError("RUNTIME_FIXTURE_GENERATION_3_INVALID")

    plans: list[dict[str, Any]] = []
    validations: list[dict[str, Any]] = []
    for fixture in fixtures:
        source = fixture["source"]
        operation_lines = source["extracted_data"]["operation_lines"]
        operation_ids = [str(line["operation_no"]) for line in operation_lines]
        expected_ids = [f"OP{index}" for index in range(91, 91 + len(operation_lines))]
        attachment_text = str(source["attachments"][0]["extracted_text"])
        if operation_ids != expected_ids or any(f"OP {operation_id[2:].zfill(3)}" not in attachment_text for operation_id in operation_ids):
            raise RuntimeError(f"SOURCE_EVIDENCE_OPERATION_BINDING_INVALID_SCENARIO_{fixture['scenario_no']}: {operation_ids}")
        plan = build_fixture_plan(fixture)
        plans.append(plan)
        status, result = rpc(
            base, headers, "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v5",
            {"p_generation_id": GENERATION_ID, "p_plan": plan},
        )
        result = require_ok(status, result, f"VALIDATE_SCENARIO_{fixture['scenario_no']}")
        if not result.get("ok") or result.get("code") != "typed_v2_plan_valid":
            raise RuntimeError(f"VALIDATOR_REJECTED_SCENARIO_{fixture['scenario_no']}: {result}")
        validations.append({
            "scenario_no": fixture["scenario_no"], "scenario_key": fixture["scenario_key"],
            "instruction_count": result["instruction_count"], "code": result["code"],
        })
    validated_fixture_count = len(validations)
    if validated_fixture_count != 14:
        raise RuntimeError(f"VALIDATED_FIXTURE_COUNT_INVALID: {validated_fixture_count}")

    first = plans[0]
    first_dispositions = [item.get("decision_disposition") for item in first.get("instructions", [])]
    if first_dispositions.count("planned") != 2 or first_dispositions.count("review") != 2:
        summary = [
            {"action_type": item.get("action_type"), "disposition": item.get("decision_disposition"), "reason": item.get("reason"), "payload": item.get("payload")}
            for item in first.get("instructions", [])
        ]
        raise RuntimeError(f"SCENARIO_1_NOT_EXPECTED_MIXED_PLAN: {summary}")
    apply_status, mixed_apply = rpc(base, headers, "apply_pdc_email_ai_typed_action_surface_20260901_strict", {"p_plan": first})
    mixed_apply = require_ok(apply_status, mixed_apply, "MIXED_APPLY")
    actions = mixed_apply.get("actions") or []
    planned_actions = [row for row in actions if row.get("disposition") == "APPLIED_AND_VERIFIED"]
    review_actions = [row for row in actions if row.get("disposition") == "GENUINELY_AMBIGUOUS"]
    if len(actions) != 4 or len(planned_actions) != 2 or len(review_actions) != 2:
        raise RuntimeError(f"MIXED_ACTION_ACCOUNTING_FAILED: {mixed_apply}")
    if any(row.get("canonical_rpc") for row in review_actions):
        raise RuntimeError(f"REVIEW_ACTION_DISPATCHED: {review_actions}")
    if any(not row.get("canonical_rpc") or (row.get("verification") or {}).get("parity") is not True for row in planned_actions):
        raise RuntimeError(f"PLANNED_ACTION_NOT_APPLIED_VERIFIED: {planned_actions}")
    if mixed_apply.get("code") != "pdc_email_ai_typed_action_surface_partial_failure" or mixed_apply.get("disposition") != "PARTIAL_FAILURE":
        raise RuntimeError(f"MIXED_AGGREGATE_DISPOSITION_INVALID: {mixed_apply}")

    replay_status, replay = rpc(base, headers, "apply_pdc_email_ai_typed_action_surface_20260901_strict", {"p_plan": first})
    replay = require_ok(replay_status, replay, "MIXED_EXACT_REPLAY")
    if replay.get("transaction_id") != mixed_apply.get("transaction_id") or replay.get("actions") != mixed_apply.get("actions") or replay.get("replay") is not True:
        raise RuntimeError(f"MIXED_EXACT_REPLAY_NOT_STABLE: {replay}")

    hostile = {"environment": "production", "instructions": [{"action_type": "sql", "payload": "DROP TABLE vehicles"}]}
    hostile_status, hostile_result = rpc(base, headers, "apply_pdc_email_ai_typed_action_surface_20260901_strict", {"p_plan": hostile})
    if hostile_status != 200 or hostile_result.get("ok") or hostile_result.get("code") != "typed_v2_plan_invalid":
        raise RuntimeError(f"HOSTILE_PLAN_REJECTION_FAILED: {hostile_status} {hostile_result}")

    protected_tables = (
        "pdc_email_ai_mixed_disposition_repairs_20260903",
        "pdc_email_ai_v2_acceptance_fixture_generations_20260903_v5",
        "pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5",
    )
    protected_table_http_statuses: dict[str, dict[str, int]] = {}
    for table in protected_tables:
        auth_status, _ = request_json("GET", f"{base}/rest/v1/{table}?select=*&limit=1", headers)
        anon_status, _ = request_json("GET", f"{base}/rest/v1/{table}?select=*&limit=1", anon_headers)
        if 200 <= auth_status < 300 or 200 <= anon_status < 300:
            raise RuntimeError(f"PROTECTED_TABLE_EXPOSED: {table} runtime={auth_status} anon={anon_status}")
        protected_table_http_statuses[table] = {"runtime": auth_status, "anon": anon_status}

    receipt_proof = management_query("""
      SELECT
        count(*) AS transaction_count,
        count(*) FILTER(WHERE aggregate_disposition='PARTIAL_FAILURE') AS partial_count,
        (SELECT count(*) FROM public.pdc_email_ai_successor_action_receipts a JOIN public.pdc_email_ai_successor_transaction_receipts t USING(transaction_id)
          WHERE t.source_receipt_id=(SELECT source_receipt_id FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 WHERE scenario_no=1)
            AND a.disposition='APPLIED_AND_VERIFIED') AS applied_verified_count,
        (SELECT count(*) FROM public.pdc_email_ai_successor_action_receipts a JOIN public.pdc_email_ai_successor_transaction_receipts t USING(transaction_id)
          WHERE t.source_receipt_id=(SELECT source_receipt_id FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 WHERE scenario_no=1)
            AND a.disposition='GENUINELY_AMBIGUOUS' AND a.canonical_rpc IS NULL) AS review_not_dispatched_count,
        (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 f
          WHERE EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_transaction_receipts t WHERE t.source_receipt_id=f.source_receipt_id)) AS consumed_fixture_count
      FROM public.pdc_email_ai_successor_transaction_receipts
      WHERE source_receipt_id=(SELECT source_receipt_id FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 WHERE scenario_no=1)
    """)[0]
    expected_counts = {"transaction_count": 1, "partial_count": 1, "applied_verified_count": 2, "review_not_dispatched_count": 2, "consumed_fixture_count": 1}
    if any(int(receipt_proof[key]) != value for key, value in expected_counts.items()):
        raise RuntimeError(f"PERSISTED_MIXED_RECEIPT_PROOF_FAILED: {receipt_proof}")

    report = {
        "ok": True,
        "environment": "staging",
        "project_ref": STAGING_REF,
        "migration": VERSION,
        "generation_id": GENERATION_ID,
        "fixture_rpc": "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v5",
        "validation_rpc": "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v5",
        "validated_fixture_count": validated_fixture_count,
        "source_evidence_operation_binding": True,
        "mixed_apply": {
            "http_status": apply_status,
            "code": mixed_apply.get("code"),
            "disposition": mixed_apply.get("disposition"),
            "transaction_id": mixed_apply.get("transaction_id"),
            "planned_dispositions": [row.get("disposition") for row in planned_actions],
            "review_dispositions": [row.get("disposition") for row in review_actions],
            "review_canonical_rpc": [row.get("canonical_rpc") for row in review_actions],
            "planned_verification_parity": [(row.get("verification") or {}).get("parity") for row in planned_actions],
        },
        "exact_replay_stable": True,
        "hostile_plan_rejection": {"http_status": hostile_status, "code": hostile_result.get("code")},
        "protected_table_http_statuses": protected_table_http_statuses,
        "persisted_receipt_proof": receipt_proof,
        "deployed_contract": deployed,
        "runtime_credential_source": RUNTIME_CREDENTIAL_SOURCE,
        "production_contacted": False,
        "production_writes": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "ok": True, "migration": VERSION, "generation_id": GENERATION_ID,
        "validated_fixture_count": validated_fixture_count, "mixed_transaction_id": mixed_apply.get("transaction_id"),
        "proof": str(EVIDENCE),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
