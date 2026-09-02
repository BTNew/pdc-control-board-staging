"""Strict typed contract for the isolated PDC email transaction successor.

This module is deliberately transport- and database-free. Email/PDF content can
only become a bounded, typed action plan; it can never supply SQL, table names,
RPC names, credentials, or an arbitrary mutation shape.
"""
from __future__ import annotations

import copy
import hashlib
import json
import re
from datetime import date
from typing import Any, Mapping

PLAN_SCHEMA_VERSION = "pdc-email-ai-plan-v1"
ACTION_CONTRACT_VERSION = "pdc-email-ai-actions-v1"
ACTION_CONTRACT_V2_VERSION = "pdc-email-ai-actions-v2"
TAXONOMY_VERSION = "pdc-operation-taxonomy-proposed/v1"
TAXONOMY_DISPOSITIONS = {"classified", "review", "unsupported", "conflict"}

ACTION_TYPES = frozenset(
    {
        "activate_vehicle",
        "activate_from_navision",
        "location_set",
        "workgroup_requirement_set",
        "operation_upsert",
        "operation_add",
        "operation_update",
        "job_card_set",
        "parts_eta_set",
        "parts_ordered",
        "parts_complete",
        "notes_append",
        "note_append",
        "job_card_upsert",
        "sublet_booking_upsert",
        "booking_set",
        "booking_move",
        "booking_cancel",
        "required_work_set",
        "work_complete",
        "rft_transfer",
        "rft_collect",
    }
)
TERMINAL_DISPOSITIONS = frozenset(
    {
        "APPLIED_AND_VERIFIED",
        "ALREADY_CORRECT",
        "SUPERSEDED",
        "NOT_APPLICABLE",
        "BLOCKED_EXACT_REASON",
        "GENUINELY_AMBIGUOUS",
        "FAILED_QUEUED_RETRY",
    }
)
SUCCESS_DISPOSITIONS = frozenset({"APPLIED_AND_VERIFIED", "ALREADY_CORRECT"})
_FORBIDDEN_KEYS = frozenset(
    {
        "sql",
        "table",
        "tables",
        "column",
        "schema",
        "rpc",
        "function",
        "query",
        "mutation",
        "dml",
        "service_role",
        "administrator",
        "admin",
        "rls_bypass",
        "security_definer",
    }
)
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
_STOCK = re.compile(r"^[A-Z0-9][A-Z0-9-]{3,79}$")
_VIN = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")
_WORK_KEYS = frozenset(
    {"PARTS", "TINT", "HOIST", "FITTING", "BUS_4X4", "FABRICATION", "ELECTRICAL", "TYRE", "PIT_INSPECTION", "SUBLET"}
)
_LOCATIONS = frozenset({"YH", "PMB", "QC", "RFT", "OTHER", "IT"})


def taxonomy_disposition_for_operation(description: Any, work_key: Any, taxonomy_version: Any) -> str:
    """Return the server-compatible disposition for a typed operation classification.

    Historical labels are evidence, not authority. In particular, a GVM token
    inside signage/decals must never turn an operation into Hoist or Sublet.
    """
    if not isinstance(taxonomy_version, str) or not re.fullmatch(r"pdc-operation-taxonomy-(?:proposed|approved)/v[0-9]+", taxonomy_version):
        return "unsupported"
    if not isinstance(description, str) or not isinstance(work_key, str):
        return "unsupported"
    normalized = re.sub(r"[^a-z0-9]+", " ", description.casefold()).strip()
    group = work_key.strip().upper()
    if group not in _WORK_KEYS:
        return "unsupported"
    if re.search(r"\bidentity conflict\b", normalized):
        return "conflict"
    if re.search(r"\b(?:unresolved|no operation rows)\b", normalized):
        return "unsupported"
    if re.search(r"\b(signage|decal|decals|safety stripping|logo|tare|gcm)\b", normalized):
        return "review"
    if group == "SUBLET":
        return "unsupported"
    if "wheel nut indicator" in normalized and group != "TYRE":
        return "conflict"
    if "fire extinguisher" in normalized and group != "FABRICATION":
        return "conflict"
    if re.search(r"\b(?:arb )?long (?:range|ranger)(?: fuel)? tank\b", normalized) and group != "HOIST":
        return "conflict"
    if re.search(r"\b12v\b.*\bsocket\b|\bsocket\b.*\b12v\b", normalized):
        return "review"
    if "safety triangle" in normalized:
        return "review"
    if re.search(r"\bweather shields?\b", normalized):
        return "review"
    return "classified"


