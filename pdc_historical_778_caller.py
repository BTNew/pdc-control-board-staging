#!/usr/bin/env python3
"""Sanitized caller for the exact frozen 773-derived 777 staging contract.

The ordinary pdc-emails worker may import this module, but must invoke it only
with a pre-frozen, locally resolved row. It never reads the mailbox, changes
flags, invents database UUIDs, or selects the normal/global pilot path. The
server-owned RPC creates/reuses the intake and derives attachment IDs by hash.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Callable, Mapping

MANIFEST_SHA256 = "aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018"
MANIFEST_UIDVALIDITY = 1
MANIFEST_HIGH_WATER_UID = 685
MANIFEST_UID_COUNT = 669
EXCLUDED_PROVIDER_UID = "1:197"
EXCLUDED_STOCK = "13056899"
AUTHORIZED_PROVIDER_UIDS = frozenset({
    "1:21", "1:22", "1:23", "1:26", "1:40", "1:57", "1:85", "1:93",
    "1:95", "1:96", "1:133", "1:134", "1:137", "1:168", "1:172",
})
PROPOSAL_REVIEW_CODES = frozenset({
    "historical_proposal_tuple_conflict",
    "historical_proposal_terminal_conflict",
    "historical_proposal_payload_conflict",
    "historical_proposal_observation_review_required",
})
EXPECTED_SUCCESS_CODE = "historical_reconciliation_782_receipt"
SUCCESS_RESPONSE_KEYS = frozenset({"ok", "code", "data"})
SUCCESS_DATA_KEYS = frozenset({
    "receipt_id", "contract_version", "manifest_sha256", "provider_uid", "parent_source_hash",
    "sender_email", "stock_number", "intake_id", "attachment_count", "proposal_id",
    "proposal_binding_kind", "proposal_observation_match", "job_card_count", "sibling_count",
    "attachment_receipts", "parent_observation", "authoritative_state", "booking_created",
    "completion_created", "location_scheduled", "parts_changed", "status_changed", "no_booking",
    "no_completion", "no_location_mutation",
})
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
PARENT_RESPONSE_KEYS = frozenset({"ok", "code", "data"})
PARENT_DATA_KEYS = frozenset({"proposal_id", "status", "version", "fingerprint"})
CHILD_RESPONSE_KEYS = frozenset({"ok", "code", "data"})
CHILD_DATA_KEYS = frozenset({
    "receipt_id", "intake_id", "attachment_id", "parent_source_hash", "canonical_source_hash",
    "attachment_source_hash", "attachment_size_bytes", "attachment_content_type", "source_uid",
    "proposal_id", "canonical_import_receipt_id", "vehicle_id", "vehicle_version", "backend_record_id",
    "backend_record_version", "job_card_number", "requested_payload_sha256", "operation_sha256",
    "operation_count", "estimated_hours_sum", "canonical_operation_line_ids", "operation_lines",
    "rule_applications", "canonical_import_response", "booking_created", "completion_created",
    "location_scheduled",
})
NESTED_RESPONSE_KEYS = frozenset({"ok", "code", "data"})
NESTED_OBSERVATION_BASE_KEYS = frozenset({"proposal_id", "status", "version", "fingerprint"})
NESTED_AUTO_DATA_KEYS = {
    "proposal_consumed": frozenset({"proposal_id", "status", "version"}),
    "uid514_exact_existing_identity_accepted": frozenset({
        "proposal_id", "stock_number", "vehicle_id", "vehicle_mutated", "board_activation_only",
        "reinstatement_receipt_required", "historical_job_card_preserved", "incoming_job_card",
    }),
    "automatically_closed_existing": frozenset({
        "proposal_id", "stock_number", "vehicle_id", "vehicle_mutated", "board_activation_only",
        "authority_refreshed", "proposal_backend_record_version", "current_backend_record_version",
        "authorization_basis", "board_purge_reactivation",
    }),
    "automatically_closed_duplicate": frozenset({
        "proposal_id", "stock_number", "vehicle_id", "vehicle_mutated", "board_activation_only",
        "primary_proposal_id",
    }),
    "automatically_applied": frozenset({
        "proposal_id", "stock_number", "backend_record_id", "vehicle_id", "navision_revision",
        "vehicle_mutated", "authority_refreshed", "proposal_backend_record_version",
        "current_backend_record_version", "board_activation_only", "booking_created", "work_mutated",
        "parts_mutated", "authorization_basis", "board_purge_reactivation",
    }),
}
VEHICLE_IMPORT_DATA_KEYS = frozenset({
    "vehicle_id", "backend_record_id", "stock_number", "job_card_number", "required_work",
    "identity_source", "booking_created", "completed_work_reopened",
})
OPERATION_IMPORT_DATA_KEYS = frozenset({
    "vehicle_id", "source_hash", "operation_lines_received", "operation_lines_added",
    "estimated_hours_added", "job_card_hours_corrected", "required_work_added", "resulting_revision",
    "booking_created", "completed_work_reopened",
})
PROTECTED_ACTIVE_LOCATIONS = frozenset({"YH", "PMB", "QC", "Other"})

ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
ACTOR_EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
RELEASE_NAME = "pdc-monitor-staging-m502-2026.08.44"
RELEASE_SOURCE_SHA = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
RELEASE_MANIFEST_SHA256 = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
CANONICAL_CONTRACT_VERSION = "788.1"
RPC_NAME = "submit_pdc_historical_reconciliation_778"
STAGING_HOST = "cdsmnqxtyyoeoznmbidd.supabase.co"


class Historical777Error(RuntimeError):
    """Sanitized bounded-run failure."""


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _length_prefixed_sha256(values: list[str]) -> str:
    payload = b"".join(len(value.encode("utf-8")).to_bytes(4, "big") + value.encode("utf-8") for value in values)
    return _sha256(payload)


def _canonical_field(name: str, value: Any) -> bytes:
    """Length-prefixed UTF-8 field encoding; None is distinct from empty."""
    name_bytes = name.encode("utf-8")
    if value is None:
        value_bytes = b"-1:"
    else:
        value_bytes = str(value).encode("utf-8")
        value_bytes = str(len(value_bytes)).encode("ascii") + b":" + value_bytes
    return str(len(name_bytes)).encode("ascii") + b":" + name_bytes + b"=" + value_bytes


def _postgres_jsonb_text(value: Any) -> str:
    """Mirror PostgreSQL jsonb::text ordering/spacing without locale changes."""
    def ordered(item: Any) -> Any:
        if isinstance(item, dict):
            return {key: ordered(item[key]) for key in sorted(item, key=lambda key: (len(key.encode("utf-8")), key.encode("utf-8")))}
        if isinstance(item, list):
            return [ordered(child) for child in item]
        return item
    return json.dumps(ordered(value), ensure_ascii=False, separators=(", ", ": "))


def canonical_request_bytes(request: Mapping[str, Any]) -> bytes:
    """Build the fixed-order 788 request binding shared with the SQL contract."""
    source = request["source_metadata"]
    auth = request["authentication"]
    parts: list[bytes] = []
    scalar_fields = [
        ("contract_version", CANONICAL_CONTRACT_VERSION),
        ("manifest_sha256", request["manifest_sha256"]),
        ("manifest_uidvalidity", request["manifest_uidvalidity"]),
        ("manifest_high_water_uid", request["manifest_high_water_uid"]),
        ("manifest_uid_count", request["manifest_uid_count"]),
        ("actor_id", ACTOR_ID), ("actor_email", ACTOR_EMAIL),
        ("gateway_instance_id", request["gateway_instance_id"]),
        ("release_name", request["release_name"]),
        ("release_source_sha", request["release_source_sha"]),
        ("release_manifest_sha256", request["release_manifest_sha256"]),
        ("runtime_activation_ready", "true"),
        ("runtime_writer_active", "true"),
        ("runtime_task_enabled", "false"),
        ("runtime_mailbox_contacted", "false"),
        ("runtime_production_writes", "false"),
        ("provider_uid", request["provider_uid"]),
        ("parent_source_hash", request["parent_source_hash"]),
        ("sender_email", request["sender_email"]),
        ("stock_number", request["stock_number"]),
        ("action_type", request["action_type"]),
        ("evidence_hash", request["evidence_hash"]),
        ("subject", request["subject"]), ("summary", request["summary"]),
        ("observations_jsonb", _postgres_jsonb_text(request["observations"])),
    ]
    for name, value in scalar_fields:
        parts.append(_canonical_field(name, value))
    for name in ("dkim_aligned", "dmarc_aligned", "gmail_authentication_results", "sender_domain", "spf_aligned"):
        value = auth.get(name)
        parts.append(_canonical_field(f"authentication.{name}", "true" if value is True else "false" if value is False else value))
    for name in ("attachment_names", "graph_message_id", "internet_message_id", "parsed_text", "provider_authserv_id", "raw_body", "received_at", "recipient_mailbox", "sender_name", "uid", "uidvalidity"):
        value = source.get(name)
        if name == "attachment_names":
            for index, item in enumerate(value, 1):
                parts.append(_canonical_field(f"source.attachment_names[{index}]", item))
        else:
            parts.append(_canonical_field(f"source.{name}", value))
    for index, item in enumerate(request["attachment_manifest"], 1):
        for name in ("attachment_kind", "content_type", "filename", "ordinal", "sha256", "size"):
            parts.append(_canonical_field(f"attachment[{index}].{name}", item[name]))
    for index, child in enumerate(request["job_card_children"], 1):
        for name in ("attachment_hash", "attachment_kind", "attachment_ordinal", "extraction_hash"):
            parts.append(_canonical_field(f"child[{index}].{name}", child[name]))
        parts.append(_canonical_field(f"child[{index}].extraction_jsonb", _postgres_jsonb_text(child["extraction"])))
    return b"".join(parts)


def canonical_request_digest(request: Mapping[str, Any]) -> str:
    return _sha256(canonical_request_bytes(request))


def _validate_nested_canonical_response(response: Mapping[str, Any], stage: str,
                                       child_data: Mapping[str, Any], request: Mapping[str, Any],
                                       operation_lines: list[Any], required_work: list[Any]) -> None:
    if not isinstance(response, Mapping) or set(response) != NESTED_RESPONSE_KEYS or response.get("ok") is not True:
        raise Historical777Error(f"historical nested {stage} response mismatch")
    code = response.get("code")
    data = response.get("data")
    if not isinstance(data, Mapping):
        raise Historical777Error(f"historical nested {stage} data mismatch")
    if stage == "observation":
        if code not in {"noticed", "already_noticed"}:
            raise Historical777Error("historical nested observation code mismatch")
        expected_keys = set(NESTED_OBSERVATION_BASE_KEYS) | {"auto_activation"}
        if code == "noticed":
            expected_keys.add("backend_record_id")
        if set(data) != expected_keys or data["proposal_id"] != child_data["proposal_id"] \
                or data["status"] not in {"pending", "applied", "rejected"} \
                or type(data["version"]) is not int or data["version"] < 1 \
                or not isinstance(data["fingerprint"], str) or re.fullmatch(r"[0-9A-F]{16}", data["fingerprint"]) is None:
            raise Historical777Error("historical nested observation data mismatch")
        if code == "noticed" and (not isinstance(data["backend_record_id"], str) or UUID_RE.fullmatch(data["backend_record_id"].lower()) is None):
            raise Historical777Error("historical nested observation backend identity mismatch")
        auto = data["auto_activation"]
        if not isinstance(auto, Mapping) or set(auto) != NESTED_RESPONSE_KEYS or auto.get("ok") is not True \
                or auto.get("code") not in NESTED_AUTO_DATA_KEYS or not isinstance(auto.get("data"), Mapping) \
                or set(auto["data"]) != NESTED_AUTO_DATA_KEYS[auto["code"]] \
                or auto["data"].get("proposal_id") != child_data["proposal_id"]:
            raise Historical777Error("historical nested auto-activation mismatch")
        auto_data = auto["data"]
        if "stock_number" in auto_data and auto_data["stock_number"] != request["stock_number"]:
            raise Historical777Error("historical nested auto-activation Stock mismatch")
        if "vehicle_id" in auto_data and (not isinstance(auto_data["vehicle_id"], str)
                or UUID_RE.fullmatch(auto_data["vehicle_id"].lower()) is None
                or auto_data["vehicle_id"] != child_data["vehicle_id"]):
            raise Historical777Error("historical nested auto-activation vehicle mismatch")
        if "backend_record_id" in auto_data and (not isinstance(auto_data["backend_record_id"], str)
                or UUID_RE.fullmatch(auto_data["backend_record_id"].lower()) is None
                or auto_data["backend_record_id"] != child_data["backend_record_id"]):
            raise Historical777Error("historical nested auto-activation backend mismatch")
        if any(type(auto_data[key]) is not bool for key in auto_data if key in {
                "vehicle_mutated", "board_activation_only", "reinstatement_receipt_required",
                "authority_refreshed", "board_purge_reactivation", "booking_created", "work_mutated", "parts_mutated"}):
            raise Historical777Error("historical nested auto-activation flag type mismatch")
        if any(type(auto_data[key]) is not int or auto_data[key] < 1 for key in auto_data if key in {
                "version", "proposal_backend_record_version", "current_backend_record_version", "navision_revision"}):
            raise Historical777Error("historical nested auto-activation version mismatch")
        expected_false = {
            "uid514_exact_existing_identity_accepted": ("vehicle_mutated", "board_activation_only"),
            "automatically_closed_existing": ("vehicle_mutated", "board_activation_only"),
            "automatically_closed_duplicate": ("vehicle_mutated", "board_activation_only"),
        }
        if auto["code"] in expected_false and any(auto_data[key] is not False for key in expected_false[auto["code"]]):
            raise Historical777Error("historical nested closed-state mismatch")
        if auto["code"] == "automatically_applied" and (
                auto_data["board_activation_only"] is not True or auto_data["booking_created"] is not False
                or auto_data["work_mutated"] is not False or auto_data["parts_mutated"] is not False):
            raise Historical777Error("historical nested applied-state mismatch")
        return
    if stage == "vehicle_import":
        if code != "canonical_receipt_and_work_imported" or set(data) != VEHICLE_IMPORT_DATA_KEYS \
                or data["vehicle_id"] != child_data["vehicle_id"] or data["backend_record_id"] != child_data["backend_record_id"] \
                or data["stock_number"] != request["stock_number"] or data["job_card_number"] != child_data["job_card_number"] \
                or data["required_work"] != required_work \
                or data["identity_source"] != "navision_exact" or data["booking_created"] is not False \
                or data["completed_work_reopened"] is not False:
            raise Historical777Error("historical nested vehicle-import mismatch")
        if any(not isinstance(data[key], str) for key in ("vehicle_id", "backend_record_id", "stock_number", "job_card_number", "identity_source")) \
                or not isinstance(data["required_work"], list) \
                or type(data["booking_created"]) is not bool or type(data["completed_work_reopened"]) is not bool:
            raise Historical777Error("historical nested vehicle-import schema mismatch")
        return
    if stage == "operation_import":
        if code not in {"operation_lines_and_hours_imported", "operation_lines_and_hours_already_imported"} \
                or set(data) != OPERATION_IMPORT_DATA_KEYS or data["vehicle_id"] != child_data["vehicle_id"] \
                or data["source_hash"] != child_data["canonical_source_hash"] \
                or data["operation_lines_received"] != len(operation_lines) \
                or any(type(data[key]) is not int or data[key] < 0 for key in ("operation_lines_received", "operation_lines_added", "estimated_hours_added", "job_card_hours_corrected", "required_work_added", "resulting_revision")) \
                or data["booking_created"] is not False or data["completed_work_reopened"] is not False:
            raise Historical777Error("historical nested operation-import mismatch")
        if type(data["booking_created"]) is not bool or type(data["completed_work_reopened"]) is not bool \
                or not isinstance(data["source_hash"], str) or re.fullmatch(r"[0-9a-f]{64}", data["source_hash"]) is None:
            raise Historical777Error("historical nested operation-import schema mismatch")
        return
    raise Historical777Error("historical nested stage mismatch")


def validate_success_response(request: Mapping[str, Any], response: Mapping[str, Any], request_hash: str,
                              seen_identity_ids: set[str] | None = None) -> None:
    """Accept success only when the deployed 795 receipt envelope is complete."""
    if set(response) != SUCCESS_RESPONSE_KEYS or response.get("ok") is not True or response.get("code") != EXPECTED_SUCCESS_CODE:
        raise Historical777Error("historical success receipt envelope mismatch")
    data = response.get("data")
    if not isinstance(data, Mapping) or set(data) != SUCCESS_DATA_KEYS:
        raise Historical777Error("historical success receipt data mismatch")
    for key in ("receipt_id", "intake_id", "proposal_id"):
        value = data.get(key)
        if not isinstance(value, str) or UUID_RE.fullmatch(value.lower()) is None:
            raise Historical777Error(f"historical success {key} readback mismatch")
    candidate_identity_ids = {data["receipt_id"].lower()}
    if seen_identity_ids is not None and candidate_identity_ids.intersection(seen_identity_ids):
        raise Historical777Error("historical receipt identity replay mismatch")
    if data["contract_version"] != "778.1" or data["manifest_sha256"] != request["manifest_sha256"] \
            or data["provider_uid"] != request["provider_uid"] \
            or data["parent_source_hash"] != request["parent_source_hash"] \
            or data["sender_email"] != request["sender_email"] \
            or data["stock_number"] != request["stock_number"]:
        raise Historical777Error("historical success receipt identity mismatch")
    if not isinstance(request_hash, str) or re.fullmatch(r"[0-9a-f]{64}", request_hash) is None \
            or request_hash != canonical_request_digest(request):
        raise Historical777Error("historical request digest readback binding mismatch")
    manifest = request["attachment_manifest"]
    children = request["job_card_children"]
    if any(type(data[key]) is not int or data[key] < 0 for key in ("attachment_count", "job_card_count", "sibling_count")) \
            or data["attachment_count"] != len(manifest) or data["job_card_count"] != sum(item["attachment_kind"] == "job_card" for item in manifest) \
            or data["sibling_count"] != sum(item["attachment_kind"] != "job_card" for item in manifest):
        raise Historical777Error("historical success attachment count mismatch")
    if data["proposal_binding_kind"] not in {"pending_proposal_observation_match", "pending_proposal_observation_mismatch"} \
            or not isinstance(data["proposal_observation_match"], bool) \
            or data["proposal_binding_kind"] != ("pending_proposal_observation_match" if data["proposal_observation_match"] else "pending_proposal_observation_mismatch"):
        raise Historical777Error("historical success proposal readback mismatch")
    parent = data["parent_observation"]
    if not isinstance(parent, Mapping) or set(parent) != PARENT_RESPONSE_KEYS or parent.get("ok") is not True \
            or parent.get("code") not in {"noticed", "already_noticed"} or not isinstance(parent.get("data"), Mapping) \
            or set(parent["data"]) != PARENT_DATA_KEYS or not isinstance(parent["data"]["proposal_id"], str) \
            or UUID_RE.fullmatch(parent["data"]["proposal_id"].lower()) is None or parent["data"]["status"] != "pending" \
            or type(parent["data"]["version"]) is not int or parent["data"]["version"] < 1 \
            or not isinstance(parent["data"]["fingerprint"], str) or re.fullmatch(r"[0-9A-F]{16}", parent["data"]["fingerprint"]) is None:
        raise Historical777Error("historical parent observation readback mismatch")
    if parent["data"]["proposal_id"] != data["proposal_id"]:
        raise Historical777Error("historical proposal identity readback mismatch")
    receipts = data["attachment_receipts"]
    if not isinstance(receipts, list) or len(receipts) != len(children):
        raise Historical777Error("historical attachment receipt readback mismatch")
    expected_occurrences = {(item["ordinal"], item["sha256"]) for item in manifest if item["attachment_kind"] in ("job_card", "ambiguous_job_card")}
    if not all(isinstance(receipt, Mapping) for receipt in receipts):
        raise Historical777Error("historical attachment occurrence completeness mismatch")
    if any(type(receipt.get("attachment_ordinal")) is not int or not isinstance(receipt.get("attachment_hash"), str) for receipt in receipts):
        raise Historical777Error("historical attachment occurrence completeness mismatch")
    actual_occurrences = {(receipt.get("attachment_ordinal"), receipt.get("attachment_hash")) for receipt in receipts}
    if len(actual_occurrences) != len(receipts) or actual_occurrences != {(child["attachment_ordinal"], child["attachment_hash"]) for child in children} \
            or actual_occurrences != expected_occurrences:
        raise Historical777Error("historical attachment occurrence completeness mismatch")
    for child, receipt in zip(children, receipts):
        if not isinstance(receipt, Mapping) or set(receipt) not in (
                {"attachment_ordinal", "attachment_hash", "result"},
                {"attachment_ordinal", "attachment_hash", "result", "authoritative_vehicle_id", "authoritative_operation_count"}):
            raise Historical777Error("historical attachment receipt shape mismatch")
        if type(receipt["attachment_ordinal"]) is not int or not isinstance(receipt["attachment_hash"], str) \
                or receipt["attachment_ordinal"] != child["attachment_ordinal"] or receipt["attachment_hash"] != child["attachment_hash"]:
            raise Historical777Error("historical attachment occurrence readback mismatch")
        result = receipt["result"]
        if child["attachment_kind"] == "ambiguous_job_card":
            if result != {"ok": False, "code": "historical_child_ambiguous"} or set(receipt) != {"attachment_ordinal", "attachment_hash", "result"}:
                raise Historical777Error("historical ambiguous attachment readback mismatch")
            continue
        if not isinstance(child.get("extraction"), Mapping) or not isinstance(child["extraction"].get("operation_lines"), list):
            raise Historical777Error("historical child extraction readback mismatch")
        operation_lines = child["extraction"]["operation_lines"]
        if not isinstance(result, Mapping) or set(result) != CHILD_RESPONSE_KEYS or result.get("ok") is not True \
                or result.get("code") != "jobcard_attachment_receipt" or not isinstance(result.get("data"), Mapping) \
                or set(result["data"]) != CHILD_DATA_KEYS:
            raise Historical777Error("historical attachment result readback mismatch")
        else:
            child_data = result["data"]
            for key in ("receipt_id", "intake_id", "attachment_id", "canonical_import_receipt_id", "vehicle_id", "backend_record_id"):
                if not isinstance(child_data[key], str) or UUID_RE.fullmatch(child_data[key].lower()) is None:
                    raise Historical777Error("historical child receipt identity mismatch")
            child_identity_ids = {child_data["receipt_id"].lower(), child_data["canonical_import_receipt_id"].lower()}
            if len(child_identity_ids) != 2 or child_identity_ids.intersection(candidate_identity_ids) \
                    or (seen_identity_ids is not None and child_identity_ids.intersection(seen_identity_ids)):
                raise Historical777Error("historical child receipt identity replay mismatch")
            candidate_identity_ids.update(child_identity_ids)
            if child_data["parent_source_hash"] != request["parent_source_hash"] \
                    or child_data["attachment_source_hash"] != child["attachment_hash"] \
                    or child_data["intake_id"] != data["intake_id"] \
                    or child_data["proposal_id"] != parent["data"]["proposal_id"] \
                    or child_data["attachment_size_bytes"] != next(item["size"] for item in manifest if item["ordinal"] == child["attachment_ordinal"]) \
                    or child_data["attachment_content_type"] != next(item["content_type"] for item in manifest if item["ordinal"] == child["attachment_ordinal"]) \
                    or child_data["job_card_number"] != child["extraction"].get("email_vehicle", {}).get("job_card_number") \
                    or child_data["operation_count"] != len(operation_lines) \
                    or type(child_data["operation_count"]) is not int or child_data["operation_count"] < 0 \
                    or type(child_data["attachment_size_bytes"]) is not int or child_data["attachment_size_bytes"] < 1 \
                    or type(child_data["vehicle_version"]) is not int or type(child_data["backend_record_version"]) is not int \
                    or child_data["canonical_source_hash"] != _length_prefixed_sha256(["pdc-attachment-canonical-source", "233.1", child_data["intake_id"], child_data["attachment_id"], request["parent_source_hash"], child["attachment_hash"]]) \
                    or child_data["source_uid"] != "pdc-jc-159:" + _sha256((child_data["intake_id"] + ":" + child_data["attachment_id"] + ":" + request["parent_source_hash"] + ":" + child["attachment_hash"]).encode("utf-8")) \
                    or child_data["requested_payload_sha256"] != _sha256(_postgres_jsonb_text({
                        "contract_version": "159.1", "actor_id": ACTOR_ID, "intake_id": child_data["intake_id"],
                        "attachment_id": child_data["attachment_id"], "parent_source_hash": request["parent_source_hash"],
                        "attachment_source_hash": child["attachment_hash"], "source_uid": child_data["source_uid"],
                        "authentication": request["authentication"], "email_vehicle": child["extraction"].get("email_vehicle", {}),
                        "required_work": child["extraction"].get("required_work", []), "operation_lines": child["extraction"].get("operation_lines", []),
                    }).encode("utf-8")) \
                    or child_data["operation_sha256"] != _sha256(_postgres_jsonb_text(child_data["operation_lines"]).encode("utf-8")) \
                    or not isinstance(child_data["source_uid"], str) or not re.fullmatch(r"pdc-jc-159:[0-9a-f]{64}", child_data["source_uid"]) \
                    or not isinstance(child_data["job_card_number"], str) or not isinstance(child_data["canonical_operation_line_ids"], list) \
                    or not isinstance(child_data["operation_lines"], list) or len(child_data["operation_lines"]) != child_data["operation_count"] \
                    or not isinstance(child_data["rule_applications"], list) or not isinstance(child_data["canonical_import_response"], Mapping) \
                    or set(child_data["canonical_import_response"]) != {"observation", "vehicle_import", "operation_import", "booking_created", "completion_created", "location_scheduled"} \
                    or any(child_data["canonical_import_response"][key] is not False for key in ("booking_created", "completion_created", "location_scheduled")) \
                    or any(not isinstance(child_data["canonical_import_response"][key], Mapping) or set(child_data["canonical_import_response"][key]) != CHILD_RESPONSE_KEYS for key in ("observation", "vehicle_import", "operation_import")) \
                    or any(child_data[key] is not False for key in ("booking_created", "completion_created", "location_scheduled")):
                raise Historical777Error("historical child receipt data mismatch")
            line_keys = {"source_row_no", "operation_no", "operation_line_id", "work_key", "description", "estimated_hours", "estimated_hours_source"}
            if not isinstance(child_data["canonical_operation_line_ids"], list) \
                    or any(not isinstance(line_id, str) for line_id in child_data["canonical_operation_line_ids"]) \
                    or len(child_data["canonical_operation_line_ids"]) != len(operation_lines) \
                    or len(set(child_data["canonical_operation_line_ids"])) != len(child_data["canonical_operation_line_ids"]) \
                    or any(not isinstance(line, Mapping) or set(line) != line_keys for line in child_data["operation_lines"]):
                raise Historical777Error("historical operation-line readback schema mismatch")
            observed_hours = Decimal("0")
            for requested_line, observed_line in zip(operation_lines, child_data["operation_lines"]):
                requested_hours = requested_line.get("estimated_hours")
                expected_hour_source = "owner_supplied_document_unknown" if requested_hours is None else requested_line.get("estimated_hours_source")
                if type(observed_line["source_row_no"]) is not int or observed_line["source_row_no"] < 1 \
                        or observed_line["source_row_no"] != requested_line.get("source_row_no") \
                        or not isinstance(observed_line["operation_no"], str) or re.fullmatch(r"OP([1-9]|[1-9][0-9]{1,2})", observed_line["operation_no"]) is None \
                        or observed_line["operation_no"] != requested_line.get("operation_no") \
                        or not isinstance(observed_line["work_key"], str) or observed_line["work_key"] not in {"bus4x4", "tint", "hoist", "fitting", "fabrication", "electrical", "tyre", "pitInspection", "PARTS", "sublet", "owner_supplied_document"} \
                        or observed_line["work_key"] != requested_line.get("work_key") \
                        or not isinstance(observed_line["description"], str) or not 1 <= len(observed_line["description"]) <= 180 \
                        or observed_line["description"] != requested_line.get("description") \
                        or not isinstance(observed_line["operation_line_id"], str) \
                        or UUID_RE.fullmatch(observed_line["operation_line_id"].lower()) is None \
                        or observed_line["estimated_hours_source"] not in {"job_card", "ai_estimate", "owner_supplied_document_unknown"} \
                        or observed_line["estimated_hours"] != requested_hours \
                        or observed_line["estimated_hours_source"] != expected_hour_source:
                    raise Historical777Error("historical operation-line binding mismatch")
                if observed_line["estimated_hours"] is not None:
                    if not isinstance(observed_line["estimated_hours"], (int, float)) or isinstance(observed_line["estimated_hours"], bool):
                        raise Historical777Error("historical operation-line hours schema mismatch")
                    try:
                        hours = Decimal(str(observed_line["estimated_hours"]))
                    except (InvalidOperation, ValueError):
                        raise Historical777Error("historical operation-line hours schema mismatch")
                    if hours < 0 or hours > Decimal("999.99") or observed_line["estimated_hours_source"] not in {"job_card", "ai_estimate"}:
                        raise Historical777Error("historical operation-line hours schema mismatch")
                    observed_hours += hours
                elif observed_line["estimated_hours_source"] != "owner_supplied_document_unknown":
                    raise Historical777Error("historical operation-line unknown-hours mismatch")
            try:
                reported_hours = Decimal(str(child_data["estimated_hours_sum"]))
            except (InvalidOperation, ValueError):
                raise Historical777Error("historical operation aggregate mismatch")
            if reported_hours < 0 or reported_hours > Decimal("99999.00") \
                    or [line["operation_line_id"] for line in child_data["operation_lines"]] != child_data["canonical_operation_line_ids"] \
                    or reported_hours != observed_hours:
                raise Historical777Error("historical operation aggregate mismatch")
            nested = child_data["canonical_import_response"]
            _validate_nested_canonical_response(nested["observation"], "observation", child_data, request, operation_lines, child["extraction"].get("required_work", []))
            _validate_nested_canonical_response(nested["vehicle_import"], "vehicle_import", child_data, request, operation_lines, child["extraction"].get("required_work", []))
            _validate_nested_canonical_response(nested["operation_import"], "operation_import", child_data, request, operation_lines, child["extraction"].get("required_work", []))
            if set(receipt) != {"attachment_ordinal", "attachment_hash", "result", "authoritative_vehicle_id", "authoritative_operation_count"} \
                or not isinstance(receipt["authoritative_vehicle_id"], str) or UUID_RE.fullmatch(receipt["authoritative_vehicle_id"].lower()) is None \
                or receipt["authoritative_vehicle_id"] != child_data["vehicle_id"] \
                or type(receipt["authoritative_operation_count"]) is not int \
                or receipt["authoritative_operation_count"] != child_data["operation_count"]:
                raise Historical777Error("historical child authoritative readback mismatch")
    state = data["authoritative_state"]
    state_keys = {"vehicle_id", "lifecycle_state", "current_location", "operation_count", "booking_count", "completion_count", "parts_changed"}
    if not isinstance(state, Mapping) or set(state) != state_keys or type(state["operation_count"]) is not int \
            or type(state["booking_count"]) is not int or type(state["completion_count"]) is not int \
            or state["operation_count"] < 0 or state["booking_count"] != 0 or state["completion_count"] != 0 \
            or state["parts_changed"] is not False:
        raise Historical777Error("historical authoritative state readback mismatch")
    if state["lifecycle_state"] is not None and not isinstance(state["lifecycle_state"], str):
        raise Historical777Error("historical authoritative lifecycle readback mismatch")
    if state["current_location"] is not None and not isinstance(state["current_location"], str):
        raise Historical777Error("historical authoritative location readback mismatch")
    if state["vehicle_id"] is not None and (not isinstance(state["vehicle_id"], str) or UUID_RE.fullmatch(state["vehicle_id"].lower()) is None):
        raise Historical777Error("historical authoritative vehicle readback mismatch")
    regular_receipts = [receipt for child, receipt in zip(children, receipts) if child["attachment_kind"] != "ambiguous_job_card"]
    child_vehicle_ids = [receipt["result"]["data"]["vehicle_id"] for receipt in regular_receipts]
    if child_vehicle_ids and (len(set(child_vehicle_ids)) != 1 or state["vehicle_id"] != child_vehicle_ids[0]
            or state["lifecycle_state"] != "active"
            or (state["current_location"] is not None and state["current_location"] not in PROTECTED_ACTIVE_LOCATIONS)):
        raise Historical777Error("historical authoritative vehicle binding mismatch")
    if not child_vehicle_ids and (state["vehicle_id"] is not None or state["lifecycle_state"] is not None or state["current_location"] is not None):
        raise Historical777Error("historical ambiguous authoritative state mismatch")
    child_operation_counts = [receipt["result"]["data"]["operation_count"] for receipt in regular_receipts]
    if child_operation_counts and state["operation_count"] != sum(child_operation_counts):
        raise Historical777Error("historical authoritative operation readback mismatch")
    if any(data[key] is not False for key in ("booking_created", "completion_created", "location_scheduled", "parts_changed", "status_changed")) \
            or any(data[key] is not True for key in ("no_booking", "no_completion", "no_location_mutation")):
        raise Historical777Error("historical protected-boundary readback mismatch")
    if seen_identity_ids is not None:
        seen_identity_ids.update(candidate_identity_ids)


def _required(row: Mapping[str, Any], key: str) -> Any:
    value = row.get(key)
    if value is None or value == "":
        raise Historical777Error(f"historical row missing {key}")
    return value


def _validate_frozen_manifest_row(row: Mapping[str, Any]) -> None:
    """Require explicit typed frozen manifest and source UID evidence."""
    expected_manifest_fields = {
        "manifest_uidvalidity": MANIFEST_UIDVALIDITY,
        "manifest_high_water_uid": MANIFEST_HIGH_WATER_UID,
        "manifest_uid_count": MANIFEST_UID_COUNT,
    }
    for key, expected in expected_manifest_fields.items():
        value = row.get(key)
        if type(value) is not int or value != expected:
            raise Historical777Error(f"historical {key} mismatch")
    provider_uid = row.get("provider_uid")
    if type(provider_uid) is not str or provider_uid not in AUTHORIZED_PROVIDER_UIDS:
        raise Historical777Error("historical provider UID mismatch")
    source_value = row.get("source_metadata")
    if not isinstance(source_value, Mapping):
        raise Historical777Error("historical source metadata type mismatch")
    source_uidvalidity = source_value.get("uidvalidity")
    if type(source_uidvalidity) is not int or source_uidvalidity != MANIFEST_UIDVALIDITY:
        raise Historical777Error("historical source UIDVALIDITY mismatch")
    source_uid = source_value.get("uid")
    expected_source_uid = int(provider_uid.split(":", 1)[1])
    if type(source_uid) is not int or source_uid != expected_source_uid:
        raise Historical777Error("historical source UID mismatch")
    if provider_uid == EXCLUDED_PROVIDER_UID or str(row.get("stock_number", "")) == EXCLUDED_STOCK:
        raise Historical777Error("historical reference row is excluded")


def _is_ambiguous_job_card(evidence: Any) -> bool:
    if not isinstance(evidence, Mapping):
        return True
    vehicle = evidence.get("email_vehicle") if isinstance(evidence.get("email_vehicle"), Mapping) else {}
    conflicts = evidence.get("conflicts")
    if conflicts is None:
        conflicts = vehicle.get("conflicts") or []
    stocks = evidence.get("stocks")
    if stocks is None:
        stocks = vehicle.get("stock_numbers") or []
    vins = evidence.get("vins")
    if vins is None:
        vins = vehicle.get("vins") or []
    job_cards = evidence.get("job_cards")
    if job_cards is None:
        job_cards = [vehicle.get("job_card_number")] if vehicle.get("job_card_number") else []
    return bool(conflicts) or len(stocks) > 1 or len(vins) > 1 or len(job_cards) != 1


def select_authorized_rows(rows: list[Mapping[str, Any]]) -> list[Mapping[str, Any]]:
    """Require exactly the immutable frozen cohort; never filter extras away."""
    if not isinstance(rows, list) or len(rows) != len(AUTHORIZED_PROVIDER_UIDS):
        raise Historical777Error("historical authorized cohort count mismatch")
    if any(not isinstance(row, Mapping) for row in rows):
        raise Historical777Error("historical authorized cohort row type mismatch")
    provider_uids = [str(row.get("provider_uid", "")) for row in rows]
    if len(set(provider_uids)) != len(AUTHORIZED_PROVIDER_UIDS) or set(provider_uids) != AUTHORIZED_PROVIDER_UIDS:
        raise Historical777Error("historical authorized cohort UID mismatch")
    for row in rows:
        _validate_frozen_manifest_row(row)
        if str(row.get("manifest_sha256", "")).lower() != MANIFEST_SHA256:
            raise Historical777Error("historical row manifest mismatch")
    return rows


def build_historical_request(row: Mapping[str, Any]) -> dict[str, Any]:
    """Build one UUID-free request; attachment children are keyed by SHA-256."""
    if not isinstance(row, Mapping):
        raise Historical777Error("historical row type mismatch")
    _validate_frozen_manifest_row(row)
    if str(_required(row, "manifest_sha256")).lower() != MANIFEST_SHA256:
        raise Historical777Error("historical row manifest mismatch")
    provider_uid = str(_required(row, "provider_uid"))
    stock = str(_required(row, "stock_number"))
    if provider_uid == EXCLUDED_PROVIDER_UID or stock == EXCLUDED_STOCK:
        raise Historical777Error("historical reference row is excluded")
    source = row["source_metadata"]
    received_at = str(_required(row, "source_received_at"))
    if source and str(source.get("received_at")) != received_at:
        raise Historical777Error("historical received time mismatch")

    attachments = list(_required(row, "attachments"))
    manifest: list[dict[str, Any]] = []
    attachment_by_hash: dict[str, list[int]] = {}
    for attachment in attachments:
        if not isinstance(attachment, Mapping):
            raise Historical777Error("historical attachment is not an object")
        digest = str(_required(attachment, "sha256")).lower()
        metadata = {
            "attachment_kind": str(attachment.get("attachment_kind") or "non_job_card_sibling"),
            "content_type": str(_required(attachment, "content_type")),
            "filename": str(_required(attachment, "filename")),
            "ordinal": int(attachment.get("ordinal", len(manifest) + 1)),
            "sha256": digest,
            "size": _required(attachment, "size"),
        }
        manifest.append(metadata)
        attachment_by_hash.setdefault(digest, []).append(len(manifest) - 1)

    raw_children = row.get("job_card_children")
    if raw_children is None:
        raw_children = []
        for attachment in attachments:
            evidence = attachment.get("extraction") or attachment.get("evidence") or {}
            if attachment.get("attachment_kind") in ("job_card", "ambiguous_job_card"):
                raw_children.append({"attachment_hash": attachment["sha256"], "attachment_kind": attachment["attachment_kind"], "extraction_hash": attachment.get("extraction_hash", ""), "extraction": evidence})
    if not isinstance(raw_children, list):
        raise Historical777Error("historical job-card children are not an array")
    children: list[dict[str, Any]] = []
    for child in raw_children:
        if not isinstance(child, Mapping):
            raise Historical777Error("historical job-card child is not an object")
        digest = str(_required(child, "attachment_hash")).lower()
        matches = attachment_by_hash.get(digest, [])
        if len(matches) != 1:
            raise Historical777Error("historical child attachment occurrence is ambiguous")
        metadata = manifest[matches[0]]
        evidence = child.get("extraction") or child.get("evidence") or {}
        kind = str(child.get("attachment_kind") or metadata["attachment_kind"])
        if kind == "job_card" and _is_ambiguous_job_card(evidence):
            kind = "ambiguous_job_card"
        if kind not in ("job_card", "ambiguous_job_card"):
            raise Historical777Error("historical child kind is not a Job Card kind")
        metadata["attachment_kind"] = kind
        children.append({
            "attachment_hash": digest,
            "attachment_ordinal": metadata["ordinal"],
            "extraction_hash": str(_required(child, "extraction_hash")).lower(),
            "extraction": evidence if isinstance(evidence, Mapping) else {},
            "attachment_kind": kind,
        })

    attachment_names = [item["filename"] for item in manifest]
    if source and source.get("attachment_names") not in (None, attachment_names):
        raise Historical777Error("historical attachment name manifest mismatch")
    request = {
        "manifest_sha256": MANIFEST_SHA256,
        "manifest_uidvalidity": MANIFEST_UIDVALIDITY,
        "manifest_high_water_uid": MANIFEST_HIGH_WATER_UID,
        "manifest_uid_count": MANIFEST_UID_COUNT,
        "gateway_instance_id": GATEWAY,
        "release_name": RELEASE_NAME,
        "release_source_sha": RELEASE_SOURCE_SHA,
        "release_manifest_sha256": RELEASE_MANIFEST_SHA256,
        "provider_uid": provider_uid,
        "parent_source_hash": str(_required(row, "parent_source_hash")).lower(),
        "sender_email": str(_required(row, "sender_email")).lower(),
        "authentication": _required(row, "authentication"),
        "stock_number": stock,
        "subject": str(_required(row, "subject")),
        "action_type": str(_required(row, "action_type")),
        "summary": str(_required(row, "summary")),
        "evidence_hash": str(_required(row, "evidence_hash")).lower(),
        "observations": _required(row, "observations"),
        "source_metadata": source,
        "attachment_manifest": manifest,
        "job_card_children": children,
    }
    request["canonical_request_utf8"] = canonical_request_bytes(request).decode("utf-8")
    return request


def _staging_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value.rstrip("/"))
    if parsed.scheme != "https" or parsed.hostname != STAGING_HOST or parsed.port is not None \
            or parsed.username or parsed.password or parsed.query or parsed.fragment \
            or parsed.path not in ("", "/"):
        raise Historical777Error("staging URL binding mismatch")
    return f"https://{STAGING_HOST}"


def _jwt_claims(token: str) -> Mapping[str, Any]:
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        claims = json.loads(base64.urlsafe_b64decode(part.encode()).decode())
    except (IndexError, ValueError, TypeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Historical777Error("current Monitor token is not a JWT") from exc
    if not isinstance(claims, dict) or claims.get("sub") != ACTOR_ID \
            or str(claims.get("email", "")).lower() != ACTOR_EMAIL \
            or claims.get("role") != "authenticated":
        raise Historical777Error("current Monitor token binding mismatch")
    return claims


def invoke_historical_rpc(request: Mapping[str, Any], *, url: str, anon_key: str, actor_token: str) -> dict[str, Any]:
    """Invoke only the dedicated authenticated staging RPC."""
    _jwt_claims(actor_token)
    body = json.dumps({"p_request": dict(request)}, separators=(",", ":"), allow_nan=False).encode("utf-8")
    http_request = urllib.request.Request(
        f"{_staging_url(url)}/rest/v1/rpc/{RPC_NAME}", data=body, method="POST",
        headers={"apikey": anon_key, "Authorization": f"Bearer {actor_token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(http_request, timeout=60) as response:
            result = json.loads(response.read(1_048_576).decode("utf-8"))
    except (urllib.error.HTTPError, urllib.error.URLError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Historical777Error("historical 777 RPC transport failure") from exc
    if not isinstance(result, dict):
        raise Historical777Error("historical 777 RPC returned non-object")
    return result


def prepare_fresh_outbox(path: Path) -> sqlite3.Connection:
    """Create a new local outbox without touching the ordinary monitor store."""
    if path.exists():
        raise Historical777Error("fresh historical outbox path already exists")
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute("create table historical_778_outbox (provider_uid text primary key, request_json text not null, request_sha256 text not null, state text not null, response_json text, attempt_count integer not null default 0, last_error_code text, review_required integer not null default 0, created_at text not null, updated_at text not null)")
    conn.commit()
    return conn


def run_bounded_historical(rows: list[Mapping[str, Any]], outbox: sqlite3.Connection,
                           rpc_call: Callable[[Mapping[str, Any]], dict[str, Any]], *,
                           limit: int | None = None) -> list[dict[str, Any]]:
    """Run only supplied frozen rows; never discovers additional mailbox messages."""
    results = []
    seen_identity_ids: set[str] = set()
    frozen_rows = select_authorized_rows(rows)
    if limit is not None:
        if not isinstance(limit, int) or limit < 1 or limit > len(frozen_rows):
            raise Historical777Error("historical bounded limit mismatch")
        frozen_rows = frozen_rows[:limit]
    for index, row in enumerate(frozen_rows, 1):
        try:
            request = build_historical_request(row)
        except Historical777Error as exc:
            provider_uid = str(row.get("provider_uid") or f"invalid-row-{index}")
            response = {"ok": False, "code": str(exc)}
            request_json = json.dumps({"provider_uid": provider_uid}, sort_keys=True)
            outbox.execute("insert into historical_778_outbox(provider_uid,request_json,request_sha256,state,attempt_count,last_error_code,review_required,created_at,updated_at) values(?,?,?,?,?,?,?,datetime('now'),datetime('now'))", (provider_uid, request_json, _sha256(request_json.encode("utf-8")), "retry", 1, response["code"], 0))
            outbox.commit()
            results.append({"provider_uid": provider_uid, "state": "retry", "code": response["code"], "ok": False})
            continue
        except Exception:
            provider_uid = str(row.get("provider_uid") or f"invalid-row-{index}")
            response = {"ok": False, "code": "historical_row_failure"}
            request_json = json.dumps({"provider_uid": provider_uid}, sort_keys=True)
            outbox.execute("insert into historical_778_outbox(provider_uid,request_json,request_sha256,state,attempt_count,last_error_code,review_required,created_at,updated_at) values(?,?,?,?,?,?,?,datetime('now'),datetime('now'))", (provider_uid, request_json, _sha256(request_json.encode("utf-8")), "retry", 1, response["code"], 0))
            outbox.commit()
            results.append({"provider_uid": provider_uid, "state": "retry", "code": response["code"], "ok": False})
            continue
        provider_uid = request["provider_uid"]
        request_json = json.dumps(request, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        request_hash = canonical_request_digest(request)
        outbox.execute("insert into historical_778_outbox(provider_uid,request_json,request_sha256,state,attempt_count,last_error_code,review_required,created_at,updated_at) values(?,?,?,?,?,?,?,datetime('now'),datetime('now'))", (provider_uid, request_json, request_hash, "pending", 0, None, 0))
        outbox.commit()
        try:
            response = rpc_call(request)
        except Exception as exc:
            response = {"ok": False, "code": str(exc) if isinstance(exc, Historical777Error) else "historical_rpc_failure"}
        if not isinstance(response, Mapping):
            response = {"ok": False, "code": "historical_rpc_non_object"}
        raw_ok = response.get("ok") is True
        code = response.get("code") if isinstance(response.get("code"), str) else (None if raw_ok else "historical_unknown_failure")
        data = response.get("data") if isinstance(response.get("data"), Mapping) else {}
        review_required = code in PROPOSAL_REVIEW_CODES or (code != EXPECTED_SUCCESS_CODE and data.get("review_required") is True)
        if raw_ok and not review_required:
            try:
                validate_success_response(request, response, request_hash, seen_identity_ids)
            except Historical777Error as exc:
                raw_ok = False
                code = str(exc)
            except Exception:
                raw_ok = False
                code = "historical_success_receipt_validation_failure"
        ok = raw_ok and not review_required
        state = "imported" if ok else ("review" if review_required else "retry")
        try:
            response_json = json.dumps(response, sort_keys=True, ensure_ascii=False)
        except (TypeError, ValueError, OverflowError):
            response = {"ok": False, "code": "historical_response_not_json_serializable"}
            response_json = json.dumps(response, sort_keys=True)
            ok = False
            review_required = False
            state = "retry"
            code = response["code"]
        outbox.execute("update historical_778_outbox set state=?,response_json=?,attempt_count=attempt_count+1,last_error_code=?,review_required=?,updated_at=datetime('now') where provider_uid=?", (state, response_json, code, int(review_required), provider_uid))
        outbox.commit()
        results.append({"provider_uid": provider_uid, "state": state, "code": code, "ok": ok})
    return results


def summarize_historical_results(results: list[Mapping[str, Any]]) -> dict[str, Any]:
    """Summarize durable outcomes; every non-ok row makes the process fail."""
    failures = [item for item in results if item.get("ok") is not True]
    return {
        "ok": not failures and bool(results),
        "rows": len(results),
        "imported": sum(item.get("state") == "imported" for item in results),
        "retry": sum(item.get("state") == "retry" for item in results),
        "review": sum(item.get("state") == "review" for item in results),
        "failed": len(failures),
        "exit_code": 0 if not failures and results else 1,
    }


def _load_rows(path: Path) -> list[Mapping[str, Any]]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Historical777Error("historical evidence export is unreadable") from exc
    rows = document.get("rows") if isinstance(document, dict) else document
    if not isinstance(rows, list):
        raise Historical777Error("historical evidence export rows are invalid")
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="bounded staging-only historical 778 caller")
    parser.add_argument("--rows-json", required=True, type=Path)
    parser.add_argument("--outbox", required=True, type=Path)
    parser.add_argument("--live-probe", action="store_true", help="call only the first selected row")
    parser.add_argument("--bounded-caller", action="store_true", help="explicitly call all supplied rows")
    args = parser.parse_args(argv)
    if args.live_probe and args.bounded_caller:
        raise Historical777Error("choose live probe or bounded caller, not both")
    if not args.live_probe and not args.bounded_caller:
        raise Historical777Error("no bounded caller mode selected")
    rows = select_authorized_rows(_load_rows(args.rows_json))
    if not rows:
        raise Historical777Error("no exact 773-derived rows supplied")

    url = os.environ.get("PDC_STAGING_SUPABASE_URL") or os.environ.get("SUPABASE_URL") or ""
    anon_key = os.environ.get("PDC_STAGING_SUPABASE_ANON_KEY") or os.environ.get("SUPABASE_ANON_KEY") or ""
    actor_token = os.environ.get("PDC_MONITOR_ACCESS_TOKEN") or ""
    gateway = os.environ.get("PDC_MONITOR_GATEWAY_INSTANCE_ID") or GATEWAY
    if gateway != GATEWAY or not url or not anon_key or not actor_token:
        raise Historical777Error("current Monitor staging bindings are incomplete")
    outbox = prepare_fresh_outbox(args.outbox)
    try:
        results = run_bounded_historical(rows, outbox, lambda request: invoke_historical_rpc(request, url=url, anon_key=anon_key, actor_token=actor_token), limit=1 if args.live_probe else None)
    finally:
        outbox.close()
    summary = summarize_historical_results(results)
    print(json.dumps({**summary, "rpc": RPC_NAME, "rows": results, "outbox": str(args.outbox)}, sort_keys=True))
    return int(summary["exit_code"])


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Historical777Error as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True), file=sys.stderr)
        raise SystemExit(1)
