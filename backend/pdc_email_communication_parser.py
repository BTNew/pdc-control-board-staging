#!/usr/bin/env python
"""Deterministic, fail-closed extraction of PMB email communication actions.

Mailbox text is evidence, never authority. This pure module performs no I/O.
Only definitive clauses, an exact approved accessory phrase, and one identity
category can produce an auto-applicable proposal.
"""
from __future__ import annotations

import re
from datetime import date
from typing import Any

MAX_TEXT_CHARS = 100_000
MAX_ACTIONS = 20
MAX_EVIDENCE_CHARS = 240

_STOCK_PATTERNS = (
    re.compile(r"\b(?:stock|stock\s*(?:no\.?|number)|ref\.?)\s*[:#-]?\s*([A-Z0-9][A-Z0-9-]{3,23})\b", re.I),
)
_JOB_CARD_PATTERNS = (
    re.compile(r"\b(?:job\s*card|jobcard|repair\s*order|jc)\s*(?:no\.?|number)?\s*[:#-]?\s*([A-Z0-9][A-Z0-9-]{3,31})\b", re.I),
)
_VIN_PATTERN = re.compile(r"\b(?:VIN|chassis)\s*[:#-]?\s*([A-HJ-NPR-Z0-9]{17})\b", re.I)
_PARTS_COMPLETE = re.compile(r"\bparts?\s+(?:are\s+|is\s+|now\s+|have\s+been\s+)?(?:complete|completed|received)\b", re.I)
_SUBLET_ACTION = re.compile(r"\bsub[ -]?let\b[^\r\n.!?]{0,160}\b(?:booked|booking|scheduled)\b[^\r\n!?]{0,160}", re.I)
_ADD_ACCESSORY = re.compile(
    r"\b(?:please\s+)?(?:add|fit|install)\s+(?:an?\s+|the\s+)?(.{2,120}?)\s+(?:to|onto|on)\s+(?:this\s+)?(?:job|job\s*card|vehicle)\b",
    re.I,
)
# Certainty is an authorization input. Any such language in the action's full
# clause makes that candidate review-only, irrespective of word order.
_UNCERTAIN_OR_NEGATED = re.compile(
    r"\?|\b(?:if|when|once|unless|provided|assuming|can|could|would|may|might|should|"
    r"will|shall|going\s+to|expect(?:ed|ing)?|propos(?:e|ed|al)|plan(?:ned)?|"
    r"intend(?:ed|s|ing)?|due|to\s+be|tentative(?:ly)?|provisional(?:ly)?|perhaps|maybe|soon|tomorrow|next\s+week|"
    r"subject\s+to|conditional\s+(?:on|upon)|contingent\s+(?:on|upon)|depend(?:ent|ing)\s+(?:on|upon)|pending|awaiting|"
    r"after(?:\s+[a-z]+){0,3}\s+(?:approval|authorisation|authorization|sign[ -]?off)|"
    r"upon(?:\s+[a-z]+){0,3}\s+(?:approval|authorisation|authorization|sign[ -]?off)|later(?:\s+(?:today|on|this\s+(?:morning|afternoon|evening)))?|"
    r"this\s+(?:morning|afternoon|evening)|tonight|next\s+(?:day|month|year)|in\s+the\s+future|at\s+a\s+later\s+(?:time|date)|"
    r"by\s+(?:close\s+of\s+business|end\s+of\s+day)|eventually|"
    r"not|no|never|don['’]?t|doesn['’]?t|isn['’]?t|aren['’]?t|won['’]?t|"
    r"without|cancel(?:led|ed|s)?|remove(?:d)?|delete(?:d)?|incomplete|pending|"
    r"outstanding|waiting|almost|nearly)\b|\b\d{1,3}\s*%",
    re.I,
)
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

# Whole normalized phrase -> (canonical description, work key). Do not replace
# this with substring matching: unknown residual words must fail closed.
ACCESSORY_ALIASES: dict[str, tuple[str, str]] = {
    "long range tank": ("Long range tank", "fitting"),
    "long range fuel tank": ("Long range tank", "fitting"),
    "uhf": ("UHF radio", "electrical"),
    "uhf radio": ("UHF radio", "electrical"),
    "towbar": ("Towbar", "fitting"),
    "tow bar": ("Towbar", "fitting"),
    "canopy": ("Canopy", "fabrication"),
    "tray": ("Tray", "fabrication"),
    "tyre": ("Tyre upgrade", "tyre"),
    "tyres": ("Tyre upgrade", "tyre"),
    "tire": ("Tyre upgrade", "tyre"),
    "tires": ("Tyre upgrade", "tyre"),
    "tyre upgrade": ("Tyre upgrade", "tyre"),
    "tire upgrade": ("Tyre upgrade", "tyre"),
    "spotlight": ("Spotlights", "electrical"),
    "spotlights": ("Spotlights", "electrical"),
    "spot light": ("Spotlights", "electrical"),
    "spot lights": ("Spotlights", "electrical"),
    "light bar": ("Light bar", "electrical"),
}


def _clean(value: str, limit: int) -> str:
    return re.sub(r"\s+", " ", value).strip(" \t\r\n.,;:-")[:limit]


def _unique_matches(patterns: tuple[re.Pattern[str], ...], text: str) -> list[str]:
    values = {_clean(match.group(1), 80).upper() for pattern in patterns for match in pattern.finditer(text)}
    return sorted(value for value in values if value)


