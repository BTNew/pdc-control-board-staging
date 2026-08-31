"""Safe interpretation boundary for the PDC email transaction successor.

The production integration point is an AI provider adapter. The included
reference adapter is deterministic for staging fixtures and intentionally emits
nothing outside the typed plan contract.
"""
from __future__ import annotations

import re
from datetime import date
from typing import Any, Mapping, Sequence

from .pdc_email_ai_successor_contract import validate_plan

MODEL_VERSION = "deterministic-staging-reference-v1"
PROMPT_VERSION = "pdc-email-ai-prompt-v1"
TAXONOMY_VERSION = "pdc-work-taxonomy-v1"
RULE_VERSION = "pdc-business-rules-v1"

_DATE_PATTERNS = (
    re.compile(r"\b(\d{1,2})\s+([A-Za-z]+)\s+(20\d{2})\b"),
    re.compile(r"\b([A-Za-z]+)\s+(\d{1,2}),?\s+(20\d{2})\b"),
    re.compile(r"\b(20\d{2})-(\d{2})-(\d{2})\b"),
)
_MONTHS = {name.lower(): number for number, names in enumerate((
    (), ("jan", "january"), ("feb", "february"), ("mar", "march"), ("apr", "april"),
    ("may",), ("jun", "june"), ("jul", "july"), ("aug", "august"),
    ("sep", "september"), ("oct", "october"), ("nov", "november"), ("dec", "december"),
)) for name in names}
_STOCK = re.compile(r"\b(?:stock(?:\s*(?:no\.?|number))?|batch)\s*[:#-]?\s*([A-Z0-9][A-Z0-9-]{3,79})\b", re.I)
_OPERATION = re.compile(
    r"^\s*(OP[1-9][0-9]{0,2})\s+(.+?)\s+(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\s*$",
    re.I,
)


def _date_from_text(text: str) -> str | None:
    found: set[str] = set()
    for index, pattern in enumerate(_DATE_PATTERNS):
        for match in pattern.finditer(text):
            try:
                if index == 0:
                    day, month, year = int(match.group(1)), _MONTHS[match.group(2).lower()], int(match.group(3))
                elif index == 1:
                    month, day, year = _MONTHS[match.group(1).lower()], int(match.group(2)), int(match.group(3))
                else:
                    year, month, day = map(int, match.groups())
                found.add(date(year, month, day).isoformat())
            except (KeyError, ValueError):
                continue
    return next(iter(found)) if len(found) == 1 else None


def _clauses(text: str) -> list[str]:
    return [part.strip() for part in re.split(r"(?<=[.!?])\s+|\r?\n+", text) if part.strip()]


def _context_index(contexts: Sequence[Mapping[str, Any]]) -> dict[str, dict[str, Any]]:
    by_stock: dict[str, dict[str, Any]] = {}
    for raw in contexts:
        row = dict(raw)
        identity = dict(row.get("identity") or {})
        stock = str(identity.get("stock_number") or "").strip().upper()
        if not row.get("vehicle_id") or not isinstance(row.get("version"), int) or not stock:
            continue
        if stock in by_stock:
            raise ValueError("duplicate authoritative Stock context")
        by_stock[stock] = row
    return by_stock


def _vehicle_for_clause(clause: str, contexts: Mapping[str, dict[str, Any]]) -> dict[str, Any] | None:
    stocks = {match.group(1).upper() for match in _STOCK.finditer(clause)}
    if len(stocks) != 1:
        return next(iter(contexts.values())) if not stocks and len(contexts) == 1 else None
    return contexts.get(next(iter(stocks)))


def _action(row: Mapping[str, Any], action_type: str, payload: dict[str, Any], evidence: str) -> dict[str, Any]:
    identity = dict(row["identity"])
    vehicle_id = str(row["vehicle_id"])
    instruction_id = "instruction-pending"
    return {
        "instruction_id": instruction_id,
        "vehicle_id": vehicle_id,
        "identity": identity,
        "expected_vehicle_version": row["version"],
        "action_type": action_type,
        "payload": payload,
        "evidence_refs": [f"correspondence:{evidence}"],
    }


def _classify_work(description: str) -> str | None:
    lowered = description.casefold()
    # GVM/weight/suspension is a Hoist-domain operation even when the source
    # sentence mentions tyres. The specific rule must win before tyre wording.
    if re.search(r"\b(gvm|weight\s+upgrade|suspension|lift\s+kit|hoist)\b", lowered):
        return "HOIST"
    if re.search(r"\bparts?|backorder|purchase\s+order\b", lowered):
        return "PARTS"
    if re.search(r"\btyres?|tires?|wheel\s+alignment\b", lowered):
        return "TYRE"
    if re.search(r"\bfabricat|weld|service\s+body|tray|canopy\b", lowered):
        return "FABRICATION"
    if re.search(r"\belectrical|wiring|uhf|light\s+bar\b", lowered):
        return "ELECTRICAL"
    if re.search(r"\btint|window\s+film\b", lowered):
        return "TINT"
    if re.search(r"\bsublet|external\s+provider\b", lowered):
        return "SUBLET"
    if re.search(r"\bfitting|tow\s*bar|bull\s*bar|winch|snorkel\b", lowered):
        return "FITTING"
    return None