class PlanValidationError(ValueError):
    """A plan failed closed before reaching any runtime or database boundary."""


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise PlanValidationError(f"{label} must be an object")
    return dict(value)


def _exact_keys(value: Mapping[str, Any], expected: set[str], label: str) -> None:
    if set(value) != expected:
        raise PlanValidationError(f"{label} keys do not match the strict contract")


def _text(value: Any, label: str, minimum: int = 1, maximum: int = 500) -> str:
    if not isinstance(value, str) or value != value.strip() or not minimum <= len(value) <= maximum:
        raise PlanValidationError(f"{label} is invalid")
    if any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise PlanValidationError(f"{label} contains control characters")
    return value


def _uuid(value: Any, label: str) -> str:
    text = _text(value, label, 36, 36).lower()
    if not _UUID.fullmatch(text):
        raise PlanValidationError(f"{label} must be a canonical UUID")
    return text


def _digest(value: Any, label: str) -> str:
    text = _text(value, label, 64, 64).lower()
    if not _HEX64.fullmatch(text):
        raise PlanValidationError(f"{label} must be a lowercase SHA-256 digest")
    return text


def _date(value: Any, label: str, *, allow_clear: bool = False) -> str | None:
    if value is None and allow_clear:
        return None
    text = _text(value, label, 10, 10)
    try:
        parsed = date.fromisoformat(text)
    except ValueError as exc:
        raise PlanValidationError(f"{label} must be an ISO date") from exc
    if parsed.isoformat() != text:
        raise PlanValidationError(f"{label} must be an ISO date")
    return text


