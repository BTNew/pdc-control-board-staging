"""Dependency-free synthetic acceptance for the successor's typed boundary.

This is a local deterministic rehearsal. It models the approved canonical
command RPC and Board snapshot; it is not substituted for live STAGING proof.
"""
from __future__ import annotations

import copy
from typing import Any, Mapping

from .pdc_email_ai_successor_contract import action_idempotency_key, validate_plan
from .pdc_email_ai_successor_executor import execute_typed_plan


VEHICLE_A = "22222222-2222-4222-8222-222222222222"
VEHICLE_B = "44444444-4444-4444-8444-444444444444"


def _vehicle(vehicle_id: str, stock: str, version: int, *, eta: str | None = None, complete: bool = False) -> dict[str, Any]:
    return {
        "id": vehicle_id,
        "stock_number": stock,
        "version": version,
        "current_location": "PMB",
        "parts_completed": complete,
        "parts_update": {"worst_eta": eta, "parts_received": complete, "parts_ordered": False},
        "work_items": [],
        "sublet_booking": {},
    }


def _plan(instructions: list[dict[str, Any]], source_digest: str = "a" * 64) -> dict[str, Any]:
    return validate_plan({
        "schema_version": "pdc-email-ai-plan-v1",
        "source": {
            "receipt_id": "11111111-1111-4111-8111-111111111111",
            "source_digest": source_digest,
            "evidence_digest": "b" * 64,
            "thread_id": "synthetic-thread",
        },
        "versions": {
            "model": "synthetic-model",
            "prompt": "synthetic-prompt",
            "taxonomy": "synthetic-taxonomy",
            "rules": "synthetic-rules",
            "action_contract": "pdc-email-ai-actions-v1",
            "supabase_actions": "synthetic-canonical-actions",
        },
        "instructions": instructions,
    })


def _instruction(number: int, vehicle_id: str, stock: str, version: int, action_type: str, payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "instruction_id": f"synthetic-{number}",
        "vehicle_id": vehicle_id,
        "identity": {"stock_number": stock, "vin": None, "backend_record_id": None},
        "expected_vehicle_version": version,
        "action_type": action_type,
        "payload": payload,
        "evidence_refs": [f"synthetic:{number}"],
    }


