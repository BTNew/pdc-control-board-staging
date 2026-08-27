#!/usr/bin/env python3
"""Deterministic active planner for the scoped PMB/PDC staging actor.

This is intentionally not a general-purpose language model. It accepts only
explicit, bounded phrases from the reviewed pmb-pdc-agentic-email-plan-v1
vocabulary and returns REVIEW_REQUIRED or NOT_APPLICABLE for everything else.
It never chooses a vehicle or a target absent from authoritative context.
"""
from __future__ import annotations

import calendar
import json
import re
import sys
from datetime import date
from typing import Any

CONTRACT = "pmb-pdc-agentic-email-plan-v1"
MONTHS = {name.casefold(): number for number, name in enumerate(calendar.month_name) if name}
MONTHS.update({name.casefold(): number for number, name in enumerate(calendar.month_abbr) if name})
STOCK = re.compile(r"(?<!\d)(\d{8})(?!\d)")
DATE_PATTERNS = (
    re.compile(r"\b(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})\b"),
    re.compile(r"\b([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})\b"),
    re.compile(r"\b(\d{4})-(\d{2})-(\d{2})\b"),
)


def fail(message: str) -> None:
    raise ValueError(message)


def parse_date(text: str) -> str | None:
    for pattern in DATE_PATTERNS:
        match = pattern.search(text)
        if not match:
            continue
        try:
            if pattern is DATE_PATTERNS[0]:
                day, month, year = int(match.group(1)), MONTHS[match.group(2).casefold()], int(match.group(3))
            elif pattern is DATE_PATTERNS[1]:
                month, day, year = MONTHS[match.group(1).casefold()], int(match.group(2)), int(match.group(3))
            else:
                year, month, day = map(int, match.groups())
            return date(year, month, day).isoformat()
        except (KeyError, TypeError, ValueError):
            return None
    return None