def _clauses(text: str) -> list[tuple[int, str]]:
    """Split on sentence punctuation only when followed by whitespace/end."""
    clauses: list[tuple[int, str]] = []
    start = 0
    for match in re.finditer(r"[!?](?=\s|$)|\.(?=\s|$)|\r?\n", text):
        end = match.end()
        if text[start:end].strip():
            clauses.append((start, text[start:end]))
        start = end
    if text[start:].strip():
        clauses.append((start, text[start:]))
    return clauses


def _parse_date(clause: str) -> str | None:
    matches: set[str] = set()
    for index, pattern in enumerate(_DATE_PATTERNS):
        for match in pattern.finditer(clause):
            try:
                if index == 0:
                    parsed = date(int(match.group(1)), int(match.group(2)), int(match.group(3)))
                elif index == 1:
                    year = int(match.group(3))
                    parsed = date(year + 2000 if year < 100 else year, int(match.group(2)), int(match.group(1)))
                else:
                    parsed = date(int(match.group(3)), _MONTHS[match.group(2).lower()], int(match.group(1)))
            except (ValueError, KeyError):
                continue
            matches.add(parsed.isoformat())
    return next(iter(matches)) if len(matches) == 1 else None


def _accessory(description: str) -> tuple[str, str] | None:
    normalized = re.sub(r"[\s-]+", " ", _clean(description, 120)).casefold()
    return ACCESSORY_ALIASES.get(normalized)


def _result(identity: dict[str, list[str]], actions: list[dict[str, Any]], review: list[str]) -> dict[str, Any]:
    review = sorted(set(review))
    return {
        "contract_version": "pmb-email-communications-v1",
        "identity": identity,
        "actions": actions,
        "review_reasons": review,
        "auto_applicable": bool(actions) and not review,
    }


def parse_communication_actions(text: str) -> dict[str, Any]:
    """Return deterministic extraction; uncertainty is explicit/non-applicable."""
    if not isinstance(text, str):
        raise TypeError("text must be a string")
    empty_identity = {"stock_numbers": [], "job_card_numbers": [], "vins": []}
    if not text.strip() or len(text) > MAX_TEXT_CHARS or "\x00" in text:
        return _result(empty_identity, [], ["invalid_or_unbounded_text"])

    identity = {
        "stock_numbers": _unique_matches(_STOCK_PATTERNS, text),
        "job_card_numbers": _unique_matches(_JOB_CARD_PATTERNS, text),
        "vins": sorted({match.group(1).upper() for match in _VIN_PATTERN.finditer(text)}),
    }
    candidates: list[tuple[int, dict[str, Any]]] = []
    review: list[str] = []

    for clause_offset, raw_clause in _clauses(text):
        clause = re.sub(r"\s+", " ", raw_clause).strip(" \t\r\n.,;:-")
        invalid_evidence = not 3 <= len(clause) <= MAX_EVIDENCE_CHARS or bool(re.search(r"[\x00-\x1f\x7f]", clause))
        uncertain = bool(_UNCERTAIN_OR_NEGATED.search(raw_clause))
        parts_mentions_completion = bool(
            re.search(r"\bparts?\b", raw_clause, re.I)
            and re.search(r"\b(?:complete|completed|received|incomplete)\b", raw_clause, re.I)
        )
        matched_parts = False
        for match in _PARTS_COMPLETE.finditer(raw_clause):
            matched_parts = True
            if invalid_evidence:
                review.append("action_evidence_invalid")
            elif uncertain:
                review.append("parts_completion_negated_or_uncertain")
            else:
                candidates.append((clause_offset + match.start(), {"action_type": "parts_complete", "evidence": clause}))
        if parts_mentions_completion and not matched_parts and uncertain:
            review.append("parts_completion_negated_or_uncertain")
        for match in _SUBLET_ACTION.finditer(raw_clause):
            if invalid_evidence:
                review.append("action_evidence_invalid")
                continue
            if uncertain:
                review.append("sublet_booking_negated_or_uncertain")
                if _parse_date(raw_clause) is None:
                    review.append("sublet_booking_date_missing_or_ambiguous")
                continue
            booking_date = _parse_date(raw_clause)
            if booking_date is None:
                review.append("sublet_booking_date_missing_or_ambiguous")
            else:
                candidates.append((clause_offset + match.start(), {"action_type": "set_sublet_booking_date", "booking_date": booking_date, "evidence": clause}))
        for match in _ADD_ACCESSORY.finditer(raw_clause):
            if invalid_evidence:
                review.append("action_evidence_invalid")
                continue
            if uncertain:
                review.append("accessory_action_negated_or_uncertain")
                continue
            classified = _accessory(match.group(1))
            if classified is None:
                review.append("accessory_not_in_approved_vocabulary")
                continue
            description, work_key = classified
            candidates.append((clause_offset + match.start(), {"action_type": "add_accessory_work", "description": description, "work_key": work_key, "evidence": clause}))

    candidates.sort(key=lambda item: item[0])
    actions = [{"source_action_no": index, **action} for index, (_, action) in enumerate(candidates, 1)]
    if len(actions) > MAX_ACTIONS:
        return _result(identity, [], ["too_many_actions"])

    populated_categories = [values for values in identity.values() if values]
    if not populated_categories:
        review.append("vehicle_identity_missing")
    elif len(populated_categories) != 1 or len(populated_categories[0]) != 1:
        review.append("vehicle_identity_ambiguous")
    if not actions:
        review.append("no_approved_action_detected")
    return _result(identity, actions, review)


__all__ = [
    "ACCESSORY_ALIASES", "MAX_ACTIONS", "MAX_EVIDENCE_CHARS", "MAX_TEXT_CHARS",
    "parse_communication_actions",
]
