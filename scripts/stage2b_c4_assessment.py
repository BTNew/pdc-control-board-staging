"""Stage 2B C4 deterministic, offline real-data readiness assessment.

Consumes only the narrow browser export produced by stage2b_c4_browser_export.js.
It has no browser, network or database code and writes only to an explicit local
output directory. Real assessment outputs are ignored by git.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import zipfile
from collections import defaultdict
from pathlib import Path

SCHEMA = "pdc.stage2b.c4-browser-assessment/v1"
SUMMARY_SCHEMA = "pdc.stage2b.c4-readiness-summary/v1"
MANIFEST_SCHEMA = "pdc.stage2b.c4-assessment-package/v1"
PLACEHOLDER_STOCKS = {
    "0", "TBA", "TBD", "UNKNOWN", "NA", "N/A", "NONE", "UNASSIGNED", "PENDING",
    "TEMP", "PLACEHOLDER", "TOBEALLOCATED", "UNALLOCATED", "AWAITINGSTOCK", "PENDINGALLOCATION",
}
TOP_KEYS = {
    "schema", "source_origin", "local_storage_sha256_before", "local_storage_sha256_after",
    "local_storage_unchanged", "families", "vehicles", "deleted_records", "notes",
    "parts_records", "workflow_records", "bookings", "parse_errors", "excluded_payloads",
    "assessment_export_sha256",
}
VEHICLE_KEYS = {
    "record_ref", "source_family", "legacy_vehicle_key", "stock_number", "vin",
    "job_card_number", "permanent_vehicle_id", "toyota_order_number", "legacy_id",
    "workflow_field_names", "parts_task_count", "parts_file_count",
}
FAMILY_KEYS = {
    "static_vehicle_count", "added_vehicle_count", "deleted_vehicle_count", "edit_row_count",
    "audit_row_count", "navision_import_present", "unknown_vehicle_storage_keys",
}
ROW_SCHEMAS = {
    "deleted_records": {"record_ref", "legacy_vehicle_key"},
    "notes": {"legacy_vehicle_key", "note_count"},
    "parts_records": {"family", "legacy_vehicle_key", "item_count"},
    "workflow_records": {"legacy_vehicle_key", "field_names"},
    "bookings": {"booking_ref", "legacy_vehicle_key", "stage_code"},
    "parse_errors": {"family", "reason_code"},
}
EXCLUDED_PAYLOADS = ["customer data", "note text", "Parts content", "file content", "audit details", "Navision payload"]
HEX64 = re.compile(r"[0-9a-f]{64}")
VIN = re.compile(r"[A-HJ-NPR-Z0-9]{17}")
CSV_COLUMNS = [
    "record_type", "record_ref", "legacy_vehicle_key", "stock_number", "vin",
    "job_card_number", "permanent_vehicle_id", "toyota_order_number",
    "classification", "reason_codes",
]


class C4AssessmentError(RuntimeError):
    pass


def canonical_json(value) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalize_identity(value) -> str | None:
    normalized = re.sub(r"[\s-]+", "", str(value or "").strip().upper())
    return normalized or None


def normalize_scoped(value) -> str | None:
    normalized = str(value or "").strip().upper()
    return normalized or None


def placeholder_stock(value) -> bool:
    raw = str(value or "").strip().upper()
    normalized = normalize_identity(value)
    return bool(normalized and (
        normalized in PLACEHOLDER_STOCKS
        or any(raw.startswith(prefix) for prefix in ("NEW-", "PD-", "PENDING-", "TEMP-"))
    ))


def valid_vin(value) -> bool:
    return bool(VIN.fullmatch(normalize_identity(value) or ""))


def _assert_hash(value, label):
    if not isinstance(value, str) or not HEX64.fullmatch(value):
        raise C4AssessmentError(f"{label} is not a SHA-256 value")


def validate_export(payload):
    if not isinstance(payload, dict) or set(payload) != TOP_KEYS or payload.get("schema") != SCHEMA:
        raise C4AssessmentError("assessment export schema is invalid")
    if payload.get("local_storage_unchanged") is not True:
        raise C4AssessmentError("assessment export did not prove unchanged localStorage")
    for key in ("local_storage_sha256_before", "local_storage_sha256_after", "assessment_export_sha256"):
        _assert_hash(payload.get(key), key)
    if payload["local_storage_sha256_before"] != payload["local_storage_sha256_after"]:
        raise C4AssessmentError("localStorage before/after checksums differ")
    for key in ("vehicles", "deleted_records", "notes", "parts_records", "workflow_records", "bookings", "parse_errors", "excluded_payloads"):
        if not isinstance(payload.get(key), list):
            raise C4AssessmentError(f"{key} must be an array")
    if not isinstance(payload.get("families"), dict) or set(payload["families"]) != FAMILY_KEYS:
        raise C4AssessmentError("families schema is invalid")
    if not isinstance(payload.get("source_origin"), str) or not re.fullmatch(r"https?://[^/@:]+(?::[0-9]{1,5})?", payload["source_origin"]):
        raise C4AssessmentError("source_origin is invalid")
    if payload["excluded_payloads"] != EXCLUDED_PAYLOADS:
        raise C4AssessmentError("excluded payload declaration is invalid")
    for count_key in ("static_vehicle_count", "added_vehicle_count", "deleted_vehicle_count", "edit_row_count", "audit_row_count"):
        value = payload["families"][count_key]
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise C4AssessmentError(f"family count is invalid: {count_key}")
    if not isinstance(payload["families"]["navision_import_present"], bool):
        raise C4AssessmentError("Navision presence flag is invalid")
    unknown_keys = payload["families"]["unknown_vehicle_storage_keys"]
    if not isinstance(unknown_keys, list) or unknown_keys != sorted(set(unknown_keys)) or not all(isinstance(value, str) for value in unknown_keys):
        raise C4AssessmentError("unknown storage-key inventory is invalid")
    for family, schema in ROW_SCHEMAS.items():
        for row in payload[family]:
            if not isinstance(row, dict) or set(row) != schema:
                raise C4AssessmentError(f"{family} row schema is invalid")
    for row in payload["notes"]:
        if not isinstance(row["note_count"], int) or isinstance(row["note_count"], bool) or row["note_count"] < 0:
            raise C4AssessmentError("note count is invalid")
    for row in payload["parts_records"]:
        if row["family"] not in {"po_tasks", "po_files"} or not isinstance(row["item_count"], int) or isinstance(row["item_count"], bool) or row["item_count"] < 0:
            raise C4AssessmentError("Parts row is invalid")
    for row in payload["workflow_records"]:
        if not isinstance(row["field_names"], list) or row["field_names"] != sorted(set(row["field_names"])) or not all(isinstance(value, str) for value in row["field_names"]):
            raise C4AssessmentError("workflow field inventory is invalid")
    refs = []
    for row in payload["vehicles"]:
        if not isinstance(row, dict) or set(row) != VEHICLE_KEYS:
            raise C4AssessmentError("vehicle assessment row schema is invalid")
        if not isinstance(row["record_ref"], str) or not row["record_ref"]:
            raise C4AssessmentError("vehicle record_ref is invalid")
        if not isinstance(row["workflow_field_names"], list):
            raise C4AssessmentError("workflow field list is invalid")
        for count_key in ("parts_task_count", "parts_file_count"):
            if not isinstance(row[count_key], int) or isinstance(row[count_key], bool) or row[count_key] < 0:
                raise C4AssessmentError("Parts count is invalid")
        refs.append(row["record_ref"])
    if len(refs) != len(set(refs)):
        raise C4AssessmentError("vehicle record_ref values are not unique")
    expected = dict(payload)
    checksum = expected.pop("assessment_export_sha256")
    if sha256_text(canonical_json(expected)) != checksum:
        raise C4AssessmentError("assessment export checksum is invalid")
    prohibited = {"customer", "client", "contact", "note_text", "file_content", "audit_details"}
    def walk(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key.lower() in prohibited:
                    raise C4AssessmentError(f"prohibited broad-data field: {key}")
                walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
    walk(payload)
    return payload


def _claim_rows(vehicles):
    specs = {
        "stock_number": normalize_identity,
        "vin": normalize_identity,
        "job_card_number": normalize_scoped,
        "permanent_vehicle_id": normalize_scoped,
        "toyota_order_number": normalize_scoped,
        "legacy_id": normalize_scoped,
    }
    owners = {name: defaultdict(list) for name in specs}
    normalized = {}
    for row in vehicles:
        normalized[row["record_ref"]] = {}
        for name, normalizer in specs.items():
            value = normalizer(row.get(name))
            normalized[row["record_ref"]][name] = value
            if value: owners[name][value].append(row["record_ref"])
    return normalized, owners


def assess_export(payload):
    payload = validate_export(payload)
    vehicles = sorted(payload["vehicles"], key=lambda row: row["record_ref"])
    normalized, owners = _claim_rows(vehicles)
    reasons = {row["record_ref"]: set() for row in vehicles}
    details = {
        "duplicate_normalized_stock_numbers": [],
        "duplicate_vins": [],
        "duplicate_job_card_numbers": [],
        "conflicting_canonical_identifiers": [],
    }
    duplicate_map = {
        "stock_number": ("duplicate_normalized_stock_number", "duplicate_normalized_stock_numbers"),
        "vin": ("duplicate_vin", "duplicate_vins"),
        "job_card_number": ("duplicate_job_card_number", "duplicate_job_card_numbers"),
    }
    for claim_type, (reason, bucket) in duplicate_map.items():
        for value, refs in sorted(owners[claim_type].items()):
            if len(refs) > 1:
                refs = sorted(refs)
                details[bucket].append({"normalized_value": value, "record_refs": refs})
                for ref in refs: reasons[ref].add(reason)
    for claim_type in ("permanent_vehicle_id", "toyota_order_number", "legacy_id"):
        for value, refs in sorted(owners[claim_type].items()):
            if len(refs) > 1:
                refs = sorted(refs)
                details["conflicting_canonical_identifiers"].append({
                    "claim_type": claim_type, "normalized_value": value, "record_refs": refs,
                })
                for ref in refs: reasons[ref].add(f"duplicate_{claim_type}")
    # A duplicated claim whose owners disagree on another populated canonical
    # claim is an explicit canonical conflict, not merely a duplicate warning.
    for claim_type in ("stock_number", "vin", "job_card_number", "permanent_vehicle_id", "toyota_order_number"):
        for value, refs in sorted(owners[claim_type].items()):
            if len(refs) < 2: continue
            for other in ("stock_number", "vin", "job_card_number", "permanent_vehicle_id", "toyota_order_number"):
                distinct = sorted({normalized[ref][other] for ref in refs if normalized[ref][other]})
                if len(distinct) > 1:
                    entry = {"claim_type": claim_type, "normalized_value": value, "disagrees_on": other, "record_refs": sorted(refs)}
                    if entry not in details["conflicting_canonical_identifiers"]:
                        details["conflicting_canonical_identifiers"].append(entry)
                    for ref in refs: reasons[ref].add("conflicting_canonical_identifiers")
    missing_fields = defaultdict(int)
    for row in vehicles:
        ref = row["record_ref"]
        values = normalized[ref]
        for field in ("stock_number", "vin", "job_card_number", "permanent_vehicle_id", "toyota_order_number"):
            if not values[field]: missing_fields[field] += 1
        if row.get("stock_number") and placeholder_stock(row["stock_number"]): reasons[ref].add("placeholder_stock")
        if row.get("vin") and not valid_vin(row["vin"]): reasons[ref].add("malformed_vin")
        canonical = [values[name] for name in ("stock_number", "vin", "job_card_number", "permanent_vehicle_id", "toyota_order_number") if values[name]]
        if not canonical: reasons[ref].add("missing_identity")
        unique_claims = 0
        for name in ("stock_number", "vin", "job_card_number", "permanent_vehicle_id", "toyota_order_number"):
            value = values[name]
            if value and len(owners[name][value]) == 1:
                if name != "stock_number" or not placeholder_stock(row.get("stock_number")):
                    if name != "vin" or valid_vin(row.get("vin")):
                        unique_claims += 1
        if canonical and unique_claims == 0 and not reasons[ref].intersection({"placeholder_stock", "malformed_vin"}):
            reasons[ref].add("cannot_match_deterministically")
    vehicle_keys = defaultdict(list)
    for row in vehicles:
        key = normalize_scoped(row.get("legacy_vehicle_key"))
        if key: vehicle_keys[key].append(row["record_ref"])
    orphan_counts = {"notes": 0, "parts": 0, "workflow": 0, "bookings": 0}
    ambiguous_link_counts = {"notes": 0, "parts": 0, "workflow": 0, "bookings": 0}
    manual_attachment_rows = []
    families = [
        ("notes", payload["notes"], "note", "note"),
        ("parts", payload["parts_records"], "parts", "parts"),
        ("workflow", payload["workflow_records"], "workflow", "workflow"),
        ("bookings", payload["bookings"], "booking", "booking"),
    ]
    for count_name, rows, record_type, prefix in families:
        for index, row in enumerate(rows):
            key = normalize_scoped(row.get("legacy_vehicle_key")) if isinstance(row, dict) else None
            matches = vehicle_keys.get(key, []) if key else []
            row_ref = str(row.get("booking_ref") or f"{prefix}:{index + 1:06d}") if isinstance(row, dict) else f"{prefix}:{index + 1:06d}"
            if not matches:
                orphan_counts[count_name] += 1
                manual_attachment_rows.append({"record_type": record_type, "record_ref": row_ref, "legacy_vehicle_key": row.get("legacy_vehicle_key") if isinstance(row, dict) else "", "classification": "invalid", "reason_codes": "orphan_vehicle_reference"})
            elif len(matches) > 1:
                ambiguous_link_counts[count_name] += 1
                manual_attachment_rows.append({"record_type": record_type, "record_ref": row_ref, "legacy_vehicle_key": row.get("legacy_vehicle_key") if isinstance(row, dict) else "", "classification": "ambiguous", "reason_codes": "ambiguous_vehicle_reference"})
                for ref in matches: reasons[ref].add("ambiguous_attached_record")
    classifications = {}
    manual_rows = []
    invalid_reasons = {"placeholder_stock", "malformed_vin", "missing_identity", "malformed_browser_family"}
    conflict_prefixes = ("duplicate_", "conflicting_")
    for row in vehicles:
        ref = row["record_ref"]
        row_reasons = sorted(reasons[ref])
        if any(reason.startswith(conflict_prefixes) for reason in row_reasons): classification = "conflicting"
        elif any(reason in invalid_reasons for reason in row_reasons): classification = "invalid"
        elif row_reasons: classification = "ambiguous"
        else: classification = "clean"
        classifications[ref] = classification
        if classification != "clean":
            manual_rows.append({
                "record_type": "vehicle", "record_ref": ref,
                "legacy_vehicle_key": row.get("legacy_vehicle_key") or "",
                "stock_number": row.get("stock_number") or "", "vin": row.get("vin") or "",
                "job_card_number": row.get("job_card_number") or "",
                "permanent_vehicle_id": row.get("permanent_vehicle_id") or "",
                "toyota_order_number": row.get("toyota_order_number") or "",
                "classification": classification, "reason_codes": ";".join(row_reasons),
            })
    for row in manual_attachment_rows:
        manual_rows.append({column: row.get(column, "") for column in CSV_COLUMNS})
    for index, row in enumerate(sorted(payload["parse_errors"], key=lambda item: (item["family"], item["reason_code"])), 1):
        manual_rows.append({column: value for column, value in zip(CSV_COLUMNS, [
            "parse_error", f"parse-error:{index:06d}", row["family"], "", "", "", "", "",
            "invalid", row["reason_code"],
        ])})
    manual_rows.sort(key=lambda row: (row["record_type"], row["record_ref"], row["reason_codes"]))
    counts = {name: list(classifications.values()).count(name) for name in ("clean", "conflicting", "ambiguous", "invalid")}
    issue_counts = {
        "clean": counts["clean"],
        "conflicting": sum(any(reason.startswith(conflict_prefixes) for reason in values) for values in reasons.values()),
        "ambiguous": sum(bool(values) and not any(reason.startswith(conflict_prefixes) for reason in values)
                         and not any(reason in invalid_reasons for reason in values) for values in reasons.values()),
        "invalid": sum(any(reason in invalid_reasons for reason in values) for values in reasons.values()),
    }
    summary = {
        "schema": SUMMARY_SCHEMA,
        "source_assessment_sha256": payload["assessment_export_sha256"],
        "source_local_storage_sha256": payload["local_storage_sha256_before"],
        "source_origin": payload.get("source_origin"),
        "total_vehicle_count": len(vehicles),
        "classification_counts": counts,
        "issue_record_counts": issue_counts,
        "missing_identity_field_counts": dict(sorted(missing_fields.items())),
        "placeholder_stock_record_count": sum(placeholder_stock(row.get("stock_number")) for row in vehicles if row.get("stock_number")),
        "malformed_vin_record_count": sum(bool(row.get("vin")) and not valid_vin(row.get("vin")) for row in vehicles),
        "duplicate_group_counts": {
            "stock_number": len(details["duplicate_normalized_stock_numbers"]),
            "vin": len(details["duplicate_vins"]),
            "job_card_number": len(details["duplicate_job_card_numbers"]),
            "canonical_conflict": len(details["conflicting_canonical_identifiers"]),
        },
        "orphan_record_counts": orphan_counts,
        "ambiguous_attachment_counts": ambiguous_link_counts,
        "cannot_match_deterministically_count": sum("cannot_match_deterministically" in values for values in reasons.values()),
        "manual_review_row_count": len(manual_rows),
        "parse_error_count": len(payload["parse_errors"]),
        "real_import_performed": False,
        "production_contacted": False,
    }
    summary["summary_sha256"] = sha256_text(canonical_json(summary))
    return summary, details, manual_rows


def render_report(summary, details):
    c = summary["issue_record_counts"]
    d = summary["duplicate_group_counts"]
    o = summary["orphan_record_counts"]
    a = summary["ambiguous_attachment_counts"]
    m = summary["missing_identity_field_counts"]
    return f"""# Stage 2B C4 — Real-Data Readiness Report

