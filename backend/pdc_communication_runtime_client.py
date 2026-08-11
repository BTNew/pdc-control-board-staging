#!/usr/bin/env python
"""Two-authority runtime client for retained PMB communication actions."""
from __future__ import annotations

from typing import Any, Mapping

try:
    from backend.pdc_jobcard_runtime_client import (
        ATTEST_RPC,
        SUCCESS_ATTEST_CODES,
        RpcClient,
        RuntimeContractError,
        _exact_keys,
        _hex64,
        _object,
    )
except ModuleNotFoundError:
    from pdc_jobcard_runtime_client import (
        ATTEST_RPC,
        SUCCESS_ATTEST_CODES,
        RpcClient,
        RuntimeContractError,
        _exact_keys,
        _hex64,
        _object,
    )

PROCESS_COMMUNICATION_RPC = "process_pdc_email_communication"
_ALLOWED_ACTIONS = {"parts_complete", "set_sublet_booking_date", "add_accessory_work"}
_ALLOWED_WORK = {"fitting", "fabrication", "electrical", "tyre"}


def validate_communication_request(request: Mapping[str, Any]) -> dict[str, Any]:
    _exact_keys(request, {"intake_id", "expected_source_hash", "extraction_hash", "provider", "extraction"}, "request")
    provider = _object(request["provider"], "provider")
    extraction = _object(request["extraction"], "extraction")
    _exact_keys(provider, {"attachment_id", "provider_message_id", "provider_authserv_id", "authentication"}, "provider")
    _exact_keys(extraction, {
        "actions", "authentication", "auto_applicable", "canonical_attachment_id",
        "canonical_document_hash", "contract_version", "identity", "review_reasons",
    }, "extraction")
    if extraction.get("contract_version") != "pmb-email-communications-v1":
        raise RuntimeContractError("communication contract_version is invalid")
    if extraction.get("auto_applicable") is not True or extraction.get("review_reasons") != []:
        raise RuntimeContractError("review-only communication cannot be auto-applied")
    if str(provider.get("attachment_id") or "") != str(extraction.get("canonical_attachment_id") or ""):
        raise RuntimeContractError("provider and extraction attachment identities differ")
    if provider.get("authentication") != extraction.get("authentication"):
        raise RuntimeContractError("provider and extraction authentication evidence differ")
    if provider.get("provider_authserv_id") != "mx.google.com":
        raise RuntimeContractError("provider_authserv_id must be mx.google.com")
    actions = extraction.get("actions")
    if not isinstance(actions, list) or not 1 <= len(actions) <= 20:
        raise RuntimeContractError("actions must contain 1 to 20 rows")
    for index, action in enumerate(actions, 1):
        if not isinstance(action, dict) or action.get("source_action_no") != index or action.get("action_type") not in _ALLOWED_ACTIONS:
            raise RuntimeContractError("actions are not canonical or ordered")
        if action["action_type"] == "parts_complete":
            _exact_keys(action, {"source_action_no", "action_type", "evidence"}, "parts action")
        elif action["action_type"] == "set_sublet_booking_date":
            _exact_keys(action, {"source_action_no", "action_type", "booking_date", "evidence"}, "sublet action")
        else:
            _exact_keys(action, {"source_action_no", "action_type", "description", "work_key", "evidence"}, "accessory action")
            if action.get("work_key") not in _ALLOWED_WORK:
                raise RuntimeContractError("accessory work_key is not approved")
    identity = _object(extraction.get("identity"), "identity")
    _exact_keys(identity, {"job_card_numbers", "stock_numbers", "vins"}, "identity")
    if sum(len(identity.get(key) or []) for key in identity) < 1:
        raise RuntimeContractError("one vehicle identity is required")
    return {
        "intake_id": str(request.get("intake_id") or ""),
        "source_hash": _hex64(request.get("expected_source_hash"), "expected_source_hash"),
        "extraction_hash": _hex64(request.get("extraction_hash"), "extraction_hash"),
        "attachment_hash": _hex64(extraction.get("canonical_document_hash"), "canonical_document_hash"),
        "provider": provider,
        "extraction": extraction,
    }


def execute_communication_request(service_client: RpcClient, actor_client: RpcClient, request: Mapping[str, Any]) -> dict[str, Any]:
    if service_client.authority != "service_role" or actor_client.authority != "authenticated_monitor":
        raise RuntimeContractError("client authorities are not separated")
    if service_client.bearer == actor_client.bearer:
        raise RuntimeContractError("service-role and monitor actor credentials must differ")
    checked = validate_communication_request(request)
    provider = checked["provider"]
    attested = service_client.rpc(ATTEST_RPC, {
        "p_intake_id": checked["intake_id"],
        "p_attachment_id": provider["attachment_id"],
        "p_expected_parent_hash": checked["source_hash"],
        "p_expected_attachment_hash": checked["attachment_hash"],
        "p_provider_message_id": provider["provider_message_id"],
        "p_provider_authserv_id": provider["provider_authserv_id"],
        "p_authentication": provider["authentication"],
    })
    if attested.get("ok") is not True or attested.get("code") not in SUCCESS_ATTEST_CODES:
        return {"ok": False, "phase": "provider_attestation", "code": str(attested.get("code") or "attestation_failed")}
    processed = actor_client.rpc(PROCESS_COMMUNICATION_RPC, {
        "p_intake_id": checked["intake_id"],
        "p_expected_source_hash": checked["source_hash"],
        "p_extraction_hash": checked["extraction_hash"],
        "p_extraction": checked["extraction"],
        "p_actor": "pdc-monitor",
    })
    if processed.get("ok") is not True:
        return {"ok": False, "phase": "operational_processing", "code": str(processed.get("code") or "processing_failed")}
    data = processed.get("data") if isinstance(processed.get("data"), dict) else {}
    return {"ok": True, "phase": "complete", "code": processed.get("code"), "receipt_id": data.get("receipt_id"), "vehicle_id": data.get("vehicle_id"), "action_count": data.get("action_count")}


__all__ = ["PROCESS_COMMUNICATION_RPC", "validate_communication_request", "execute_communication_request"]