def exact_contexts(raw: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(raw, list) or not raw:
        fail("authoritative vehicle contexts are required")
    result: dict[str, dict[str, Any]] = {}
    for row in raw:
        if not isinstance(row, dict) or not isinstance(row.get("vehicle_id"), str) or not isinstance(row.get("identity"), dict):
            fail("vehicle context is invalid")
        vehicle_id = row["vehicle_id"]
        if vehicle_id in result:
            fail("duplicate vehicle context")
        identity = row["identity"]
        stock = str(identity.get("stock_number") or "").strip().upper()
        result[vehicle_id] = {"vehicle_id": vehicle_id, "identity": identity, "stock": stock}
    return result


def bound_vehicle(text: str, contexts: dict[str, dict[str, Any]]) -> dict[str, Any] | None:
    stocks = {match.group(1) for match in STOCK.finditer(text)}
    if len(stocks) > 1:
        return None
    if stocks:
        matches = [row for row in contexts.values() if row["stock"] in stocks]
        return matches[0] if len(matches) == 1 else None
    return next(iter(contexts.values())) if len(contexts) == 1 else None


def instruction_row(candidate: dict[str, Any], vehicle: dict[str, Any] | None, disposition: str) -> dict[str, Any]:
    return {
        "instruction_id": candidate["instruction_id"],
        "evidence_refs": [candidate["evidence_ref"]],
        "vehicle_id": vehicle["vehicle_id"] if vehicle else None,
        "identity": vehicle["identity"] if vehicle else {},
        "interpreted_text": candidate["text"],
        "disposition": disposition,
    }


def action(candidate: dict[str, Any], vehicle: dict[str, Any], action_type: str, target: dict[str, Any], reason: str) -> dict[str, Any]:
    expected = dict(target)
    if action_type in {"parts_complete", "parts_ordered"}:
        key = "parts.complete" if action_type == "parts_complete" else "parts.ordered"
        expected = {key: True}
    elif action_type in {"parts_eta_set", "eta_set", "eta_clear", "notes_set", "sublet_booking_date_set"}:
        expected = dict(target)
    return {
        "action_type": action_type,
        "target": target,
        "expected": expected,
        "evidence_refs": [candidate["evidence_ref"]],
        "instruction_ids": [candidate["instruction_id"]],
        "reason": reason,
    }


def classify(candidate: dict[str, Any], vehicle: dict[str, Any] | None) -> tuple[str, list[dict[str, Any]]]:
    text = re.sub(r"\s+", " ", str(candidate.get("text") or "")).strip()
    lowered = text.casefold()
    if not text:
        return "REVIEW_REQUIRED", []
    if " or " in lowered or "next friday" in lowered or "next saturday" in lowered:
        return "REVIEW_REQUIRED", []
    if re.search(r"\bfyi\b|no action required|for information only", lowered):
        return "NOT_APPLICABLE", []
    if vehicle is None:
        return "REVIEW_REQUIRED", []
    if re.search(r"\bcancel\b|\bdo not (?:fit|install)\b|\bremove\b", lowered):
        return "SUPERSEDED", []
    planned: list[dict[str, Any]] = []
    if re.search(r"\bparts?\s+(?:are\s+)?complete\b|\bmark\s+parts?\s+complete\b", lowered):
        planned.append(action(candidate, vehicle, "parts_complete", {"parts.complete": True}, "explicit Parts complete instruction"))
    if "parts eta" in lowered:
        value = parse_date(text)
        if value:
            planned.append(action(candidate, vehicle, "parts_eta_set", {"parts.eta": value}, "explicit Parts ETA instruction"))
        else:
            return "REVIEW_REQUIRED", []
    if re.search(r"\bset\s+eta\b|\bvehicle\s+eta\b", lowered):
        value = parse_date(text)
        if value:
            planned.append(action(candidate, vehicle, "eta_set", {"vehicle.eta": value}, "explicit vehicle ETA instruction"))
        else:
            return "REVIEW_REQUIRED", []
    if "sublet" in lowered and re.search(r"\bbook\b|\bdate\b", lowered):
        value = parse_date(text)
        if value:
            planned.append(action(candidate, vehicle, "sublet_booking_date_set", {"sublet.booking_date": value}, "explicit existing Sublet booking-date instruction"))
        else:
            return "REVIEW_REQUIRED", []
    note = re.search(r"\badd\s+note\s+(.+?)(?:[.!?]|$)", text, re.IGNORECASE)
    if note:
        value = note.group(1).strip()
        if value:
            planned.append(action(candidate, vehicle, "notes_set", {"vehicle.notes": value}, "explicit vehicle note instruction"))
        else:
            return "REVIEW_REQUIRED", []
    return ("ACTIONABLE", planned) if planned else ("REVIEW_REQUIRED", [])


def main() -> int:
    request = json.load(sys.stdin)
    if not isinstance(request, dict) or set(request) != {"contract_version", "evidence", "vehicle_contexts"}:
        fail("planner request envelope is invalid")
    if request["contract_version"] != "pmb-pdc-agentic-planner-request-v1":
        fail("planner request contract is invalid")
    evidence = request["evidence"]
    if not isinstance(evidence, dict) or not isinstance(evidence.get("instruction_candidates"), list):
        fail("planner evidence is invalid")
    contexts = exact_contexts(request["vehicle_contexts"])
    instructions: list[dict[str, Any]] = []
    actions_by_vehicle: dict[str, list[dict[str, Any]]] = {key: [] for key in contexts}
    for candidate in evidence["instruction_candidates"]:
        if not isinstance(candidate, dict) or set(candidate) != {"instruction_id", "evidence_ref", "text"}:
            fail("instruction candidate is invalid")
        vehicle = bound_vehicle(str(candidate["text"]), contexts)
        disposition, planned = classify(candidate, vehicle)
        instructions.append(instruction_row(candidate, vehicle, disposition))
        for planned_action in planned:
            actions_by_vehicle[vehicle["vehicle_id"]].append(planned_action)
    vehicles = [
        {"vehicle_id": row["vehicle_id"], "identity": row["identity"], "actions": actions_by_vehicle[row["vehicle_id"]]}
        for row in contexts.values()
    ]
    json.dump({"contract_version": CONTRACT, "instructions": instructions, "vehicles": vehicles}, sys.stdout, sort_keys=True, separators=(",", ":"), allow_nan=False)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(json.dumps({"error": str(exc)}, sort_keys=True, separators=(",", ":")), file=sys.stderr)
        raise SystemExit(2)
