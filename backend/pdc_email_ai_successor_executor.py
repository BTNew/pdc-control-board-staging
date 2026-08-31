"""Single-command executor and independent authoritative readback verifier."""
from __future__ import annotations

from typing import Any, Mapping

from .pdc_email_ai_successor_contract import (
    SUCCESS_DISPOSITIONS,
    TERMINAL_DISPOSITIONS,
    PlanValidationError,
    aggregate_disposition,
    validate_plan,
)

COMMAND_RPC = "apply_pdc_email_ai_transaction_successor"
READBACK_RPC = "get_pdc_email_vehicle_location_snapshot"


class ExecutorContractError(ValueError):
    """Remote result cannot prove the requested typed plan."""


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise ExecutorContractError(f"{label} must be an object")
    return dict(value)


def _readback_value(vehicle: Mapping[str, Any], action: Mapping[str, Any]) -> Any:
    action_type = action["action_type"]
    payload = action["payload"]
    if action_type == "parts_eta_set":
        return _object(vehicle.get("parts_update") or {}, "vehicle.parts_update").get("worst_eta")
    if action_type == "parts_complete":
        return vehicle.get("parts_completed", _object(vehicle.get("parts_update") or {}, "vehicle.parts_update").get("parts_received"))
    if action_type == "parts_ordered":
        return _object(vehicle.get("parts_update") or {}, "vehicle.parts_update").get("parts_ordered")
    if action_type == "location_set":
        return str(vehicle.get("current_location") or "").upper()
    if action_type == "workgroup_requirement_set":
        work_key = payload["work_key"]
        for item in vehicle.get("work_items") or []:
            if isinstance(item, Mapping) and str(item.get("work_key") or "").upper() == work_key.upper():
                return item.get("required")
        return None
    if action_type == "sublet_booking_upsert":
        booking = vehicle.get("sublet_booking")
        if not booking and isinstance(vehicle.get("sublet_bookings"), list):
            booking = next((item for item in vehicle["sublet_bookings"] if item.get("booking_id") == payload.get("booking_id")), None)
        return _object(booking or {}, "vehicle.sublet_booking").get("booking_date", _object(booking or {}, "vehicle.sublet_booking").get("out_date"))
    if action_type == "notes_append":
        return vehicle.get("notes") or vehicle.get("team_notes")
    if action_type == "rft_transfer":
        return str(vehicle.get("current_location") or "").upper() == "RFT"
    if action_type == "rft_collect":
        return bool(vehicle.get("rft_collected") or vehicle.get("rft_collected_at") or vehicle.get("completed"))
    return None


def _expected_value(action: Mapping[str, Any]) -> Any:
    payload = action["payload"]
    if action["action_type"] == "parts_eta_set":
        return payload["eta"]
    if action["action_type"] in {"parts_complete", "parts_ordered"}:
        return True
    if action["action_type"] == "location_set":
        return payload["location"].upper()
    if action["action_type"] == "workgroup_requirement_set":
        return payload["required"]
    if action["action_type"] == "sublet_booking_upsert":
        return payload["out_date"]
    if action["action_type"] in {"rft_transfer", "rft_collect"}:
        return True
    if action["action_type"] == "notes_append":
        return payload["text"]
    return None


def _validate_action_results(result: Mapping[str, Any], plan: Mapping[str, Any]) -> list[dict[str, Any]]:
    actions = result.get("actions")
    if not isinstance(actions, list) or len(actions) != len(plan["instructions"]):
        raise ExecutorContractError("command response action accounting is incomplete")
    expected_ids = [item["instruction_id"] for item in plan["instructions"]]
    observed_ids = []
    normalized = []
    for index, item in enumerate(actions):
        row = _object(item, f"command.actions[{index}]")
        for key in ("instruction_id", "disposition", "expected", "actual"):
            if key not in row:
                raise ExecutorContractError("command response action shape is incomplete")
        if row["instruction_id"] not in expected_ids or row["instruction_id"] in observed_ids:
            raise ExecutorContractError("command response action identity is invalid")
        if row["disposition"] not in TERMINAL_DISPOSITIONS:
            raise ExecutorContractError("command response disposition is invalid")
        observed_ids.append(row["instruction_id"])
        normalized.append(row)
    if observed_ids != expected_ids:
        raise ExecutorContractError("command response action order or accounting differs from plan")
    return normalized


def _verify_readback(plan: Mapping[str, Any], readback: Mapping[str, Any], action_results: list[Mapping[str, Any]]) -> dict[str, Any]:
    data = _object(readback.get("data"), "readback.data")
    vehicles = data.get("vehicles")
    if not isinstance(vehicles, list):
        raise ExecutorContractError("readback vehicles are missing")
    by_id = {str(row.get("id")): row for row in vehicles if isinstance(row, Mapping) and row.get("id")}
    checks: list[dict[str, Any]] = []
    parity = True
    for action, result in zip(plan["instructions"], action_results):
        if result["disposition"] not in SUCCESS_DISPOSITIONS:
            checks.append({"instruction_id": action["instruction_id"], "checked": False, "reason": "action_not_successful"})
            continue
        vehicle = by_id.get(action["vehicle_id"])
        expected = _expected_value(action)
        actual = _readback_value(vehicle, action) if vehicle else None
        matches = vehicle is not None and (actual == expected or (action["action_type"] == "notes_append" and expected in str(actual or "")))
        parity = parity and matches
        checks.append({"instruction_id": action["instruction_id"], "checked": True, "matches": matches, "expected": expected, "actual": actual})
    return {"parity": parity, "checks": checks, "revision": data.get("revision")}


def execute_typed_plan(client: Any, plan: Mapping[str, Any]) -> dict[str, Any]:
    """Apply once through the typed command and prove it with a fresh snapshot."""
    try:
        validated = validate_plan(plan)
    except PlanValidationError as exc:
        raise ExecutorContractError(str(exc)) from exc
    if not hasattr(client, "rpc"):
        raise ExecutorContractError("client does not expose the fixed RPC interface")

    command = client.rpc(COMMAND_RPC, validated)
    command_obj = _object(command, "command response")
    disposition = command_obj.get("disposition")
    if disposition not in {"SUCCESS", "PARTIAL_FAILURE", "NO_ACTIONS"}:
        raise ExecutorContractError("command response aggregate disposition is invalid")
    action_results = _validate_action_results(command_obj, validated)
    if disposition != aggregate_disposition([row["disposition"] for row in action_results]):
        raise ExecutorContractError("command aggregate disposition does not match action results")

    readback = _object(client.rpc(READBACK_RPC, {}), "readback response")
    if readback.get("ok") is not True or not isinstance(readback.get("data"), Mapping):
        return {"ok": False, "code": "readback_unavailable", "disposition": "FAILED_QUEUED_RETRY", "command": command_obj, "readback": readback}
    proof = _verify_readback(validated, readback, action_results)
    success = command_obj.get("ok") is True and disposition == "SUCCESS" and proof["parity"]
    return {
        "ok": success,
        "code": "verified" if success else "readback_mismatch",
        "disposition": "SUCCESS" if success else disposition,
        "actions": action_results,
        "command": command_obj,
        "readback": proof,
    }


__all__ = ["COMMAND_RPC", "READBACK_RPC", "ExecutorContractError", "execute_typed_plan"]