def _no_forbidden(value: Any, path: str = "plan") -> None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if str(key).casefold() in _FORBIDDEN_KEYS:
                raise PlanValidationError(f"{path}.{key} is forbidden")
            _no_forbidden(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _no_forbidden(child, f"{path}[{index}]")


def _identity(value: Any, label: str) -> dict[str, Any]:
    identity = _object(value, label)
    _exact_keys(identity, {"stock_number", "vin", "backend_record_id"}, label)
    stock = identity["stock_number"]
    vin = identity["vin"]
    if stock is not None:
        stock = _text(stock, f"{label}.stock_number", 4, 80).upper()
        if not _STOCK.fullmatch(stock):
            raise PlanValidationError(f"{label}.stock_number is invalid")
    if vin is not None:
        vin = _text(vin, f"{label}.vin", 17, 17).upper()
        if not _VIN.fullmatch(vin):
            raise PlanValidationError(f"{label}.vin is invalid")
    if stock is None and vin is None:
        raise PlanValidationError(f"{label} requires Stock or VIN")
    backend = identity["backend_record_id"]
    if backend is not None:
        backend = _uuid(backend, f"{label}.backend_record_id")
    return {"stock_number": stock, "vin": vin, "backend_record_id": backend}


def _finite_nonnegative(value: Any, label: str, maximum: float = 99999.99) -> int | float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise PlanValidationError(f"{label} must be a finite non-negative number")
    if isinstance(value, float) and (value != value or value in (float("inf"), float("-inf"))):
        raise PlanValidationError(f"{label} must be finite")
    if value < 0 or value > maximum:
        raise PlanValidationError(f"{label} is outside bounds")
    if round(float(value), 2) != float(value):
        raise PlanValidationError(f"{label} has more than two decimal places")
    return value


def _operation_line(value: Any, label: str) -> dict[str, Any]:
    line = _object(value, label)
    _exact_keys(line, {"operation_no", "source_row_no", "work_key", "description", "estimated_hours"}, label)
    operation_no = _text(line["operation_no"], f"{label}.operation_no", 3, 20).upper()
    if not re.fullmatch(r"OP[1-9][0-9]{0,2}", operation_no):
        raise PlanValidationError(f"{label}.operation_no is invalid")
    source_row = line["source_row_no"]
    if isinstance(source_row, bool) or not isinstance(source_row, int) or not 1 <= source_row <= 999999999:
        raise PlanValidationError(f"{label}.source_row_no is invalid")
    work_key = _text(line["work_key"], f"{label}.work_key", 2, 32).upper()
    if work_key not in _WORK_KEYS:
        raise PlanValidationError(f"{label}.work_key is not in the controlled taxonomy")
    description = _text(line["description"], f"{label}.description", 1, 500)
    hours = _finite_nonnegative(line["estimated_hours"], f"{label}.estimated_hours", 999.99)
    return {
        "operation_no": operation_no,
        "source_row_no": source_row,
        "work_key": work_key,
        "description": description,
        "estimated_hours": hours,
    }


def _payload(action_type: str, value: Any, label: str) -> dict[str, Any]:
    payload = _object(value, label)
    if action_type in {"activate_from_navision", "activate_vehicle"}:
        _exact_keys(payload, {"backend_record_id", "stock_number", "vin", "job_card_number"}, label)
        _uuid(payload["backend_record_id"], f"{label}.backend_record_id")
        stock = _text(payload["stock_number"], f"{label}.stock_number", 4, 80).upper()
        if not _STOCK.fullmatch(stock):
            raise PlanValidationError(f"{label}.stock_number is invalid")
        if payload["vin"] is not None:
            vin = _text(payload["vin"], f"{label}.vin", 17, 17).upper()
            if not _VIN.fullmatch(vin):
                raise PlanValidationError(f"{label}.vin is invalid")
        if payload["job_card_number"] is not None:
            _text(payload["job_card_number"], f"{label}.job_card_number", 1, 80)
    elif action_type == "location_set":
        _exact_keys(payload, {"location", "reason"}, label)
        if _text(payload["location"], f"{label}.location", 2, 20).upper() not in _LOCATIONS:
            raise PlanValidationError(f"{label}.location is not controlled")
        _text(payload["reason"], f"{label}.reason", 3, 400)
    elif action_type == "workgroup_requirement_set":
        _exact_keys(payload, {"work_key", "required"}, label)
        if _text(payload["work_key"], f"{label}.work_key", 2, 32).upper() not in _WORK_KEYS:
            raise PlanValidationError(f"{label}.work_key is not controlled")
        if type(payload["required"]) is not bool:
            raise PlanValidationError(f"{label}.required must be boolean")
    elif action_type == "operation_upsert":
        _exact_keys(payload, {"operation_no", "source_row_no", "work_key", "description", "estimated_hours"}, label)
        return _operation_line(payload, label)
    elif action_type == "job_card_set":
        _exact_keys(payload, {"attachment_digest", "job_card_number", "source_uid", "stock_number", "vin"}, label)
        _digest(payload["attachment_digest"], f"{label}.attachment_digest")
        job_card = _text(payload["job_card_number"], f"{label}.job_card_number", 2, 80).upper()
        if not re.fullmatch(r"(?:JC|J)[0-9]{6,12}", job_card):
            raise PlanValidationError(f"{label}.job_card_number is invalid")
        _text(payload["source_uid"], f"{label}.source_uid", 1, 200)
        stock = _text(payload["stock_number"], f"{label}.stock_number", 4, 80).upper()
        if not _STOCK.fullmatch(stock):
            raise PlanValidationError(f"{label}.stock_number is invalid")
        if payload["vin"] is not None:
            vin = _text(payload["vin"], f"{label}.vin", 17, 17).upper()
            if not _VIN.fullmatch(vin):
                raise PlanValidationError(f"{label}.vin is invalid")
    elif action_type in {"operation_add", "operation_update"}:
        _exact_keys(payload, {"operation_no", "source_row_no", "work_key", "description", "estimated_hours", "taxonomy_version", "taxonomy_disposition", "source_uid"}, label)
        line = _operation_line({key: payload[key] for key in ("operation_no", "source_row_no", "work_key", "description", "estimated_hours")}, label)
        _text(payload["source_uid"], f"{label}.source_uid", 1, 200)
        _text(payload["taxonomy_version"], f"{label}.taxonomy_version", 1, 160)
        if payload["taxonomy_disposition"] not in TAXONOMY_DISPOSITIONS:
            raise PlanValidationError(f"{label}.taxonomy_disposition is invalid")
        expected_disposition = taxonomy_disposition_for_operation(line["description"], line["work_key"], payload["taxonomy_version"])
        if payload["taxonomy_disposition"] != expected_disposition:
            raise PlanValidationError(f"{label}.taxonomy_disposition conflicts with the versioned taxonomy")
        return {**line, "source_uid": payload["source_uid"], "taxonomy_version": payload["taxonomy_version"], "taxonomy_disposition": payload["taxonomy_disposition"]}
    elif action_type == "parts_eta_set":
        _exact_keys(payload, {"eta"}, label)
        _date(payload["eta"], f"{label}.eta", allow_clear=True)
    elif action_type in {"parts_ordered", "parts_complete", "rft_transfer", "rft_collect"}:
        _exact_keys(payload, {"confirmed"}, label)
        if payload["confirmed"] is not True:
            raise PlanValidationError(f"{label}.confirmed must be true")
    elif action_type == "notes_append":
        _exact_keys(payload, {"text"}, label)
        _text(payload["text"], f"{label}.text", 1, 2000)
    elif action_type == "note_append":
        _exact_keys(payload, {"text", "event_at"}, label)
        _text(payload["text"], f"{label}.text", 1, 2000)
        _text(payload["event_at"], f"{label}.event_at", 20, 40)
    elif action_type == "job_card_upsert":
        _exact_keys(payload, {"job_card_number", "lines"}, label)
        _text(payload["job_card_number"], f"{label}.job_card_number", 1, 80)
        lines = payload["lines"]
        if not isinstance(lines, list) or not 1 <= len(lines) <= 50:
            raise PlanValidationError(f"{label}.lines must contain 1 to 50 rows")
        normalized = [_operation_line(row, f"{label}.lines[{index}]") for index, row in enumerate(lines)]
        if len({row["operation_no"] for row in normalized}) != len(normalized):
            raise PlanValidationError(f"{label}.lines contains duplicate operation numbers")
        if len({row["source_row_no"] for row in normalized}) != len(normalized):
            raise PlanValidationError(f"{label}.lines contains duplicate source rows")
        payload["lines"] = normalized
    elif action_type == "sublet_booking_upsert":
        _exact_keys(payload, {"mode", "booking_id", "provider_id", "provider_name", "expected_booking_version", "out_date", "expected_return_date"}, label)
        mode = _text(payload["mode"], f"{label}.mode", 6, 6).lower()
        if mode not in {"create", "update"}:
            raise PlanValidationError(f"{label}.mode is invalid")
        if mode == "update":
            _uuid(payload["booking_id"], f"{label}.booking_id")
        elif payload["booking_id"] is not None:
            raise PlanValidationError(f"{label}.booking_id must be null for create")
        _uuid(payload["provider_id"], f"{label}.provider_id")
        _text(payload["provider_name"], f"{label}.provider_name", 1, 120)
        booking_version = payload["expected_booking_version"]
        if isinstance(booking_version, bool) or not isinstance(booking_version, int) or booking_version < 1:
            raise PlanValidationError(f"{label}.expected_booking_version is invalid")
        out_date = _date(payload["out_date"], f"{label}.out_date")
        return_date = _date(payload["expected_return_date"], f"{label}.expected_return_date")
        if out_date and return_date and return_date < out_date:
            raise PlanValidationError(f"{label} has invalid date order")
    elif action_type == "booking_set":
        _exact_keys(payload, {"stage_code", "bay_number", "scheduled_start_at", "duration_minutes", "technician_id"}, label)
        _text(payload["stage_code"], f"{label}.stage_code", 2, 40)
        if isinstance(payload["bay_number"], bool) or not isinstance(payload["bay_number"], int) or payload["bay_number"] < 1:
            raise PlanValidationError(f"{label}.bay_number is invalid")
        _text(payload["scheduled_start_at"], f"{label}.scheduled_start_at", 20, 40)
        if isinstance(payload["duration_minutes"], bool) or not isinstance(payload["duration_minutes"], int) or payload["duration_minutes"] < 60:
            raise PlanValidationError(f"{label}.duration_minutes must be at least 60")
        if payload["technician_id"] is not None:
            _uuid(payload["technician_id"], f"{label}.technician_id")
    elif action_type == "booking_move":
        _exact_keys(payload, {"booking_id", "expected_booking_version", "stage_code", "bay_number", "scheduled_start_at", "duration_minutes", "override_reason"}, label)
        _uuid(payload["booking_id"], f"{label}.booking_id")
        if isinstance(payload["expected_booking_version"], bool) or not isinstance(payload["expected_booking_version"], int) or payload["expected_booking_version"] < 1:
            raise PlanValidationError(f"{label}.expected_booking_version is invalid")
        _text(payload["stage_code"], f"{label}.stage_code", 2, 40)
        if isinstance(payload["bay_number"], bool) or not isinstance(payload["bay_number"], int) or payload["bay_number"] < 1:
            raise PlanValidationError(f"{label}.bay_number is invalid")
        _text(payload["scheduled_start_at"], f"{label}.scheduled_start_at", 20, 40)
        if isinstance(payload["duration_minutes"], bool) or not isinstance(payload["duration_minutes"], int) or payload["duration_minutes"] < 60:
            raise PlanValidationError(f"{label}.duration_minutes must be at least 60")
        if payload["override_reason"] is not None:
            _text(payload["override_reason"], f"{label}.override_reason", 3, 400)
    elif action_type == "booking_cancel":
        _exact_keys(payload, {"booking_id", "expected_booking_version", "reason"}, label)
        _uuid(payload["booking_id"], f"{label}.booking_id")
        if isinstance(payload["expected_booking_version"], bool) or not isinstance(payload["expected_booking_version"], int) or payload["expected_booking_version"] < 1:
            raise PlanValidationError(f"{label}.expected_booking_version is invalid")
        _text(payload["reason"], f"{label}.reason", 3, 400)
    elif action_type == "required_work_set":
        _exact_keys(payload, {"work_key", "required"}, label)
        if _text(payload["work_key"], f"{label}.work_key", 2, 32).upper() not in _WORK_KEYS:
            raise PlanValidationError(f"{label}.work_key is not controlled")
        if type(payload["required"]) is not bool:
            raise PlanValidationError(f"{label}.required must be boolean")
    elif action_type == "work_complete":
        _exact_keys(payload, {"booking_id", "expected_booking_version", "work_key", "completed_at"}, label)
        _uuid(payload["booking_id"], f"{label}.booking_id")
        if isinstance(payload["expected_booking_version"], bool) or not isinstance(payload["expected_booking_version"], int) or payload["expected_booking_version"] < 1:
            raise PlanValidationError(f"{label}.expected_booking_version is invalid")
        if _text(payload["work_key"], f"{label}.work_key", 2, 32).upper() not in _WORK_KEYS:
            raise PlanValidationError(f"{label}.work_key is not controlled")
        _text(payload["completed_at"], f"{label}.completed_at", 20, 40)
    else:
        raise PlanValidationError(f"unsupported action_type {action_type}")
    return payload


def validate_plan(value: Mapping[str, Any]) -> dict[str, Any]:
    """Validate and return a detached, normalized typed plan."""
    # The v2 planner has a deliberately richer envelope (stable plan id,
    # disposition and provenance fields) than the original successor planner.
    # Keep this public entry point backwards-compatible while routing v2 plans
    # through their single strict validator before any executor boundary.
    if isinstance(value, Mapping) and "plan_id" in value and "source_receipt_id" in value:
        from .pdc_email_ai_v2_actions import validate_v2_plan

        return validate_v2_plan(value)
    source_plan = copy.deepcopy(_object(value, "plan"))
    _no_forbidden(source_plan)
    _exact_keys(source_plan, {"schema_version", "source", "versions", "instructions"}, "plan")
    if source_plan["schema_version"] != PLAN_SCHEMA_VERSION:
        raise PlanValidationError("schema_version is invalid")

    source = _object(source_plan["source"], "source")
    _exact_keys(source, {"receipt_id", "source_digest", "evidence_digest", "thread_id", "message_id", "attachment_digests"}, "source")
    _uuid(source["receipt_id"], "source.receipt_id")
    _digest(source["source_digest"], "source.source_digest")
    _digest(source["evidence_digest"], "source.evidence_digest")
    _text(source["thread_id"], "source.thread_id", 1, 512)
    _text(source["message_id"], "source.message_id", 1, 1024)
    attachment_digests = source["attachment_digests"]
    if not isinstance(attachment_digests, list) or len(attachment_digests) > 25:
        raise PlanValidationError("source.attachment_digests is invalid")
    attachment_digests = [_digest(item, "source.attachment_digests item") for item in attachment_digests]
    if len(set(attachment_digests)) != len(attachment_digests):
        raise PlanValidationError("source.attachment_digests contains duplicates")
    source["attachment_digests"] = attachment_digests

    versions = _object(source_plan["versions"], "versions")
    _exact_keys(versions, {"model", "prompt", "taxonomy", "rules", "action_contract", "supabase_actions"}, "versions")
    for key, item in versions.items():
        _text(item, f"versions.{key}", 1, 160)
    if versions["action_contract"] not in {ACTION_CONTRACT_VERSION, ACTION_CONTRACT_V2_VERSION}:
        raise PlanValidationError("versions.action_contract is invalid")

    instructions = source_plan["instructions"]
    if not isinstance(instructions, list) or len(instructions) > 200:
        raise PlanValidationError("instructions must contain 0 to 200 rows")
    normalized: list[dict[str, Any]] = []
    ids: set[str] = set()
    for index, raw in enumerate(instructions, 1):
        row = _object(raw, f"instructions[{index}]")
        _exact_keys(row, {"instruction_id", "vehicle_id", "identity", "expected_vehicle_version", "action_type", "payload", "evidence_refs"}, f"instructions[{index}]")
        instruction_id = _text(row["instruction_id"], f"instructions[{index}].instruction_id", 1, 160)
        if instruction_id in ids:
            raise PlanValidationError("instruction_id must be unique")
        ids.add(instruction_id)
        vehicle_id = _uuid(row["vehicle_id"], f"instructions[{index}].vehicle_id")
        identity = _identity(row["identity"], f"instructions[{index}].identity")
        version = row["expected_vehicle_version"]
        if isinstance(version, bool) or not isinstance(version, int) or version < 1:
            raise PlanValidationError(f"instructions[{index}].expected_vehicle_version is invalid")
        action_type = _text(row["action_type"], f"instructions[{index}].action_type", 1, 80)
        if action_type not in ACTION_TYPES:
            raise PlanValidationError(f"instructions[{index}].action_type is not allowed")
        if action_type in {"activate_vehicle", "operation_add", "operation_update", "booking_set", "booking_move", "booking_cancel", "required_work_set", "work_complete", "note_append"} and versions["action_contract"] != ACTION_CONTRACT_V2_VERSION:
            raise PlanValidationError(f"instructions[{index}].action_type requires the v2 action contract")
        payload = _payload(action_type, row["payload"], f"instructions[{index}].payload")
        refs = row["evidence_refs"]
        if not isinstance(refs, list) or not 1 <= len(refs) <= 20:
            raise PlanValidationError(f"instructions[{index}].evidence_refs is invalid")
        refs = [_text(ref, f"instructions[{index}].evidence_refs", 1, 300) for ref in refs]
        if len(set(refs)) != len(refs):
            raise PlanValidationError(f"instructions[{index}].evidence_refs contains duplicates")
        normalized.append(
            {
                "instruction_id": instruction_id,
                "vehicle_id": vehicle_id,
                "identity": identity,
                "expected_vehicle_version": version,
                "action_type": action_type,
                "payload": payload,
                "evidence_refs": refs,
            }
        )
    return {"schema_version": PLAN_SCHEMA_VERSION, "source": source, "versions": versions, "instructions": normalized}


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def action_idempotency_key(plan: Mapping[str, Any], instruction: Mapping[str, Any]) -> str:
    """Stable per-source/per-vehicle/per-action key for at-least-once delivery."""
    source = _object(plan.get("source"), "plan.source")
    material = {
        "source_digest": source.get("source_digest"),
        "receipt_id": source.get("receipt_id"),
        "vehicle_id": instruction.get("vehicle_id"),
        "instruction_id": instruction.get("instruction_id"),
        "action_type": instruction.get("action_type"),
        "payload": instruction.get("payload"),
    }
    return hashlib.sha256(canonical_json(material).encode("utf-8")).hexdigest()


def aggregate_disposition(dispositions: list[str]) -> str:
    if not dispositions:
        return "NO_ACTIONS"
    if any(item not in TERMINAL_DISPOSITIONS for item in dispositions):
        raise PlanValidationError("unknown terminal disposition")
    if all(item in SUCCESS_DISPOSITIONS for item in dispositions):
        return "SUCCESS"
    return "PARTIAL_FAILURE"


__all__ = [
    "ACTION_CONTRACT_VERSION",
    "ACTION_CONTRACT_V2_VERSION",
    "ACTION_TYPES",
    "PLAN_SCHEMA_VERSION",
    "PlanValidationError",
    "TAXONOMY_DISPOSITIONS",
    "TAXONOMY_VERSION",
    "TERMINAL_DISPOSITIONS",
    "action_idempotency_key",
    "aggregate_disposition",
    "canonical_json",
    "taxonomy_disposition_for_operation",
    "validate_plan",
]
