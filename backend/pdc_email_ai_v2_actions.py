"""Least-authority typed action requests for the v2 runtime.

The shadow client is intentionally the only enabled client in this package. It
validates a request and records the proposed action without calling Supabase or
mutating an operational store. A later controlled client must implement this
same request shape behind an independent gate.
"""
from __future__ import annotations

import hashlib
import json
import re
import uuid
from datetime import date, datetime
from typing import Any, Mapping

from .pdc_email_ai_successor_contract import ACTION_TYPES, taxonomy_disposition_for_operation


class ActionContractError(ValueError):
    """A request is outside the closed, staging-only action contract."""


_FORBIDDEN = {"sql", "table", "tables", "query", "rpc", "function", "dml", "service_role", "administrator", "admin", "production"}
_ISO_TIMESTAMP = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})$")


def _walk_safe(value: Any, path: str = "payload") -> None:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if str(key).casefold() in _FORBIDDEN:
                raise ActionContractError(f"{path}.{key} is forbidden")
            _walk_safe(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _walk_safe(child, f"{path}[{index}]")


def _text(value: Any, label: str, limit: int = 500) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > limit or value != value.strip():
        raise ActionContractError(f"{label} is invalid")
    return value


def _digest(value: Any, label: str) -> str:
    value = _text(value, label, 64)
    if len(value) != 64 or value != value.lower() or any(ch not in "0123456789abcdef" for ch in value):
        raise ActionContractError(f"{label} must be a lowercase SHA-256 digest")
    return value


def _uuid(value: Any, label: str) -> str:
    value = _text(value, label, 36).lower()
    try:
        parsed = uuid.UUID(value)
    except ValueError as exc:
        raise ActionContractError(f"{label} must be a UUID") from exc
    if str(parsed) != value:
        raise ActionContractError(f"{label} must be canonical")
    return value


def _exact_keys(value: Mapping[str, Any], expected: set[str], label: str) -> None:
    if set(value) != expected:
        raise ActionContractError(f"{label} keys do not match the strict v2 contract")


def _bounded_int(value: Any, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ActionContractError(f"{label} is invalid")
    return value


def _date_time(value: Any, label: str) -> str:
    value = _text(value, label, 64)
    if not _ISO_TIMESTAMP.fullmatch(value):
        raise ActionContractError(f"{label} is invalid")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ActionContractError(f"{label} is invalid") from exc
    if parsed.tzinfo is None:
        raise ActionContractError(f"{label} must include a timezone")
    if parsed.date().isoformat() != value[:10]:
        raise ActionContractError(f"{label} is invalid")
    return value


def _validate_v2_payload(action_type: str, payload: Mapping[str, Any], label: str, *, allow_unknown_hours: bool = False) -> None:
    if action_type == "activate_vehicle":
        _exact_keys(payload, {"backend_record_id", "stock_number", "vin", "job_card_number"}, label)
        _uuid(payload["backend_record_id"], f"{label}.backend_record_id")
        _text(payload["stock_number"], f"{label}.stock_number", 80)
        if payload["vin"] is not None:
            _text(payload["vin"], f"{label}.vin", 17)
        if payload["job_card_number"] is not None:
            _text(payload["job_card_number"], f"{label}.job_card_number", 80)
    elif action_type in {"parts_complete", "parts_ordered", "rft_transfer", "rft_collect"}:
        _exact_keys(payload, {"confirmed"}, label)
        if payload["confirmed"] is not True:
            raise ActionContractError(f"{label}.confirmed must be true")
    elif action_type == "parts_eta_set":
        _exact_keys(payload, {"eta"}, label)
        if payload["eta"] is not None:
            try:
                if date.fromisoformat(payload["eta"]).isoformat() != payload["eta"]:
                    raise ValueError
            except (TypeError, ValueError) as exc:
                raise ActionContractError(f"{label}.eta is invalid") from exc
    elif action_type == "job_card_set":
        _exact_keys(payload, {"attachment_digest", "job_card_number", "source_uid", "stock_number", "vin"}, label)
        _digest(payload["attachment_digest"], f"{label}.attachment_digest")
        if not isinstance(payload["job_card_number"], str) or re.fullmatch(r"(?:JC|J)[0-9]{6,12}", payload["job_card_number"].upper()) is None:
            raise ActionContractError(f"{label}.job_card_number is invalid")
        _text(payload["source_uid"], f"{label}.source_uid", 200)
        stock = _text(payload["stock_number"], f"{label}.stock_number", 80).upper()
        if re.fullmatch(r"[A-Z0-9][A-Z0-9-]{3,79}", stock) is None:
            raise ActionContractError(f"{label}.stock_number is invalid")
        if payload["vin"] is not None:
            vin = _text(payload["vin"], f"{label}.vin", 17).upper()
            if re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", vin) is None:
                raise ActionContractError(f"{label}.vin is invalid")
    elif action_type in {"operation_add", "operation_update"}:
        _exact_keys(payload, {"source_uid", "operation_no", "source_row_no", "work_key", "description", "estimated_hours", "taxonomy_version", "taxonomy_disposition"}, label)
        _text(payload["source_uid"], f"{label}.source_uid", 200)
        operation_no = _text(payload["operation_no"], f"{label}.operation_no", 20).upper()
        if not (re.fullmatch(r"OP[1-9][0-9]{0,2}", operation_no)
                or re.fullmatch(r"PD[0-9]{3}-[A-F0-9]{8}", operation_no)):
            raise ActionContractError(f"{label}.operation_no is invalid")
        _bounded_int(payload["source_row_no"], f"{label}.source_row_no", 1)
        work_key = _text(payload["work_key"], f"{label}.work_key", 32).upper()
        if work_key not in {"PARTS", "TINT", "HOIST", "FITTING", "BUS_4X4", "FABRICATION", "ELECTRICAL", "TYRE", "PIT_INSPECTION", "SUBLET"}:
            raise ActionContractError(f"{label}.work_key is not controlled")
        description = _text(payload["description"], f"{label}.description", 500)
        hours = payload["estimated_hours"]
        if hours is None and (allow_unknown_hours or operation_no.startswith("PD")):
            pass
        elif isinstance(hours, bool) or not isinstance(hours, (int, float)) or hours < 0 or hours > 999.99:
            raise ActionContractError(f"{label}.estimated_hours is invalid")
        taxonomy_version = _text(payload["taxonomy_version"], f"{label}.taxonomy_version", 160)
        if taxonomy_version != "pdc-operation-taxonomy-proposed/v1":
            raise ActionContractError(f"{label}.taxonomy_version is invalid")
        if payload["taxonomy_disposition"] not in {"classified", "review", "unsupported", "conflict"}:
            raise ActionContractError(f"{label}.taxonomy_disposition is invalid")
        expected_disposition = taxonomy_disposition_for_operation(description, work_key, taxonomy_version)
        if payload["taxonomy_disposition"] != expected_disposition:
            raise ActionContractError(f"{label}.taxonomy_disposition conflicts with the versioned taxonomy")
    elif action_type == "booking_set":
        _exact_keys(payload, {"stage_code", "bay_number", "scheduled_start_at", "duration_minutes", "technician_id"}, label)
        _text(payload["stage_code"], f"{label}.stage_code", 40)
        _bounded_int(payload["bay_number"], f"{label}.bay_number", 1)
        _date_time(payload["scheduled_start_at"], f"{label}.scheduled_start_at")
        _bounded_int(payload["duration_minutes"], f"{label}.duration_minutes", 60)
        if payload["technician_id"] is not None:
            _uuid(payload["technician_id"], f"{label}.technician_id")
    elif action_type == "booking_move":
        _exact_keys(payload, {"booking_id", "expected_booking_version", "stage_code", "bay_number", "scheduled_start_at", "duration_minutes", "override_reason"}, label)
        _uuid(payload["booking_id"], f"{label}.booking_id")
        _bounded_int(payload["expected_booking_version"], f"{label}.expected_booking_version", 1)
        _text(payload["stage_code"], f"{label}.stage_code", 40)
        _bounded_int(payload["bay_number"], f"{label}.bay_number", 1)
        _date_time(payload["scheduled_start_at"], f"{label}.scheduled_start_at")
        _bounded_int(payload["duration_minutes"], f"{label}.duration_minutes", 60)
        if payload["override_reason"] is not None:
            _text(payload["override_reason"], f"{label}.override_reason", 400)
    elif action_type == "booking_cancel":
        _exact_keys(payload, {"booking_id", "expected_booking_version", "reason"}, label)
        _uuid(payload["booking_id"], f"{label}.booking_id")
        _bounded_int(payload["expected_booking_version"], f"{label}.expected_booking_version", 1)
        _text(payload["reason"], f"{label}.reason", 400)
    elif action_type == "required_work_set":
        _exact_keys(payload, {"work_key", "required"}, label)
        _text(payload["work_key"], f"{label}.work_key", 32)
        if type(payload["required"]) is not bool:
            raise ActionContractError(f"{label}.required must be boolean")
    elif action_type == "work_complete":
        _exact_keys(payload, {"booking_id", "expected_booking_version", "work_key", "completed_at"}, label)
        _uuid(payload["booking_id"], f"{label}.booking_id")
        _bounded_int(payload["expected_booking_version"], f"{label}.expected_booking_version", 1)
        _text(payload["work_key"], f"{label}.work_key", 32)
        _date_time(payload["completed_at"], f"{label}.completed_at")
    elif action_type == "note_append":
        _exact_keys(payload, {"text", "event_at"}, label)
        _text(payload["text"], f"{label}.text", 2000)
        _date_time(payload["event_at"], f"{label}.event_at")
    elif action_type == "location_set":
        _exact_keys(payload, {"location", "reason"}, label)
        if _text(payload["location"], f"{label}.location", 20).upper() not in {"YH", "PMB", "QC", "RFT", "OTHER", "IT"}:
            raise ActionContractError(f"{label}.location is not controlled")
        _text(payload["reason"], f"{label}.reason", 400)
    else:
        raise ActionContractError(f"unsupported v2 action type {action_type}")


def _validate_authoritative_identity(
    row: Mapping[str, Any], index: int, authoritative_contexts: list[Mapping[str, Any]] | None,
) -> None:
    identity = row["identity"]
    if row["vehicle_id"] is None:
        if row["decision_disposition"] != "review" or row["action_type"] != "note_append":
            raise ActionContractError(f"instructions[{index}].unbound identity is not review-only evidence")
        return
    unresolved = all(identity[key] is None for key in ("stock_number", "vin", "backend_record_id"))
    if unresolved:
        if row["decision_disposition"] != "review" or row["action_type"] != "note_append":
            raise ActionContractError(f"instructions[{index}].identity unresolved evidence shape is invalid")
        return
    if authoritative_contexts is None:
        return
    contexts = {str(item.get("vehicle_id")): item for item in authoritative_contexts if item.get("vehicle_id")}
    authoritative = contexts.get(row["vehicle_id"])
    if authoritative is None:
        raise ActionContractError(f"instructions[{index}] authoritative vehicle context is missing")
    source_identity = authoritative.get("identity") or {}
    expected = {
        "stock_number": authoritative.get("stock_number") or source_identity.get("stock_number"),
        "vin": authoritative.get("vin") or source_identity.get("vin"),
        "backend_record_id": authoritative.get("backend_record_id") or source_identity.get("backend_record_id"),
    }
    for key, supplied in expected.items():
        supplied = identity[key]
        if supplied is None:
            continue
        if expected[key] is None or str(supplied).upper() != str(expected[key]).upper():
            raise ActionContractError(f"instructions[{index}].identity {key} is not authoritative")


def validate_v2_plan(value: Mapping[str, Any], *, authoritative_contexts: list[Mapping[str, Any]] | None = None) -> dict[str, Any]:
    """Validate the planner's canonical v2 plan before any action request."""
    plan = json.loads(json.dumps(dict(value), sort_keys=True, ensure_ascii=False, allow_nan=False))
    _exact_keys(plan, {"schema_version", "plan_id", "environment", "source_receipt_id", "source_digest", "evidence_digest", "source_thread_id", "source_message_id", "attachment_digests", "versions", "instructions", "aggregate_disposition", "planner_status", "planner_failure_reason", "created_at"}, "plan")
    if plan["schema_version"] != "pdc-email-ai-plan-v1" or plan["environment"] != "staging":
        raise ActionContractError("v2 plan schema or environment is invalid")
    _uuid(plan["plan_id"], "plan_id")
    _uuid(plan["source_receipt_id"], "source_receipt_id")
    _digest(plan["source_digest"], "source_digest")
    _digest(plan["evidence_digest"], "evidence_digest")
    _text(plan["source_thread_id"], "source_thread_id", 512)
    _text(plan["source_message_id"], "source_message_id", 1024)
    if not isinstance(plan["attachment_digests"], list) or len(plan["attachment_digests"]) > 25:
        raise ActionContractError("attachment_digests are invalid")
    for digest in plan["attachment_digests"]:
        _digest(digest, "attachment_digest")
    if len(set(plan["attachment_digests"])) != len(plan["attachment_digests"]):
        raise ActionContractError("attachment_digests contain duplicates")
    if plan["aggregate_disposition"] not in {"planned", "applied", "partial_failure", "review", "quarantined", "no_actions"}:
        raise ActionContractError("aggregate_disposition is invalid")
    if plan["planner_status"] not in {"available", "unavailable", "failed"}:
        raise ActionContractError("planner_status is invalid")
    if plan["planner_failure_reason"] is not None:
        _text(plan["planner_failure_reason"], "planner_failure_reason", 1000)
    _date_time(plan["created_at"], "created_at")
    versions = plan["versions"]
    if not isinstance(versions, Mapping):
        raise ActionContractError("v2 plan versions are required")
    _exact_keys(versions, {"transport_release_version", "planner_version", "model_version", "prompt_version", "business_rule_version", "ruleset_version", "taxonomy_version", "supabase_action_contract_version", "source_digest", "evidence_digest"}, "versions")
    for key, item in versions.items():
        _text(item, f"versions.{key}", 160)
    if versions["taxonomy_version"] != "pdc-operation-taxonomy-proposed/v1" or versions["supabase_action_contract_version"] != "pdc-email-ai-action-request-v1":
        raise ActionContractError("v2 plan version identity is invalid")
    if versions["source_digest"] != plan["source_digest"] or versions["evidence_digest"] != plan["evidence_digest"]:
        raise ActionContractError("v2 plan digest identity is inconsistent")
    instructions = plan["instructions"]
    if not isinstance(instructions, list) or len(instructions) > 200:
        raise ActionContractError("v2 instructions are invalid")
    ids: set[str] = set()
    for index, raw in enumerate(instructions, 1):
        row = raw if isinstance(raw, Mapping) else {}
        _exact_keys(row, {"instruction_id", "vehicle_id", "identity", "action_type", "payload", "evidence_refs", "required_evidence", "expected_state", "decision_disposition", "provenance", "audit_event_ref", "reason"}, f"instructions[{index}]")
        instruction_id = _text(row["instruction_id"], f"instructions[{index}].instruction_id", 160)
        if instruction_id in ids:
            raise ActionContractError("v2 instruction IDs must be unique")
        ids.add(instruction_id)
        disposition = row["decision_disposition"]
        if disposition not in {"planned", "review", "unsupported", "conflict"}:
            raise ActionContractError(f"instructions[{index}].decision_disposition is invalid")
        if row["vehicle_id"] is not None:
            _uuid(row["vehicle_id"], f"instructions[{index}].vehicle_id")
        elif disposition != "review" or row["action_type"] != "note_append":
            raise ActionContractError(f"instructions[{index}].unbound identity is not review-only evidence")
        if not isinstance(row["identity"], Mapping) or set(row["identity"]) != {"vehicle_id", "stock_number", "vin", "backend_record_id"}:
            raise ActionContractError(f"instructions[{index}].identity is invalid")
        identity = row["identity"]
        identity_vehicle_id = None if identity["vehicle_id"] is None else _uuid(identity["vehicle_id"], f"instructions[{index}].identity.vehicle_id")
        if identity_vehicle_id != row["vehicle_id"]:
            raise ActionContractError(f"instructions[{index}].identity vehicle mismatch")
        if identity["stock_number"] is None and identity["vin"] is None:
            if row["decision_disposition"] == "planned":
                raise ActionContractError(f"instructions[{index}].identity is unresolved")
        elif identity["stock_number"] is not None and (not isinstance(identity["stock_number"], str) or not identity["stock_number"].strip()):
            raise ActionContractError(f"instructions[{index}].identity stock is invalid")
        if identity["stock_number"] is not None:
            stock = _text(identity["stock_number"], f"instructions[{index}].identity.stock_number", 80).upper()
            if not re.fullmatch(r"[A-Z0-9][A-Z0-9-]{3,79}", stock):
                raise ActionContractError(f"instructions[{index}].identity.stock_number is invalid")
        if identity["vin"] is not None:
            vin = _text(identity["vin"], f"instructions[{index}].identity.vin", 17).upper()
            if not re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", vin):
                raise ActionContractError(f"instructions[{index}].identity.vin is invalid")
        if identity["backend_record_id"] is not None:
            _uuid(identity["backend_record_id"], f"instructions[{index}].identity.backend_record_id")
        _validate_authoritative_identity(row, index, authoritative_contexts)
        expected = row["expected_state"]
        if not isinstance(expected, Mapping) or set(expected) != {"vehicle_version", "backend_revision"}:
            raise ActionContractError(f"instructions[{index}].expected_state is invalid")
        _bounded_int(expected["vehicle_version"], f"instructions[{index}].expected_state.vehicle_version", 1)
        _bounded_int(expected["backend_revision"], f"instructions[{index}].expected_state.backend_revision", 0)
        action = _text(row["action_type"], f"instructions[{index}].action_type", 80)
        if action not in ACTION_TYPES:
            raise ActionContractError(f"instructions[{index}].action_type is not controlled")
        if not isinstance(row["payload"], Mapping):
            raise ActionContractError(f"instructions[{index}].payload is invalid")
        if disposition == "planned" or action in {"operation_add", "operation_update"}:
            _validate_v2_payload(
                action,
                row["payload"],
                f"instructions[{index}].payload",
                allow_unknown_hours=disposition != "planned" and action in {"operation_add", "operation_update"},
            )
        if not isinstance(row["evidence_refs"], list) or not row["evidence_refs"]:
            raise ActionContractError(f"instructions[{index}].evidence_refs is required")
        if not isinstance(row["provenance"], Mapping) or set(row["provenance"]) != {"transport_release_version", "planner_version", "model_version", "prompt_version", "business_rule_version", "ruleset_version", "taxonomy_version", "supabase_action_contract_version", "source_digest", "evidence_digest"}:
            raise ActionContractError(f"instructions[{index}].provenance is invalid")
        for version_key in ("transport_release_version", "planner_version", "model_version", "prompt_version", "business_rule_version", "ruleset_version", "taxonomy_version", "supabase_action_contract_version"):
            _text(row["provenance"].get(version_key), f"instructions[{index}].provenance.{version_key}", 160)
            if row["provenance"][version_key] != versions[version_key]:
                raise ActionContractError(f"instructions[{index}].provenance.{version_key} identity is invalid")
        if row["provenance"].get("source_digest") != plan["source_digest"] or row["provenance"].get("evidence_digest") != plan["evidence_digest"]:
            raise ActionContractError(f"instructions[{index}].provenance digest identity is invalid")
        _digest(row["provenance"]["source_digest"], f"instructions[{index}].provenance.source_digest")
        _digest(row["provenance"]["evidence_digest"], f"instructions[{index}].provenance.evidence_digest")
        _walk_safe(row)
    return plan


def build_action_request(
    *,
    plan_id: str,
    source_receipt_id: str,
    source_digest: str,
    evidence_digest: str,
    instruction: Mapping[str, Any],
    environment: str = "staging",
    runtime_actor: str = "pdc_email_ai_runtime",
) -> dict[str, Any]:
    """Build a closed typed request; never accept a database operation name."""
    if environment != "staging":
        raise ActionContractError("only staging action requests are permitted")
    if runtime_actor != "pdc_email_ai_runtime":
        raise ActionContractError("runtime actor is not the approved v2 actor")
    _uuid(plan_id, "plan_id")
    _uuid(source_receipt_id, "source_receipt_id")
    source_digest = _digest(source_digest, "source_digest")
    evidence_digest = _digest(evidence_digest, "evidence_digest")
    row = dict(instruction)
    action_type = _text(row.get("action_type"), "instruction.action_type", 80)
    if action_type not in ACTION_TYPES:
        raise ActionContractError("instruction action type is not controlled")
    instruction_id = _text(row.get("instruction_id"), "instruction.instruction_id", 160)
    vehicle_id = _uuid(row.get("vehicle_id"), "instruction.vehicle_id")
    payload = row.get("payload")
    if not isinstance(payload, Mapping) or not payload:
        raise ActionContractError("instruction payload is required")
    payload = json.loads(json.dumps(dict(payload), sort_keys=True, ensure_ascii=False, allow_nan=False))
    _walk_safe(payload)
    if row.get("decision_disposition") == "planned" or action_type in {"operation_add", "operation_update"}:
        _validate_v2_payload(action_type, payload, "instruction.payload", allow_unknown_hours=row.get("decision_disposition") != "planned" and action_type in {"operation_add", "operation_update"})
    evidence_refs = row.get("evidence_refs")
    if not isinstance(evidence_refs, list) or not evidence_refs:
        raise ActionContractError("typed evidence references are required")
    refs = []
    for ref in evidence_refs:
        if isinstance(ref, Mapping):
            if set(ref) != {"kind", "ref", "required_for_action"}:
                raise ActionContractError("evidence reference shape is invalid")
            if type(ref["required_for_action"]) is not bool:
                raise ActionContractError("evidence required flag is invalid")
            refs.append({"kind": _text(ref["kind"], "evidence.kind", 40), "ref": _text(ref["ref"], "evidence.ref", 320), "required_for_action": ref["required_for_action"]})
        else:
            refs.append(_text(ref, "evidence.ref", 320))
    expected = row.get("expected_state")
    if not isinstance(expected, Mapping) or set(expected) != {"vehicle_version", "backend_revision"}:
        raise ActionContractError("expected authoritative state is required")
    if isinstance(expected["vehicle_version"], bool) or not isinstance(expected["vehicle_version"], int) or expected["vehicle_version"] < 1 or isinstance(expected["backend_revision"], bool) or not isinstance(expected["backend_revision"], int) or expected["backend_revision"] < 0:
        raise ActionContractError("expected state versions are invalid")
    provenance = row.get("provenance")
    if not isinstance(provenance, Mapping):
        raise ActionContractError("provenance is required")
    provenance = json.loads(json.dumps(dict(provenance), sort_keys=True, ensure_ascii=False, allow_nan=False))
    _walk_safe(provenance, "provenance")
    material = {"plan_id": plan_id, "source_digest": source_digest, "instruction_id": instruction_id, "vehicle_id": vehicle_id, "action_type": action_type, "payload": payload}
    action_key = hashlib.sha256(json.dumps(material, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()
    return {
        "schema_version": "pdc-email-ai-action-request-v1",
        "request_id": str(uuid.uuid5(uuid.NAMESPACE_URL, "pdc-v2-request:" + action_key)),
        "environment": "staging",
        "runtime_actor": runtime_actor,
        "plan_id": plan_id,
        "source_receipt_id": source_receipt_id,
        "source_digest": source_digest,
        "evidence_digest": evidence_digest,
        "instruction_id": instruction_id,
        "vehicle_id": vehicle_id,
        "expected_vehicle_version": expected["vehicle_version"],
        "action_type": action_type,
        "payload": payload,
        "action_key": action_key,
        "provenance": provenance,
        "evidence_refs": refs,
        "requested_at": "2026-09-01T00:00:00+00:00",
    }


class ShadowActionClient:
    """Validate-and-record action requests without an operational write."""

    def __init__(self) -> None:
        self.requests: list[dict[str, Any]] = []

    def submit(self, request: Mapping[str, Any]) -> dict[str, Any]:
        row = dict(request)
        if row.get("environment") != "staging" or row.get("runtime_actor") != "pdc_email_ai_runtime":
            raise ActionContractError("shadow client refuses non-v2 request")
        _walk_safe(row)
        self.requests.append(json.loads(json.dumps(row, sort_keys=True, ensure_ascii=False)))
        return {"request_id": row["request_id"], "action_key": row["action_key"], "instruction_id": row["instruction_id"], "disposition": "planned", "operational_write_attempted": False, "readback_required": True}


__all__ = ["ActionContractError", "ShadowActionClient", "build_action_request", "validate_v2_plan"]
