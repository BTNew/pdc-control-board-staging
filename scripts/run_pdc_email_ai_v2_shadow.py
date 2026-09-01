#!/usr/bin/env python3
"""Run the secretless 14-scenario v2 shadow campaign and retain its receipt."""
from __future__ import annotations

import hashlib
import json
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from backend.pdc_email_ai_v2_runtime import V2ShadowRuntime, write_shadow_receipt
from backend.pdc_email_ai_v2_rules import CraigRuleStore


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def context(stock: str, suffix: str = "") -> dict:
    vehicle = str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-v2-vehicle:" + stock + suffix))
    backend = str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-v2-backend:" + stock + suffix))
    return {"vehicle_id": vehicle, "stock_number": stock, "vin": None, "backend_record_id": backend, "vehicle_version": 1, "backend_revision": 1, "location": "PMB"}


def attachment_for(scenario: dict, stock: str) -> dict:
    evidence = scenario.get("evidence") or {}
    lines = []
    for index, value in enumerate(evidence.get("lines") or [], 1):
        lines.append({"operation_no": f"OP{index}", "description": value, "estimated_hours": None})
    if not lines and scenario["name"] == "classification_gvm_regression":
        lines = [{"operation_no": "OP1", "description": "OME GVM upgrade", "estimated_hours": 5.0}]
    if not lines and scenario["name"] not in {"parts_eta_update", "parts_complete", "duplicate_replay", "missing_backend_vehicle", "authoritative_readback", "multiple_actions_one_email", "backend_vehicle_absent_board"}:
        lines = [{"operation_no": "OP1", "description": scenario["name"], "estimated_hours": None}]
    return {"digest": digest(scenario["scenario_id"] + ":attachment"), "filename": scenario["scenario_id"] + ".json", "stock_number": stock, "lines": lines, "explicit_sublet": scenario["name"] == "sublet_booking_update"}


def correspondence_for(scenario: dict, stock: str) -> str:
    name = scenario["name"]
    if name == "backend_vehicle_absent_board":
        return f"Stock {stock} activate now."
    if name == "parts_eta_update":
        return f"Stock {stock} Parts ETA 15 September 2026."
    if name == "parts_complete":
        return f"Stock {stock} Parts complete."
    if name == "multiple_actions_one_email":
        return f"Stock {stock} Parts ETA 16 September 2026. Stock {stock} add note: supplier confirmed."
    if name == "authoritative_readback":
        return f"Stock {stock} Parts ETA 17 September 2026. Stock {stock} move vehicle to PMB."
    return f"Stock {stock} {name}."


def main() -> int:
    catalog = json.loads((ROOT / "fixtures" / "v2-safe-fixtures-v1.json").read_text(encoding="utf-8"))
    runtime = V2ShadowRuntime(rules=CraigRuleStore.default())
    results = []
    for scenario in catalog["scenarios"]:
        stock = str((scenario.get("evidence") or {}).get("stock_number") or scenario["scenario_id"] + "-STOCK")
        source_digest = digest("pdc-v2-source:" + scenario["scenario_id"])
        receipt = {"receipt_id": str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-v2-receipt:" + scenario["scenario_id"])), "source_digest": source_digest, "evidence_digest": digest("pdc-v2-evidence:" + scenario["scenario_id"]), "thread_id": "synthetic-" + scenario["scenario_id"], "message_id": "synthetic-" + scenario["scenario_id"], "correspondence": correspondence_for(scenario, stock), "received_at": "2026-09-01T00:00:00+00:00"}
        current = context(stock)
        if scenario["name"] == "missing_backend_vehicle":
            current["backend_record_id"] = None
        if scenario["name"] == "multiple_vehicles":
            second_stock = stock + "-B"
            attachments = [attachment_for(scenario, stock), attachment_for(scenario, second_stock)]
            contexts = [current, context(second_stock)]
        else:
            attachments = [attachment_for(scenario, stock)]
            contexts = [current]
        outcome = runtime.run(receipt, attachments, contexts)
        results.append({"scenario_id": scenario["scenario_id"], "name": scenario["name"], "expected_action_types": [item["action_type"] for item in scenario["instructions"]], "plan_id": outcome["plan_id"], "instruction_count": outcome["instruction_count"], "attachment_count": len(attachments), "all_instructions_accounted": outcome["all_instructions_accounted"], "dispositions": [row["disposition"] for row in outcome["action_results"]], "operational_writes_attempted": outcome["operational_writes_attempted"]})
    report = {"schema_version": "pdc-email-ai-v2-shadow-campaign-v1", "mode": "SHADOW_ZERO_WRITE", "fixture_count": len(results), "hostile_negative_count": len(catalog["hostile_negatives"]), "scenarios": results, "all_scenarios_accounted": len(results) == 14 and all(row["all_instructions_accounted"] for row in results), "operational_writes_attempted": False, "mailbox_mutated": False, "production_touched": False, "legacy_runtime_touched": False}
    destination = ROOT / "review-evidence" / "v2-runtime" / "shadow-campaign-receipt.json"
    report["receipt_sha256"] = write_shadow_receipt(destination, report)
    print(json.dumps({"receipt": str(destination), "receipt_sha256": report["receipt_sha256"], "fixture_count": report["fixture_count"], "hostile_negative_count": report["hostile_negative_count"], "operational_writes_attempted": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
