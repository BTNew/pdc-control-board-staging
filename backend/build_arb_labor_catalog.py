#!/usr/bin/env python
"""Build a conservative ARB product-code to labour-hours catalogue.

The source PDF is not redistributed. Run pdftotext -layout first, then provide the
resulting text file. Only explicit fit times or rows whose four price columns
prove Dealer Price + Fitting = Dealer Fitted are accepted. Ambiguous product
codes are retained as candidates but are never auto-estimated.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LABOUR_RATE = 160.0
SOURCE_DOCUMENT = "ARB National Dealer Retail Price List — February 2026"
SOURCE_CODE = "DRT20260201.1"
EFFECTIVE_MONTH = "2026-02"
STOP_CODES = {
    "BLACK", "BATTERY", "CHARGE", "COLOUR", "CONTROL", "DEALER", "FITTING",
    "FRONT", "INCLUDES", "LABOUR", "MODEL", "OPTIONAL", "REQUIRED", "RETAIL",
    "RIGHT", "SYSTEM", "VEHICLE", "WITH", "WITHOUT",
}


def _normal_code(value: str) -> str:
    value = re.sub(r"^[0-9]+(?=[A-Z])", "", value.strip().upper())
    if value in STOP_CODES or not re.fullmatch(r"[A-Z0-9][A-Z0-9-]{2,39}", value):
        return ""
    return value


def _codes_from_prefix(prefix: str, explicit_time: bool) -> list[str]:
    groups = re.findall(r"\(([^)]{2,120})\)", prefix)
    codes: list[str] = []
    if groups:
        for token in re.split(r"[,/\s]+", groups[0]):
            code = _normal_code(token)
            if code and (re.search(r"\d", code) or len(code) >= 5):
                codes.append(code)
    else:
        match = re.match(r"^\s*(?:\d+(?:,\d+)*)?([A-Z][A-Z0-9-]{2,39})\b", prefix)
        if match:
            code = _normal_code(match.group(1))
            # Bare all-letter headings are too easy to mistake for product codes.
            if code and (re.search(r"\d", code) or explicit_time and len(code) >= 5):
                codes.append(code)
    return list(dict.fromkeys(codes))


def _fit_time(line: str) -> tuple[float | None, str]:
    match = re.search(r"(?:Add|Allow|Fit\.?\s*:?)[ \t]*(\d+(?:\.\d+)?)[ \t]*(?:hrs?|hours?)\b", line, re.I)
    if match:
        return float(match.group(1)), "explicit-hours"
    match = re.search(r"(?:Add|Allow)[ \t]*(\d+(?:\.\d+)?)[ \t]*(?:min(?:ute)?s?)\b", line, re.I)
    if match:
        return float(match.group(1)) / 60.0, "explicit-minutes"
    return None, ""


def _price_fit_time(line: str) -> tuple[float | None, float | None]:
    amounts = [float(value.replace(",", "")) for value in re.findall(r"(?<![A-Z0-9])([0-9][\d,]*\.\d{2})(?!\d)", line)]
    if len(amounts) < 4:
        return None, None
    dealer_price, fitting, dealer_fitted, _retail_fitted = amounts[-4:]
    if fitting <= 0 or abs((dealer_price + fitting) - dealer_fitted) > 0.11:
        return None, None
    raw_hours = fitting / LABOUR_RATE
    # Catalogue values resolve to 5-minute increments at the stated $160/hr rate.
    rounded_hours = round(raw_hours * 12) / 12
    if not 0.05 <= rounded_hours <= 30 or abs(raw_hours - rounded_hours) > 0.005:
        return None, None
    return rounded_hours, fitting


def _description(prefix: str) -> str:
    value = re.sub(r"^\s*(?:\d+(?:,\d+)*)?\([^)]*\)\s*", "", prefix)
    value = re.sub(r"^\s*(?:\d+(?:,\d+)*)?[A-Z][A-Z0-9-]{2,39}\s+", "", value)
    value = re.sub(r"\b(?:Add|Allow|Fit\.?)\s*$", "", value, flags=re.I)
    return re.sub(r"\s+", " ", value).strip(" ,.;-")[:200]


def parse_catalog(text: str) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    page = 1
    # split('\n') preserves form-feed page delimiters; splitlines() would discard them.
    for raw in text.split("\n"):
        if "\f" in raw:
            page += raw.count("\f")
            raw = raw.replace("\f", "")
        line = " ".join(raw.split())
        if not line:
            continue
        explicit_hours, explicit_source = _fit_time(line)
        amount_match = re.search(r"\d[\d,]*\.\d{2}", line)
        prefix = line[:amount_match.start()] if amount_match else line
        codes = _codes_from_prefix(prefix, explicit_hours is not None)
        # A fitting charge beside a bundle belongs to the complete bundle, not to
        # each component code. Only one-code rows are safe for automatic lookup.
        if len(codes) != 1:
            continue
        hours = explicit_hours
        fitting_charge = None
        source = explicit_source
        if hours is None:
            hours, fitting_charge = _price_fit_time(line)
            source = "catalog-fitting-charge-at-160" if hours is not None else ""
        if hours is None or not 0.05 <= hours <= 30:
            continue
        if fitting_charge is None:
            fitting_charge = round(hours * LABOUR_RATE, 2)
        rows.append({
            "codes": codes,
            "hours": round(hours, 4),
            "fittingCharge": round(fitting_charge, 2),
            "description": _description(prefix),
            "page": page,
            "method": source,
        })

    by_code: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        for code in row["codes"]:
            by_code[code].append(row)

    entries: dict[str, dict[str, Any]] = {}
    ambiguous: dict[str, list[dict[str, Any]]] = {}
    for code, candidates in sorted(by_code.items()):
        by_hours: dict[float, list[dict[str, Any]]] = defaultdict(list)
        for candidate in candidates:
            by_hours[candidate["hours"]].append(candidate)
        compact_candidates = []
        for hours, same_hours in sorted(by_hours.items()):
            representative = same_hours[0]
            compact_candidates.append({
                "hours": hours,
                "fittingCharge": representative["fittingCharge"],
                "description": representative["description"],
                "page": representative["page"],
                "method": representative["method"],
                "occurrences": len(same_hours),
            })
        if len(compact_candidates) == 1:
            entries[code] = compact_candidates[0]
        else:
            ambiguous[code] = compact_candidates

    return {
        "schemaVersion": 1,
        "sourceDocument": SOURCE_DOCUMENT,
        "sourceCode": SOURCE_CODE,
        "effectiveMonth": EFFECTIVE_MONTH,
        "labourRate": LABOUR_RATE,
        "labourRateSourcePage": 6,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "acceptedRows": len(rows),
        "entries": entries,
        "ambiguous": ambiguous,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_text", type=Path)
    parser.add_argument("--json-output", type=Path, required=True)
    parser.add_argument("--js-output", type=Path)
    args = parser.parse_args()
    result = parse_catalog(args.source_text.read_text(encoding="utf-8", errors="replace"))
    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.js_output:
        args.js_output.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(result, separators=(",", ":"), ensure_ascii=False)
        args.js_output.write_text(f"// Generated from {SOURCE_CODE}; do not hand-edit.\nwindow.ARB_LABOUR_CATALOG = {payload};\n", encoding="utf-8")
    print(json.dumps({
        "acceptedRows": result["acceptedRows"],
        "unambiguousCodes": len(result["entries"]),
        "ambiguousCodes": len(result["ambiguous"]),
        "jsonOutput": str(args.json_output),
        "jsOutput": str(args.js_output or ""),
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
