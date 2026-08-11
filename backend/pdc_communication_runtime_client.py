#!/usr/bin/env python
"""Fail-closed two-authority runtime client for PMB communication actions."""
from __future__ import annotations

import hashlib
import re
from datetime import date
from typing import Any, Mapping

try:
    from backend.pdc_email_communication_parser import ACCESSORY_ALIASES, MAX_ACTIONS, MAX_EVIDENCE_CHARS
    from backend.pdc_jobcard_runtime_client import (
        ATTEST_RPC, SUCCESS_ATTEST_CODES, RpcClient, RuntimeContractError,
        _attestation_success, _authentication, _exact_keys, _failure, _hex64, _object, _provider,
        _success_envelope, _text, _uuid, _validate_authority_clients,
    )
except ModuleNotFoundError:
    from pdc_email_communication_parser import ACCESSORY_ALIASES, MAX_ACTIONS, MAX_EVIDENCE_CHARS
    from pdc_jobcard_runtime_client import (
        ATTEST_RPC, SUCCESS_ATTEST_CODES, RpcClient, RuntimeContractError,
        _attestation_success, _authentication, _exact_keys, _failure, _hex64, _object, _provider,
        _success_envelope, _text, _uuid, _validate_authority_clients,
    )

PROCESS_COMMUNICATION_RPC = "process_pdc_email_communication"
SUCCESS_COMMUNICATION_CODES = {"communication_receipt"}
_ALLOWED_ACTIONS = {"parts_complete", "set_sublet_booking_date", "add_accessory_work"}
_APPROVED_ACCESSORIES = set(ACCESSORY_ALIASES.values())


def _identity(value: Any) -> dict[str, list[str]]:
    identity = _object(value, "identity")
    _exact_keys(identity, {"job_card_numbers", "stock_numbers", "vins"}, "identity")
    limits = {"job_card_numbers": 80, "stock_numbers": 80, "vins": 17}
    populated = 0
    for key, maximum in limits.items():
        rows = identity[key]
        if not isinstance(rows, list) or len(rows) > 1:
            raise RuntimeContractError(f"identity.{key} must contain at most one value")
        if rows:
            item = _text(rows[0], f"identity.{key}[0]", 1, maximum)
            if key == "vins" and (len(item) != 17 or any(character in "IOQ" or not character.isalnum() or not character.isupper() for character in item)):
                raise RuntimeContractError("identity VIN is invalid")
            if key == "stock_numbers" and re.fullmatch(r"[A-Z0-9][A-Z0-9-]{3,23}", item) is None:
                raise RuntimeContractError("identity stock number is invalid")
            if key == "job_card_numbers" and re.fullmatch(r"[A-Z0-9][A-Z0-9-]{3,31}", item) is None:
                raise RuntimeContractError("identity job card number is invalid")
            populated += 1
    if populated != 1:
        raise RuntimeContractError("exactly one vehicle identity category is required")
    return identity


def _evidence(value: Any) -> str:
    return _text(value, "action evidence", 3, MAX_EVIDENCE_CHARS)


