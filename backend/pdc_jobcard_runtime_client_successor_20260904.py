#!/usr/bin/env python
"""Fail-closed two-authority staging client for retained PMB job cards."""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Mapping

STAGING_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
STAGING_HOST = f"{STAGING_PROJECT_REF}.supabase.co"
STAGING_URL = f"https://{STAGING_HOST}"
ATTEST_RPC = "attest_pdc_provider_email_observation"
PROCESS_RPC = "process_email_intake_work"
NON_NAVISION_PROCESS_RPC = "process_pdc_non_navision_jobcard"
SUCCESS_ATTEST_CODES = {"provider_observation_attested", "provider_observation_already_attested"}
SUCCESS_JOB_CARD_CODES = {"jobcard_attachment_receipt", "non_navision_jobcard_receipt"}
HEX64 = set("0123456789abcdef")
WORK_KEYS = {
    "bus4x4", "tint", "hoist", "fitting", "fabrication", "electrical",
    "tyre", "pitInspection", "PARTS", "sublet", "owner_supplied_document",
}
_AUTH_KEYS = {"dkim_aligned", "dmarc_aligned", "gmail_authentication_results", "sender_domain", "spf_aligned"}
_EMAIL_VEHICLE_KEYS = {
    "cancelled", "conflicts", "customer_name", "eta_to_kewdale", "job_card_number",
    "registration", "stock_numbers", "toyota_order_number", "vehicle_description", "vins",
}
_CONTROL = re.compile(r"[\x00-\x1f\x7f]")


class RuntimeContractError(RuntimeError):
    """Safe, bounded runtime/contract failure."""


def _strict_staging_url(value: Any) -> str:
    if not isinstance(value, str) or value != value.strip() or not value:
        raise RuntimeContractError("staging Supabase URL is invalid")
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise RuntimeContractError("staging Supabase URL is invalid") from exc
    if (
        parsed.scheme != "https" or parsed.hostname != STAGING_HOST or port is not None
        or parsed.username is not None or parsed.password is not None
        or parsed.path not in ("", "/") or parsed.query or parsed.fragment
    ):
        raise RuntimeContractError("refusing a non-HTTPS or non-staging Supabase URL")
    return STAGING_URL


