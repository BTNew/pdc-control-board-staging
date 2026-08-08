#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from scripts.pdc_bulk_workbook_adapter import STAGE_MAPPING_POLICY, adapt_workbook
from staging_conn import get_conn
from staging_env import assert_staging_target, load_local_env

EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
DEFAULT_WORKBOOK = Path.home() / "AppData" / "Local" / "hermes" / "cache" / "documents" / "doc_dd1168d8b7ba_Hermes_PDC_JC_Stock_Operations_Matched.xlsx"
DEFAULT_OUTPUT = ROOT / "artifacts" / "reset_136_preview.json"


def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def digest(value: object) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def norm_stock(value: object) -> str:
    return str(value or "").strip().upper()


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare exact staging reset 136 workbook/Navision preview.")
    parser.add_argument("--workbook", type=Path, default=DEFAULT_WORKBOOK)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    adapted = adapt_workbook(args.workbook, stage_mapping_policy=STAGE_MAPPING_POLICY)
    payload = adapted.payload
    stocks = sorted({norm_stock(row["stock_number"]) for row in payload})

    with get_conn() as conn:
        conn.set_session(readonly=True, isolation_level="REPEATABLE READ")
        with conn.cursor() as cur:
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            if cur.fetchone() != (EXPECTED_REF,):
                raise RuntimeError("staging sentinel mismatch")
            cur.execute("select transaction_timestamp() at time zone 'UTC'")
            snapshot_at = cur.fetchone()[0].isoformat() + "Z"
            cur.execute("""
                select public.normalize_vehicle_stock_number(r.normalized_data->>'batch') stock,
                       r.id::text,r.row_hash,r.version,r.dealer_code,r.canonical_vehicle_id::text,
                       public.navision_operational_location(r.normalized_data) deployed_location,
                       coalesce(r.normalized_data->>'toyotaStatus',''),
                       coalesce(r.normalized_data->>'navisionLocationStatus',''),
                       coalesce(r.normalized_data->>'navisionSubLocationDescription',''),
                       coalesce(r.normalized_data->>'internalStatus',''),
                       public.navision_kewdale_eta_from_payload(r.normalized_data)::text
                from public.navision_backend_records r
                where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current
                  and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=any(%s::text[])
                order by stock,r.id
            """, (stocks,))
            authority_rows = cur.fetchall()
            cur.execute("""
                select public.normalize_vehicle_stock_number(v.stock_number) stock,v.id::text,
                       v.lifecycle_state::text,v.deleted_at is null,v.visible_on_board,v.current_location
                from public.vehicles v
                where public.normalize_vehicle_stock_number(v.stock_number)=any(%s::text[])
                order by stock,v.id
            """, (stocks,))
            vehicle_rows = cur.fetchall()
            cur.execute("""
                select public.normalize_vehicle_stock_number(r.normalized_data->>'batch') stock,
                       a.backend_record_id::text,a.canonical_vehicle_id::text,a.active,a.completed_at is not null
                from public.navision_board_activations a
                join public.navision_backend_records r on r.id=a.backend_record_id
                where public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=any(%s::text[])
                order by stock,a.backend_record_id
            """, (stocks,))
            activation_rows = cur.fetchall()
            cur.execute("select version,name from supabase_migrations.schema_migrations order by version::integer desc limit 1")
            migration_head = cur.fetchone()
            conn.rollback()

    authorities: dict[str, list[dict]] = {stock: [] for stock in stocks}
    for row in authority_rows:
        authority = dict(zip((
            "stock_number", "backend_record_id", "row_hash", "version", "dealer_code", "canonical_vehicle_id",
            "deployed_location", "toyota_status", "navision_location_status", "navision_sub_location_description",
            "internal_status", "kewdale_eta",
        ), row))
        authorities[row[0]].append(authority)
    vehicles: dict[str, list[dict]] = {stock: [] for stock in stocks}
    for row in vehicle_rows:
        vehicles[row[0]].append(dict(zip(("stock_number", "vehicle_id", "lifecycle_state", "not_deleted", "visible_on_board", "current_location"), row)))
    activations: dict[str, list[dict]] = {stock: [] for stock in stocks}
    for row in activation_rows:
        activations[row[0]].append(dict(zip(("stock_number", "backend_record_id", "canonical_vehicle_id", "active", "completed"), row)))

    decisions: dict[str, dict] = {}
    for stock in stocks:
        nav = authorities[stock]
        existing = vehicles[stock]
        acts = activations[stock]
        reason = None
        if len(nav) == 0:
            reason = "no_current_navision_stock_match"
        elif len(nav) > 1:
            reason = "multiple_current_navision_stock_matches"
        elif len(existing) > 1:
            reason = "multiple_operational_or_historical_stock_matches"
        else:
            authority = nav[0]
            existing_ids = {row["vehicle_id"] for row in existing}
            authority_vehicle = authority["canonical_vehicle_id"]
            activation_vehicle_ids = {row["canonical_vehicle_id"] for row in acts if row["canonical_vehicle_id"]}
            if authority_vehicle and authority_vehicle not in existing_ids:
                reason = "navision_canonical_vehicle_identity_conflict"
            elif any(vehicle_id not in existing_ids for vehicle_id in activation_vehicle_ids):
                reason = "navision_activation_vehicle_identity_conflict"
            elif authority_vehicle and activation_vehicle_ids and activation_vehicle_ids != {authority_vehicle}:
                reason = "navision_canonical_activation_disagreement"
        if reason:
            decisions[stock] = {"accepted": False, "reason": reason}
            continue
        authority = nav[0]
        deployed = authority["deployed_location"]
        location = "RFT" if deployed == "Completed" else deployed
        if location not in {"YH", "IT", "PMB", "RFT", "Other"}:
            decisions[stock] = {"accepted": False, "reason": "unsupported_navision_location", "raw_location": deployed}
            continue
        decisions[stock] = {
            "accepted": True,
            "backend_record_id": authority["backend_record_id"],
            "backend_row_hash": authority["row_hash"],
            "backend_version": authority["version"],
            "canonical_vehicle_id": authority["canonical_vehicle_id"],
            "existing_vehicle_id": existing[0]["vehicle_id"] if existing else None,
            "location": location,
            "deployed_location": deployed,
            "location_evidence": {
                "toyota_status": authority["toyota_status"],
                "navision_location_status": authority["navision_location_status"],
                "navision_sub_location_description": authority["navision_sub_location_description"],
                "internal_status": authority["internal_status"],
                "kewdale_eta": authority["kewdale_eta"],
            },
        }

    accepted_pairs = []
    exceptions = []
    for source in payload:
        stock = norm_stock(source["stock_number"])
        decision = decisions[stock]
        if decision["accepted"]:
            accepted_pairs.append({
                "row_no": source["row_no"],
                "job_card_number": source["job_card_number"],
                "stock_number": stock,
                "backend_record_id": decision["backend_record_id"],
                "backend_row_hash": decision["backend_row_hash"],
                "backend_version": decision["backend_version"],
                "canonical_vehicle_id": decision["canonical_vehicle_id"],
                "existing_vehicle_id": decision["existing_vehicle_id"],
                "location": decision["location"],
                "deployed_location": decision["deployed_location"],
                "location_evidence": decision["location_evidence"],
                "operations": source["operations"],
            })
        else:
            exceptions.append({
                "row_no": source["row_no"],
                "job_card_number": source["job_card_number"],
                "stock_number": stock,
                "reason": decision["reason"],
                "operation_count": len(source["operations"]),
            })

    accepted_stocks = sorted({row["stock_number"] for row in accepted_pairs})
    exception_stocks = sorted({row["stock_number"] for row in exceptions})
    accepted_operations = [op for row in accepted_pairs for op in row["operations"]]
    exception_operations = sum(row["operation_count"] for row in exceptions)
    authority_binding = [{
        "stock_number": stock,
        "backend_record_id": decisions[stock].get("backend_record_id"),
        "backend_row_hash": decisions[stock].get("backend_row_hash"),
        "backend_version": decisions[stock].get("backend_version"),
        "location": decisions[stock].get("location"),
        "accepted": decisions[stock]["accepted"],
        "reason": decisions[stock].get("reason"),
    } for stock in stocks]
    stage_counts = Counter(op["work_key"] for op in accepted_operations)
    location_counts = Counter(decisions[stock]["location"] for stock in accepted_stocks)
    reason_counts = Counter(row["reason"] for row in exceptions)
    repeated_stock_pairs = {stock: sum(1 for row in payload if norm_stock(row["stock_number"]) == stock) for stock in stocks}
    repeated_stock_pairs = {stock: count for stock, count in repeated_stock_pairs.items() if count > 1}

    summary = {
        "workbook_sha256": adapted.evidence["workbook_sha256"],
        "source_payload_sha256": adapted.evidence["payload_sha256"],
        "authority_binding_sha256": digest(authority_binding),
        "accepted_payload_sha256": digest(accepted_pairs),
        "snapshot_at_utc": snapshot_at,
        "migration_head": list(migration_head),
        "workbook_pair_count": len(payload),
        "workbook_unique_stock_count": len(stocks),
        "workbook_operation_count": adapted.evidence["operation_count"],
        "accepted_pair_count": len(accepted_pairs),
        "accepted_unique_stock_count": len(accepted_stocks),
        "accepted_operation_count": len(accepted_operations),
        "accepted_estimated_hours_count": sum(op["estimated_hours"] is not None for op in accepted_operations),
        "accepted_missing_hours_count": sum(op["estimated_hours"] is None for op in accepted_operations),
        "exception_pair_count": len(exceptions),
        "exception_unique_stock_count": len(exception_stocks),
        "exception_operation_count": exception_operations,
        "location_counts": dict(sorted(location_counts.items())),
        "stage_counts": dict(sorted(stage_counts.items())),
        "exception_reason_counts": dict(sorted(reason_counts.items())),
        "repeated_stock_pair_counts": repeated_stock_pairs,
    }
    if summary["accepted_pair_count"] + summary["exception_pair_count"] != summary["workbook_pair_count"]:
        raise RuntimeError("pair reconciliation mismatch")
    if summary["accepted_operation_count"] + summary["exception_operation_count"] != summary["workbook_operation_count"]:
        raise RuntimeError("operation reconciliation mismatch")
    output = {
        "format": "pdc-staging-reset-preview-136-v1",
        "project_ref": EXPECTED_REF,
        "stage_mapping_policy": STAGE_MAPPING_POLICY,
        "summary": summary,
        "authority_binding": authority_binding,
        "accepted_pairs": accepted_pairs,
        "exceptions": exceptions,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(canonical_bytes(output))
    print(json.dumps({"ok": True, "output": str(args.output), **summary}, sort_keys=True))


if __name__ == "__main__":
    main()