def _actions(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not 1 <= len(value) <= MAX_ACTIONS:
        raise RuntimeContractError("actions must contain 1 to 20 rows")
    for index, action_value in enumerate(value, 1):
        action = _object(action_value, f"actions[{index}]")
        if action.get("source_action_no") != index or isinstance(action.get("source_action_no"), bool) or action.get("action_type") not in _ALLOWED_ACTIONS:
            raise RuntimeContractError("actions are not canonical or ordered")
        action_type = action["action_type"]
        if action_type == "parts_complete":
            _exact_keys(action, {"source_action_no", "action_type", "evidence"}, "parts action")
        elif action_type == "set_sublet_booking_date":
            _exact_keys(action, {"source_action_no", "action_type", "booking_date", "evidence"}, "sublet action")
            booking_date = _text(action["booking_date"], "booking_date", 10, 10)
            try:
                parsed = date.fromisoformat(booking_date)
            except ValueError as exc:
                raise RuntimeContractError("booking_date is not a valid ISO date") from exc
            if parsed.year < 2000 or parsed.year > 2099:
                raise RuntimeContractError("booking_date is outside the supported range")
        else:
            _exact_keys(action, {"source_action_no", "action_type", "description", "work_key", "evidence"}, "accessory action")
            description = _text(action["description"], "accessory description", 3, 120)
            work_key = _text(action["work_key"], "accessory work_key", 1, 32)
            if (description, work_key) not in _APPROVED_ACCESSORIES:
                raise RuntimeContractError("accessory description/work_key pair is not approved")
        _evidence(action["evidence"])
    return value


def validate_communication_request(request: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(request, Mapping):
        raise RuntimeContractError("request must be an object")
    _exact_keys(request, {"intake_id", "expected_source_hash", "extraction_hash", "provider", "extraction"}, "request")
    extraction = _object(request["extraction"], "extraction")
    _exact_keys(extraction, {
        "actions", "authentication", "auto_applicable", "canonical_attachment_id",
        "canonical_document_hash", "contract_version", "identity", "review_reasons",
    }, "extraction")
    if extraction["contract_version"] != "pmb-email-communications-v1":
        raise RuntimeContractError("communication contract_version is invalid")
    if extraction["auto_applicable"] is not True or extraction["review_reasons"] != []:
        raise RuntimeContractError("review-only communication cannot be auto-applied")
    provider = _provider(request["provider"], extraction)
    _authentication(extraction["authentication"])
    _identity(extraction["identity"])
    _actions(extraction["actions"])
    return {
        "intake_id": _uuid(request["intake_id"], "intake_id"),
        "source_hash": _hex64(request["expected_source_hash"], "expected_source_hash"),
        "extraction_hash": _hex64(request["extraction_hash"], "extraction_hash"),
        "attachment_hash": _hex64(extraction["canonical_document_hash"], "canonical_document_hash"),
        "provider": provider, "extraction": extraction,
    }


def _communication_readback(data: dict[str, Any], checked: dict[str, Any]) -> dict[str, Any]:
    expected_actions = checked["extraction"]["actions"]
    required = {"receipt_id", "intake_id", "attachment_id", "vehicle_id", "action_count", "actions", "booking_created", "location_changed"}
    if set(data) != required:
        raise RuntimeContractError("communication readback keys are invalid")
    receipt_id = _uuid(data["receipt_id"], "readback receipt_id")
    vehicle_id = _uuid(data["vehicle_id"], "readback vehicle_id")
    if _uuid(data["intake_id"], "readback intake_id") != checked["intake_id"]:
        raise RuntimeContractError("communication readback intake_id differs from request")
    if _uuid(data["attachment_id"], "readback attachment_id") != checked["provider"]["attachment_id"]:
        raise RuntimeContractError("communication readback attachment_id differs from request")
    if data["booking_created"] is not False or data["location_changed"] is not False:
        raise RuntimeContractError("communication readback violates no-booking/location invariant")
    actions = data["actions"]
    count = data["action_count"]
    if isinstance(count, bool) or not isinstance(count, int) or count != len(expected_actions) or not isinstance(actions, list) or len(actions) != len(expected_actions):
        raise RuntimeContractError("communication readback action count is invalid")
    for expected, observed_value in zip(expected_actions, actions):
        observed = _object(observed_value, "communication readback action")
        _exact_keys(observed, {"source_action_no", "action_type", "evidence", "retained_clause", "retained_clause_sha256", "requested_action", "before_data", "after_data"}, "communication readback action")
        retained_clause = re.sub(r"\s+", " ", expected["evidence"]).strip(" .,;:-").lower()
        retained_hash = hashlib.sha256(retained_clause.encode("utf-8")).hexdigest()
        if (isinstance(observed["source_action_no"], bool)
                or not isinstance(observed["source_action_no"], int)
                or observed["source_action_no"] != expected["source_action_no"]
                or observed["action_type"] != expected["action_type"]
                or observed["evidence"] != expected["evidence"]
                or observed["requested_action"] != expected
                or observed["retained_clause"] != retained_clause
                or observed["retained_clause_sha256"] != retained_hash):
            raise RuntimeContractError("communication readback action differs from request")
        if observed["before_data"] is not None and not isinstance(observed["before_data"], dict):
            raise RuntimeContractError("communication readback before_data is invalid")
        if not isinstance(observed["after_data"], dict):
            raise RuntimeContractError("communication readback after_data is invalid")
    return {"receipt_id": receipt_id, "vehicle_id": vehicle_id, "action_count": len(actions)}


def execute_communication_request(service_client: RpcClient, actor_client: RpcClient, request: Mapping[str, Any]) -> dict[str, Any]:
    _validate_authority_clients(service_client, actor_client)
    checked = validate_communication_request(request)
    provider = checked["provider"]
    attested = service_client.rpc(ATTEST_RPC, {
        "p_intake_id": checked["intake_id"], "p_attachment_id": provider["attachment_id"],
        "p_expected_parent_hash": checked["source_hash"], "p_expected_attachment_hash": checked["attachment_hash"],
        "p_provider_message_id": provider["provider_message_id"], "p_provider_authserv_id": provider["provider_authserv_id"],
        "p_authentication": provider["authentication"],
    })
    if not isinstance(attested, dict) or attested.get("ok") is not True:
        return _failure(attested, "provider_attestation", "attestation_failed")
    _attestation_success(attested)
    processed = actor_client.rpc(PROCESS_COMMUNICATION_RPC, {
        "p_intake_id": checked["intake_id"], "p_expected_source_hash": checked["source_hash"],
        "p_extraction_hash": checked["extraction_hash"], "p_extraction": checked["extraction"], "p_actor": "pdc-monitor",
    })
    if not isinstance(processed, dict) or processed.get("ok") is not True:
        return _failure(processed, "operational_processing", "processing_failed")
    code, data = _success_envelope(processed, SUCCESS_COMMUNICATION_CODES, "communication processing")
    readback = _communication_readback(data, checked)
    return {"ok": True, "phase": "complete", "code": code, **readback}


__all__ = ["PROCESS_COMMUNICATION_RPC", "SUCCESS_COMMUNICATION_CODES", "validate_communication_request", "execute_communication_request"]
