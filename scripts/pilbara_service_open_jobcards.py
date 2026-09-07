#!/usr/bin/env python3
"""Preview/apply the Pilbara Service open-job-card CSV on PDC STAGING only."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

IMPORTER_VERSION = "pilbara_service_open_jobcards_v1"
EXPECTED_SOURCE_HASH = "9803905a50abcacef851a823f5d7bb708e9890a0aa4c49273e91566ea4ebf69e"
EXPECTED_SOURCE_ROWS = 162
EXPECTED_ACCEPTED_ROWS = 161
EXPECTED_GROUPS = 37
STAGING_REF = "cdsmnqxtyyoeoznmbidd"


@dataclass(frozen=True)
class ParsedSource:
    source_hash: str
    accepted: list[dict[str, Any]]
    quarantined: list[dict[str, Any]]


def _clean(value: Any) -> str:
    return str(value or "").strip()


def _hours(value: Any) -> Decimal | None:
    text = _clean(value).replace(",", "")
    if not text:
        return None
    try:
        result = Decimal(text)
    except InvalidOperation as error:
        raise ValueError(f"invalid estimated labour hours: {value!r}") from error
    if result < 0:
        raise ValueError("estimated labour hours cannot be negative")
    return result


def _decimal_json(value: Decimal | None) -> int | float | None:
    if value is None:
        return None
    return int(value) if value == value.to_integral() else float(value)


def normalize_operation(raw: dict[str, Any], source_order: int) -> dict[str, Any]:
    stock = _clean(raw.get("Stock #"))
    repair_order = _clean(raw.get("R/O #"))
    line_number = int(_clean(raw.get("Line #")))
    description = _clean(raw.get("Operation Desc"))
    source_hours = _hours(raw.get("Estimated labour hours"))
    is_pre_delivery = (
        _clean(raw.get("Dept")).upper() == "PD"
        or "PRE-DELIVERY" in description.upper()
        or "PRE DELIVERY" in description.upper()
    )
    defaulted = is_pre_delivery and (source_hours is None or source_hours == 0)
    effective_hours = Decimal("1.5") if defaulted else source_hours
    parts_raw = _clean(raw.get("Parts on Backorder"))
    parts_key = parts_raw.casefold()
    parts_semantics = (
        "explicitly_backordered" if parts_key == "yes"
        else "not_backordered" if parts_key == "no"
        else "review"
    )
    operation = {
        "importer_version": IMPORTER_VERSION,
        "stock_number": stock,
        "repair_order_number": repair_order,
        "original_line_number": line_number,
        "source_order": source_order,
        "natural_identity": [IMPORTER_VERSION, stock, repair_order, line_number],
        "operation_description": description,
        "source_estimated_hours": _decimal_json(source_hours),
        "effective_estimated_hours": _decimal_json(effective_hours),
        "hours_provenance": "pre_delivery_default_1_5" if defaulted else "source_explicit" if source_hours is not None else "source_blank",
        "parts_on_backorder_raw": parts_raw,
        "parts_semantics": parts_semantics,
        "classification": "Review",
        "raw_row": dict(raw),
    }
    semantic_fields = (
        operation["importer_version"], operation["stock_number"], operation["repair_order_number"],
        operation["original_line_number"], operation["source_order"], operation["operation_description"],
        operation["source_estimated_hours"], operation["effective_estimated_hours"], operation["hours_provenance"],
        operation["parts_on_backorder_raw"], operation["parts_semantics"], operation["classification"],
    )
    if any("\x1f" in str(value) for value in semantic_fields if value is not None):
        raise ValueError("source contains reserved semantic hash delimiter")
    operation["semantic_hash"] = hashlib.sha256(
        "\x1f".join("" if value is None else str(value) for value in semantic_fields).encode("utf-8")
    ).hexdigest()
    return operation


def preview_from_candidates(rows: list[dict[str, Any]], candidates: dict[str, list[str]]) -> dict[str, Any]:
    buckets: dict[str, list[dict[str, Any]]] = {"matched": [], "unmatched": [], "ambiguous": []}
    for row in rows:
        count = len(candidates.get(str(row["stock_number"]), []))
        bucket = "matched" if count == 1 else "unmatched" if count == 0 else "ambiguous"
        buckets[bucket].append(row)

    def totals(bucket_rows: list[dict[str, Any]]) -> dict[str, int]:
        return {
            "stocks": len({str(row["stock_number"]) for row in bucket_rows}),
            "groups": len({(str(row["stock_number"]), str(row["repair_order_number"])) for row in bucket_rows}),
            "lines": len(bucket_rows),
        }

    return {name: totals(bucket_rows) for name, bucket_rows in buckets.items()} | {"standalone_vehicles_created": 0}


def plan_operation_changes(
    rows: list[dict[str, Any]],
    existing_by_identity: dict[tuple[Any, ...], str],
) -> dict[str, Any]:
    outcomes: list[dict[str, Any]] = []
    counts = {"insert": 0, "update": 0, "unchanged": 0, "conflict": 0}
    for row in rows:
        identity = tuple(row["natural_identity"])
        existing_hash = existing_by_identity.get(identity)
        decision = "insert" if existing_hash is None else "unchanged" if existing_hash == row["semantic_hash"] else "conflict"
        counts[decision] += 1
        outcomes.append({"natural_identity": list(identity), "decision": decision})
    return {"counts": counts, "outcomes": outcomes, "apply_allowed": counts["conflict"] == 0}


def live_candidates(stocks: set[str]) -> tuple[dict[str, list[str]], list[dict[str, Any]]]:
    from inspect_pdc14_staging import STAGING_REF as configured_ref, management_query

    if configured_ref != STAGING_REF:
        raise RuntimeError("refusing non-STAGING target")
    if any(not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", stock) for stock in stocks):
        raise ValueError("unsafe stock value")
    stock_json = json.dumps(sorted(stocks)).replace("'", "''")
    query = f"""