@dataclass(frozen=True)
class RpcClient:
    url: str
    apikey: str
    bearer: str
    authority: str
    timeout: int = 60

    def __post_init__(self) -> None:
        object.__setattr__(self, "url", _strict_staging_url(self.url))
        for value, label in ((self.apikey, "apikey"), (self.bearer, "bearer")):
            if not isinstance(value, str) or not 8 <= len(value) <= 16_384 or _CONTROL.search(value):
                raise RuntimeContractError(f"{label} credential is invalid")
        if self.authority not in {"service_role", "authenticated_monitor"}:
            raise RuntimeContractError("RPC client authority is invalid")
        if isinstance(self.timeout, bool) or not isinstance(self.timeout, int) or not 1 <= self.timeout <= 180:
            raise RuntimeContractError("RPC timeout is invalid")

    def rpc(self, name: str, payload: Mapping[str, Any]) -> dict[str, Any]:
        if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,127}", name):
            raise RuntimeContractError("RPC name is invalid")
        data = json.dumps(dict(payload), separators=(",", ":"), allow_nan=False).encode("utf-8")
        request = urllib.request.Request(
            f"{self.url}/rest/v1/rpc/{name}", data=data, method="POST",
            headers={"apikey": self.apikey, "Authorization": f"Bearer {self.bearer}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                status = getattr(response, "status", None)
                if status is None:
                    status = response.getcode()
                if status != 200:
                    raise RuntimeContractError(f"{self.authority} RPC {name} returned unexpected HTTP status")
                raw_bytes = response.read(1_048_577)
                if len(raw_bytes) > 1_048_576:
                    raise RuntimeContractError(f"{self.authority} RPC {name} returned an oversized result")
                raw = raw_bytes.decode("utf-8", errors="strict")
        except urllib.error.HTTPError as exc:
            exc.read(4096)
            raise RuntimeContractError(f"{self.authority} RPC {name} failed HTTP {exc.code}") from exc
        except (urllib.error.URLError, UnicodeDecodeError) as exc:
            raise RuntimeContractError(f"{self.authority} RPC {name} transport failed") from exc
        try:
            result = json.loads(raw) if raw else None
        except json.JSONDecodeError as exc:
            raise RuntimeContractError(f"{self.authority} RPC {name} returned invalid JSON") from exc
        if not isinstance(result, dict):
            raise RuntimeContractError(f"{self.authority} RPC {name} returned an invalid result")
        return result


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise RuntimeContractError(f"{label} must be an object")
    return value


def _exact_keys(value: Mapping[str, Any], expected: set[str], label: str) -> None:
    if not isinstance(value, Mapping) or set(value) != expected:
        raise RuntimeContractError(f"{label} keys do not match the contract")


def _text(value: Any, label: str, minimum: int, maximum: int, *, pattern: str | None = None) -> str:
    if not isinstance(value, str) or value != value.strip() or not minimum <= len(value) <= maximum or _CONTROL.search(value):
        raise RuntimeContractError(f"{label} is invalid")
    if pattern and re.fullmatch(pattern, value) is None:
        raise RuntimeContractError(f"{label} is invalid")
    return value


def _uuid(value: Any, label: str) -> str:
    text = _text(value, label, 36, 36)
    try:
        parsed = uuid.UUID(text)
    except (ValueError, AttributeError) as exc:
        raise RuntimeContractError(f"{label} must be a canonical UUID") from exc
    if parsed.int == 0 or str(parsed) != text.lower():
        raise RuntimeContractError(f"{label} must be a canonical UUID")
    return str(parsed)


def _hex64(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(character not in HEX64 for character in value):
        raise RuntimeContractError(f"{label} must be a lowercase SHA-256 hex digest")
    return value


def _authentication(value: Any) -> dict[str, Any]:
    auth = _object(value, "provider.authentication")
    _exact_keys(auth, _AUTH_KEYS, "provider.authentication")
    for key in ("dkim_aligned", "dmarc_aligned", "gmail_authentication_results", "spf_aligned"):
        if type(auth[key]) is not bool:
            raise RuntimeContractError(f"provider.authentication.{key} must be boolean")
    domain = _text(auth["sender_domain"], "provider.authentication.sender_domain", 1, 253).lower()
    if domain != auth["sender_domain"] or re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?", domain) is None:
        raise RuntimeContractError("provider.authentication.sender_domain is invalid")
    if auth["gmail_authentication_results"] is not True or not any(auth[key] for key in ("spf_aligned", "dkim_aligned", "dmarc_aligned")):
        raise RuntimeContractError("trusted aligned Gmail authentication evidence is required")
    return auth


def _provider(provider_value: Any, extraction: Mapping[str, Any]) -> dict[str, Any]:
    provider = _object(provider_value, "provider")
    _exact_keys(provider, {"attachment_id", "provider_message_id", "provider_authserv_id", "authentication"}, "provider")
    attachment_id = _uuid(provider["attachment_id"], "provider.attachment_id")
    if attachment_id != _uuid(extraction.get("canonical_attachment_id"), "canonical_attachment_id"):
        raise RuntimeContractError("provider and extraction attachment identities differ")
    _text(provider["provider_message_id"], "provider.provider_message_id", 1, 1024)
    if provider["provider_authserv_id"] != "mx.google.com":
        raise RuntimeContractError("provider_authserv_id must be mx.google.com")
    auth = _authentication(provider["authentication"])
    if auth != extraction.get("authentication"):
        raise RuntimeContractError("provider and extraction authentication evidence differ")
    return provider


def _string_list(value: Any, label: str, maximum: int, item_max: int, pattern: str | None = None) -> list[str]:
    if not isinstance(value, list) or len(value) > maximum:
        raise RuntimeContractError(f"{label} is invalid")
    rows = [_text(item, f"{label} item", 1, item_max, pattern=pattern) for item in value]
    if len(set(rows)) != len(rows):
        raise RuntimeContractError(f"{label} contains duplicates")
    return rows


def _email_vehicle(value: Any) -> dict[str, Any]:
    vehicle = _object(value, "email_vehicle")
    _exact_keys(vehicle, _EMAIL_VEHICLE_KEYS, "email_vehicle")
    if vehicle["cancelled"] is not False or vehicle["conflicts"] != []:
        raise RuntimeContractError("email_vehicle is cancelled or conflicted")
    stocks = _string_list(vehicle["stock_numbers"], "email_vehicle.stock_numbers", 1, 80)
    vins = _string_list(vehicle["vins"], "email_vehicle.vins", 1, 17, r"[A-HJ-NPR-Z0-9]{17}")
    if len(stocks) + len(vins) != 1:
        raise RuntimeContractError("email_vehicle requires exactly one stock or VIN identity")
    _text(vehicle["job_card_number"], "email_vehicle.job_card_number", 1, 80)
    for key in ("customer_name", "eta_to_kewdale", "registration", "toyota_order_number", "vehicle_description"):
        item = vehicle[key]
        if item is not None:
            _text(item, f"email_vehicle.{key}", 1, 300)
    return vehicle


def _operation_lines(value: Any, required_value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not 1 <= len(value) <= 50:
        raise RuntimeContractError("operation_lines must contain 1 to 50 source rows")
    required = _string_list(required_value, "required_work", 10, 32)
    if any(item not in WORK_KEYS or item == "owner_supplied_document" for item in required) or len(set(required)) != len(required):
        raise RuntimeContractError("required_work is invalid")
    source_rows: set[int] = set()
    observed_work: set[str] = set()
    for index, row_value in enumerate(value, 1):
        row = _object(row_value, f"operation_lines[{index}]")
        _exact_keys(row, {"source_row_no", "operation_no", "work_key", "description", "estimated_hours"}, "operation line")
        source_no = row["source_row_no"]
        if isinstance(source_no, bool) or not isinstance(source_no, int) or not 1 <= source_no <= 999_999_999 or source_no in source_rows:
            raise RuntimeContractError("operation source_row_no is invalid or duplicated")
        source_rows.add(source_no)
        if row["operation_no"] != f"OP{index}":
            raise RuntimeContractError("operation_no must be ordered OP1..OPn")
        work_key = row["work_key"]
        if work_key not in WORK_KEYS:
            raise RuntimeContractError("operation work_key is invalid")
        if work_key != "owner_supplied_document":
            observed_work.add(work_key)
        _text(row["description"], "operation description", 1, 180)
        hours = row["estimated_hours"]
        if isinstance(hours, bool) or not isinstance(hours, (int, float, Decimal)) or (isinstance(hours, float) and not math.isfinite(hours)):
            raise RuntimeContractError("estimated_hours must be a finite number")
        try:
            decimal_hours = Decimal(str(hours))
        except InvalidOperation as exc:
            raise RuntimeContractError("estimated_hours is invalid") from exc
        try:
            valid_precision = decimal_hours == decimal_hours.quantize(Decimal("0.01"))
        except InvalidOperation as exc:
            raise RuntimeContractError("estimated_hours is invalid") from exc
        if not Decimal("0") <= decimal_hours <= Decimal("999.99") or not valid_precision:
            raise RuntimeContractError("estimated_hours is outside bounds or precision")
    if set(required) != observed_work:
        raise RuntimeContractError("required_work must exactly match operation work keys")
    return value


def validate_request(request: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(request, Mapping):
        raise RuntimeContractError("request must be an object")
    _exact_keys(request, {"intake_id", "expected_source_hash", "extraction_hash", "provider", "extraction"}, "request")
    extraction = _object(request["extraction"], "extraction")
    _exact_keys(extraction, {"authentication", "canonical_attachment_id", "canonical_document_hash", "contract_version", "email_vehicle", "operation_lines", "required_work"}, "extraction")
    if extraction["contract_version"] != "pmb-email-work-v2":
        raise RuntimeContractError("extraction contract_version must be pmb-email-work-v2")
    provider = _provider(request["provider"], extraction)
    _authentication(extraction["authentication"])
    _email_vehicle(extraction["email_vehicle"])
    _operation_lines(extraction["operation_lines"], extraction["required_work"])
    return {
        "intake_id": _uuid(request["intake_id"], "intake_id"),
        "source_hash": _hex64(request["expected_source_hash"], "expected_source_hash"),
        "extraction_hash": _hex64(request["extraction_hash"], "extraction_hash"),
        "attachment_hash": _hex64(extraction["canonical_document_hash"], "canonical_document_hash"),
        "provider": provider, "extraction": extraction,
    }


def _validate_authority_clients(service_client: RpcClient, actor_client: RpcClient) -> None:
    if getattr(service_client, "authority", None) != "service_role" or getattr(actor_client, "authority", None) != "authenticated_monitor":
        raise RuntimeContractError("client authorities are not separated")
    if _strict_staging_url(getattr(service_client, "url", None)) != _strict_staging_url(getattr(actor_client, "url", None)):
        raise RuntimeContractError("client staging URLs differ")
    service_key = getattr(service_client, "bearer", None)
    if getattr(service_client, "apikey", None) != service_key:
        raise RuntimeContractError("service-role apikey and bearer must be the same service credential")
    credentials = (service_key, getattr(actor_client, "apikey", None), getattr(actor_client, "bearer", None))
    if any(not isinstance(item, str) or len(item) < 8 for item in credentials) or len(set(credentials)) != 3:
        raise RuntimeContractError("service-role, anon and monitor actor credentials must be pairwise distinct")


def _success_envelope(result: Any, codes: set[str], label: str) -> tuple[str, dict[str, Any]]:
    if not isinstance(result, dict) or set(result) != {"ok", "code", "data"} or result.get("ok") is not True or result.get("code") not in codes or not isinstance(result.get("data"), dict):
        raise RuntimeContractError(f"{label} returned an invalid success/readback shape")
    return result["code"], result["data"]


def _attestation_success(result: Any) -> str:
    code, data = _success_envelope(result, SUCCESS_ATTEST_CODES, "provider attestation")
    _exact_keys(data, {"observation_id", "request_sha256"}, "provider attestation data")
    _uuid(data["observation_id"], "provider observation_id")
    _hex64(data["request_sha256"], "provider request_sha256")
    return code


def _failure(result: Any, phase: str, fallback: str) -> dict[str, Any]:
    # A response body is remote-controlled even when it is valid JSON.  Keep the
    # public runtime result to local, phase-specific enums only.
    return {"ok": False, "phase": phase, "code": fallback}


def _positive_int(value: Any, label: str, maximum: int = 2_147_483_647) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= maximum:
        raise RuntimeContractError(f"{label} is invalid")
    return value


def _decimal(value: Any, label: str) -> Decimal:
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)) or (isinstance(value, float) and not math.isfinite(value)):
        raise RuntimeContractError(f"{label} must be a finite number")
    try:
        parsed = Decimal(str(value))
        if not parsed.is_finite() or parsed != parsed.quantize(Decimal("0.01")):
            raise RuntimeContractError(f"{label} has invalid precision")
    except InvalidOperation as exc:
        raise RuntimeContractError(f"{label} is invalid") from exc
    if not Decimal("0") <= parsed <= Decimal("99999999.99"):
        raise RuntimeContractError(f"{label} is outside bounds")
    return parsed


def _receipt_operation_lines(
    value: Any, expected_lines: list[dict[str, Any]], *, canonical: bool,
) -> tuple[list[dict[str, Any]], Decimal]:
    if not isinstance(value, list) or len(value) != len(expected_lines):
        raise RuntimeContractError("job-card readback operation_lines are invalid")
    total = Decimal("0")
    line_ids: set[str] = set()
    base_keys = {"source_row_no", "operation_no", "work_key", "description", "estimated_hours"}
    expected_keys = base_keys | (
        {"operation_line_id", "estimated_hours_source"} if canonical else
        {"parser_contract", "source_start", "source_end", "retained_source_text"}
    )
    for index, (observed_value, expected) in enumerate(zip(value, expected_lines), 1):
        observed = _object(observed_value, f"readback operation_lines[{index}]")
        _exact_keys(observed, expected_keys, "readback operation line")
        for key in ("source_row_no", "operation_no", "work_key", "description"):
            if observed[key] != expected[key] or type(observed[key]) is not type(expected[key]):
                raise RuntimeContractError("job-card readback operation line differs from request")
        observed_hours = _decimal(observed["estimated_hours"], "readback operation estimated_hours")
        if observed_hours != _decimal(expected["estimated_hours"], "request operation estimated_hours"):
            raise RuntimeContractError("job-card readback operation hours differ from request")
        total += observed_hours
        if canonical:
            line_id = _uuid(observed["operation_line_id"], "canonical operation line ID")
            if line_id in line_ids or observed["estimated_hours_source"] != "job_card":
                raise RuntimeContractError("canonical operation line metadata is invalid")
            line_ids.add(line_id)
        else:
            if observed["parser_contract"] != "pmb-email-work-v2/operation-line-v1":
                raise RuntimeContractError("non-Navision operation parser contract is invalid")
            start, end, retained = observed["source_start"], observed["source_end"], observed["retained_source_text"]
            if (isinstance(start, bool) or not isinstance(start, int) or start < 0
                    or isinstance(end, bool) or not isinstance(end, int) or end <= start
                    or not isinstance(retained, str) or not retained.strip()
                    or end - start != len(retained) or end > 500000):
                raise RuntimeContractError("non-Navision operation source coordinates are invalid")
            retained_normalized = " ".join(retained.split()).casefold()
            description_normalized = " ".join(expected["description"].split()).casefold()
            if description_normalized not in retained_normalized:
                raise RuntimeContractError("non-Navision retained source text is not bound to the requested description")
            numeric_values: list[Decimal] = []
            for match in re.finditer(
                r"(?<![A-Za-z0-9])(\d+(?:\.\d+)?)[ ]*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)(?![A-Za-z0-9])",
                retained, flags=re.I,
            ):
                try:
                    duration = Decimal(match.group(1))
                    if match.group(2).casefold().startswith("m"):
                        duration /= Decimal("60")
                    numeric_values.append(duration)
                except InvalidOperation:
                    continue
            for token in re.findall(r"(?<![A-Za-z0-9])\d+(?:\.\d+)?(?![A-Za-z0-9])", retained):
                try:
                    numeric_values.append(Decimal(token))
                except InvalidOperation:
                    continue
            if _decimal(expected["estimated_hours"], "request operation estimated_hours") not in numeric_values:
                raise RuntimeContractError("non-Navision retained source text is not bound to the requested hours")
    return value, total


def _jobcard_readback(data: dict[str, Any], checked: dict[str, Any], code: str) -> dict[str, Any]:
    extraction = checked["extraction"]
    expected_lines = extraction["operation_lines"]
    expected_count = len(expected_lines)
    canonical_keys = {
        "receipt_id", "intake_id", "attachment_id", "parent_source_hash", "attachment_source_hash",
        "attachment_size_bytes", "attachment_content_type", "source_uid", "proposal_id",
        "canonical_import_receipt_id", "vehicle_id", "vehicle_version", "backend_record_id",
        "backend_record_version", "job_card_number", "requested_payload_sha256", "operation_sha256",
        "operation_count", "estimated_hours_sum", "canonical_operation_line_ids", "operation_lines",
        "canonical_import_response", "booking_created", "completion_created", "location_scheduled",
    }
    non_navision_keys = {
        "receipt_id", "vehicle_id", "vehicle_created", "operation_count", "operation_lines",
        "initial_location", "mapping_review_count", "booking_created", "completion_created",
    }
    _exact_keys(data, canonical_keys if code == "jobcard_attachment_receipt" else non_navision_keys, "job-card readback")
    receipt_id = _uuid(data["receipt_id"], "readback receipt_id")
    vehicle_id = _uuid(data["vehicle_id"], "readback vehicle_id")
    count = data["operation_count"]
    if isinstance(count, bool) or not isinstance(count, int) or count != expected_count:
        raise RuntimeContractError("job-card readback operation_count does not match request")
    _, operation_sum = _receipt_operation_lines(data["operation_lines"], expected_lines, canonical=code == "jobcard_attachment_receipt")
    if data["booking_created"] is not False or data["completion_created"] is not False:
        raise RuntimeContractError("job-card readback violates no-booking/completion invariant")

    hours: int | float | None = None
    if code == "jobcard_attachment_receipt":
        if _uuid(data["intake_id"], "readback intake_id") != checked["intake_id"]:
            raise RuntimeContractError("job-card readback intake_id differs from request")
        if _uuid(data["attachment_id"], "readback attachment_id") != checked["provider"]["attachment_id"]:
            raise RuntimeContractError("job-card readback attachment_id differs from request")
        if _hex64(data["parent_source_hash"], "readback parent_source_hash") != checked["source_hash"]:
            raise RuntimeContractError("job-card readback parent source hash differs from request")
        if _hex64(data["attachment_source_hash"], "readback attachment_source_hash") != checked["attachment_hash"]:
            raise RuntimeContractError("job-card readback attachment source hash differs from request")
        _positive_int(data["attachment_size_bytes"], "readback attachment_size_bytes", 10_485_760)
        _text(data["attachment_content_type"], "readback attachment_content_type", 1, 255)
        _text(data["source_uid"], "readback source_uid", 1, 100)
        for key in ("proposal_id", "canonical_import_receipt_id", "backend_record_id"):
            _uuid(data[key], f"readback {key}")
        _positive_int(data["vehicle_version"], "readback vehicle_version")
        _positive_int(data["backend_record_version"], "readback backend_record_version")
        if data["job_card_number"] != extraction["email_vehicle"]["job_card_number"]:
            raise RuntimeContractError("job-card readback job_card_number differs from request")
        _hex64(data["requested_payload_sha256"], "readback requested_payload_sha256")
        _hex64(data["operation_sha256"], "readback operation_sha256")
        canonical_response = data["canonical_import_response"]
        _exact_keys(canonical_response, {
            "observation", "vehicle_import", "operation_import", "booking_created",
            "completion_created", "location_scheduled",
        }, "job-card canonical import response")
        if (not isinstance(canonical_response["observation"], dict)
                or not isinstance(canonical_response["vehicle_import"], dict)
                or not isinstance(canonical_response["operation_import"], dict)
                or canonical_response["booking_created"] is not False
                or canonical_response["completion_created"] is not False
                or canonical_response["location_scheduled"] is not False):
            raise RuntimeContractError("job-card canonical import response is invalid")
        if data["location_scheduled"] is not False:
            raise RuntimeContractError("job-card readback violates no-location-scheduling invariant")
        ids = data["canonical_operation_line_ids"]
        if not isinstance(ids, list) or len(ids) != expected_count:
            raise RuntimeContractError("job-card canonical operation IDs are invalid")
        normalized_ids = [_uuid(item, "canonical operation line ID") for item in ids]
        if len(set(normalized_ids)) != expected_count or normalized_ids != [line["operation_line_id"] for line in data["operation_lines"]]:
            raise RuntimeContractError("job-card canonical operation IDs differ from operation lines")
        if _decimal(data["estimated_hours_sum"], "job-card readback estimated_hours_sum") != operation_sum:
            raise RuntimeContractError("job-card readback estimated_hours_sum differs from operation rows")
        hours = data["estimated_hours_sum"]
    else:
        if type(data["vehicle_created"]) is not bool:
            raise RuntimeContractError("non-Navision readback vehicle_created is invalid")
        review_count = data["mapping_review_count"]
        expected_review_count = sum(1 for line in expected_lines if line["work_key"] == "owner_supplied_document")
        if isinstance(review_count, bool) or not isinstance(review_count, int) or review_count != expected_review_count:
            raise RuntimeContractError("non-Navision readback mapping_review_count is invalid")
        expected_location = "YH" if data["vehicle_created"] else None
        if data["initial_location"] != expected_location:
            raise RuntimeContractError("non-Navision readback initial_location is invalid")
    return {"receipt_id": receipt_id, "vehicle_id": vehicle_id, "operation_count": count, "estimated_hours_sum": hours}


def execute_jobcard_request(service_client: RpcClient, actor_client: RpcClient, request: Mapping[str, Any]) -> dict[str, Any]:
    _validate_authority_clients(service_client, actor_client)
    checked = validate_request(request)
    provider = checked["provider"]
    attested = service_client.rpc(ATTEST_RPC, {
        "p_intake_id": checked["intake_id"], "p_attachment_id": provider["attachment_id"],
        "p_expected_parent_hash": checked["source_hash"], "p_expected_attachment_hash": checked["attachment_hash"],
        "p_provider_message_id": provider["provider_message_id"], "p_provider_authserv_id": provider["provider_authserv_id"],
        "p_authentication": provider["authentication"],
    })
    if not isinstance(attested, dict) or attested.get("ok") is not True:
        return _failure(attested, "provider_attestation", "attestation_failed")
    attestation_code = _attestation_success(attested)
    payload = {"p_intake_id": checked["intake_id"], "p_expected_source_hash": checked["source_hash"], "p_extraction_hash": checked["extraction_hash"], "p_extraction": checked["extraction"], "p_actor": "pdc-monitor"}
    processed = actor_client.rpc(PROCESS_RPC, payload)
    expected_success_code = "jobcard_attachment_receipt"
    if not isinstance(processed, dict) or processed.get("ok") is not True:
        code = processed.get("code") if isinstance(processed, dict) else None
        if code != "backend_stock_not_found":
            return _failure(processed, "operational_processing", "processing_failed")
        processed = actor_client.rpc(NON_NAVISION_PROCESS_RPC, payload)
        expected_success_code = "non_navision_jobcard_receipt"
        if not isinstance(processed, dict) or processed.get("ok") is not True:
            return _failure(processed, "non_navision_processing", "processing_failed")
    code, data = _success_envelope(processed, SUCCESS_JOB_CARD_CODES, "job-card processing")
    if code != expected_success_code:
        raise RuntimeContractError("job-card processing returned a success code for the wrong RPC path")
    readback = _jobcard_readback(data, checked, code)
    return {"ok": True, "phase": "complete", "attestation_code": attestation_code, "code": code, **readback}


def _actor_access_token(url: str, anon_key: str) -> str:
    direct = os.environ.get("PDC_MONITOR_ACCESS_TOKEN", "").strip()
    if direct:
        return direct
    email = os.environ.get("PDC_MONITOR_EMAIL", "").strip()
    password = os.environ.get("PDC_MONITOR_PASSWORD", "")
    if not email or not password:
        raise RuntimeContractError("monitor actor credentials are unavailable")
    payload = json.dumps({"email": email, "password": password}).encode("utf-8")
    req = urllib.request.Request(f"{url}/auth/v1/token?grant_type=password", data=payload, method="POST", headers={"apikey": anon_key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            status = getattr(response, "status", None)
            if status is None:
                status = response.getcode()
            if status != 200:
                raise RuntimeContractError("monitor actor authentication returned unexpected HTTP status")
            raw = response.read(65_537)
            if len(raw) > 65_536:
                raise RuntimeContractError("monitor actor authentication response is oversized")
            result = json.loads(raw.decode("utf-8", errors="strict"))
    except (urllib.error.HTTPError, urllib.error.URLError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeContractError("monitor actor authentication failed") from exc
    token = result.get("access_token") if isinstance(result, dict) else None
    if not isinstance(token, str) or not 8 <= len(token) <= 16_384 or _CONTROL.search(token):
        raise RuntimeContractError("monitor actor authentication returned no valid access token")
    return token


def clients_from_environment() -> tuple[RpcClient, RpcClient]:
    url = _strict_staging_url(os.environ.get("SUPABASE_URL", "").strip())
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    anon_key = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    if not service_key or not anon_key:
        raise RuntimeContractError("staging service-role and anon keys are required")
    if service_key == anon_key:
        raise RuntimeContractError("service-role and anon credentials must be distinct")
    direct_actor = os.environ.get("PDC_MONITOR_ACCESS_TOKEN", "").strip()
    if direct_actor and direct_actor in {service_key, anon_key}:
        raise RuntimeContractError("service-role, anon and monitor actor credentials must be pairwise distinct")
    actor_token = _actor_access_token(url, anon_key)
    clients = (RpcClient(url, service_key, service_key, "service_role"), RpcClient(url, anon_key, actor_token, "authenticated_monitor"))
    _validate_authority_clients(*clients)
    return clients


def main() -> int:
    parser = argparse.ArgumentParser(description="Execute one retained PMB job-card v2 request using separated authorities")
    parser.add_argument("--request", required=True, help="Profile-owned retained v2 request JSON")
    args = parser.parse_args()
    try:
        request = json.loads(Path(args.request).read_text(encoding="utf-8"))
        service_client, actor_client = clients_from_environment()
        result = execute_jobcard_request(service_client, actor_client, _object(request, "request"))
    except (OSError, json.JSONDecodeError, RuntimeContractError) as exc:
        result = {"ok": False, "phase": "preflight", "code": type(exc).__name__, "error": str(exc)}
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("ok") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