class SyntheticStagingClient:
    """Small canonical-RPC/read-model double with exact replay semantics."""

    def __init__(self) -> None:
        self.vehicles = {
            VEHICLE_A: _vehicle(VEHICLE_A, "13000765", 9),
            VEHICLE_B: _vehicle(VEHICLE_B, "13000766", 4),
        }
        self.receipts: dict[str, dict[str, Any]] = {}
        self.effects = 0
        self.disabled = False
        self.production_writes = False
        self.outbound_email = False

    def rpc(self, name: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        if name == "apply_pdc_email_ai_transaction_successor":
            return self.apply(payload)
        if name == "get_pdc_email_vehicle_location_snapshot":
            return {"ok": True, "code": "ok", "data": {"revision": self.effects, "vehicles": copy.deepcopy(list(self.vehicles.values()))}}
        raise AssertionError(f"arbitrary RPC attempted: {name}")

    def apply(self, plan: Mapping[str, Any]) -> dict[str, Any]:
        if self.disabled:
            return {"ok": False, "code": "successor_disabled", "disposition": "FAILED_QUEUED_RETRY", "actions": []}
        source_digest = plan["source"]["source_digest"]
        if source_digest in self.receipts:
            return {**copy.deepcopy(self.receipts[source_digest]), "replay": True}
        working = copy.deepcopy(self.vehicles)
        actions: list[dict[str, Any]] = []
        all_success = True
        pending_effects = 0
        initial_versions = {vehicle_id: vehicle["version"] for vehicle_id, vehicle in working.items()}
        preflight_error = next(
            (instruction for instruction in plan["instructions"]
             if instruction["vehicle_id"] not in working
             or initial_versions[instruction["vehicle_id"]] != instruction["expected_vehicle_version"]),
            None,
        )
        for instruction in plan["instructions"]:
            key = action_idempotency_key(plan, instruction)
            vehicle = working.get(instruction["vehicle_id"])
            disposition = "BLOCKED_EXACT_REASON"
            reason = "synthetic canonical boundary rejected action"
            expected: dict[str, Any] = {}
            actual: dict[str, Any] = {}
            if vehicle is None:
                reason = "vehicle_not_found"
            elif preflight_error is not None:
                reason = "stale_authoritative_vehicle_version_requires_replan"
            elif instruction["action_type"] == "parts_eta_set":
                expected = {"parts.eta": instruction["payload"]["eta"]}
                vehicle["parts_update"]["worst_eta"] = instruction["payload"]["eta"]
                vehicle["version"] += 1
                actual = {"parts.eta": vehicle["parts_update"]["worst_eta"]}
                disposition = "APPLIED_AND_VERIFIED"
                reason = "synthetic canonical Parts ETA"
            elif instruction["action_type"] == "parts_complete":
                expected = {"parts.complete": True}
                vehicle["parts_completed"] = True
                vehicle["parts_update"]["parts_received"] = True
                vehicle["version"] += 1
                actual = {"parts.complete": True}
                disposition = "APPLIED_AND_VERIFIED"
                reason = "synthetic canonical Parts Complete"
            else:
                reason = "canonical_action_not_in_synthetic_boundary"
            if disposition != "APPLIED_AND_VERIFIED":
                all_success = False
            else:
                pending_effects += 1
            actions.append({
                "instruction_id": instruction["instruction_id"],
                "action_key": key,
                "disposition": disposition,
                "expected": expected,
                "actual": actual,
            })
        if all_success and actions:
            self.vehicles = working
            self.effects += pending_effects
            aggregate = "SUCCESS"
        elif actions:
            if preflight_error is None:
                self.vehicles = working
                self.effects += pending_effects
            aggregate = "PARTIAL_FAILURE"
        else:
            aggregate = "NO_ACTIONS"
        result = {
            "ok": aggregate == "SUCCESS",
            "code": "pdc_email_ai_transaction_completed",
            "disposition": aggregate,
            "actions": actions,
            "state": {"vehicles": copy.deepcopy(list(self.vehicles.values()))},
        }
        self.receipts[source_digest] = copy.deepcopy(result)
        return result


def run_synthetic_acceptance() -> dict[str, Any]:
    client = SyntheticStagingClient()
    plan = _plan([
        _instruction(1, VEHICLE_A, "13000765", 9, "parts_eta_set", {"eta": "2026-09-15"}),
        _instruction(2, VEHICLE_A, "13000765", 9, "parts_complete", {"confirmed": True}),
        _instruction(3, VEHICLE_B, "13000766", 4, "parts_complete", {"confirmed": True}),
    ])
    atomic = execute_typed_plan(client, plan)
    replay_effects_before = client.effects
    replay = execute_typed_plan(client, plan)
    replay_zero_duplicate_effects = client.effects == replay_effects_before
    unrelated_isolation = client.vehicles[VEHICLE_B]["stock_number"] == "13000766"
    partial_plan = _plan([
        _instruction(4, VEHICLE_A, "13000765", client.vehicles[VEHICLE_A]["version"], "notes_append", {"text": "requires reviewed notes RPC"}),
    ], source_digest="c" * 64)
    partial = execute_typed_plan(client, partial_plan)
    client.disabled = True
    disabled = client.rpc("apply_pdc_email_ai_transaction_successor", plan)
    return {
        "ok": atomic["ok"] and atomic["disposition"] == "SUCCESS" and replay_zero_duplicate_effects and unrelated_isolation and partial["disposition"] == "PARTIAL_FAILURE" and disabled["code"] == "successor_disabled",
        "atomic_multi_action": atomic["disposition"],
        "exact_replay_zero_duplicate_effects": replay_zero_duplicate_effects,
        "unrelated_vehicle_isolation": unrelated_isolation,
        "partial_action": partial["disposition"],
        "disable_fail_closed": disabled["code"],
        "production_writes": client.production_writes,
        "outbound_email": client.outbound_email,
    }


__all__ = ["SyntheticStagingClient", "run_synthetic_acceptance"]
