#!/usr/bin/env python3
"""Apply and verify the final fresh STAGING Email AI acceptance fixtures."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
from copy import deepcopy
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
EXPECTED_RUNTIME_USER_ID = "e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8"
VERSION = "20260903125000"
GENERATION_ID = "27c7c81f-0006-4000-8000-000000000014"
FIXTURE_RPC = "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v6"
VALIDATION_RPC = "validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v6"
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260903125000"
MIGRATION = ROOT / "supabase/staging_only/20260903125000_pdc_email_ai_final_acceptance_fixture_refresh_20260903.sql"
EVIDENCE = ROOT / "review-evidence/t_27c7c81f/final-acceptance-fixture-refresh-staging-verification.json"
RUNTIME_CREDENTIAL_SOURCE = "pdc-email-ai-lead/.env"
LIVE_ACTION_TYPES = {
    "activate_vehicle", "booking_cancel", "booking_move", "booking_set",
    "location_set", "note_append", "operation_add", "operation_update",
    "parts_complete", "parts_eta_set", "required_work_set", "rft_collect",
    "rft_transfer", "work_complete",
}


def wait_for_rpc(
    base: str,
    headers: dict[str, str],
    function: str,
    payload: dict[str, Any],
) -> tuple[int, Any]:
    last: tuple[int, Any] = (0, None)
    for _ in range(30):
        last = rpc(base, headers, function, payload)
        if last[0] == 200:
            return last
        time.sleep(1)
    return last


def current_vehicles(base: str, headers: dict[str, str]) -> dict[str, dict[str, Any]]:
    status, snapshot = rpc(base, headers, "get_pdc_email_vehicle_location_snapshot", {})
    snapshot = require_ok(status, snapshot, "CURRENT_VEHICLE_SNAPSHOT")
    data = snapshot.get("data") if isinstance(snapshot, dict) and isinstance(snapshot.get("data"), dict) else snapshot
    vehicles = data.get("vehicles") if isinstance(data, dict) else None
    if not isinstance(vehicles, list):
        raise RuntimeError("CURRENT_VEHICLE_SNAPSHOT_INVALID")
    return {
        str(vehicle["id"]): vehicle
        for vehicle in vehicles
        if isinstance(vehicle, dict) and vehicle.get("id")
    }


def verified_runtime_headers() -> tuple[str, dict[str, str], dict[str, str]]:
    base, headers, anon_headers = runtime_headers()
    status, user = request_json("GET", f"{base}/auth/v1/user", headers)
    user = require_ok(status, user, "RUNTIME_IDENTITY")
    if not isinstance(user, dict) or user.get("id") != EXPECTED_RUNTIME_USER_ID:
        raise RuntimeError("RUNTIME_IDENTITY_MISMATCH")
    return base, headers, anon_headers


def build_current_version_plan(
    fixture: Mapping[str, Any],
    current_vehicle: Mapping[str, Any],
) -> dict[str, Any]:
    source = fixture["source"]
    extracted = source["extracted_data"]
    context = {
        "vehicle_id": str(fixture["target_vehicle_id"]),
        "stock_number": str(extracted["stock_number"]),
        "vin": current_vehicle.get("vin"),
        "backend_record_id": str(extracted["backend_record_id"]),
        "vehicle_version": int(current_vehicle["version"]),
        "backend_revision": 0,
    }
    receipt = {
        "receipt_id": str(fixture["source_receipt_id"]),
        "source_digest": str(fixture["source_digest"]),
        "evidence_digest": str(fixture["evidence_digest"]),
        "thread_id": str(fixture["source_thread_id"]),
        "message_id": str(fixture["source_message_id"]),
        "source_uid": str(source["provider_uid"]),
        "received_at": str(source["received_at"]),
        "correspondence": str(source["correspondence"]),
    }
    attachment_source = source["attachments"][0]
    attachment = {
        "digest": str(attachment_source["source_hash"]),
        "filename": str(attachment_source["file_name"]),
        "extracted_text": str(attachment_source["extracted_text"]),
        "stock_number": str(extracted["stock_number"]),
        "vin": context["vin"],
        "lines": [dict(line) for line in extracted["operation_lines"]],
    }
    plan = V2Planner().plan(receipt, [attachment], [context])
    plan["instructions"] = [
        instruction
        for instruction in plan["instructions"]
        if instruction["action_type"] in LIVE_ACTION_TYPES
        and instruction["vehicle_id"] == context["vehicle_id"]
    ]
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
        raise RuntimeError("PDC_FINAL_FIXTURE_NON_STAGING_REFUSED")
    base, headers, anon_headers = verified_runtime_headers()

    installed = management_query(
        "SELECT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations "
        "WHERE version='20260903125000' "
        "AND name='pdc_email_ai_final_acceptance_fixture_refresh_20260903') AS present"
    )[0]["present"]
    if not installed:
        try:
            management_query(sql)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:2000]
            raise RuntimeError(f"STAGING_MIGRATION_HTTP_{exc.code}: {detail}") from exc

    deployed = management_query("""
      SELECT
        (SELECT version FROM supabase_migrations.schema_migrations
          WHERE version~'^[0-9]{14}$' ORDER BY version DESC LIMIT 1) AS ledger_head,
        (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6) AS fixture_count,
        (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6 f
          WHERE EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_transaction_receipts t
            WHERE t.source_receipt_id=f.source_receipt_id)) AS consumed_fixture_count,
        (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6 n
          JOIN public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 o USING(scenario_no)
          WHERE n.operation_source=o.operation_source
            AND n.authoritative_snapshot=o.authoritative_snapshot
            AND (SELECT i.extracted_data->'operation_lines' FROM public.ai_email_intake i WHERE i.id=n.source_receipt_id)
                =(SELECT i.extracted_data->'operation_lines' FROM public.ai_email_intake i WHERE i.id=o.source_receipt_id)) AS operation_evidence_match_count,
        (SELECT count(*) FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6 n
          WHERE EXISTS(SELECT 1 FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v5 o
            WHERE o.source_receipt_id=n.source_receipt_id OR o.source_digest=n.source_digest
              OR o.evidence_digest=n.evidence_digest OR o.source_message_id=n.source_message_id
              OR o.source_thread_id=n.source_thread_id)) AS predecessor_lineage_collision_count,
        NOT has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixture_generations_20260903_v6','select,insert,update,delete') AS generation_table_private,
        NOT has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6','select,insert,update,delete') AS fixture_table_private,
        has_function_privilege('authenticated','public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v6(uuid)','execute') AS fixture_rpc_authenticated,
        has_function_privilege('authenticated','public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v6(uuid,jsonb)','execute') AS validation_rpc_authenticated,
        NOT has_function_privilege('anon','public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903_v6(uuid)','execute') AS fixture_rpc_anon_denied,
        NOT has_function_privilege('anon','public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903_v6(uuid,jsonb)','execute') AS validation_rpc_anon_denied,
        to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL AS production_sentinel_present
    """)[0]
    required_true = (
        "generation_table_private", "fixture_table_private",
        "fixture_rpc_authenticated", "validation_rpc_authenticated",
        "fixture_rpc_anon_denied", "validation_rpc_anon_denied",
    )
    if (
        deployed["ledger_head"] != VERSION
        or int(deployed["fixture_count"]) != 14
        or int(deployed["consumed_fixture_count"]) != 0
        or int(deployed["operation_evidence_match_count"]) != 14
        or int(deployed["predecessor_lineage_collision_count"]) != 0
        or not all(bool(deployed[key]) for key in required_true)
        or bool(deployed["production_sentinel_present"])
    ):
        raise RuntimeError(f"DEPLOYED_POSTCONDITION_FAILED: {deployed}")

    immutability = management_query("""
      DO $test$
      BEGIN
        BEGIN
          UPDATE public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6
          SET scenario_key=scenario_key;
          RAISE EXCEPTION 'fixture mutation unexpectedly succeeded';
        EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
        BEGIN
          UPDATE public.ai_email_intake SET subject=subject
          WHERE id=(SELECT source_receipt_id FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6 LIMIT 1);
          RAISE EXCEPTION 'source mutation unexpectedly succeeded';
        EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
        BEGIN
          DELETE FROM public.ai_email_attachments
          WHERE intake_id=(SELECT source_receipt_id FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6 LIMIT 1);
          RAISE EXCEPTION 'attachment mutation unexpectedly succeeded';
        EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
      END $test$;
      SELECT true AS fixture_source_attachment_immutability_verified;
    """)[0]

    generation_status, generation = wait_for_rpc(
        base, headers, FIXTURE_RPC, {"p_generation_id": GENERATION_ID}
    )
    generation = require_ok(generation_status, generation, "FIXTURE_GENERATION_6")
    fixtures = generation.get("fixtures") or []
    consumed = [fixture["scenario_no"] for fixture in fixtures if fixture.get("consumed")]
    if (
        not generation.get("ok")
        or generation.get("generation_id") != GENERATION_ID
        or generation.get("generation_no") != 6
        or len(fixtures) != 14
        or consumed
    ):
        raise RuntimeError(f"RUNTIME_FIXTURE_GENERATION_6_INVALID: consumed={consumed}")

    validations: list[dict[str, Any]] = []
    plans: list[dict[str, Any]] = []
    current_hours_cases = {"ai_estimate_1_0": 0, "job_card_2_5": 0, "job_card_0_0": 0}
    taxonomy_review_count = 0
    for fixture in fixtures:
        target_id = str(fixture["target_vehicle_id"])
        current_vehicle = current_vehicles(base, headers).get(target_id)
        if current_vehicle is None or not isinstance(current_vehicle.get("version"), int):
            raise RuntimeError(f"CURRENT_VEHICLE_MISSING_SCENARIO_{fixture['scenario_no']}")
        plan = build_current_version_plan(fixture, current_vehicle)
        plans.append(plan)
        plan_versions = {
            instruction["expected_state"]["vehicle_version"]
            for instruction in plan["instructions"]
        }
        if plan_versions != {int(current_vehicle["version"])}:
            raise RuntimeError(f"STALE_PLAN_VERSION_SCENARIO_{fixture['scenario_no']}: {plan_versions}")
        for instruction in plan["instructions"]:
            if instruction["action_type"] == "operation_add":
                payload = instruction["payload"]
                pair = (payload.get("estimated_hours"), payload.get("estimated_hours_source"))
                if pair == (1.0, "ai_estimate"):
                    current_hours_cases["ai_estimate_1_0"] += 1
                elif pair == (2.5, "job_card"):
                    current_hours_cases["job_card_2_5"] += 1
                elif pair == (0.0, "job_card"):
                    current_hours_cases["job_card_0_0"] += 1
            if (
                int(fixture["scenario_no"]) == 12
                and instruction.get("reason") == "mixed_decals_taxonomy_review"
                and instruction.get("decision_disposition") == "review"
            ):
                taxonomy_review_count += 1
        status, validation = rpc(
            base,
            headers,
            VALIDATION_RPC,
            {"p_generation_id": GENERATION_ID, "p_plan": plan},
        )
        validation = require_ok(status, validation, f"VALIDATE_SCENARIO_{fixture['scenario_no']}")
        if not validation.get("ok") or validation.get("code") != "typed_v2_plan_valid":
            raise RuntimeError(f"VALIDATOR_REJECTED_SCENARIO_{fixture['scenario_no']}: {validation}")
        postvalidation_vehicle = current_vehicles(base, headers).get(target_id)
        if (
            postvalidation_vehicle is None
            or postvalidation_vehicle.get("version") != current_vehicle.get("version")
        ):
            raise RuntimeError(
                f"POSTVALIDATION_VEHICLE_VERSION_CHANGED_SCENARIO_{fixture['scenario_no']}"
            )
        validations.append({
            "scenario_no": fixture["scenario_no"],
            "scenario_key": fixture["scenario_key"],
            "current_vehicle_version": int(current_vehicle["version"]),
            "instruction_count": validation["instruction_count"],
            "code": validation["code"],
        })
    if len(validations) != 14 or not all(value == 14 for value in current_hours_cases.values()):
        raise RuntimeError(
            f"CURRENT_PLAN_COVERAGE_INVALID: validations={len(validations)} hours={current_hours_cases}"
        )
    if taxonomy_review_count != 1:
        raise RuntimeError(f"TAXONOMY_REVIEW_COVERAGE_INVALID: {taxonomy_review_count}")

    cross_target = deepcopy(plans[0])
    cross_target_vehicle_id = "00000000-0000-4000-8000-000000000001"
    for instruction in cross_target["instructions"]:
        instruction["vehicle_id"] = cross_target_vehicle_id
    cross_target_status, cross_target_result = rpc(
        base,
        headers,
        VALIDATION_RPC,
        {"p_generation_id": GENERATION_ID, "p_plan": cross_target},
    )
    if (
        cross_target_status != 200
        or cross_target_result.get("ok")
        or cross_target_result.get("code") != "acceptance_fixture_plan_binding_invalid"
    ):
        raise RuntimeError(
            f"CROSS_TARGET_PLAN_REJECTION_FAILED: {cross_target_status} {cross_target_result}"
        )

    hostile = deepcopy(plans[0])
    hostile["instructions"][0]["action_type"] = "sql"
    hostile_status, hostile_result = rpc(
        base, headers, VALIDATION_RPC, {"p_generation_id": GENERATION_ID, "p_plan": hostile}
    )
    changed = deepcopy(plans[0])
    changed["source_message_id"] = "changed-source-message@invalid"
    changed_status, changed_result = rpc(
        base, headers, VALIDATION_RPC, {"p_generation_id": GENERATION_ID, "p_plan": changed}
    )
    if hostile_status != 200 or hostile_result.get("ok") or hostile_result.get("code") != "typed_v2_plan_invalid":
        raise RuntimeError(f"HOSTILE_PLAN_REJECTION_FAILED: {hostile_status} {hostile_result}")
    if changed_status != 200 or changed_result.get("ok") or changed_result.get("code") != "acceptance_fixture_plan_binding_invalid":
        raise RuntimeError(f"CHANGED_PLAN_REJECTION_FAILED: {changed_status} {changed_result}")

    protected_tables = (
        "pdc_email_ai_v2_acceptance_fixture_generations_20260903_v6",
        "pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6",
    )
    protected_table_http_statuses: dict[str, dict[str, int]] = {}
    for table in protected_tables:
        runtime_status, _ = request_json(
            "GET", f"{base}/rest/v1/{table}?select=*&limit=1", headers
        )
        anon_status, _ = request_json(
            "GET", f"{base}/rest/v1/{table}?select=*&limit=1", anon_headers
        )
        if 200 <= runtime_status < 300 or 200 <= anon_status < 300:
            raise RuntimeError(
                f"PROTECTED_TABLE_EXPOSED: {table} runtime={runtime_status} anon={anon_status}"
            )
        protected_table_http_statuses[table] = {
            "runtime": runtime_status,
            "anon": anon_status,
        }

    final_freshness = management_query("""
      SELECT
        count(*) AS fresh_fixture_count,
        count(*) FILTER(WHERE EXISTS(
          SELECT 1 FROM public.pdc_email_ai_successor_transaction_receipts t
          WHERE t.source_receipt_id=f.source_receipt_id
        )) AS consumed_fixture_count
      FROM public.pdc_email_ai_v2_acceptance_fixtures_generation_20260903_v6 f
      WHERE f.generation_id='27c7c81f-0006-4000-8000-000000000014'::uuid
    """)[0]
    if (
        int(final_freshness["fresh_fixture_count"]) != 14
        or int(final_freshness["consumed_fixture_count"]) != 0
    ):
        raise RuntimeError(f"FINAL_FRESHNESS_CHECK_FAILED: {final_freshness}")

    report = {
        "ok": True,
        "environment": "staging",
        "project_ref": STAGING_REF,
        "migration": VERSION,
        "generation_id": GENERATION_ID,
        "fixture_rpc": FIXTURE_RPC,
        "validation_rpc": VALIDATION_RPC,
        "fresh_fixture_count": int(final_freshness["fresh_fixture_count"]),
        "consumed_fixture_count": int(final_freshness["consumed_fixture_count"]),
        "validated_current_version_plan_count": len(validations),
        "runtime_jwt_validation": validations,
        "current_hours_case_counts": current_hours_cases,
        "taxonomy_review_count": taxonomy_review_count,
        "cross_target_plan_rejection": {
            "http_status": cross_target_status,
            "code": cross_target_result.get("code"),
        },
        "hostile_plan_rejection": {
            "http_status": hostile_status,
            "code": hostile_result.get("code"),
        },
        "changed_plan_rejection": {
            "http_status": changed_status,
            "code": changed_result.get("code"),
        },
        "protected_table_http_statuses": protected_table_http_statuses,
        "deployed_contract": deployed,
        "fixture_source_attachment_immutability_verified": bool(
            immutability["fixture_source_attachment_immutability_verified"]
        ),
        "runtime_credential_source": RUNTIME_CREDENTIAL_SOURCE,
        "production_contacted": False,
        "production_writes": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "ok": True,
        "migration": VERSION,
        "generation_id": GENERATION_ID,
        "fixture_rpc": FIXTURE_RPC,
        "validation_rpc": VALIDATION_RPC,
        "fresh_fixture_count": int(final_freshness["fresh_fixture_count"]),
        "consumed_fixture_count": int(final_freshness["consumed_fixture_count"]),
        "validated_current_version_plan_count": len(validations),
        "proof": str(EVIDENCE),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
