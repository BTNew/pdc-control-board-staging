"""Deterministic, narrow reconciliation for the Stage 2B C3 synthetic pilot.

This module is intentionally offline and portable. It consumes only the typed
migration-031 vehicle-reference artifact plus narrow synthetic legacy claims and
operation evidence. It never opens a database connection or reads browser state.
"""
from __future__ import annotations

import hashlib
import json
import re
from copy import deepcopy

from workshop_vehicle_reference_artifact import (
    VehicleReferenceArtifactError,
    validate_vehicle_reference_artifact,
)

REPORT_SCHEMA_VERSION = "pdc.stage2b.vehicle-reconciliation/v1"
SYNTHETIC_SOURCE_SYSTEM = "stage2b_c3_synthetic_pilot"
MAX_SAFE_INTEGER = 2**53 - 1
ALLOWED_OUTCOMES = {
    "matched", "created", "unchanged", "updated", "missing_in_shared",
    "missing_in_legacy", "ambiguous", "conflict", "stale_version",
    "invalid_source", "manual_review_required",
}
REPORT_RESULT_KEYS = {
    "scenario_id", "outcome", "vehicle_id", "source_system",
    "source_record_id", "matched_claim_type", "expected_version",
    "actual_version", "reason_code",
}
SCOPED_TYPES = {"job_card_number", "toyota_order_number", "source_record_id"}
CLAIM_TYPES = {
    "stock_number", "vin", "job_card_number", "permanent_vehicle_id",
    "toyota_order_number", "source_record_id",
}
PLACEHOLDER_STOCKS = {"0", "TBA", "TBD", "UNKNOWN", "NA", "N/A", "NONE", "UNASSIGNED"}
OPERATION_EVIDENCE_KEYS = {
    "scenario_id", "source_system", "source_record_id", "operation_fingerprint",
    "code", "action", "vehicle_id", "actual_version",
}
OPERATION_CODES = {
    "stale_version", "optimistic_version_mismatch", "ambiguous_match",
    "duplicate_normalized_claim", "conflicting_match", "canonical_alias_conflict",
    "canonical_source_evidence_conflict", "unlinked_source_evidence",
}
OPERATION_ACTIONS = {"insert", "update", "no_change"}


class C3ReconciliationError(RuntimeError):
    pass


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _canonical_bytes(value):
    return canonical_json(value).encode("utf-8")


def operation_fingerprint(record):
    logical = {
        "scenario_id": str(record.get("id") or record.get("scenario_id") or ""),
        "source_system": normalize_source(record.get("source_system")),
        "source_record_id": normalize_source_identifier(record.get("source_record_id")),
        "payload": record.get("payload") or {},
        "expected_version": record.get("expected_version"),
    }
    return hashlib.sha256(_canonical_bytes(logical)).hexdigest()


def build_operation_evidence(record, *, code=None, action=None, vehicle_id=None, actual_version=None):
    evidence = {
        "scenario_id": str(record.get("id") or record.get("scenario_id") or ""),
        "source_system": normalize_source(record.get("source_system")),
        "source_record_id": normalize_source_identifier(record.get("source_record_id")),
        "operation_fingerprint": operation_fingerprint(record),
        "code": code,
        "action": action,
        "vehicle_id": vehicle_id,
        "actual_version": actual_version,
    }
    return evidence


