from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

SAMPLED_ASSERTIONS = {"A04", "A16", "A21", "A22", "A23", "A26"}
REQUIRED_FIELDS = (
    "before_state",
    "request_payload_redacted",
    "response",
    "status",
    "authoritative_db_readback",
    "ui_readback",
    "audit_history_or_typed_action_receipt",
    "expected_version_behavior",
    "observed_version_behavior",
    "expected_idempotency_behavior",
    "observed_idempotency_behavior",
    "rollback_cleanup_result",
    "evidence_paths",
)


def nonempty(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (list, dict)):
        return bool(value)
    return True


def validate(ledger_path: Path, evidence_root: Path) -> list[str]:
    errors: list[str] = []
    try:
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"ledger unreadable: {exc}"]

    assertions = ledger.get("assertions")
    if not isinstance(assertions, list):
        return ["assertions must be an array"]

    assertion_ids = [item.get("id") for item in assertions if isinstance(item, dict)]
    by_id = {item.get("id"): item for item in assertions if isinstance(item, dict)}
    duplicates = sorted({assertion_id for assertion_id in assertion_ids if assertion_ids.count(assertion_id) > 1})
    if duplicates:
        errors.append(f"duplicate assertion ids: {', '.join(duplicates)}")
    missing = sorted(SAMPLED_ASSERTIONS - by_id.keys())
    if missing:
        errors.append(f"missing sampled assertions: {', '.join(missing)}")

    root = evidence_root.resolve()
    for assertion_id in sorted(SAMPLED_ASSERTIONS & by_id.keys()):
        item = by_id[assertion_id]
        if item.get("status") != item.get("result"):
            errors.append(f"{assertion_id}.status does not match result")
        for field in REQUIRED_FIELDS:
            if not nonempty(item.get(field)):
                errors.append(f"{assertion_id}.{field} is empty")
        paths = item.get("evidence_paths")
        if not isinstance(paths, list):
            continue
        for raw_path in paths:
            if not isinstance(raw_path, str) or not raw_path.strip():
                errors.append(f"{assertion_id}.evidence_paths contains an invalid path")
                continue
            candidate = (root / raw_path).resolve()
            try:
                candidate.relative_to(root)
            except ValueError:
                errors.append(f"{assertion_id}.evidence_paths escapes evidence root: {raw_path}")
                continue
            if not candidate.is_file():
                errors.append(f"{assertion_id}.evidence_paths does not resolve: {raw_path}")

    machine_path = root / "lanes" / "transactions" / "aud001-transaction-evidence.json"
    try:
        machine = json.loads(machine_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"AUD-001 machine evidence unreadable: {exc}")
        machine = {}
    transactions = machine.get("transactions", {}) if isinstance(machine, dict) else {}
    transaction_fields = (
        "before_state",
        "request_payload_redacted",
        "response",
        "authoritative_db_readback",
        "audit_history_or_typed_action_receipt",
    )
    for assertion_id in sorted((SAMPLED_ASSERTIONS - {"A26"}) & by_id.keys()):
        transaction = transactions.get(assertion_id)
        if not isinstance(transaction, dict):
            errors.append(f"{assertion_id} missing from AUD-001 machine transactions")
            continue
        for field in transaction_fields:
            if by_id[assertion_id].get(field) != transaction.get(field):
                errors.append(f"{assertion_id}.{field} does not match AUD-001 machine evidence")

    cleanup = machine.get("cleanup", {}) if isinstance(machine, dict) else {}
    ui_readback = machine.get("ui_readback", {}) if isinstance(machine, dict) else {}
    bounded_delete = cleanup.get("bounded_delete", {}) if isinstance(cleanup, dict) else {}
    relations = bounded_delete.get("relations", []) if isinstance(bounded_delete, dict) else []
    if cleanup.get("post_cleanup", {}).get("total") != 0:
        errors.append("AUD-001 cleanup post-cleanup total is not zero")
    if bounded_delete.get("deleted_total") != sum(item.get("count", 0) for item in relations if isinstance(item, dict)):
        errors.append("AUD-001 cleanup deleted_total does not match relation counts")
    if any(item.get("count", 0) > item.get("max_expected", -1) for item in relations if isinstance(item, dict)):
        errors.append("AUD-001 cleanup exceeded a manifest relation bound")
    if ui_readback.get("fixture_visible") is not True or ui_readback.get("snapshot_rpc", {}).get("fixture_present") is not True:
        errors.append("AUD-001 fixture-specific UI/snapshot read-back is not proven")
    if any(event.get("kind") in {"production_request", "pageerror"} for event in ui_readback.get("events", []) if isinstance(event, dict)):
        errors.append("AUD-001 browser evidence contains a production request or page error")
    if "A26" in by_id and isinstance(cleanup, dict):
        a26 = by_id["A26"]
        if a26.get("before_state") != cleanup.get("pre_cleanup"):
            errors.append("A26.before_state does not match pre-cleanup inventory")
        if a26.get("response") != bounded_delete:
            errors.append("A26.response does not match bounded cleanup result")
        if a26.get("rollback_cleanup_result") != cleanup:
            errors.append("A26.rollback_cleanup_result does not match machine cleanup evidence")

    summary = ledger.get("functional_summary", {})
    passed = sum(item.get("result") == "pass" for item in assertions if isinstance(item, dict))
    failed = sum(item.get("result") == "fail" for item in assertions if isinstance(item, dict))
    if summary.get("scored_assertions") != len(assertions):
        errors.append("functional_summary.scored_assertions does not match assertion count")
    if summary.get("passed") != passed:
        errors.append("functional_summary.passed does not match computed pass count")
    if summary.get("failed") != failed:
        errors.append("functional_summary.failed does not match computed fail count")
    expected_ratio = round(passed * 100 / len(assertions), 1) if assertions else 0.0
    if summary.get("pass_ratio_percent") != expected_ratio:
        errors.append("functional_summary.pass_ratio_percent does not match computed ratio")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate sampled overnight transaction evidence.")
    parser.add_argument("ledger", type=Path)
    parser.add_argument(
        "--evidence-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="Root against which evidence_paths are resolved",
    )
    args = parser.parse_args()
    errors = validate(args.ledger, args.evidence_root)
    if errors:
        print(json.dumps({"ok": False, "error_count": len(errors), "errors": errors}, indent=2))
        return 1
    print(json.dumps({"ok": True, "sampled_assertions": sorted(SAMPLED_ASSERTIONS)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
