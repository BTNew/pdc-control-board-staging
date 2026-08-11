#!/usr/bin/env python
"""Fail-closed dispatcher for one profile-owned retained PMB intake item."""
from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping

try:
    from backend.pdc_email_communication_parser import parse_communication_actions
    from backend.pdc_communication_runtime_client import execute_communication_request
    from backend.pdc_jobcard_runtime_client import RpcClient, RuntimeContractError, execute_jobcard_request
except ModuleNotFoundError:
    from pdc_email_communication_parser import parse_communication_actions
    from pdc_communication_runtime_client import execute_communication_request
    from pdc_jobcard_runtime_client import RpcClient, RuntimeContractError, execute_jobcard_request

_PROVIDER_KEYS = {"attachment_id", "attachment_source_hash", "provider_message_id", "provider_authserv_id", "authentication"}


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise RuntimeContractError(f"{label} must be an object")
    return dict(value)


def _hash(value: Any) -> str:
    try:
        encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise RuntimeContractError("extraction is not canonical JSON") from exc
    return hashlib.sha256(encoded).hexdigest()


def execute_retained_intake(service_client: RpcClient, actor_client: RpcClient, item: Mapping[str, Any]) -> dict[str, Any]:
    request = _mapping(item, "intake item")
    common = {"intake_id", "expected_source_hash", "provider", "kind"}
    provider = _mapping(request.get("provider"), "provider")
    if set(provider) != _PROVIDER_KEYS:
        raise RuntimeContractError("retained provider keys are invalid")
    runtime_provider = {key: value for key, value in provider.items() if key != "attachment_source_hash"}

    if request.get("kind") == "jobcard":
        if set(request) != common | {"extraction"}:
            raise RuntimeContractError("jobcard intake keys are invalid")
        extraction = _mapping(request["extraction"], "jobcard extraction")
        return execute_jobcard_request(service_client, actor_client, {
            "intake_id": request["intake_id"], "expected_source_hash": request["expected_source_hash"],
            "extraction_hash": _hash(extraction), "provider": runtime_provider, "extraction": extraction,
        })

    if request.get("kind") != "communication" or set(request) != common | {"retained_text"}:
        raise RuntimeContractError("intake kind or keys are invalid")
    retained_text = request["retained_text"]
    if not isinstance(retained_text, str):
        raise RuntimeContractError("retained_text must be a string")
    parsed = parse_communication_actions(retained_text)
    if parsed.get("auto_applicable") is not True:
        return {
            "ok": False, "phase": "review_required", "code": "communication_review_required",
            "review_reasons": parsed.get("review_reasons", []), "mutation_attempted": False, "message_sent": False,
        }
    extraction = {
        **parsed, "authentication": provider.get("authentication"),
        "canonical_attachment_id": provider.get("attachment_id"),
        "canonical_document_hash": provider.get("attachment_source_hash"),
        "contract_version": "pmb-email-communications-v1",
    }
    return execute_communication_request(service_client, actor_client, {
        "intake_id": request["intake_id"], "expected_source_hash": request["expected_source_hash"],
        "extraction_hash": _hash(extraction), "provider": runtime_provider, "extraction": extraction,
    })


__all__ = ["execute_retained_intake"]