## Scope and safety

- Assessment only; no import or upload was performed.
- Browser-local storage was read without mutation; before/after SHA-256 values matched.
- Supabase staging and production were not contacted.
- Export is narrow: customer details, note text, file contents, audit details and full Navision payloads are excluded.

## Vehicle readiness

| Measure | Count |
|---|---:|
| Total vehicles | {summary['total_vehicle_count']} |
| Clean | {c['clean']} |
| Conflicting | {c['conflicting']} |
| Ambiguous | {c['ambiguous']} |
| Invalid | {c['invalid']} |
| Manual-review rows | {summary['manual_review_row_count']} |
| Cannot match deterministically | {summary['cannot_match_deterministically_count']} |

Issue counts may overlap: for example, a malformed VIN duplicated across records is both conflicting and invalid. `classification_counts` in the machine-readable summary provides the deterministic primary classification used by the CSV.

## Identity quality

| Measure | Count |
|---|---:|
| Duplicate normalized stock groups | {d['stock_number']} |
| Duplicate VIN groups | {d['vin']} |
| Duplicate job-card groups | {d['job_card_number']} |
| Conflicting canonical-identifier findings | {d['canonical_conflict']} |
| Placeholder stock records | {summary['placeholder_stock_record_count']} |
| Malformed VIN records | {summary['malformed_vin_record_count']} |
| Missing stock | {m.get('stock_number', 0)} |
| Missing VIN | {m.get('vin', 0)} |
| Missing job card | {m.get('job_card_number', 0)} |
| Missing permanent vehicle ID | {m.get('permanent_vehicle_id', 0)} |
| Missing Toyota order | {m.get('toyota_order_number', 0)} |