def _validate_operation_evidence(record, operation, candidate_ids, items):
    if not operation:
        return
    if not isinstance(operation, dict) or set(operation) != OPERATION_EVIDENCE_KEYS:
        raise C3ReconciliationError("operation evidence schema is invalid")
    expected = build_operation_evidence(record)
    for key in ("scenario_id", "source_system", "source_record_id", "operation_fingerprint"):
        if operation.get(key) != expected[key]:
            raise C3ReconciliationError("operation evidence is not bound to its source record")
    code, action = operation.get("code"), operation.get("action")
    if (code is None) == (action is None):
        raise C3ReconciliationError("operation evidence must contain exactly one result kind")
    if code is not None and code not in OPERATION_CODES:
        raise C3ReconciliationError("operation evidence code is invalid")
    if action is not None and action not in OPERATION_ACTIONS:
        raise C3ReconciliationError("operation evidence action is invalid")
    vehicle_id, actual_version = operation.get("vehicle_id"), operation.get("actual_version")
    if actual_version is not None and (not isinstance(actual_version, int) or isinstance(actual_version, bool)
                                       or actual_version < 1 or actual_version > MAX_SAFE_INTEGER):
        raise C3ReconciliationError("operation evidence version is invalid")
    if vehicle_id is not None:
        if vehicle_id not in items or vehicle_id not in candidate_ids:
            raise C3ReconciliationError("operation evidence vehicle is not an artifact candidate")
    if action is not None and (vehicle_id is None or actual_version is not None):
        raise C3ReconciliationError("successful operation evidence is invalid")
    if code in {"stale_version", "optimistic_version_mismatch"}:
        if vehicle_id is None or actual_version != items[vehicle_id]["version"]:
            raise C3ReconciliationError("stale operation evidence does not match the artifact")
    elif code in {"ambiguous_match", "duplicate_normalized_claim", "conflicting_match",
                  "canonical_alias_conflict", "canonical_source_evidence_conflict"}:
        if vehicle_id is not None or actual_version is not None or len(candidate_ids) < 2:
            raise C3ReconciliationError("conflict operation evidence is not supported by artifact candidates")
    elif code == "unlinked_source_evidence":
        if vehicle_id is not None or actual_version is not None or candidate_ids:
            raise C3ReconciliationError("unlinked operation evidence conflicts with the artifact")


def normalize_source(value):
    normalized = str(value or "").strip().lower()
    return normalized or None


def normalize_source_identifier(value):
    normalized = str(value or "").strip().upper()
    return normalized or None


def normalize_stock(value):
    normalized = re.sub(r"[\s-]+", "", str(value or "").strip().upper())
    return normalized or None


def normalize_vin(value):
    return normalize_stock(value)


def is_real_stock(value):
    raw = str(value or "").strip().upper()
    normalized = normalize_stock(value)
    return bool(normalized and normalized not in PLACEHOLDER_STOCKS and not any(
        raw.startswith(prefix) for prefix in ("NEW-", "PD-", "PENDING-", "TEMP-")
    ))