def _operation_action(row: Mapping[str, Any], attachment_text: str, evidence: str) -> dict[str, Any] | None:
    lines: list[dict[str, Any]] = []
    for source_row_no, raw_line in enumerate(attachment_text.splitlines(), 1):
        match = _OPERATION.match(raw_line.strip())
        if not match:
            continue
        operation_no, description, hours = match.groups()
        work_key = _classify_work(description)
        if work_key is None:
            continue
        lines.append(
            {
                "operation_no": operation_no.upper(),
                "source_row_no": source_row_no,
                "work_key": work_key,
                "description": description.strip(),
                "estimated_hours": float(hours),
            }
        )
    if not lines:
        return None
    job_card_number = str((row.get("state") or {}).get("job_card_number") or "").strip()
    if not job_card_number:
        return None
    return _action(row, "job_card_upsert", {"job_card_number": job_card_number, "lines": lines}, evidence)


def interpret_correspondence(
    receipt: Mapping[str, Any],
    attachments: Sequence[Mapping[str, Any]],
    authoritative_vehicle_contexts: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Interpret complete evidence into a validated plan, never a DB command."""
    contexts = _context_index(authoritative_vehicle_contexts)
    body = str(receipt.get("correspondence") or "")
    attachment_text = "\n\n".join(str(item.get("extracted_text") or "") for item in attachments)
    actions: list[dict[str, Any]] = []
    for clause in _clauses(body):
        row = _vehicle_for_clause(clause, contexts)
        if row is None:
            continue
        lowered = clause.casefold()
        stock = str(row["identity"].get("stock_number") or "").upper()
        if re.search(r"\bactivate\b", lowered) and row["identity"].get("backend_record_id"):
            identity = row["identity"]
            actions.append(_action(row, "activate_from_navision", {
                "backend_record_id": identity["backend_record_id"],
                "stock_number": stock,
                "vin": identity.get("vin"),
                "job_card_number": (row.get("state") or {}).get("job_card_number"),
            }, clause[:240]))
        if re.search(r"\bparts?\s+eta\b", lowered):
            parsed_date = _date_from_text(clause)
            if parsed_date:
                actions.append(_action(row, "parts_eta_set", {"eta": parsed_date}, clause[:240]))
        if re.search(r"\bparts?\s+(?:are\s+)?(?:now\s+)?(?:complete|completed|received)\b", lowered):
            actions.append(_action(row, "parts_complete", {"confirmed": True}, clause[:240]))
        if re.search(r"\bparts?\s+ordered\b", lowered):
            actions.append(_action(row, "parts_ordered", {"confirmed": True}, clause[:240]))
        location = re.search(r"\b(?:move|set|place)\s+(?:it|vehicle|stock\s+\d+)?\s*(?:to|at)\s+(YH|PMB|QC|RFT|IT|OTHER)\b", clause, re.I)
        if location:
            actions.append(_action(row, "location_set", {"location": location.group(1).upper(), "reason": clause[:400]}, clause[:240]))
        note = re.search(r"\badd\s+note\s*[:#-]?\s*(.+)$", clause, re.I)
        if note and note.group(1).strip():
            actions.append(_action(row, "notes_append", {"text": note.group(1).strip().rstrip(".")}, clause[:240]))
        if re.search(r"\bsub[ -]?let\b", lowered) and re.search(r"\b(?:booked|scheduled)\b", lowered):
            state = row.get("state") or {}
            sublet = state.get("sublet") or {}
            parsed_date = _date_from_text(clause)
            if (
                parsed_date
                and sublet.get("explicit_evidence") is True
                and sublet.get("booking_id")
                and sublet.get("provider_id")
                and sublet.get("provider_name")
                and sublet.get("version")
                and sublet.get("expected_return_date")
            ):
                actions.append(_action(row, "sublet_booking_upsert", {
                    "mode": "update", "booking_id": sublet["booking_id"],
                    "provider_id": sublet["provider_id"],
                    "provider_name": sublet["provider_name"],
                    "expected_booking_version": int(sublet["version"]),
                    "out_date": parsed_date,
                    "expected_return_date": sublet["expected_return_date"],
                }, clause[:240]))

    for stock, row in contexts.items():
        marker = attachment_text.upper().find(stock)
        if marker >= 0:
            operation = _operation_action(row, attachment_text, f"attachment:{stock}")
            if operation:
                actions.append(operation)

    for index, item in enumerate(actions, 1):
        item["instruction_id"] = f"instruction-{index:04d}"

    source = {
        "receipt_id": receipt.get("receipt_id"),
        "source_digest": receipt.get("source_digest"),
        "evidence_digest": receipt.get("evidence_digest"),
        "thread_id": receipt.get("thread_id"),
    }
    plan = {
        "schema_version": "pdc-email-ai-plan-v1",
        "source": source,
        "versions": {
            "model": MODEL_VERSION,
            "prompt": PROMPT_VERSION,
            "taxonomy": TAXONOMY_VERSION,
            "rules": RULE_VERSION,
            "action_contract": "pdc-email-ai-actions-v1",
            "supabase_actions": "staging-canonical-2026-08-31",
        },
        "instructions": actions,
    }
    return validate_plan(plan)


__all__ = ["interpret_correspondence"]
