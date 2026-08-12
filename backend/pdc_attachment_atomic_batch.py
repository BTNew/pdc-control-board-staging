"""Credential-free, fail-closed dispatcher for the retained UIDVALIDITY 1 / UID 478 fixture.

The module performs no mailbox, network, authentication, or database access.  A caller
must provide already-retained descriptors, existing terminal receipts, and an executor.
"""
from __future__ import annotations

import re
from collections.abc import Callable, Mapping, Sequence
from typing import Any


class AttachmentBatchContractError(ValueError):
    """The retained fixture or executor response violated the bounded contract."""


EXPECTED_UID478_ATTACHMENTS = (
    {"file_name": "12658679.pdf", "job_card_number": "J139124174", "line_count": 20,
     "stock_number": None, "vin": "MR0MABAVX02401646"},
    {"file_name": "12661296.pdf", "job_card_number": "J139125297", "line_count": 5,
     "stock_number": "12661296", "vin": None},
    {"file_name": "12550488.pdf", "job_card_number": "J139124665", "line_count": 23,
     "stock_number": "12550488", "vin": None},
    {"file_name": "12535460.pdf", "job_card_number": "J139125061", "line_count": 14,
     "stock_number": "12535460", "vin": None},
)

_SHA256 = re.compile(r"^[a-f0-9]{64}$")
_UUID = re.compile(r"^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$", re.I)
_TERMINAL = frozenset(("applied", "review"))
_DESCRIPTOR_KEYS = frozenset((
    "attachment_id", "file_name", "sha256", "job_card_number", "line_count",
    "stock_number", "vin", "original_extracted_values", "match_evidence",
))


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise AttachmentBatchContractError(f"{label} must be an object")
    return dict(value)


def _validate_fixture(message: Mapping[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    value = _object(message, "message")
    if set(value) != {"mailbox", "uidvalidity", "uid", "received_at", "attachments"}:
        raise AttachmentBatchContractError("message keys are invalid")
    # This helper deliberately cannot be widened by caller configuration.  In
    # particular, 470-477 and every mailbox generation other than 1 fail closed.
    if value["mailbox"] != "pmbcontroller@gmail.com" or value["uidvalidity"] != 1 or value["uid"] != 478:
        raise AttachmentBatchContractError("only mailbox UIDVALIDITY 1 UID 478 is accepted")
    if not isinstance(value["received_at"], str) or not value["received_at"].strip():
        raise AttachmentBatchContractError("received_at is required")
    raw = value["attachments"]
    if not isinstance(raw, Sequence) or isinstance(raw, (str, bytes)) or len(raw) != 4:
        raise AttachmentBatchContractError("exactly four attachment descriptors are required")

    attachments: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_hashes: set[str] = set()
    for index, expected in enumerate(EXPECTED_UID478_ATTACHMENTS):
        item = _object(raw[index], f"attachment {index + 1}")
        if set(item) != _DESCRIPTOR_KEYS:
            raise AttachmentBatchContractError(f"attachment {index + 1} keys are invalid")
        for key, expected_value in expected.items():
            if item.get(key) != expected_value:
                raise AttachmentBatchContractError(f"attachment {index + 1} {key} does not match fixture")
        attachment_id = item["attachment_id"]
        digest = item["sha256"]
        if not isinstance(attachment_id, str) or not _UUID.fullmatch(attachment_id):
            raise AttachmentBatchContractError("attachment_id is invalid")
        if not isinstance(digest, str) or not _SHA256.fullmatch(digest):
            raise AttachmentBatchContractError("attachment sha256 is invalid")
        if attachment_id in seen_ids or digest in seen_hashes:
            raise AttachmentBatchContractError("attachment identity is duplicated")
        seen_ids.add(attachment_id); seen_hashes.add(digest)
        extracted = _object(item["original_extracted_values"], "original_extracted_values")
        if extracted != {key: expected[key] for key in ("job_card_number", "line_count", "stock_number", "vin")}:
            raise AttachmentBatchContractError("original extracted values do not match descriptor")
        evidence = _object(item["match_evidence"], "match_evidence")
        if not evidence:
            raise AttachmentBatchContractError("match evidence is required")
        attachments.append(item)
    return value, attachments


def _terminal_receipt(value: Any, label: str) -> dict[str, Any]:
    receipt = _object(value, label)
    if receipt.get("status") not in _TERMINAL or not isinstance(receipt.get("receipt_id"), str) or not receipt["receipt_id"]:
        raise AttachmentBatchContractError(f"{label} must contain terminal status and receipt_id")
    return receipt


def execute_uid478_batch(
    message: Mapping[str, Any],
    existing_terminal_receipts: Mapping[tuple[str, str], Mapping[str, Any]],
    executor: Callable[[dict[str, Any]], Mapping[str, Any]],
) -> dict[str, Any]:
    """Validate and independently dispatch all unresolved UID478 attachments.

    Existing receipts are keyed by ``(attachment_id, sha256)``. Exact terminal
    replay is returned without invoking the executor. Executor exceptions become a
    nonterminal attempt result and do not prevent dispatch of later attachments.
    """
    envelope, attachments = _validate_fixture(message)
    if not isinstance(existing_terminal_receipts, Mapping) or not callable(executor):
        raise AttachmentBatchContractError("receipt map and executor are required")

    results: list[dict[str, Any]] = []
    for item in attachments:
        key = (item["attachment_id"], item["sha256"])
        if key in existing_terminal_receipts:
            receipt = _terminal_receipt(existing_terminal_receipts[key], "existing receipt")
            results.append({"attachment_id": key[0], "file_name": item["file_name"], **receipt, "replayed": True})
            continue
        dispatch = {**item, "mailbox": envelope["mailbox"], "mailbox_uidvalidity": 1,
                    "mailbox_uid": 478, "message_received_at": envelope["received_at"]}
        try:
            response = _object(executor(dispatch), "executor response")
        except AttachmentBatchContractError:
            raise
        except Exception as exc:  # each attachment is an independent attempt
            results.append({"attachment_id": key[0], "file_name": item["file_name"],
                            "status": "attempt", "error_type": type(exc).__name__, "replayed": False})
            continue
        receipt = _terminal_receipt(response, "executor response")
        results.append({"attachment_id": key[0], "file_name": item["file_name"], **receipt, "replayed": False})

    all_terminal = len(results) == 4 and all(row.get("status") in _TERMINAL for row in results)
    return {
        "mailbox": envelope["mailbox"], "uidvalidity": 1, "uid": 478,
        "attachments": results, "terminal_count": sum(row.get("status") in _TERMINAL for row in results),
        "all_terminal": all_terminal, "high_water_eligible": all_terminal,
        "next_high_water_uid": 478 if all_terminal else None,
    }


__all__ = ["AttachmentBatchContractError", "EXPECTED_UID478_ATTACHMENTS", "execute_uid478_batch"]
