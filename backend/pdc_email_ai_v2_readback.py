"""Pure authoritative readback validator and Board/AI projection builder."""
from __future__ import annotations

import copy
import hashlib
import json
import uuid
from typing import Any, Mapping

from .pdc_email_ai_v2_actions import ActionContractError


_REQUIRED = {"vehicle_id", "stock_number", "vin", "backend_record_id", "vehicle_version", "backend_revision", "location", "operations", "required_work", "parts", "bookings", "lifecycle"}


def _uuid(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise ActionContractError(f"{label} is invalid")
    try:
        parsed = uuid.UUID(value)
    except ValueError as exc:
        raise ActionContractError(f"{label} is invalid") from exc
    if str(parsed) != value.lower():
        raise ActionContractError(f"{label} is not canonical")
    return value.lower()


def _json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def _digest(value: Mapping[str, Any]) -> str:
    return hashlib.sha256(_json(value).encode("utf-8")).hexdigest()


def project_readback(state: Mapping[str, Any], *, source_revision: int, readback_receipt_id: str | None = None) -> dict[str, Any]:
    """Project only authoritative state fields into the v2 readback shape."""
    row = dict(state)
    if set(_REQUIRED) - set(row):
        raise ActionContractError("authoritative state is incomplete")
    vehicle_id = _uuid(row["vehicle_id"], "vehicle_id")
    if isinstance(source_revision, bool) or not isinstance(source_revision, int) or source_revision < 0:
        raise ActionContractError("source_revision is invalid")
    version = row["vehicle_version"]
    backend_revision = row["backend_revision"]
    if isinstance(version, bool) or not isinstance(version, int) or version < 1:
        raise ActionContractError("vehicle_version is invalid")
    if isinstance(backend_revision, bool) or not isinstance(backend_revision, int) or backend_revision < 0:
        raise ActionContractError("backend_revision is invalid")
    body = {
        "schema_version": "pdc-email-ai-readback-v1",
        "environment": "staging",
        "readback_receipt_id": readback_receipt_id or str(uuid.uuid5(uuid.NAMESPACE_URL, f"pdc-v2-readback:{vehicle_id}:{source_revision}")),
        "vehicle_id": vehicle_id,
        "vehicle_version": version,
        "source_revision": source_revision,
        "identity": {key: row[key] for key in ("vehicle_id", "stock_number", "vin", "backend_record_id")},
        "location": {"code": str(row["location"]).upper(), "source": "authoritative"},
        "required_work": copy.deepcopy(row["required_work"]),
        "operations": copy.deepcopy(row["operations"]),
        "parts": copy.deepcopy(row["parts"]),
        "bookings": copy.deepcopy(row["bookings"]),
        "lifecycle": copy.deepcopy(row["lifecycle"]),
        "read_at": "2026-09-01T00:00:00+00:00",
    }
    if body["location"]["code"] not in {"YH", "PMB", "QC", "RFT", "OTHER", "IT"}:
        raise ActionContractError("authoritative location is not controlled")
    body["projection_digest"] = _digest(body)
    return body


def validate_readback(readback: Mapping[str, Any]) -> dict[str, Any]:
    """Fail closed on environment, identity or projection-digest mismatch."""
    row = copy.deepcopy(dict(readback))
    if row.get("environment") != "staging":
        raise ActionContractError("readback is not staging-bound")
    if row.get("schema_version") != "pdc-email-ai-readback-v1":
        raise ActionContractError("readback schema version is invalid")
    expected = row.pop("projection_digest", None)
    if not isinstance(expected, str) or len(expected) != 64 or any(ch not in "0123456789abcdef" for ch in expected):
        raise ActionContractError("readback projection digest is invalid")
    actual = _digest(row)
    if actual != expected:
        raise ActionContractError("readback projection digest mismatch")
    _uuid(row.get("readback_receipt_id"), "readback_receipt_id")
    _uuid(row.get("vehicle_id"), "vehicle_id")
    if row.get("identity", {}).get("vehicle_id") != row.get("vehicle_id"):
        raise ActionContractError("readback identity vehicle mismatch")
    return {**row, "projection_digest": expected}


__all__ = ["project_readback", "validate_readback"]
