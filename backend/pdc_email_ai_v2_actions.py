"""Least-authority typed action requests for the v2 runtime.

The shadow client is intentionally the only enabled client in this package. It
validates a request and records the proposed action without calling Supabase or
mutating an operational store. A later controlled client must implement this
same request shape behind an independent gate.
"""
from __future__ import annotations

import hashlib
import json
import uuid
from typing import Any, Mapping

from .pdc_email_ai_successor_contract import ACTION_TYPES


class ActionContractError(ValueError):
    """A request is outside the closed, staging-only action contract."""


_FORBIDDEN = {"sql", "table", "tables", "query", "rpc", "function", "dml", "service_role", "administrator", "admin", "production"}


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
    value = _text(value, label, 64).lower()
    if len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value):
        raise ActionContractError(f"{label} must be a SHA-256 digest")
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
    evidence_refs = row.get("evidence_refs")
    if not isinstance(evidence_refs, list) or not evidence_refs:
        raise ActionContractError("typed evidence references are required")
    refs = []
    for ref in evidence_refs:
        if not isinstance(ref, Mapping):
            raise ActionContractError("evidence references must be typed objects")
        if set(ref) != {"kind", "ref", "required_for_action"}:
            raise ActionContractError("evidence reference shape is invalid")
        refs.append({"kind": _text(ref["kind"], "evidence.kind", 40), "ref": _text(ref["ref"], "evidence.ref", 320), "required_for_action": type(ref["required_for_action"]) is bool and ref["required_for_action"]})
        if type(ref["required_for_action"]) is not bool:
            raise ActionContractError("evidence required flag is invalid")
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


__all__ = ["ActionContractError", "ShadowActionClient", "build_action_request"]
