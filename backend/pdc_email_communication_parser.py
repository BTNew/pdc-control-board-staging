#!/usr/bin/env python
"""Deterministic, fail-closed extraction of PMB email communication actions.

Mailbox text is evidence, never authority.  This module performs no I/O and no
Board mutation.  The profile-owned monitor must bind its output to retained,
provider-authenticated message/attachment evidence before an enrolled Importer
can invoke the staging action adapter.
"""
from __future__ import annotations

import re
from datetime import date, datetime
from typing import Any

MAX_TEXT_CHARS = 100_000
MAX_ACTIONS = 20

_STOCK_PATTERNS = (
    re.compile(r"\b(?:stock|stock\s*(?:no\.?|number)|ref\.?)\s*[:#-]?\s*([A-Z0-9][A-Z0-9-]{3,23})\b", re.I),
)
_JOB_CARD_PATTERNS = (
    re.compile(r"\b(?:job\s*card|jobcard|repair\s*order|jc)\s*(?:no\.?|number)?\s*[:#-]?\s*([A-Z0-9][A-Z0-9-]{3,31})\b", re.I),
)
_VIN_PATTERN = re.compile(r"\b(?:VIN|chassis)\s*[:#-]?\s*([A-HJ-NPR-Z0-9]{17})\b", re.I)
_NEGATED_PARTS = re.compile(
    r"\bparts?\b[^.!?\n]{0,60}\b(?:not|aren['’]?t|are\s+not|isn['’]?t|is\s+not|won['’]?t|will\s+not|incomplete|waiting|outstanding|pending|almost|nearly|expect(?:ed)?|should\s+be|will\s+be)\b[^.!?\n]{0,40}\b(?:complete|completed|received|ready)\b"
    r"|\bparts?\b[^.!?\n]{0,40}\b(?:incomplete|waiting|outstanding|pending)\b",
    re.I,
)
_PARTS_UNCERTAIN = re.compile(r"\?|\b(?:when|once|if|soon|tomorrow|next\s+week|\d{1,3}\s*%)\b", re.I)
_PARTS_COMPLETE = re.compile(r"\bparts?\s+(?:are\s+|is\s+|now\s+|have\s+been\s+)?(?:complete|completed|received|ready)\b", re.I)
_SUBLET_CLAUSE = re.compile(r"\bsub[ -]?let\b[^\r\n.!?]{0,120}\b(?:booked|booking|scheduled)\b[^\r\n.!?]{0,120}", re.I)
_SUBLET_UNCERTAIN = re.compile(
    r"\b(?:not\s+booked|isn['’]?t\s+booked|aren['’]?t\s+booked|will\s+be\s+booked|should\s+be\s+booked|proposed|tentative|provisional|cancel(?:led)?)\b|\?",
    re.I,
)
_ADD_ACCESSORY = re.compile(
    r"\b(?:please\s+)?(?:add|fit|install)\s+(?:an?\s+|the\s+)?(.{3,120}?)\s+(?:to|onto|on)\s+(?:this\s+)?(?:job|job\s*card|vehicle)\b",
    re.I,
)
_REMOVE_OR_NEGATE = re.compile(r"\b(?:do\s+not|don['’]?t|not\s+required|remove|delete|cancel|without)\b", re.I)
_DATE_PATTERNS = (
    re.compile(r"\b(20\d{2})-(0[1-9]|1[0-2])-([0-2]\d|3[01])\b"),
    re.compile(r"\b([0-2]?\d|3[01])[/.-]([01]?\d)[/.-](20\d{2}|\d{2})\b"),
    re.compile(r"\b([0-2]?\d|3[01])\s+(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(20\d{2})\b", re.I),
)
_MONTHS = {name.lower(): index for index, names in enumerate((
    (), ("jan", "january"), ("feb", "february"), ("mar", "march"), ("apr", "april"),
    ("may",), ("jun", "june"), ("jul", "july"), ("aug", "august"),
    ("sep", "september"), ("oct", "october"), ("nov", "november"), ("dec", "december"),
)) for name in names}
_ACCESSORY_RULES = (
    (re.compile(r"\blong\s*range\s*(?:fuel\s*)?tank\b", re.I), "Long range tank", "fitting"),
    (re.compile(r"\b(?:bull\s*bar|tow\s*bar|canopy|snorkel|roof\s*rack|side\s*steps?|seat\s*covers?)\b", re.I), None, "fitting"),
    (re.compile(r"\b(?:driving\s*lights?|light\s*bar|dual\s*battery|uhf|brake\s*controller)\b", re.I), None, "electrical"),
    (re.compile(r"\b(?:tray|service\s*body|tool\s*box|water\s*tank)\b", re.I), None, "fabrication"),
    (re.compile(r"\b(?:tyres?|tires?|wheel\s*alignment)\b", re.I), None, "tyre"),
)


def _clean(value: str, limit: int) -> str:
    return re.sub(r"\s+", " ", value or "").strip(" \t\r\n.,;:-")[:limit]