## Attached browser-local records

| Family | Orphan | Ambiguous link |
|---|---:|---:|
| Notes | {o['notes']} | {a['notes']} |
| Parts | {o['parts']} | {a['parts']} |
| Workflow | {o['workflow']} | {a['workflow']} |
| Bookings | {o['bookings']} | {a['bookings']} |

## Deterministic evidence

- Source assessment SHA-256: `{summary['source_assessment_sha256']}`
- Browser-local snapshot SHA-256: `{summary['source_local_storage_sha256']}`
- Summary SHA-256: `{summary['summary_sha256']}`
- Parse errors: `{summary['parse_error_count']}`

Every non-clean vehicle and every orphan/ambiguous attached record is listed in `STAGE-2B-C4-MANUAL-REVIEW-LIST.csv`. Duplicate values and record references are retained in the package's narrow `assessment-summary.json`; broad customer and operational payloads are not retained.
"""


def render_import_plan(summary):
    c = summary["issue_record_counts"]
    return f"""# Stage 2B C4 — Import Plan

## Current gate

**NOT APPROVED FOR REAL IMPORT.** Readiness assessment found {c['conflicting']} conflicting, {c['ambiguous']} ambiguous and {c['invalid']} invalid vehicle records. C4 performs no import.

## Required dry-run preview