def is_valid_vin(value):
    return bool(re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", normalize_vin(value) or ""))


def assert_exact_staging_project_ref(project_ref):
    if str(project_ref or "").strip() != "cdsmnqxtyyoeoznmbidd":
        raise C3ReconciliationError("refusing C3 execution outside exact guarded staging project")
    return True


def _claim(identifier_type, value, source_system):
    if identifier_type == "stock_number":
        normalized = normalize_stock(value)
    elif identifier_type == "vin":
        normalized = normalize_vin(value)
    else:
        normalized = normalize_source_identifier(value)
    return (identifier_type, normalize_source(source_system) if identifier_type in SCOPED_TYPES else "", normalized)


def legacy_claims(record):
    payload = record.get("payload") or {}
    claims = []
    stock = payload.get("stock_number")
    vin = payload.get("vin")
    if stock is not None and is_real_stock(stock):
        claims.append(_claim("stock_number", stock, None))
    if vin is not None and is_valid_vin(vin):
        claims.append(_claim("vin", vin, None))
    for identifier_type in ("job_card_number", "permanent_vehicle_id", "toyota_order_number"):
        if payload.get(identifier_type):
            claims.append(_claim(identifier_type, payload[identifier_type], record.get("source_system")))
    if record.get("include_source_record_claim", True) and record.get("source_record_id"):
        claims.append(_claim("source_record_id", record["source_record_id"], record.get("source_system")))
    return [row for row in claims if row[2]]


def _invalid_record_reason(record):
    if normalize_source(record.get("source_system")) != SYNTHETIC_SOURCE_SYSTEM:
        return "invalid_source_namespace"
    if not normalize_source_identifier(record.get("source_record_id")):
        return "missing_source_record_id"
    payload = record.get("payload")
    if not isinstance(payload, dict):
        return "malformed_payload"
    if payload.get("vin") is not None and not is_valid_vin(payload.get("vin")):
        return "malformed_vin"
    if payload.get("stock_number") is not None and not is_real_stock(payload.get("stock_number")):
        return "placeholder_stock"
    identity_payload = any(payload.get(key) for key in (
        "stock_number", "vin", "job_card_number", "permanent_vehicle_id", "toyota_order_number"
    ))
    if not identity_payload and record.get("allow_source_evidence_only") is not True:
        return "missing_identity"
    return None


def _artifact_index(artifact):
    owners = {}
    items = {}
    evidence = {}
    for item in artifact["items"]:
        items[item["vehicle_id"]] = item
        for claim in item["identifiers"]:
            key = (
                claim["identifier_type"],
                claim.get("source_system") or "",
                claim["normalized_value"],
            )
            owners.setdefault(key, set()).add(item["vehicle_id"])
            evidence.setdefault((key, item["vehicle_id"]), set()).add(claim["origin"])
    conflict_classes = {
        (row["identifier_type"], row.get("source_system") or "", row["normalized_value"]): row["classification"]
        for row in artifact["conflicts"]
    }
    return owners, items, evidence, conflict_classes


def _result(record, outcome, reason_code, *, vehicle_id=None, matched_claim_type=None,
            expected_version=None, actual_version=None):
    row = {
        "scenario_id": str(record.get("id") or record.get("scenario_id") or ""),
        "outcome": outcome,
        "vehicle_id": vehicle_id,
        "source_system": normalize_source(record.get("source_system")),
        "source_record_id": normalize_source_identifier(record.get("source_record_id")),
        "matched_claim_type": matched_claim_type,
        "expected_version": expected_version,
        "actual_version": actual_version,
        "reason_code": reason_code,
    }
    if set(row) != REPORT_RESULT_KEYS or outcome not in ALLOWED_OUTCOMES:
        raise C3ReconciliationError("invalid reconciliation result")
    return row


def build_reconciliation_report(*, artifact, legacy_records, operation_results,
                                actual_vehicle_fields=None, expected_resolver_revision,
                                source_system=SYNTHETIC_SOURCE_SYSTEM):
    if normalize_source(source_system) != SYNTHETIC_SOURCE_SYSTEM:
        raise C3ReconciliationError("C3 reconciliation source namespace is not synthetic")
    try:
        artifact = validate_vehicle_reference_artifact(
            deepcopy(artifact), expected_resolver_revision=expected_resolver_revision,
        )
    except VehicleReferenceArtifactError:
        raise
    if not isinstance(legacy_records, list) or not isinstance(operation_results, dict):
        raise C3ReconciliationError("legacy records and operation results are required")
    legacy_ids = [str(record.get("id") or record.get("scenario_id") or "")
                  for record in legacy_records if isinstance(record, dict)]
    if len(legacy_ids) != len(legacy_records) or len(set(legacy_ids)) != len(legacy_ids) or not all(legacy_ids):
        raise C3ReconciliationError("legacy record identities are invalid")
    if not set(operation_results).issubset(set(legacy_ids)):
        raise C3ReconciliationError("operation evidence contains an unknown scenario")
    actual_vehicle_fields = actual_vehicle_fields or {}
    owners, items, evidence, conflict_classes = _artifact_index(artifact)
    results = []
    referenced_vehicle_ids = set()

    for record in legacy_records:
        invalid_reason = _invalid_record_reason(record)
        if invalid_reason:
            results.append(_result(record, "invalid_source", invalid_reason))
            continue

        operation = operation_results.get(record.get("id"), {})
        # Even a refused conflict/ambiguity still proves that the legacy row
        # references those shared candidates. Mark them so they are not later
        # misreported as missing from the legacy source.
        operation_candidates = set()
        for operation_claim in legacy_claims(record):
            operation_candidates.update(owners.get(operation_claim, set()))
        _validate_operation_evidence(record, operation, operation_candidates, items)
        referenced_vehicle_ids.update(operation_candidates)
        if operation.get("vehicle_id") in items:
            referenced_vehicle_ids.add(operation["vehicle_id"])
        code = operation.get("code")
        if code in {"stale_version", "optimistic_version_mismatch"}:
            results.append(_result(
                record, "stale_version", "optimistic_version_mismatch",
                vehicle_id=operation.get("vehicle_id"),
                expected_version=record.get("expected_version"),
                actual_version=operation.get("actual_version"),
            ))
            continue
        if code in {"ambiguous_match", "duplicate_normalized_claim"}:
            results.append(_result(record, "ambiguous", code))
            continue
        if code in {"conflicting_match", "canonical_alias_conflict", "canonical_source_evidence_conflict"}:
            results.append(_result(record, "conflict", code))
            continue
        if code == "unlinked_source_evidence":
            results.append(_result(record, "missing_in_shared", "deleted_retained_source_evidence"))
            continue

        candidate_ids = set()
        matched_claims = []
        duplicate_claim = None
        conflict_class = None
        for claim in legacy_claims(record):
            ids = owners.get(claim, set())
            if len(ids) > 1:
                duplicate_claim = claim[0]
                conflict_class = conflict_classes.get(claim)
            if ids:
                candidate_ids.update(ids)
                matched_claims.append((claim, ids))
        if duplicate_claim:
            outcome = "conflict" if conflict_class in {"canonical_alias_conflict", "canonical_source_evidence_conflict"} else "ambiguous"
            results.append(_result(record, outcome, conflict_class or "duplicate_normalized_claim", matched_claim_type=duplicate_claim))
            continue
        if len(candidate_ids) > 1:
            results.append(_result(record, "conflict", "conflicting_match"))
            continue
        if not candidate_ids:
            results.append(_result(record, "missing_in_shared", "no_shared_identity_match"))
            continue

        vehicle_id = next(iter(candidate_ids))
        referenced_vehicle_ids.add(vehicle_id)
        item = items[vehicle_id]
        expected_version = record.get("expected_version")
        actual_version = item["version"]
        matched_claim_type = next((claim[0] for claim, ids in matched_claims if vehicle_id in ids), None)
        if item["is_archived"]:
            results.append(_result(
                record, "manual_review_required", "archived_vehicle",
                vehicle_id=vehicle_id, matched_claim_type=matched_claim_type,
                expected_version=expected_version, actual_version=actual_version,
            ))
            continue
        if expected_version is not None and expected_version != actual_version:
            results.append(_result(
                record, "stale_version", "optimistic_version_mismatch",
                vehicle_id=vehicle_id, matched_claim_type=matched_claim_type,
                expected_version=expected_version, actual_version=actual_version,
            ))
            continue
        desired = record.get("desired_fields") or {}
        actual = actual_vehicle_fields.get(vehicle_id, {})
        if any(actual.get(key) != value for key, value in desired.items()):
            results.append(_result(
                record, "manual_review_required", "manual_edit_divergence",
                vehicle_id=vehicle_id, matched_claim_type=matched_claim_type,
                expected_version=expected_version, actual_version=actual_version,
            ))
            continue

        action = operation.get("action")
        if action == "insert":
            outcome, reason = "created", "import_inserted"
        elif action == "update":
            outcome, reason = "updated", "import_updated"
        elif action == "no_change":
            outcome, reason = "unchanged", "no_change"
        elif (matched_claim_type == "source_record_id" and
              "source_evidence" in evidence.get((next(claim for claim, ids in matched_claims if vehicle_id in ids), vehicle_id), set())):
            outcome, reason = "matched", "source_evidence_match"
        elif "alias" in evidence.get((next(claim for claim, ids in matched_claims if vehicle_id in ids), vehicle_id), set()):
            outcome, reason = "matched", "alias_match"
        elif "source_evidence" in evidence.get((next(claim for claim, ids in matched_claims if vehicle_id in ids), vehicle_id), set()):
            outcome, reason = "matched", "source_evidence_match"
        else:
            outcome, reason = "unchanged", "no_change"
        results.append(_result(
            record, outcome, reason, vehicle_id=vehicle_id,
            matched_claim_type=matched_claim_type, expected_version=expected_version,
            actual_version=actual_version,
        ))

    for item in artifact["items"]:
        if item["vehicle_id"] in referenced_vehicle_ids:
            continue
        source_claim = next((claim for claim in item["identifiers"]
                             if claim["identifier_type"] == "source_record_id"
                             and claim.get("source_system") == SYNTHETIC_SOURCE_SYSTEM), None)
        if not source_claim:
            continue
        synthetic_record = {
            "id": f"missing-in-legacy:{item['vehicle_id']}",
            "source_system": SYNTHETIC_SOURCE_SYSTEM,
            "source_record_id": source_claim["value"],
        }
        results.append(_result(
            synthetic_record, "missing_in_legacy", "shared_record_has_no_legacy_source",
            vehicle_id=item["vehicle_id"], matched_claim_type="source_record_id",
            actual_version=item["version"],
        ))

    results.sort(key=_canonical_bytes)
    logical = {
        "schema_version": REPORT_SCHEMA_VERSION,
        "resolver_revision": expected_resolver_revision,
        "source_system": SYNTHETIC_SOURCE_SYSTEM,
        "result_count": len(results),
        "results": results,
    }
    return {**logical, "checksum": {"algorithm": "sha256", "value": hashlib.sha256(_canonical_bytes(logical)).hexdigest()}}


def validate_reconciliation_report(report):
    required = {"schema_version", "resolver_revision", "source_system", "result_count", "results", "checksum"}
    if not isinstance(report, dict) or set(report) != required:
        raise C3ReconciliationError("reconciliation report schema is invalid")
    if report["schema_version"] != REPORT_SCHEMA_VERSION or report["source_system"] != SYNTHETIC_SOURCE_SYSTEM:
        raise C3ReconciliationError("reconciliation report identity is invalid")
    if isinstance(report["resolver_revision"], bool) or not isinstance(report["resolver_revision"], int) or not 0 <= report["resolver_revision"] <= MAX_SAFE_INTEGER:
        raise C3ReconciliationError("reconciliation resolver revision is invalid")
    if not isinstance(report["results"], list) or report["result_count"] != len(report["results"]):
        raise C3ReconciliationError("reconciliation result count is invalid")
    if report["results"] != sorted(report["results"], key=_canonical_bytes):
        raise C3ReconciliationError("reconciliation results are not canonically ordered")
    for row in report["results"]:
        if not isinstance(row, dict) or set(row) != REPORT_RESULT_KEYS or row.get("outcome") not in ALLOWED_OUTCOMES:
            raise C3ReconciliationError("reconciliation result row is invalid")
        if row.get("source_system") != SYNTHETIC_SOURCE_SYSTEM:
            raise C3ReconciliationError("reconciliation result escaped synthetic namespace")
    checksum = report.get("checksum")
    if not isinstance(checksum, dict) or set(checksum) != {"algorithm", "value"} or checksum.get("algorithm") != "sha256":
        raise C3ReconciliationError("reconciliation checksum metadata is invalid")
    logical = {key: report[key] for key in ("schema_version", "resolver_revision", "source_system", "result_count", "results")}
    expected = hashlib.sha256(_canonical_bytes(logical)).hexdigest()
    if checksum.get("value") != expected:
        raise C3ReconciliationError("reconciliation checksum mismatch")
    return deepcopy(report)
