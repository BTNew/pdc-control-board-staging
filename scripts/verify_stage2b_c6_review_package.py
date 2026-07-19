#!/usr/bin/env python3
"""Verify a focused Stage 2B C6 review extraction and optional source ZIP."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import urlparse

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SCHEMA = "pdc.stage2b.c6-review-package/v1"
EXPECTED_BRANCH = "feature/stage2b-shared-vehicle-master"
EXPECTED_BASELINE = "2fecc7c552dc1d1ee185b2dbf378b915896deb60"
MANIFEST_KEYS = {"schema_version", "source_branch", "source_head", "baseline_head", "migration_032_required", "migration_inventory", "files"}
EVIDENCE_PREFIX = "review-evidence/stage2b-c6/"
REQUIRED_FILES = {
    "SOURCE-PROVENANCE.json",
    "REVIEW-BUILD-PROVENANCE.json",
    "FINAL-TEST-RESULTS.json",
    "STAGE-2B-C6-OPERATIONAL-STAGING-REHEARSAL.md",
    ".github/workflows/stage2b-c6-final.yml", "package.json", "test_all.js",
    "scripts/stage2b_c6_prepare_apply.py",
    "scripts/stage2b_c6_operational_rehearsal.py",
    "scripts/stage2b_c6_operational_scenarios.py",
    "scripts/stage2b_c6_browser_realtime_acceptance.js",
    "scripts/stage2b_c6_post_rehearsal_verify.py",
    "scripts/stage2b_c6_full_schema_verify.py",
    "scripts/stage2b_c6_full_schema_evidence.py",
    "scripts/stage2b_c6_viewer_contract_verify.py",
    "scripts/stage2b_c6_staging_boundary_verify.py",
    "scripts/stage2b_c6_sql_parse.py",
    "scripts/build_stage2b_c6_review_package.py",
    "scripts/verify_stage2b_c6_review_package.py",
    "backend/test_stage2b_c6_operational_rehearsal.py",
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
    EVIDENCE_PREFIX + "migration-031-bounded-evidence.json",
    EVIDENCE_PREFIX + "c2b-bounded-evidence.json",
    EVIDENCE_PREFIX + "bounded-evidence-attestation.json",
    EVIDENCE_PREFIX + "preflight-baseline.json",
    EVIDENCE_PREFIX + "operational-scenarios.json",
    EVIDENCE_PREFIX + "viewer-contract-live-verification.json",
    EVIDENCE_PREFIX + "staging-final-boundary-verification.json",
    EVIDENCE_PREFIX + "staging-deployment-identity.json",
    EVIDENCE_PREFIX + "browser-realtime-acceptance.json",
    EVIDENCE_PREFIX + "staging-dry-run.json",
    EVIDENCE_PREFIX + "post-rehearsal-verification.json",
    EVIDENCE_PREFIX + "full-schema-unrelated-row-protection.json",
    EVIDENCE_PREFIX + "full-schema-rollback-verification.json",
    EVIDENCE_PREFIX + "full-schema-live-run.json",
    EVIDENCE_PREFIX + "operational-acceptance-checklist.json",
    EVIDENCE_PREFIX + "approved-c4-sanitized-assessment.json",
    "review-evidence/stage2b-c5/approved-c4-sanitized-assessment.json",
}
APPROVED_C4_SHA256 = "980bab0cc0bf79a8156fb78b2587df165406d3fd7d92929468fda66e2ba81016"
C4_PACKAGE_PATH = EVIDENCE_PREFIX + "approved-c4-package.zip"
BINARY_SOURCE_SUFFIXES = {".png"}
GENERATED_PACKAGE_FILES = {"SOURCE-PROVENANCE.json", "REVIEW-BUILD-PROVENANCE.json", "FINAL-TEST-RESULTS.json"}
FINAL_TEST_EVIDENCE_PREFIX = "FINAL-TEST-EVIDENCE/"
REQUIRED_FINAL_GATES = {
    "root_javascript_aggregate", "stage2b_python_regression", "c2b_parity_artifact",
    "c6_focused", "dual_revision_rollback", "authenticated_viewer_read_write",
    "true_browser_offline", "guarded_migrations_028_031", "backup_restore",
    "unrelated_46_table_hashing", "isolated_46_table_rollback_hashing", "sql_parser",
    "database_lint", "linked_migration_dry_run", "credential_scan",
    "prohibited_content_scan", "syntax_compile", "git_diff_check",
}
CREDENTIAL_PATTERNS = (
    re.compile(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}"),
    re.compile(r"-----BEGIN [A-Z ]+PRIVATE KEY-----"),
    re.compile(r"(?i)sb_secret_[a-z0-9_-]{16,}"),
)
SAFE_TEST_PASSWORDS = {"unused", "pass", "redacted", "must-not-leak", "***"}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_sha(value) -> str:
    return sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))


def git_oid(kind: str, data: bytes) -> str:
    return hashlib.sha1(f"{kind} {len(data)}\0".encode("ascii") + data).hexdigest()


def verify_source_provenance(manifest):
    provenance = json.loads((ROOT / "SOURCE-PROVENANCE.json").read_text(encoding="utf-8"))
    if (provenance.get("schema") != "pdc.stage2b.c6-source-provenance/v1"
            or provenance.get("source_head") != manifest["source_head"]
            or provenance.get("baseline_parent") != EXPECTED_BASELINE):
        raise SystemExit("source provenance identity is invalid")
    build = json.loads((ROOT / "REVIEW-BUILD-PROVENANCE.json").read_text(encoding="utf-8"))
    included_source_files = sorted(
        path for path in manifest["files"]
        if not path.startswith("review-evidence/") and not path.startswith(FINAL_TEST_EVIDENCE_PREFIX)
        and path not in GENERATED_PACKAGE_FILES)
    ci = build.get("cross_platform_ci", {})
    final_results = json.loads((ROOT / "FINAL-TEST-RESULTS.json").read_text(encoding="utf-8"))
    c4 = build.get("approved_c4_provenance", {})
    final_gates = final_results.get("gates", [])
    final_gate_names = {gate.get("name") for gate in final_gates}
    final_totals = final_results.get("test_totals", {})
    referenced_final_evidence = []
    for gate in final_gates:
        refs = gate.get("evidence")
        refs = [refs] if isinstance(refs, str) else refs
        if not isinstance(refs, list) or not refs or any(not isinstance(ref, str) for ref in refs):
            raise SystemExit("final gate evidence references are incomplete")
        for ref in refs:
            safe_relative(ref)
            if not ref.startswith(FINAL_TEST_EVIDENCE_PREFIX) or ref not in manifest["files"] or not (ROOT / ref).is_file():
                raise SystemExit(f"final gate evidence does not resolve inside package: {ref}")
            referenced_final_evidence.append(ref)
    expected_final_evidence = {ref: manifest["files"][ref] for ref in sorted(set(referenced_final_evidence))}
    if (build.get("schema") != "pdc.stage2b.c6-review-build-provenance/v1"
            or build.get("source_branch") != EXPECTED_BRANCH
            or build.get("source_head") != manifest["source_head"]
            or build.get("upstream_ref") != f"origin/{EXPECTED_BRANCH}"
            or build.get("remote_head") != manifest["source_head"]
            or build.get("remote_head_match") is not True
            or build.get("clean_worktree") is not True
            or build.get("included_source_files") != included_source_files
            or ci.get("workflow") != "Stage 2B C6 final portable verification"
            or not str(ci.get("run_id", "")).isdigit()
            or ci.get("run_url") != f"https://github.com/BTNew/pdc-control-board/actions/runs/{ci.get('run_id')}"
            or ci.get("head_sha") != manifest["source_head"]
            or ci.get("conclusion") != "success"
            or ci.get("operating_systems") != ["Windows", "Ubuntu", "macOS"]
            or c4.get("path") != C4_PACKAGE_PATH
            or c4.get("sha256") != APPROVED_C4_SHA256
            or not re.fullmatch(r"[0-9a-f]{40}", str(c4.get("git_blob_oid", "")))
            or c4.get("included_as_nested_archive") is not False
            or build.get("final_test_results_sha256") != sha256((ROOT / "FINAL-TEST-RESULTS.json").read_bytes())
            or build.get("final_test_evidence") != expected_final_evidence
            or final_results.get("schema") != "pdc.stage2b.c6-final-test-results/v1"
            or final_results.get("source_head") != manifest["source_head"]
            or final_results.get("remote_head") != manifest["source_head"]
            or final_results.get("overall") != "passed"
            or not REQUIRED_FINAL_GATES.issubset(final_gate_names)
            or any(gate.get("exit_code") != 0 or gate.get("result") != "passed" for gate in final_gates)
            or final_totals.get("failed") != 0
            or not all(isinstance(final_totals.get(key), int) and final_totals.get(key) >= 0
                       for key in ("unique_tests", "execution_tests", "passed", "skipped", "failed"))
            or not str(build.get("git_status_short_branch", "")).startswith(f"## {EXPECTED_BRANCH}...origin/{EXPECTED_BRANCH}")):
        raise SystemExit("clean/remote/source-file build provenance is invalid")
    commit_bytes = provenance["commit_content_utf8"].encode("utf-8")
    if git_oid("commit", commit_bytes) != manifest["source_head"]:
        raise SystemExit("source commit object does not hash to source_head")
    lines = provenance["commit_content_utf8"].splitlines()
    roots = [line.split()[1] for line in lines if line.startswith("tree ")]
    parents = [line.split()[1] for line in lines if line.startswith("parent ")]
    if len(roots) != 1 or parents != [EXPECTED_BASELINE]:
        raise SystemExit("source commit does not have the exact authoritative C5 parent")
    trees = provenance.get("trees")
    if not isinstance(trees, dict) or roots[0] not in trees:
        raise SystemExit("source tree proof is incomplete")
    for claimed_oid, entries in trees.items():
        raw = b""
        for entry in entries:
            mode = str(entry["mode"]).lstrip("0") or "0"
            name = entry["name"]
            if not name or "/" in name or "\0" in name or entry["type"] not in {"blob", "tree"}:
                raise SystemExit("unsafe source tree entry")
            raw += mode.encode("ascii") + b" " + name.encode("utf-8") + b"\0" + bytes.fromhex(entry["oid"])
        if git_oid("tree", raw) != claimed_oid:
            raise SystemExit("source tree object hash mismatch")
    blobs = {}
    def walk(tree_oid, prefix=""):
        for entry in trees[tree_oid]:
            path = prefix + entry["name"]
            if entry["type"] == "tree":
                if entry["oid"] not in trees:
                    raise SystemExit("referenced source subtree is missing")
                walk(entry["oid"], path + "/")
            else:
                blobs[path] = entry["oid"]
    walk(roots[0])
    if blobs.get(C4_PACKAGE_PATH) != c4["git_blob_oid"]:
        raise SystemExit("approved C4 Git-blob provenance is invalid")
    for relative in manifest["files"]:
        if relative in GENERATED_PACKAGE_FILES or relative.startswith(FINAL_TEST_EVIDENCE_PREFIX):
            continue
        if relative not in blobs or git_oid("blob", (ROOT / relative).read_bytes()) != blobs[relative]:
            raise SystemExit(f"package member is not bound to source commit: {relative}")


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
        forbidden_urls = ("postgres://", "postgresql://")
        url_hits = [value for value in forbidden_urls if value in text.lower()]
        if url_hits:
            raise SystemExit(f"prohibited evidence content in {relative}: {url_hits}")
        if relative.endswith(".json"):
            parsed = json.loads(text)
            forbidden_keys = {
                "password", "database_url", "service_role", "customer_email",
                "note_text", "file_content", "audit_details", "customer_name",
            }
            key_hits = []

            def inspect(value, path=""):
                if isinstance(value, dict):
                    for key, child in value.items():
                        child_path = f"{path}.{key}" if path else key
                        if key.lower() in forbidden_keys:
                            customer_null = (
                                relative.endswith("operational-proof.json")
                                and key.lower() == "customer_name" and child is None
                            )
                            if not customer_null:
                                key_hits.append(child_path)
                        inspect(child, child_path)
                elif isinstance(value, list):
                    for index, child in enumerate(value):
                        inspect(child, f"{path}[{index}]")

            inspect(parsed)
            if key_hits:
                raise SystemExit(f"prohibited evidence fields in {relative}: {key_hits}")
        else:
            lowered = text.lower()
            hits = [value for value in (
                "password", "database_url", "service_role", "customer_email",
                "note_text", "file_content", "audit_details", "customer_name",
            ) if value in lowered]
            if hits:
                raise SystemExit(f"prohibited evidence content in {relative}: {hits}")


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
    migration_bounded = evidence_json("migration-031-bounded-evidence.json")
    c2b_bounded = evidence_json("c2b-bounded-evidence.json")
    bounded_attestation = evidence_json("bounded-evidence-attestation.json")
    c4_payload = evidence_json("approved-c4-sanitized-assessment.json")
    expected_refs = [f"added:{index:06d}" for index in range(6, 31)]
    if selected.get("selected_count") != 25 or [row["record_ref"] for row in selected.get("records", [])] != expected_refs:
        raise SystemExit("selected-record evidence is not the exact 25-row deterministic rehearsal")
    from stage2b_c4_assessment import assess_export
    from stage2b_c6_operational_rehearsal import canonical_sha, select_records, selected_manifest
    c4_summary, _, _ = assess_export(c4_payload)
    reproduced = selected_manifest(select_records(c4_payload), c4_summary["source_assessment_sha256"])
    if reproduced != selected:
        raise SystemExit("included approved C4 assessment does not reproduce the selected 25-row manifest")
    for artifact in (selected, preview, recon):
        checksum = artifact.get("checksum", {})
        logical = {key: value for key, value in artifact.items() if key != "checksum"}
        if checksum != {"algorithm": "sha256", "value": canonical_sha(logical)}:
            raise SystemExit("evidence checksum is invalid")
    rollback_logical = {key: value for key, value in rollback_export.items() if key != "checksum"}
    if (rollback_export.get("checksum") != {"algorithm": "sha256", "value": canonical_sha(rollback_logical)}
            or rollback.get("rollback_export_checksum") != rollback_export.get("checksum")):
        raise SystemExit("rollback export/report checksum binding is invalid")
    if (preview.get("preview_count") != 25 or preview.get("zero_ambiguity") is not True
            or preview.get("zero_conflict") is not True or preview.get("deterministic_repreview") is not True
            or any(row.get("action") != "insert" or row.get("candidate_count") != 0 for row in preview.get("actions", []))):
        raise SystemExit("preview evidence is incomplete or non-deterministic")
    if (applied.get("applied_count") != 25 or applied.get("preview_apply_parity") is not True
            or len(applied.get("actions", [])) != 25
            or any(row.get("action") != "insert" or row.get("version") != 1
                   or row.get("preview_checksum") != row.get("apply_embedded_preview_checksum")
                   for row in applied.get("actions", []))):
        raise SystemExit("apply evidence does not prove exact preview parity")
    if (replay.get("replay_count") != 25 or replay.get("duplicate_vehicles_created") != 0
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
    if (recon.get("result_count") != 25 or recon.get("matched") != 25 or recon.get("variance") != 0
            or recon.get("c2b_safely_matched") != 25 or recon.get("c2b_refused_or_review") != 0
            or recon.get("c2b_node_validator_passed") is not True
            or any(not (row.get("source_evidence_retained") and row.get("all_original_identifiers_retained")
                        and row.get("typed_artifact_exact") and row.get("browser_source_exact")
                        and row.get("version") == 1) for row in recon.get("results", []))):
        raise SystemExit("C2b/reconciliation evidence failed")
    if (rollback.get("full_isolated_rollback_passed") is not True
            or rollback.get("stale_revision_refused") is not True
            or rollback.get("database_revision_lock_verified") is not True
            or rollback.get("resolver_revision_lock_verified") is not True
            or rollback.get("database_resolver_revision_lock") != rollback.get("resolver_revision")
            or rollback.get("resolver_stale_revision_database_query_executed") is not True
            or rollback.get("resolver_stale_revision_refused") is not True
            or rollback.get("resolver_stale_revision_attempted") != rollback.get("resolver_revision") + 1
            or rollback.get("revisions_unchanged_through_apply") is not True
            or rollback.get("vehicle_master_independent_advance_test", {}).get("saved_rollback_refused_after_advance") is not True
            or rollback.get("vehicle_master_independent_advance_test", {}).get("advance_rolled_back_before_apply") is not True
            or rollback.get("resolver_independent_advance_test", {}).get("saved_rollback_refused_after_advance") is not True
            or rollback.get("resolver_independent_advance_test", {}).get("advance_rolled_back_before_apply") is not True
            or rollback.get("stale_revision_database_query_executed") is not True
            or rollback.get("stale_revision_attempted") != rollback.get("exact_revision_lock") + 1
            or rollback.get("restored_schema_all_checks_passed") is not True
            or rollback.get("validated_foreign_keys") != 72
            or rollback.get("unrelated_restored_rows_unchanged") is not True
            or rollback.get("temporary_schema_removed") is not True
            or rollback.get("public_pilot_rows_changed_by_rehearsal") != 0
            or any(rollback.get("after_rollback_counts", {}).values())):
        raise SystemExit("rollback rehearsal evidence failed")
    if (counts.get("deltas", {}).get("vehicles") != 25
            or counts.get("selected_namespace_counts", {}).get("unresolved_conflicts") != 0
            or counts.get("unrelated_vehicles_unchanged") is not True
            or counts.get("unrelated_vehicle_full_row_sha256_before") != counts.get("unrelated_vehicle_full_row_sha256_after")):
        raise SystemExit("before/after or unrelated-vehicle evidence failed")
    if (backup.get("encrypted") is not True or backup.get("migration_version") != "031"
            or backup.get("decrypt_and_manifest_verified") is not True
            or backup.get("isolated_restore_all_checks_passed") is not True
            or backup.get("foreign_keys_skipped") != [] or backup.get("restore_schema_removed") is not True):
        raise SystemExit("backup/restore evidence failed")
    required_false = ("frontend_reads_switched", "direct_select_retired", "deployed", "merged", "ai_work_started")
    if (safety.get("exact_staging_project_ref") != "cdsmnqxtyyoeoznmbidd"
            or safety.get("database_connection_guarded_to_exact_staging_project") is not True
            or safety.get("browser_local_authority_unchanged") is not True
            or safety.get("browser_local_records_modified") != 0
            or safety.get("pilot_records_retained") is not True
            or safety.get("unrelated_vehicles_changed") != 0
            or safety.get("identity_conflicts_created") != 0
            or any(safety.get(key) is not False for key in required_false)):
        raise SystemExit("C6 safety/authority evidence failed")
    reference = proof.get("migration_031_reference", {})
    identity_artifact = reference
    classification = proof.get("c2b_classification", {})
    restore = proof.get("rollback_restore_report", {})
    selected_ids = {row["vehicle_id"] for row in recon.get("results", [])}
    artifact_ids = {row.get("vehicle_id") for row in identity_artifact.get("items", [])}
    if (identity_artifact.get("schema") != "pdc.stage2b.c6-selected-migration-031-identity-evidence/v1"
            or identity_artifact.get("source_rpc") != "public.export_workshop_legacy_vehicle_identities"
            or identity_artifact.get("selection") != "exact_selected_vehicle_ids"
            or identity_artifact.get("resolver_revision") != recon.get("resolver_revision")
            or identity_artifact.get("item_count") != len(identity_artifact.get("items", []))
            or selected_ids != artifact_ids
            or identity_artifact.get("item_count") != 25
            or identity_artifact.get("unrelated_vehicle_records_retained") != 0
            or identity_artifact.get("staff_records_retained") != 0
            or "technicians" in identity_artifact
            or len(classification.get("safely_matched", [])) != 25
            or any(classification.get(key) for key in classification if key != "safely_matched")
            or restore.get("all_checks_passed") is not True
            or restore.get("foreign_keys_added") != 72
            or restore.get("foreign_keys_skipped") != []):
        raise SystemExit("migration 031/C2b/full-restore operational proof failed")
    approved_ids = sorted(selected_ids)
    bounded_items = migration_bounded.get("artifact", {}).get("items", [])
    bounded_artifact_ids = sorted(row.get("vehicle_id") for row in bounded_items)
    bounded_classification = c2b_bounded.get("classification", {})
    bounded_c2b_ids = sorted(row.get("resolved", {}).get("vehicle_id") for row in bounded_classification.get("safely_matched", []))
    expected_item_fields = ["identifiers", "is_archived", "vehicle_id", "version"]
    expected_identifier_fields = ["identifier_type", "normalized_value", "origin", "source_system", "value"]
    checksum_basis = {
        "approved_vehicle_ids": approved_ids,
        "migration_031": migration_bounded.get("artifact"),
        "c2b": bounded_classification,
    }
    if (migration_bounded.get("schema") != "pdc.stage2b.c6-migration-031-bounded/v1"
            or c2b_bounded.get("schema") != "pdc.stage2b.c6-c2b-bounded/v1"
            or bounded_attestation.get("schema") != "pdc.stage2b.c6-bounded-evidence-attestation/v1"
            or migration_bounded.get("approved_vehicle_count") != 25
            or c2b_bounded.get("approved_vehicle_count") != 25
            or migration_bounded.get("approved_vehicle_ids") != approved_ids
            or c2b_bounded.get("approved_vehicle_ids") != approved_ids
            or bounded_artifact_ids != approved_ids or bounded_c2b_ids != approved_ids
            or migration_bounded.get("allowed_item_fields") != expected_item_fields
            or migration_bounded.get("allowed_identifier_fields") != expected_identifier_fields
            or any(sorted(row) != expected_item_fields for row in bounded_items)
            or any(sorted(identifier) != expected_identifier_fields for row in bounded_items for identifier in row.get("identifiers", []))
            or migration_bounded.get("checksum") != {"algorithm": "sha256", "value": canonical_sha(migration_bounded.get("artifact"))}
            or c2b_bounded.get("checksum") != {"algorithm": "sha256", "value": canonical_sha(bounded_classification)}
            or bounded_attestation.get("approved_vehicle_ids") != approved_ids
            or bounded_attestation.get("migration_031_vehicle_ids") != approved_ids
            or bounded_attestation.get("c2b_vehicle_ids") != approved_ids
            or bounded_attestation.get("other_vehicle_uuid_count") != 0
            or bounded_attestation.get("technician_records_retained") != 0
            or bounded_attestation.get("customer_fields_retained") != 0
            or bounded_attestation.get("relationship_records_retained") != 0
            or bounded_attestation.get("strict_selected_id_predicate") is not True
            or bounded_attestation.get("no_unselected_identity_can_enter_classifier") is not True
            or bounded_attestation.get("checksum") != {"algorithm": "sha256", "value": canonical_sha(checksum_basis)}):
        raise SystemExit("strictly bounded migration-031/C2b evidence failed")
    uuid_re = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", re.I)
    packaged_vehicle_ids = set()
    def collect_vehicle_ids(value, key=""):
        vehicle_key = key.endswith("vehicle_id") or key.endswith("vehicle_ids")
        if vehicle_key and isinstance(value, str) and uuid_re.fullmatch(value):
            packaged_vehicle_ids.add(value)
        elif vehicle_key and isinstance(value, list):
            packaged_vehicle_ids.update(item for item in value if isinstance(item, str) and uuid_re.fullmatch(item))
        if isinstance(value, dict):
            for child_key, child in value.items(): collect_vehicle_ids(child, child_key)
        elif isinstance(value, list):
            for child in value: collect_vehicle_ids(child, key)
    for relative in REQUIRED_FILES:
        if relative.startswith(EVIDENCE_PREFIX) and relative.endswith(".json"):
            collect_vehicle_ids(json.loads((ROOT / relative).read_text(encoding="utf-8")))
    if packaged_vehicle_ids != set(approved_ids):
        raise SystemExit("package contains an unapproved vehicle UUID or omits an approved vehicle UUID")
    if summary != {"schema": "pdc.stage2b.c6-pilot-summary/v1", "selected_count": 25,
                   "preview": {"insert": 25, "update": 0, "no_change": 0, "refused": 0},
                   "apply": {"insert": 25, "update": 0, "no_change": 0, "failed": 0},
                   "replay_exact": 25, "response_loss_replay_exact": 1,
                   "reconciled": 25, "reconciliation_variance": 0,
                   "rollback_rehearsal_passed": True, "backup_restore_passed": True,
                   "pilot_records_retained": True}:
        raise SystemExit("pilot summary is not exact")
    operational = evidence_json("operational-scenarios.json")
    viewer_live = evidence_json("viewer-contract-live-verification.json")
    final_boundary = evidence_json("staging-final-boundary-verification.json")
    deployment = evidence_json("staging-deployment-identity.json")
    browser = evidence_json("browser-realtime-acceptance.json")
    dry_run = evidence_json("staging-dry-run.json")
    post = evidence_json("post-rehearsal-verification.json")
    full_schema = evidence_json("full-schema-unrelated-row-protection.json")
    full_rollback = evidence_json("full-schema-rollback-verification.json")
    full_live = evidence_json("full-schema-live-run.json")
    checklist = evidence_json("operational-acceptance-checklist.json")
    preflight = evidence_json("preflight-baseline.json")
    if (preflight.get("exact_staging_project_ref") != "cdsmnqxtyyoeoznmbidd"
            or preflight.get("migration_ledger_tip") != "031"
            or preflight.get("authoritative_c5_head") != EXPECTED_BASELINE):
        raise SystemExit("C6 preflight baseline is invalid")
    if (operational.get("passed") is not True or operational.get("selected_vehicle_count") != 25
            or operational.get("roles", {}).get("administrator_read_and_mutate") is not True
            or operational.get("roles", {}).get("controller_operator_read_and_mutate") is not True
            or operational.get("roles", {}).get("viewer_read_only") is not True
            or operational.get("roles", {}).get("viewer_vehicle_read", {}).get("passed") is not True
            or operational.get("roles", {}).get("viewer_workshop_read", {}).get("passed") is not True
            or operational.get("roles", {}).get("viewer_vehicle_write_refused") is not True
            or operational.get("roles", {}).get("viewer_workshop_write_refused") is not True
            or operational.get("roles", {}).get("viewer_contract", {}).get("vehicle_fields_returned") != ["active_workshop_booking_id", "current_location", "id", "lifecycle_state", "version", "workshop_status"]
            or operational.get("roles", {}).get("viewer_contract", {}).get("workshop_fields_returned") != ["id", "status", "vehicle_id", "version"]
            or operational.get("roles", {}).get("viewer_contract", {}).get("prohibited_fields_absent") is not True
            or operational.get("roles", {}).get("viewer_contract", {}).get("broad_direct_vehicle_projection_used") is not False
            or operational.get("roles", {}).get("viewer_contract", {}).get("technician_or_sensitive_data_retained") is not False
            or operational.get("optimistic_concurrency", {}).get("winners") != 1
            or operational.get("optimistic_concurrency", {}).get("version_conflicts") != 1
            or operational.get("optimistic_concurrency", {}).get("stale_edit_refused") is not True
            or operational.get("workshop", {}).get("vehicle_uuid_retained_every_step") is not True
            or operational.get("unrelated_row_protection", {}).get("all_full_row_hashes_unchanged") is not True
            or operational.get("cleanup", {}).get("temporary_roles_remaining") != 0
            or operational.get("cleanup", {}).get("temporary_schemas_remaining") != 0):
        raise SystemExit("C6 authenticated operational scenarios failed")
    if (viewer_live.get("schema") != "pdc.stage2b.c6-viewer-contract-live-verification/v1"
            or viewer_live.get("exact_staging_project_ref") != "cdsmnqxtyyoeoznmbidd"
            or viewer_live.get("approved_vehicle_id") not in selected_ids
            or viewer_live.get("approved_booking_id") is None
            or viewer_live.get("authentication", {}).get("sign_in_status") != 200
            or viewer_live.get("authentication", {}).get("get_user_status") != 200
            or viewer_live.get("authentication", {}).get("session_user_matches_get_user") is not True
            or viewer_live.get("authentication", {}).get("role_read_status") != 200
            or viewer_live.get("authentication", {}).get("account_status_read_status") != 200
            or viewer_live.get("authentication", {}).get("role") != "viewer"
            or viewer_live.get("authentication", {}).get("account_status") != "approved"
            or viewer_live.get("authentication", {}).get("raw_identity_retained") is not False
            or viewer_live.get("vehicle_fields_returned") != ["active_workshop_booking_id", "current_location", "id", "lifecycle_state", "version", "workshop_status"]
            or viewer_live.get("workshop_fields_returned") != ["id", "status", "vehicle_id", "version"]
            or viewer_live.get("vehicle_fields_returned") != viewer_live.get("vehicle_fields_allowed")
            or viewer_live.get("workshop_fields_returned") != viewer_live.get("workshop_fields_allowed")
            or viewer_live.get("prohibited_fields_absent") is not True
            or viewer_live.get("broad_direct_vehicle_projection_used") is not False
            or viewer_live.get("technician_or_sensitive_data_retained") is not False
            or viewer_live.get("viewer_vehicle_read_status") != 200
            or viewer_live.get("viewer_workshop_read_status") != 200
            or viewer_live.get("viewer_vehicle_write_status") != 403
            or viewer_live.get("viewer_workshop_write_status") != 403
            or viewer_live.get("viewer_vehicle_write_sqlstate") != "42501"
            or viewer_live.get("viewer_workshop_write_sqlstate") != "42501"
            or viewer_live.get("viewer_vehicle_write_refused") is not True
            or viewer_live.get("viewer_workshop_write_refused") is not True
            or viewer_live.get("write_response_bodies_retained") is not False
            or viewer_live.get("passed") is not True):
        raise SystemExit("live authenticated viewer contract evidence failed")
    if (final_boundary.get("schema") != "pdc.stage2b.c6-staging-final-boundary/v1"
            or final_boundary.get("approved_vehicle_count") != 25
            or final_boundary.get("retained_vehicle_count") != 25
            or final_boundary.get("approved_vehicle_ids") != approved_ids
            or final_boundary.get("approved_uuid_set_exact") is not True
            or final_boundary.get("staging_total_vehicle_count") != 32
            or final_boundary.get("additional_staging_vehicles_excluded_from_evidence") != 7
            or final_boundary.get("temporary_c6_schemas") != 0
            or final_boundary.get("passed") is not True):
        raise SystemExit("final exact-25 staging boundary evidence failed")
    deployment_sha = sha256((ROOT / EVIDENCE_PREFIX / "staging-deployment-identity.json").read_bytes())
    expected_deployment = {"repository": "BTNew/pdc-control-board-staging", "commit": "35c836a5de76feeeb201d149ea43397c674b322a",
                           "buildId": 1101689672, "status": "built", "url": "https://btnew.github.io/pdc-control-board-staging/",
                           "indexSha256": "3a145f6eb03558a4461b3f9a1a6fbfb14aaf6ddf528a091a6e553e59a898c9e6",
                           "identityEvidenceSha256": deployment_sha}
    if (deployment.get("schema") != "pdc.stage2b.c6-staging-deployment-identity/v1"
            or deployment.get("exact_staging_project_ref") != "cdsmnqxtyyoeoznmbidd"
            or deployment.get("staging_url") != expected_deployment["url"]
            or deployment.get("github_pages", {}).get("repository") != expected_deployment["repository"]
            or deployment.get("github_pages", {}).get("commit") != expected_deployment["commit"]
            or deployment.get("github_pages", {}).get("build_id") != expected_deployment["buildId"]
            or deployment.get("github_pages", {}).get("status") != "built"
            or deployment.get("index", {}).get("sha256") != expected_deployment["indexSha256"]
            or len(deployment.get("assets", [])) != 13
            or deployment.get("all_checks_passed") is not True):
        raise SystemExit("staging deployment identity evidence failed")
    required_browser = ("exactStagingProject", "stagingDeploymentIdentityBound", "administratorRole", "controllerRole", "viewerRole", "viewerPermittedRead",
                        "twoIndependentBrowserContexts", "twoUserRealtimeRefresh", "staleWhileDisconnected",
                        "initialOnlineStateSynchronized", "browserContextActuallyOffline", "httpUnavailableDuringOffline",
                        "websocketDisconnectedDuringOffline", "offlineUiClearlyDisconnected",
                        "offlineMutationNotReportedPersisted", "postOnlineRefetchExact",
                        "reconnectCaughtMissedUpdate", "noDuplicateChannelsAfterReconnect",
                        "repeatedOfflineOnlineTransitions", "noDuplicateChannelsAfterRepeatedReconnect",
                        "noMultipliedRealtimeCallbacks", "browserRefreshPreservedUUIDAndVersion",
                        "staleEditRejected", "operatorBrowserProfileIsolated", "authorityCanariesPresentBeforeBootstrapCompleted",
                        "browserLocalCanonicalObservationsEqual", "browserLocalAuthorityUnchanged",
                        "browserLocalDataNotCleared", "zeroInstrumentedBrowserProductionProjectRequests", "stagingSupabaseContacted",
                        "noPageErrors", "noUnexpectedConsoleErrors", "noCspViolations", "noUnexpectedHttpFailures")
    browser_isolation = browser.get("browserProfileIsolation", {})
    browser_observations = browser.get("browserLocalAuthorityObservations", {})
    before_observations = browser_observations.get("before", [])
    after_observations = browser_observations.get("after", [])
    observation_shape_valid = (len(before_observations) == len(after_observations) == 3
                               and before_observations == after_observations
                               and all(set(item) == {"keyCount", "byteCount", "sha256"}
                                       and isinstance(item["keyCount"], int) and item["keyCount"] >= 8
                                       and isinstance(item["byteCount"], int) and item["byteCount"] > 0
                                       and isinstance(item["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", item["sha256"])
                                       for item in before_observations))
    if (browser.get("passed") is not True or browser.get("sessions") != 3
            or browser.get("stagingDeployment") != expected_deployment
            or browser.get("productionRequests") != []
            or browser.get("reconnectCycles") != 2
            or browser.get("realtimeCallbackDelta") != 1
            or browser.get("onlinePeerRealtimeVersion") != browser.get("changedVersion")
            or browser.get("onlinePeerRealtimeEventDelta") != 1
            or browser.get("unexpectedFailedRequests") != []
            or browser.get("pageErrors") != []
            or browser.get("securityPolicyViolations") != []
            or browser_isolation.get("mode") != "playwright-ephemeral-incognito-contexts"
            or browser_isolation.get("persistentUserDataDirUsed") is not False
            or browser_isolation.get("operatorBrowserProfileOpened") is not False
            or browser_isolation.get("authorityCanariesPresentBeforeBootstrapCompleted") is not True
            or browser_isolation.get("authorityCanariesUnchanged") is not True
            or sorted(browser_isolation.get("authorityCanaryKeys", [])) != sorted([
                "vehicleTrackingCoreNavisionOnlyVehicles:v1", "vehicleTrackingCoreNavisionOnlyEdits:v1",
                "vehicleTrackingCoreNavisionOnlyDeleted:v1", "vehicleTrackingCoreNavisionOnlyPoTasks:v1",
                "vehicleTrackingCoreNavisionOnlyPoFiles:v1", "vehicleTrackingCoreNavisionOnlyAuditLog:v1",
                "vehicleTrackingCoreWorkshopPlan:v1", "vehicleTrackingCoreNotes:C6-AUTHORITY-CANARY"])
            or browser_observations.get("canonicalSerialization") != "JSON.stringify(sorted [key,value] arrays)"
            or browser_observations.get("exactHashKeyAndByteEquality") is not True
            or observation_shape_valid is not True
            or browser.get("browserLocalStoresUnchanged") is not True
            or any(browser.get("checks", {}).get(key) is not True for key in required_browser)):
        raise SystemExit("C6 browser/Realtime/reconnect evidence failed")
    if (dry_run.get("exact_staging_project_ref") != "cdsmnqxtyyoeoznmbidd"
            or dry_run.get("up_to_date") is not True or dry_run.get("migrations_pushed") != 0):
        raise SystemExit("C6 staging dry-run evidence failed")
    if (post.get("passed") is not True or post.get("selected_vehicle_count") != 25
            or post.get("reconciled_to_original_source") != 25 or post.get("reconciliation_variance") != 0
            or post.get("unrelated_row_protection", {}).get("all_full_row_hashes_unchanged") is not True
            or post.get("cleanup", {}).get("temporary_roles_remaining") != 0
            or post.get("cleanup", {}).get("temporary_schemas_remaining") != 0
            or post.get("cleanup", {}).get("unresolved_identity_conflicts") != 0
            or post.get("staging_dry_run_up_to_date") is not True
            or post.get("instrumented_browser_production_project_requests") != []
            or post.get("production_project_requests_observed_in_instrumented_browser_contexts") != 0
            or post.get("database_connection_guarded_to_exact_staging_project") is not True
            or post.get("browser_local_authority_unchanged") is not True
            ):
        raise SystemExit("C6 post-rehearsal reconciliation/cleanup evidence failed")
    expected_fk_scope = {"public_total": 130, "payload_internal_restorable": 72,
                         "external_auth_not_in_backup": 58, "restored_and_validated": 72}
    expected_object_counts = {"columns": 641, "constraints": 188, "indexes": 143, "sequences": 0}
    hashing_required = {"algorithm", "row_projection", "stable_order", "aggregation", "canonical_serialization", "comparison", "partition_stability", "selected_boundary"}
    def stable_partition_ok(baseline, after):
        return (baseline.get("partition_reconciled") is True
                and baseline.get("baseline_all_count") == baseline.get("baseline_dependent_count") + baseline.get("baseline_unrelated_count")
                and baseline.get("baseline_unrelated_count") == after.get("frozen_unrelated_count")
                and baseline.get("baseline_unrelated_keyset_sha256") == after.get("frozen_unrelated_keyset_sha256")
                and baseline.get("baseline_unrelated_full_row_sha256") == after.get("frozen_unrelated_full_row_sha256")
                and after.get("missing_frozen_unrelated_rows") == 0
                and after.get("changed_frozen_unrelated_rows") == 0
                and after.get("new_rows_outside_baseline_partition") == 0
                and after.get("stable_unrelated_rows_unchanged") is True)
    if (full_schema.get("table_count") != 46 or len(full_schema.get("tables", {})) != 46
            or sorted(full_schema.get("table_inventory", [])) != sorted(full_schema.get("tables", {}))
            or set(full_schema.get("hashing_method", {})) != hashing_required
            or full_schema.get("all_unrelated_full_row_hashes_unchanged") is not True
            or full_schema.get("schema_objects_equal") is not True
            or full_schema.get("restored_schema_objects") != full_schema.get("public_schema_objects")
            or full_schema.get("foreign_key_scope") != expected_fk_scope
            or full_schema.get("all_checks_passed") is not True
            or any(full_schema.get("restored_schema_objects", {}).get(key, {}).get("count") != count
                   for key, count in expected_object_counts.items())
            or full_schema.get("restored_schema_objects", {}).get("foreign_keys", {}).get("discovered") != 72
            or full_schema.get("restored_schema_objects", {}).get("foreign_keys", {}).get("validated") != 72
            or any(row.get("unchanged") is not True or not stable_partition_ok(row, row)
                   for row in full_schema.get("tables", {}).values())):
        raise SystemExit("full-schema unrelated-row proof is incomplete")
    if (full_rollback.get("table_count") != 46
            or sorted(full_rollback.get("table_inventory", [])) != sorted(full_rollback.get("before", {}))
            or set(full_rollback.get("hashing_method", {})) != hashing_required
            or len(full_rollback.get("before", {})) != 46 or len(full_rollback.get("after", {})) != 46
            or len(full_rollback.get("full_tables_before", {})) != 46 or len(full_rollback.get("full_tables_after", {})) != 46
            or full_rollback.get("all_unrelated_full_row_hashes_unchanged") is not True
            or full_rollback.get("stale_revision_database_query_executed") is not True
            or full_rollback.get("stale_revision_refused") is not True
            or full_rollback.get("stale_revision_attempted") != full_rollback.get("exact_revision_lock") + 1
            or full_rollback.get("resolver_stale_revision_database_query_executed") is not True
            or full_rollback.get("resolver_stale_revision_refused") is not True
            or full_rollback.get("resolver_stale_revision_attempted") != full_rollback.get("resolver_revision_lock") + 1
            or full_rollback.get("revisions_unchanged_through_apply") is not True
            or full_rollback.get("vehicle_master_independent_advance_test", {}).get("saved_rollback_refused_after_advance") is not True
            or full_rollback.get("vehicle_master_independent_advance_test", {}).get("advance_rolled_back_before_apply") is not True
            or full_rollback.get("resolver_independent_advance_test", {}).get("saved_rollback_refused_after_advance") is not True
            or full_rollback.get("resolver_independent_advance_test", {}).get("advance_rolled_back_before_apply") is not True
            or full_rollback.get("schema_objects_equal_and_unchanged") is not True
            or full_rollback.get("restored_schema_objects_before") != full_rollback.get("restored_schema_objects_after")
            or full_rollback.get("restored_schema_objects_before") != full_rollback.get("public_schema_objects")
            or full_rollback.get("required_public_functions_unchanged") is not True
            or full_rollback.get("required_public_functions_before") != full_rollback.get("required_public_functions_after")
            or full_rollback.get("foreign_keys_discovered") != 72
            or full_rollback.get("foreign_keys_validated") != 72
            or full_rollback.get("foreign_key_scope") != expected_fk_scope
            or any(full_rollback.get("restored_schema_objects_before", {}).get(key, {}).get("count") != count
                   for key, count in expected_object_counts.items())
            or full_rollback.get("all_checks_passed") is not True
            or full_rollback.get("temporary_schema_removed") is not True
            or full_rollback.get("public_rows_changed") != 0
            or any(not stable_partition_ok(full_rollback.get("before", {}).get(table, {}),
                                           full_rollback.get("after", {}).get(table, {}))
                   for table in full_rollback.get("table_inventory", []))):
        raise SystemExit("full-schema isolated rollback proof is incomplete")
    if (full_live.get("schema") != "pdc.stage2b.c6-full-schema-live-run/v1"
            or full_live.get("exact_staging_project_ref") != "cdsmnqxtyyoeoznmbidd"
            or full_live.get("pre_rehearsal_fixture", {}).get("file_sha256") != "c561b50acb8840526b33042520decd4cbf19f450f9ef58fda6f21c2678d1183b"
            or full_live.get("rollback_fixture", {}).get("file_sha256") != "04dbcee2a3c3f7ea8f3a635f02a6f4cbf2d12fbd29005a434a51efee4047d6f5"
            or full_live.get("pre_rehearsal_fixture", {}).get("table_count") != 46
            or full_live.get("rollback_fixture", {}).get("table_count") != 46
            or full_live.get("pre_rehearsal_restore", {}).get("all_checks_passed") is not True
            or full_live.get("rollback_restore", {}).get("all_checks_passed") is not True
            or full_live.get("pre_rehearsal_restore", {}).get("foreign_keys_added") != 72
            or full_live.get("rollback_restore", {}).get("foreign_keys_added") != 72
            or full_live.get("pre_rehearsal_restore", {}).get("foreign_keys_skipped") != []
            or full_live.get("rollback_restore", {}).get("foreign_keys_skipped") != []
            or full_live.get("unrelated_table_count") != 46
            or full_live.get("unrelated_rows_equal") is not True
            or full_live.get("rollback_table_count") != 46
            or full_live.get("rollback_unrelated_rows_equal") is not True
            or full_live.get("rollback_schema_objects_equal") is not True
            or full_live.get("foreign_keys_validated") != 72
            or full_live.get("dual_revision_refusal") is not True
            or full_live.get("temporary_schemas_removed") is not True
            or full_live.get("all_checks_passed") is not True):
        raise SystemExit("tracked full-schema live-run evidence is incomplete")
    if checklist.get("passed") is not True or any(value is not True for key, value in checklist.items()
                                                   if key not in {"schema", "passed"}):
        raise SystemExit("C6 operational acceptance checklist is incomplete")


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
        if Path(relative).suffix.lower() in {".zip", ".tar", ".gz", ".tgz", ".7z", ".rar"}:
            raise SystemExit(f"nested archive is forbidden: {relative}")
        if Path(relative).suffix.lower() not in BINARY_SOURCE_SUFFIXES:
            try: scan_text(relative, data.decode("utf-8"))
            except UnicodeDecodeError as exc: raise SystemExit(f"non-UTF-8 package file: {relative}") from exc
    verify_source_provenance(manifest)
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
    with tempfile.TemporaryDirectory(prefix="pdc-c6-verifier-pycache-") as pycache:
        env = {**os.environ, "PYTHONPATH": str(ROOT / "scripts"), "PYTHONDONTWRITEBYTECODE": "1",
               "PYTHONPYCACHEPREFIX": pycache}
        completed = subprocess.run(command, cwd=ROOT, env=env, check=False)
    if completed.returncode: raise SystemExit(completed.returncode)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--zip", dest="zip_path"); args = parser.parse_args(argv)
    manifest, extracted_files = load_and_verify_extraction()
    if args.zip_path: verify_zip(Path(args.zip_path).resolve(), manifest, extracted_files)
    safe_config = ROOT / "pdc-supabase-config.js"
    safe_project_ref = ROOT / "supabase" / ".temp" / "project-ref"
    if safe_config.exists() or safe_project_ref.exists():
        raise SystemExit("unexpected browser or staging configuration exists before extracted tests")
    safe_config.write_bytes((ROOT / "pdc-supabase-config.example.js").read_bytes())
    safe_project_ref.parent.mkdir(parents=True, exist_ok=True)
    safe_project_ref.write_text("cdsmnqxtyyoeoznmbidd\n", encoding="utf-8")
    try:
        npm = shutil.which("npm.cmd" if os.name == "nt" else "npm")
        if not npm:
            raise SystemExit("npm executable is unavailable")
        run([npm, "test"])
        run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "backend", "-p", "test_stage2b*.py", "-v"])
        run([sys.executable, "-B", "-m", "unittest",
             "backend.test_stage2b_offline_vehicle_reference_artifact",
             "backend.test_stage2b_importer_identity_export_foundation",
             "backend.test_stage2b_importer_identity_export_adapter",
             "backend.test_stage2b_importer_identity_export_staging", "-v"])
        run([sys.executable, "-B", "-m", "unittest", "backend.test_stage2b_c6_operational_rehearsal", "-v"])
        run([sys.executable, "-B", "scripts/stage2b_c6_sql_parse.py"])
        compile_paths = [str(path.relative_to(ROOT)) for path in sorted((ROOT / "scripts").glob("stage2b_c6_*.py"))]
        compile_paths += ["scripts/pdc_backup.py", "scripts/pdc_restore.py"]
        run([sys.executable, "-B", "-m", "py_compile", *compile_paths])
        run(["node", "--check", "scripts/stage2b_c6_browser_realtime_acceptance.js"])
        run(["node", "--check", "scripts/workshop_planner_legacy_validate.js"])
    finally:
        safe_config.unlink(missing_ok=True)
        safe_project_ref.unlink(missing_ok=True)
        try:
            safe_project_ref.parent.rmdir()
        except OSError:
            pass
    repeated_manifest, repeated_files = load_and_verify_extraction()
    if repeated_manifest != manifest or repeated_files != extracted_files:
        raise SystemExit("verification mutated the exact package extraction")
    print(json.dumps({"manifest_files": len(manifest["files"]), "final_test_evidence_files": len([path for path in manifest["files"] if path.startswith(FINAL_TEST_EVIDENCE_PREFIX)]), "package_scan": "passed", "semantic_evidence": "passed", "non_secret_tests": "passed", "source_head": manifest["source_head"]}, sort_keys=True))


if __name__ == "__main__":
    main()