1. Resolve every row in the manual-review CSV and produce a signed-off resolution ledger.
2. Generate a fresh migration-031 typed reference artifact from the exact approved staging project identified by the existing guarded C3 configuration.
3. Run migration-029 preview only, in staging, against deterministic batches. Persist request IDs, source checksums, expected versions, actions and refusal reasons.
4. Re-run the same preview and require byte-identical actions and checksum before approval.

## Approval gates

- Gate A — data owner: manual conflicts, ambiguous links, placeholders and malformed identities resolved.
- Gate B — technical: deterministic preview, zero unresolved conflicts, exact project guard, credential scan and independent review pass.
- Gate C — explicit execution approval: a separate preview showing exact counts/actions/checksum and rollback revision. Approval expires if input, artifact revision, quote, environment or preview changes.
- No approval is implied by this document.

## Backup requirements

- Fresh encrypted backup immediately before any staging apply.
- Verify checksum, migration ledger and isolated-schema restore; then drop temporary schema/role.
- Record baseline counts for vehicles, identifiers, aliases, source evidence, history, audit, receipts and bookings.

## Manual conflict resolution

- Never choose a winner by row order or fuzzy matching.
- Resolve duplicate stock/VIN/job-card and cross-identifier ownership against the source system of record.
- Give every decision an owner, reason, date and immutable source-record reference.
- Invalid or unresolved records remain excluded; attached orphan data is never silently discarded.

