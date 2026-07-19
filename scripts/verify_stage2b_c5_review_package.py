#!/usr/bin/env python3
"""Verify a focused Stage 2B C5 review extraction and optional source ZIP."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SCHEMA = "pdc.stage2b.c5-review-package/v1"
EXPECTED_BRANCH = "feature/stage2b-shared-vehicle-master"
EXPECTED_BASELINE = "1a73e3a1d1bf6c3abd2b8a349e2f1c2e0f7490ac"
MANIFEST_KEYS = {"schema_version", "source_branch", "source_head", "baseline_head", "migration_032_required", "migration_inventory", "files"}
EVIDENCE_PREFIX = "review-evidence/stage2b-c5/"
REQUIRED_FILES = {
    "STAGE-2B-C5-CONTROLLED-STAGING-PILOT.md",
    "scripts/stage2b_c5_real_data_pilot.py",
    "scripts/build_stage2b_c5_review_package.py",
    "scripts/verify_stage2b_c5_review_package.py",
    "backend/test_stage2b_c5_real_data_pilot.py",
    "scripts/stage2b_c4_assessment.py",
    "scripts/workshop_legacy_import.py",
    "scripts/workshop_vehicle_reference_artifact.py",
    "scripts/workshop_planner_legacy_validate.js",
    "scripts/pdc_backup.py", "scripts/pdc_restore.py",
    "supabase/migrations/028_stage2b_vehicle_master_foundation.sql",
    "supabase/migrations/029_stage2b_vehicle_master_operations.sql",
    "supabase/migrations/030_stage2b_lifecycle_identity_resolver.sql",
    "supabase/migrations/031_stage2b_importer_identity_export.sql",
    EVIDENCE_PREFIX + "selected-record-manifest.json",
    EVIDENCE_PREFIX + "approval-manifest.md",
    EVIDENCE_PREFIX + "preview-result.json",
    EVIDENCE_PREFIX + "apply-result.json",
    EVIDENCE_PREFIX + "replay-evidence.json",
    EVIDENCE_PREFIX + "reconciliation-report.json",
    EVIDENCE_PREFIX + "rollback-export.json",
    EVIDENCE_PREFIX + "rollback-report.json",
    EVIDENCE_PREFIX + "before-after-row-counts.json",
    EVIDENCE_PREFIX + "backup-restore-evidence.json",
    EVIDENCE_PREFIX + "safety.json",
    EVIDENCE_PREFIX + "pilot-summary.json",
    EVIDENCE_PREFIX + "operational-proof.json",
    EVIDENCE_PREFIX + "approved-c4-sanitized-assessment.json",
    EVIDENCE_PREFIX + "approved-c4-package.zip",
}
APPROVED_C4_SHA256 = "980bab0cc0bf79a8156fb78b2587df165406d3fd7d92929468fda66e2ba81016"
C4_PACKAGE_PATH = EVIDENCE_PREFIX + "approved-c4-package.zip"
CREDENTIAL_PATTERNS = (
    re.compile(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}"),
    re.compile(r"-----BEGIN [A-Z ]+PRIVATE KEY-----"),
    re.compile(r"(?i)sb_secret_[a-z0-9_-]{16,}"),
)
SAFE_TEST_PASSWORDS = {"unused", "pass", "redacted", "must-not-leak", "***"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_relative(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or "\\" in value or path.as_posix() != value:
        raise SystemExit(f"unsafe package path: {value}")
    return path


def scan_text(relative: str, text: str) -> None:
    for pattern in CREDENTIAL_PATTERNS:
        if pattern.search(text):
            raise SystemExit(f"credential-like content: {relative}")
    for match in re.finditer(r"postgres(?:ql)?://[^\s\"']+", text, flags=re.IGNORECASE):
        raw = match.group(0).rstrip(")],;}")
        parsed = urlparse(raw)
        if parsed.password not in SAFE_TEST_PASSWORDS and "must-not-leak" not in raw:
            raise SystemExit(f"credential-bearing database URL: {relative}")
    if relative.startswith(EVIDENCE_PREFIX):
        lowered = text.lower()
        forbidden = ("postgres://", "postgresql://", "password", "database_url", "service_role",
                     "customer_email", "note_text", "file_content", "audit_details")
        if not relative.endswith("operational-proof.json"):
            forbidden += ("customer_name",)
        hits = [value for value in forbidden if value in lowered]
        if hits:
            raise SystemExit(f"prohibited evidence content in {relative}: {hits}")
        if relative.endswith("operational-proof.json"):
            parsed = json.loads(text)
            def has_non_null_customer(value):
                if isinstance(value, dict):
                    return any((key == "customer_name" and child is not None) or has_non_null_customer(child)
                               for key, child in value.items())
                if isinstance(value, list):
                    return any(has_non_null_customer(child) for child in value)
                return False
            if has_non_null_customer(parsed):
                raise SystemExit("operational proof contains customer data")


def evidence_json(relative):
    return json.loads((ROOT / EVIDENCE_PREFIX / relative).read_text(encoding="utf-8"))


def verify_semantics():
    selected = evidence_json("selected-record-manifest.json")
    preview = evidence_json("preview-result.json")
    applied = evidence_json("apply-result.json")
    replay = evidence_json("replay-evidence.json")
    recon = evidence_json("reconciliation-report.json")
    rollback_export = evidence_json("rollback-export.json")
    rollback = evidence_json("rollback-report.json")
    counts = evidence_json("before-after-row-counts.json")
    backup = evidence_json("backup-restore-evidence.json")
    safety = evidence_json("safety.json")
    summary = evidence_json("pilot-summary.json")
    proof = evidence_json("operational-proof.json")
    c4_payload = evidence_json("approved-c4-sanitized-assessment.json")
    with zipfile.ZipFile(ROOT / C4_PACKAGE_PATH) as c4_archive:
        c4_member = json.loads(c4_archive.read("STAGE-2B-C4-SANITIZED-ASSESSMENT.json"))
    if sha256((ROOT / C4_PACKAGE_PATH).read_bytes()) != APPROVED_C4_SHA256 or c4_member != c4_payload:
        raise SystemExit("approved C4 package/member provenance is invalid")
    expected_refs = [f"added:{index:06d}" for index in range(1, 6)]
    if selected.get("selected_count") != 5 or [row["record_ref"] for row in selected.get("records", [])] != expected_refs:
        raise SystemExit("selected-record evidence is not the exact five-row deterministic pilot")
    from stage2b_c4_assessment import assess_export
    from stage2b_c5_real_data_pilot import canonical_sha, select_records, selected_manifest
    c4_summary, _, _ = assess_export(c4_payload)
    reproduced = selected_manifest(select_records(c4_payload), c4_summary["source_assessment_sha256"])
    if reproduced != selected:
        raise SystemExit("included approved C4 assessment does not reproduce the selected five-row manifest")
    for artifact in (selected, preview, recon):
        checksum = artifact.get("checksum", {})
        logical = {key: value for key, value in artifact.items() if key != "checksum"}
        if checksum != {"algorithm": "sha256", "value": canonical_sha(logical)}:
            raise SystemExit("evidence checksum is invalid")
    rollback_logical = {key: value for key, value in rollback_export.items() if key != "checksum"}
    if (rollback_export.get("checksum") != {"algorithm": "sha256", "value": canonical_sha(rollback_logical)}
            or rollback.get("rollback_export_checksum") != rollback_export.get("checksum")):
        raise SystemExit("rollback export/report checksum binding is invalid")
    if (preview.get("preview_count") != 5 or preview.get("zero_ambiguity") is not True
            or preview.get("zero_conflict") is not True or preview.get("deterministic_repreview") is not True
            or any(row.get("action") != "insert" or row.get("candidate_count") != 0 for row in preview.get("actions", []))):
        raise SystemExit("preview evidence is incomplete or non-deterministic")
    if (applied.get("applied_count") != 5 or applied.get("preview_apply_parity") is not True
            or len(applied.get("actions", [])) != 5
            or any(row.get("action") != "insert" or row.get("version") != 1
                   or row.get("preview_checksum") != row.get("apply_embedded_preview_checksum")
                   for row in applied.get("actions", []))):
        raise SystemExit("apply evidence does not prove exact preview parity")
    if (replay.get("replay_count") != 5 or replay.get("duplicate_vehicles_created") != 0
            or replay.get("complete_response_identity") is not True
            or replay.get("fresh_connection_response_loss_replay") is not True
            or sum(row.get("fresh_connection_after_response_loss") is True for row in replay.get("results", [])) != 1
            or not all(row.get("identical_complete_response") is True for row in replay.get("results", []))):
        raise SystemExit("durable receipt or response-loss replay evidence failed")
    if (set(proof.get("preview_responses", {})) != set(expected_refs)
            or set(proof.get("apply_responses", {})) != set(expected_refs)
            or set(proof.get("replay_responses", {})) != set(expected_refs)
            or proof.get("response_loss_record_ref") not in expected_refs):
        raise SystemExit("operational response proof inventory is incomplete")
    for ref in expected_refs:
        previews = proof["preview_responses"][ref]
        approved = previews.get("approved_preview", {})
        current_first = previews.get("current_repreview_first")
        current_second = previews.get("current_repreview_second")
        apply_response = proof["apply_responses"][ref]
        replay_response = proof["replay_responses"][ref]
        if (approved.get("ok") is not True or approved.get("data", {}).get("action") != "insert"
                or current_first != current_second
                or current_first.get("data", {}).get("action") != "no_change"
                or apply_response != replay_response
                or apply_response.get("ok") is not True
                or apply_response.get("data", {}).get("preview") != approved.get("data")):
            raise SystemExit(f"raw preview/apply/replay proof failed: {ref}")
    if (recon.get("result_count") != 5 or recon.get("matched") != 5 or recon.get("variance") != 0
            or recon.get("c2b_safely_matched") != 5 or recon.get("c2b_refused_or_review") != 0
            or recon.get("c2b_node_validator_passed") is not True
            or any(not (row.get("source_evidence_retained") and row.get("all_original_identifiers_retained")
                        and row.get("typed_artifact_exact") and row.get("browser_source_exact")
                        and row.get("version") == 1) for row in recon.get("results", []))):
        raise SystemExit("C2b/reconciliation evidence failed")
    if (rollback.get("full_isolated_rollback_passed") is not True
            or rollback.get("stale_revision_refused") is not True
            or rollback.get("database_revision_lock_verified") is not True
            or rollback.get("stale_revision_database_query_executed") is not True
            or rollback.get("stale_revision_attempted") != rollback.get("exact_revision_lock") + 1
            or rollback.get("restored_schema_all_checks_passed") is not True
            or rollback.get("validated_foreign_keys") != 72
            or rollback.get("unrelated_restored_rows_unchanged") is not True
            or rollback.get("temporary_schema_removed") is not True
            or rollback.get("public_pilot_rows_changed_by_rehearsal") != 0
            or any(rollback.get("after_rollback_counts", {}).values())):
        raise SystemExit("rollback rehearsal evidence failed")
    if (counts.get("deltas", {}).get("vehicles") != 5
            or counts.get("selected_namespace_counts", {}).get("unresolved_conflicts") != 0
            or counts.get("unrelated_vehicles_unchanged") is not True
            or counts.get("unrelated_vehicle_full_row_sha256_before") != counts.get("unrelated_vehicle_full_row_sha256_after")):
        raise SystemExit("before/after or unrelated-vehicle evidence failed")
    if (backup.get("encrypted") is not True or backup.get("migration_version") != "031"
            or backup.get("decrypt_and_manifest_verified") is not True
            or backup.get("isolated_restore_all_checks_passed") is not True
            or backup.get("foreign_keys_skipped") != [] or backup.get("restore_schema_removed") is not True):
        raise SystemExit("backup/restore evidence failed")
    required_false = ("production_contacted", "production_linked", "frontend_reads_switched",
                      "direct_select_retired", "deployed", "merged", "ai_work_started")
    if (safety.get("exact_staging_project_ref") != "cdsmnqxtyyoeoznmbidd"
            or safety.get("operational_connection_uses_guarded_dsn") is not True
            or safety.get("browser_local_authority_unchanged") is not True
            or safety.get("browser_local_records_modified") != 0
            or safety.get("pilot_records_retained") is not True
            or safety.get("unrelated_vehicles_changed") != 0
            or safety.get("identity_conflicts_created") != 0
            or any(safety.get(key) is not False for key in required_false)):
        raise SystemExit("C5 safety/authority evidence failed")
    reference = proof.get("migration_031_reference", {})
    identity_artifact = reference.get("vehicleIdentityArtifact", {})
    classification = proof.get("c2b_classification", {})
    restore = proof.get("rollback_restore_report", {})
    selected_ids = {row["vehicle_id"] for row in recon.get("results", [])}
    artifact_ids = {row.get("vehicle_id") for row in identity_artifact.get("items", [])}
    if (identity_artifact.get("resolver_revision") != recon.get("resolver_revision")
            or identity_artifact.get("item_count") != len(identity_artifact.get("items", []))
            or not selected_ids.issubset(artifact_ids)
            or len(classification.get("safely_matched", [])) != 5
            or any(classification.get(key) for key in classification if key != "safely_matched")
            or restore.get("all_checks_passed") is not True
            or restore.get("foreign_keys_added") != 72
            or restore.get("foreign_keys_skipped") != []):
        raise SystemExit("migration 031/C2b/full-restore operational proof failed")
    if summary != {"schema": "pdc.stage2b.c5-pilot-summary/v1", "selected_count": 5,
                   "preview": {"insert": 5, "update": 0, "no_change": 0, "refused": 0},
                   "apply": {"insert": 5, "update": 0, "no_change": 0, "failed": 0},
                   "replay_exact": 5, "response_loss_replay_exact": 1,
                   "reconciled": 5, "reconciliation_variance": 0,
                   "rollback_rehearsal_passed": True, "backup_restore_passed": True,
                   "pilot_records_retained": True}:
        raise SystemExit("pilot summary is not exact")


def load_and_verify_extraction():
    manifest = json.loads((ROOT / "REVIEW-MANIFEST.json").read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or set(manifest) != MANIFEST_KEYS:
        raise SystemExit("manifest schema is invalid")
    if (manifest["schema_version"] != EXPECTED_SCHEMA or manifest["source_branch"] != EXPECTED_BRANCH
            or manifest["baseline_head"] != EXPECTED_BASELINE
            or not re.fullmatch(r"[0-9a-f]{40}", str(manifest["source_head"]))
            or manifest["migration_032_required"] is not False
            or manifest["migration_inventory"] != ["028", "029", "030", "031"]):
        raise SystemExit("manifest identity is invalid")
    files = manifest["files"]
    if not isinstance(files, dict) or not REQUIRED_FILES.issubset(files):
        raise SystemExit("manifest file inventory is incomplete")
    expected = {safe_relative(relative).as_posix() for relative in files}
    actual = set()
    for path in ROOT.rglob("*"):
        if path.is_symlink(): raise SystemExit(f"symlink is forbidden: {path}")
        if path.is_file(): actual.add(path.relative_to(ROOT).as_posix())
    if actual != expected | {"REVIEW-MANIFEST.json"}:
        raise SystemExit(f"unmanifested or missing files: extra={sorted(actual-expected-{'REVIEW-MANIFEST.json'})} missing={sorted(expected-actual)}")
    for relative, expected_hash in files.items():
        data = (ROOT / relative).read_bytes()
        if sha256(data) != expected_hash: raise SystemExit(f"checksum mismatch: {relative}")
        if relative == C4_PACKAGE_PATH:
            if sha256(data) != APPROVED_C4_SHA256: raise SystemExit("approved C4 package hash mismatch")
            with zipfile.ZipFile(ROOT / relative) as nested:
                names = [info.filename for info in nested.infolist()]
                if len(names) != len(set(names)): raise SystemExit("duplicate approved C4 members")
                for info in nested.infolist():
                    safe_relative(info.filename)
                    if info.is_dir(): continue
                    try: scan_text(f"{relative}!/{info.filename}", nested.read(info).decode("utf-8"))
                    except UnicodeDecodeError as exc: raise SystemExit(f"non-UTF-8 C4 member: {info.filename}") from exc
        else:
            try: scan_text(relative, data.decode("utf-8"))
            except UnicodeDecodeError as exc: raise SystemExit(f"non-UTF-8 package file: {relative}") from exc
    verify_semantics()
    return manifest, actual


def verify_zip(zip_path: Path, manifest, extracted_files):
    with zipfile.ZipFile(zip_path) as archive:
        infos = archive.infolist(); names = [info.filename for info in infos]
        if len(names) != len(set(names)): raise SystemExit("duplicate ZIP members")
        root_name = ROOT.name
        expected_names = {f"{root_name}/{relative}" for relative in extracted_files}
        if set(names) != expected_names: raise SystemExit("ZIP inventory differs from extraction")
        for info in infos:
            relative = info.filename.removeprefix(root_name + "/"); safe_relative(relative)
            if ((info.external_attr >> 16) & 0o170000) == 0o120000: raise SystemExit("ZIP symlink is forbidden")
            expected_hash = sha256((ROOT / "REVIEW-MANIFEST.json").read_bytes()) if relative == "REVIEW-MANIFEST.json" else manifest["files"][relative]
            if sha256(archive.read(info)) != expected_hash: raise SystemExit(f"ZIP byte mismatch: {info.filename}")


def run(command):
    env = {**os.environ, "PYTHONPATH": str(ROOT / "scripts"), "PYTHONDONTWRITEBYTECODE": "1"}
    completed = subprocess.run(command, cwd=ROOT, env=env, check=False)
    if completed.returncode: raise SystemExit(completed.returncode)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--zip", dest="zip_path"); args = parser.parse_args(argv)
    manifest, extracted_files = load_and_verify_extraction()
    if args.zip_path: verify_zip(Path(args.zip_path).resolve(), manifest, extracted_files)
    run([sys.executable, "-B", "-m", "unittest", "backend.test_stage2b_c5_real_data_pilot", "-v"])
    run([sys.executable, "-B", "-c", "from pathlib import Path; [compile(Path(p).read_text(encoding='utf-8'), p, 'exec') for p in ('scripts/stage2b_c5_real_data_pilot.py','backend/test_stage2b_c5_real_data_pilot.py')]"])
    run(["node", "--check", "scripts/workshop_planner_legacy_validate.js"])
    print(json.dumps({"manifest_files": len(manifest["files"]), "package_scan": "passed", "semantic_evidence": "passed", "non_secret_tests": "passed", "source_head": manifest["source_head"]}, sort_keys=True))


if __name__ == "__main__":
    main()