with requested as (
  select value as stock_number from jsonb_array_elements_text('{stock_json}'::jsonb)
), inspected as (
  select r.stock_number,
    cardinality(n.ids)::integer as current_navision_count,
    cardinality(v.ids)::integer as exact_vehicle_count,
    case when cardinality(n.ids)=1 and cardinality(v.ids)<=1
      and (n.canonical_vehicle_id is null or n.canonical_vehicle_id=any(v.ids)) then 1 else 0 end as compatible_pair_count,
    case when cardinality(n.ids)=1 and cardinality(v.ids)<=1
      and (n.canonical_vehicle_id is null or n.canonical_vehicle_id=any(v.ids)) then array[n.ids[1]::text] else '{{}}'::text[] end as candidate_vehicle_ids
  from requested r
  cross join lateral (select coalesce(array_agg(b.id order by b.id),'{{}}'::uuid[]) ids,min(b.canonical_vehicle_id::text)::uuid canonical_vehicle_id
    from public.navision_backend_records b where b.source_system='microsoft_navision' and b.is_current and b.record_status='current'
      and b.dealer_code='37047'
      and btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=btrim(r.stock_number)) n
  cross join lateral (select coalesce(array_agg(v.id order by v.id),'{{}}'::uuid[]) ids from public.vehicles v
    where v.deleted_at is null and btrim(v.stock_number)=btrim(r.stock_number)) v
)
select stock_number,current_navision_count,exact_vehicle_count,compatible_pair_count,candidate_vehicle_ids
from inspected order by stock_number
"""
    rows = management_query(query)
    return {row["stock_number"]: list(row["candidate_vehicle_ids"]) for row in rows}, rows


def parse_source(path: Path, expected_hash: str = EXPECTED_SOURCE_HASH) -> ParsedSource:
    source_bytes = path.read_bytes()
    source_hash = hashlib.sha256(source_bytes).hexdigest()
    if source_hash != expected_hash:
        raise ValueError(f"source hash mismatch: expected {expected_hash}, received {source_hash}")

    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != EXPECTED_SOURCE_ROWS:
        raise ValueError(f"source row count mismatch: expected {EXPECTED_SOURCE_ROWS}, received {len(rows)}")

    accepted: list[dict[str, Any]] = []
    quarantined: list[dict[str, Any]] = []
    for source_order, raw in enumerate(rows, start=1):
        stock = _clean(raw.get("Stock #"))
        repair_order = _clean(raw.get("R/O #"))
        line_text = _clean(raw.get("Line #"))
        raw_evidence = dict(raw)
        if not stock or not repair_order or not line_text:
            quarantined.append({
                "source_order": source_order,
                "reason": "invalid_blank_natural_identity",
                "raw_row": raw_evidence,
            })
            continue
        try:
            line_number = int(line_text)
        except ValueError as error:
            raise ValueError(f"invalid Line # at source order {source_order}: {line_text!r}") from error
        if line_number < 1:
            raise ValueError(f"invalid Line # at source order {source_order}: {line_number}")

        accepted.append(normalize_operation(raw_evidence, source_order))

    if len(accepted) != EXPECTED_ACCEPTED_ROWS or len(quarantined) != 1:
        raise ValueError("source accepted/quarantine count mismatch")
    groups = {(row["stock_number"], row["repair_order_number"]) for row in accepted}
    if len(groups) != EXPECTED_GROUPS:
        raise ValueError(f"source group count mismatch: expected {EXPECTED_GROUPS}, received {len(groups)}")
    identities = {(row["stock_number"], row["repair_order_number"], row["original_line_number"]) for row in accepted}
    if len(identities) != len(accepted):
        raise ValueError("duplicate operation natural identity")
    return ParsedSource(source_hash, accepted, quarantined)


def build_database_payload(parsed: ParsedSource) -> list[dict[str, Any]]:
    return sorted(
        [dict(row) for row in parsed.accepted] + [dict(row) for row in parsed.quarantined],
        key=lambda row: int(row["source_order"]),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("parse", "live-preview"))
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    parsed = parse_source(args.source)
    result: dict[str, Any] = {
        "importer_version": IMPORTER_VERSION,
        "source_hash": parsed.source_hash,
        "accepted_lines": len(parsed.accepted),
        "quarantined_lines": len(parsed.quarantined),
        "groups": len({(row["stock_number"], row["repair_order_number"]) for row in parsed.accepted}),
        "stocks": len({row["stock_number"] for row in parsed.accepted}),
        "max_description_length": max(len(row["operation_description"]) for row in parsed.accepted),
        "max_original_line_number": max(row["original_line_number"] for row in parsed.accepted),
        "blank_effective_hours": sum(row["effective_estimated_hours"] is None for row in parsed.accepted),
        "parts_semantics": {value: sum(row["parts_semantics"] == value for row in parsed.accepted) for value in ("explicitly_backordered", "not_backordered", "review")},
    }
    if args.mode == "live-preview":
        candidates, inspection = live_candidates({row["stock_number"] for row in parsed.accepted})
        result["preview"] = preview_from_candidates(parsed.accepted, candidates)
        result["candidate_cardinality"] = {
            "all_requested_stocks_returned": len(inspection) == result["stocks"],
            "current_navision_zero": sum(row["current_navision_count"] == 0 for row in inspection),
            "current_navision_multiple": sum(row["current_navision_count"] > 1 for row in inspection),
            "exact_vehicle_zero": sum(row["exact_vehicle_count"] == 0 for row in inspection),
            "exact_vehicle_multiple": sum(row["exact_vehicle_count"] > 1 for row in inspection),
            "compatible_pair_exactly_one": sum(row["compatible_pair_count"] == 1 for row in inspection),
        }
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