## Staged batch sizes

- Pilot: 10 clean records.
- Verification batch: 25 clean records.
- Subsequent batches: maximum 50 clean records, reduced after any conflict or retry.
- Stop on any stale version, ambiguity, unexpected action, receipt mismatch or reconciliation variance.

## Rollback

- Staging/test only, disabled by default, explicit and revision-locked.
- Refuse stale artifacts/revisions. Export affected rows and receipts before rollback.
- After rollback, reconcile against backup baseline and require zero residue.

## Post-import reconciliation

- Re-export migration-031 references after each batch.
- Compare every source record to canonical UUID, matched claim type, expected/actual version, action and deterministic reason.
- Require exact receipt replay after simulated response loss and zero unresolved conflict/orphan drift.

## Browser-local fallback and authority cutover

Browser-local authority may remain a read-only fallback while any manual-review row, unmatched attachment, reconciliation variance, stale-version failure or rollback uncertainty remains. It must not be cleared.

Authority cutover may be proposed only after all approved batches reconcile exactly; zero unresolved conflicts/orphans remain; backup/restore and rollback are proven; a sustained read-only comparison window passes; browser-local fallback export is retained; and a separate reviewed approval explicitly authorizes cutover. C4 does not authorize cutover or direct-SELECT retirement.
"""


def csv_bytes(rows):
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=CSV_COLUMNS, lineterminator="\n")
    writer.writeheader()
    for row in rows: writer.writerow({key: row.get(key, "") for key in CSV_COLUMNS})
    return stream.getvalue().encode("utf-8")


def build_package(payload, output_dir: Path):
    summary, details, manual_rows = assess_export(payload)
    output_dir.mkdir(parents=True, exist_ok=True)
    assessment = {
        "summary": summary,
        "duplicate_findings": details,
        "browser_family_inventory": payload["families"],
        "parse_errors": payload["parse_errors"],
    }
    files = {
        "STAGE-2B-C4-SANITIZED-ASSESSMENT.json": (canonical_json(payload) + "\n").encode("utf-8"),
        "STAGE-2B-C4-REAL-DATA-READINESS-REPORT.md": render_report(summary, details).encode("utf-8"),
        "STAGE-2B-C4-MANUAL-REVIEW-LIST.csv": csv_bytes(manual_rows),
        "STAGE-2B-C4-IMPORT-PLAN.md": render_import_plan(summary).encode("utf-8"),
        "assessment-summary.json": (json.dumps(assessment, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8"),
    }
    checksums = {name: sha256_bytes(data) for name, data in sorted(files.items())}
    manifest = {
        "schema": MANIFEST_SCHEMA,
        "source_assessment_sha256": payload["assessment_export_sha256"],
        "summary_sha256": summary["summary_sha256"],
        "files": [{"path": name, "size": len(files[name]), "sha256": checksums[name]} for name in sorted(files)],
        "real_import_performed": False,
        "production_contacted": False,
    }
    files["manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
    files["SHA256SUMS.txt"] = "".join(f"{sha256_bytes(files[name])}  {name}\n" for name in sorted(files)).encode("utf-8")
    for name, data in files.items(): (output_dir / name).write_bytes(data)
    zip_name = f"PDC-Stage2B-C4-Real-Data-Readiness-{summary['summary_sha256'][:12]}.zip"
    zip_path = output_dir / zip_name
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, files[name])
    return {"summary": summary, "zip_path": str(zip_path.resolve()), "zip_size": zip_path.stat().st_size, "zip_sha256": sha256_bytes(zip_path.read_bytes())}


def verify_package(zip_path: Path):
    if not zip_path.is_file(): raise C4AssessmentError("assessment ZIP does not exist")
    with zipfile.ZipFile(zip_path) as archive:
        names = archive.namelist()
        expected = sorted([
            "SHA256SUMS.txt", "STAGE-2B-C4-IMPORT-PLAN.md", "STAGE-2B-C4-MANUAL-REVIEW-LIST.csv",
            "STAGE-2B-C4-REAL-DATA-READINESS-REPORT.md", "STAGE-2B-C4-SANITIZED-ASSESSMENT.json",
            "assessment-summary.json", "manifest.json",
        ])
        if names != expected: raise C4AssessmentError("assessment ZIP member set/order is invalid")
        data = {name: archive.read(name) for name in names}
    manifest = json.loads(data["manifest.json"])
    if manifest.get("schema") != MANIFEST_SCHEMA or manifest.get("real_import_performed") is not False or manifest.get("production_contacted") is not False:
        raise C4AssessmentError("assessment package manifest is invalid")
    listed = {row["path"]: row for row in manifest.get("files", [])}
    for name in expected:
        if name in {"manifest.json", "SHA256SUMS.txt"}: continue
        row = listed.get(name)
        if not row or row.get("size") != len(data[name]) or row.get("sha256") != sha256_bytes(data[name]):
            raise C4AssessmentError(f"manifest mismatch for {name}")
    expected_sums = "".join(f"{sha256_bytes(data[name])}  {name}\n" for name in sorted(data) if name != "SHA256SUMS.txt").encode("utf-8")
    if data["SHA256SUMS.txt"] != expected_sums: raise C4AssessmentError("SHA256SUMS.txt is invalid")
    source_payload = json.loads(data["STAGE-2B-C4-SANITIZED-ASSESSMENT.json"])
    recomputed_summary, recomputed_details, recomputed_rows = assess_export(source_payload)
    packaged_assessment = json.loads(data["assessment-summary.json"])
    if packaged_assessment != {
        "summary": recomputed_summary,
        "duplicate_findings": recomputed_details,
        "browser_family_inventory": source_payload["families"],
        "parse_errors": source_payload["parse_errors"],
    }:
        raise C4AssessmentError("assessment summary does not recompute from sanitized input")
    if data["STAGE-2B-C4-MANUAL-REVIEW-LIST.csv"] != csv_bytes(recomputed_rows):
        raise C4AssessmentError("manual-review CSV does not recompute from sanitized input")
    if data["STAGE-2B-C4-REAL-DATA-READINESS-REPORT.md"] != render_report(recomputed_summary, recomputed_details).encode("utf-8"):
        raise C4AssessmentError("readiness report does not recompute from sanitized input")
    return {"zip_size": zip_path.stat().st_size, "zip_sha256": sha256_bytes(zip_path.read_bytes())}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--verify-zip", type=Path)
    args = parser.parse_args()
    if args.verify_zip:
        print(json.dumps(verify_package(args.verify_zip), sort_keys=True)); return
    if not args.input or not args.output_dir: parser.error("--input and --output-dir are required")
    payload = json.loads(args.input.read_text(encoding="utf-8"))
    print(json.dumps(build_package(payload, args.output_dir), sort_keys=True))


if __name__ == "__main__":
    main()