def _unique_matches(patterns: tuple[re.Pattern[str], ...], text: str) -> list[str]:
    values = {_clean(match.group(1), 80).upper() for pattern in patterns for match in pattern.finditer(text)}
    return sorted(value for value in values if value)


def _parse_date(clause: str) -> str | None:
    matches: set[str] = set()
    for index, pattern in enumerate(_DATE_PATTERNS):
        for match in pattern.finditer(clause):
            try:
                if index == 0:
                    parsed = date(int(match.group(1)), int(match.group(2)), int(match.group(3)))
                elif index == 1:
                    year = int(match.group(3))
                    if year < 100:
                        year += 2000
                    parsed = date(year, int(match.group(2)), int(match.group(1)))
                else:
                    parsed = date(int(match.group(3)), _MONTHS[match.group(2).lower()], int(match.group(1)))
            except (ValueError, KeyError):
                continue
            matches.add(parsed.isoformat())
    return next(iter(matches)) if len(matches) == 1 else None


def _accessory(description: str) -> tuple[str, str] | None:
    clean = _clean(description, 120)
    for pattern, fixed, work_key in _ACCESSORY_RULES:
        if pattern.search(clean):
            return fixed or clean, work_key
    return None


def parse_communication_actions(text: str) -> dict[str, Any]:
    """Return a deterministic v1 extraction; uncertainty is explicit and non-applicable."""
    if not isinstance(text, str):
        raise TypeError("text must be a string")
    if not text.strip() or len(text) > MAX_TEXT_CHARS or "\x00" in text:
        return {"contract_version": "pmb-email-communications-v1", "identity": {}, "actions": [], "review_reasons": ["invalid_or_unbounded_text"], "auto_applicable": False}

    stock_numbers = _unique_matches(_STOCK_PATTERNS, text)
    job_cards = _unique_matches(_JOB_CARD_PATTERNS, text)
    vins = sorted({match.group(1).upper() for match in _VIN_PATTERN.finditer(text)})
    identity = {"stock_numbers": stock_numbers, "job_card_numbers": job_cards, "vins": vins}
    actions: list[dict[str, Any]] = []
    review: list[str] = []

    parts_match = _PARTS_COMPLETE.search(text)
    if _NEGATED_PARTS.search(text):
        review.append("parts_completion_negated_or_uncertain")
    elif parts_match:
        starts = [text.rfind(mark, 0, parts_match.start()) for mark in (".", "!", "?", "\n")]
        clause_start = max(starts) + 1
        ends = [pos for mark in (".", "!", "?", "\n") if (pos := text.find(mark, parts_match.end())) >= 0]
        clause_end = min(ends) + 1 if ends else min(len(text), parts_match.end() + 120)
        parts_clause = text[clause_start:clause_end]
        if _PARTS_UNCERTAIN.search(parts_clause):
            review.append("parts_completion_negated_or_uncertain")
        else:
            actions.append({"source_action_no": len(actions) + 1, "action_type": "parts_complete", "evidence": _clean(parts_match.group(0), 180)})

    for match in _SUBLET_CLAUSE.finditer(text):
        clause = _clean(match.group(0), 240)
        local_context = text[max(0, match.start() - 40):min(len(text), match.end() + 2)]
        if _SUBLET_UNCERTAIN.search(local_context):
            review.append("sublet_booking_negated_or_uncertain")
            continue
        booking_date = _parse_date(clause)
        if not booking_date:
            review.append("sublet_booking_date_missing_or_ambiguous")
        else:
            actions.append({"source_action_no": len(actions) + 1, "action_type": "set_sublet_booking_date", "booking_date": booking_date, "evidence": clause})

    for match in _ADD_ACCESSORY.finditer(text):
        clause = _clean(match.group(0), 240)
        local_context = text[max(0, match.start() - 40):match.end()]
        if _REMOVE_OR_NEGATE.search(local_context):
            review.append("accessory_action_negated")
            continue
        classified = _accessory(match.group(1))
        if not classified:
            review.append("accessory_not_in_approved_vocabulary")
            continue
        description, work_key = classified
        actions.append({"source_action_no": len(actions) + 1, "action_type": "add_accessory_work", "description": description, "work_key": work_key, "evidence": clause})

    if len(actions) > MAX_ACTIONS:
        return {"contract_version": "pmb-email-communications-v1", "identity": identity, "actions": [], "review_reasons": ["too_many_actions"], "auto_applicable": False}
    if len(stock_numbers) + len(job_cards) + len(vins) == 0:
        review.append("vehicle_identity_missing")
    if len(stock_numbers) > 1 or len(job_cards) > 1 or len(vins) > 1:
        review.append("vehicle_identity_ambiguous")
    if not actions:
        review.append("no_approved_action_detected")

    review = sorted(set(review))
    return {
        "contract_version": "pmb-email-communications-v1",
        "identity": identity,
        "actions": actions,
        "review_reasons": review,
        "auto_applicable": bool(actions) and not review,
    }


__all__ = ["parse_communication_actions", "MAX_TEXT_CHARS", "MAX_ACTIONS"]
