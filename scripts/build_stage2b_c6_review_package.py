#!/usr/bin/env python3
"""Build a commit-exact, credential-scanned Stage 2B C6 review ZIP."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from verify_stage2b_c6_review_package import REQUIRED_FINAL_GATES, scan_text

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BRANCH = "feature/stage2b-shared-vehicle-master"
BASELINE_HEAD = "2fecc7c552dc1d1ee185b2dbf378b915896deb60"
EXACT_FILES = {
    ".gitignore",
    ".github/workflows/stage2b-c6-final.yml",
    "package.json",
    "test_all.js",
    "STAGE-2B-C6-OPERATIONAL-STAGING-REHEARSAL.md",
    "backend/test_stage2b_c6_operational_rehearsal.py",
    "scripts/stage2b_c4_assessment.py",
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
    "scripts/workshop_legacy_import.py",
    "scripts/workshop_vehicle_reference_artifact.py",
    "scripts/workshop_planner_legacy_validate.js",
    "scripts/pdc_backup.py", "scripts/pdc_restore.py",
    "supabase/migrations/028_stage2b_vehicle_master_foundation.sql",
    "supabase/migrations/029_stage2b_vehicle_master_operations.sql",
    "supabase/migrations/030_stage2b_lifecycle_identity_resolver.sql",
    "supabase/migrations/031_stage2b_importer_identity_export.sql",
}
SOURCE_PREFIXES = ("backend/", "scripts/", "supabase/", "_staging_test_tools/", "tests/", "vendor/", "assets/")
SOURCE_SUFFIXES = {".py", ".js", ".json", ".html", ".css", ".svg", ".png", ".csv", ".sql", ".toml", ".txt", ".sh", ".bat"}
BINARY_SOURCE_SUFFIXES = {".png"}
for path in subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines():
    suffix = Path(path).suffix.lower()
    if ((path.startswith(SOURCE_PREFIXES) or "/" not in path) and suffix in SOURCE_SUFFIXES
            and not path.startswith("review-evidence/") and not path.endswith("package-review.json")
            and not path.endswith("master-import-audit.json")):
        EXACT_FILES.add(path)
EVIDENCE_FILES = {
    "review-evidence/stage2b-c6/selected-record-manifest.json",
    "review-evidence/stage2b-c6/approval-manifest.md",
    "review-evidence/stage2b-c6/preview-result.json",
    "review-evidence/stage2b-c6/apply-result.json",
    "review-evidence/stage2b-c6/replay-evidence.json",
    "review-evidence/stage2b-c6/reconciliation-report.json",
    "review-evidence/stage2b-c6/rollback-export.json",
    "review-evidence/stage2b-c6/rollback-report.json",
    "review-evidence/stage2b-c6/before-after-row-counts.json",
    "review-evidence/stage2b-c6/backup-restore-evidence.json",
    "review-evidence/stage2b-c6/safety.json",
    "review-evidence/stage2b-c6/pilot-summary.json",
    "review-evidence/stage2b-c6/operational-proof.json",
    "review-evidence/stage2b-c6/migration-031-bounded-evidence.json",
    "review-evidence/stage2b-c6/c2b-bounded-evidence.json",
    "review-evidence/stage2b-c6/bounded-evidence-attestation.json",
    "review-evidence/stage2b-c6/preflight-baseline.json",
    "review-evidence/stage2b-c6/operational-scenarios.json",
    "review-evidence/stage2b-c6/viewer-contract-live-verification.json",
    "review-evidence/stage2b-c6/staging-final-boundary-verification.json",
    "review-evidence/stage2b-c6/staging-deployment-identity.json",
    "review-evidence/stage2b-c6/browser-realtime-acceptance.json",
    "review-evidence/stage2b-c6/staging-dry-run.json",
    "review-evidence/stage2b-c6/post-rehearsal-verification.json",
    "review-evidence/stage2b-c6/full-schema-unrelated-row-protection.json",
    "review-evidence/stage2b-c6/full-schema-rollback-verification.json",
    "review-evidence/stage2b-c6/full-schema-live-run.json",
    "review-evidence/stage2b-c6/operational-acceptance-checklist.json",
    "review-evidence/stage2b-c6/approved-c4-sanitized-assessment.json",
    "review-evidence/stage2b-c5/approved-c4-sanitized-assessment.json",
}
APPROVED_C4_SHA256 = "980bab0cc0bf79a8156fb78b2587df165406d3fd7d92929468fda66e2ba81016"
C4_PACKAGE_PATH = "review-evidence/stage2b-c6/approved-c4-package.zip"
FINAL_TEST_EVIDENCE_PREFIX = "FINAL-TEST-EVIDENCE/"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def committed_bytes(head, path):
    return subprocess.check_output(["git", "show", f"{head}:{path}"], cwd=ROOT)


def source_provenance(head):
    commit_content = subprocess.check_output(["git", "cat-file", "commit", head], cwd=ROOT)
    tree_oid = next(line.split()[1] for line in commit_content.decode("utf-8").splitlines() if line.startswith("tree "))
    trees, pending = {}, [tree_oid]
    while pending:
        oid = pending.pop()
        if oid in trees:
            continue
        entries = []
        for record in subprocess.check_output(["git", "ls-tree", "-z", oid], cwd=ROOT).split(b"\0"):
            if not record:
                continue
            metadata, name = record.split(b"\t", 1)
            mode, kind, child_oid = metadata.decode("ascii").split()
            entries.append({"mode": mode, "type": kind, "oid": child_oid, "name": name.decode("utf-8")})
            if kind == "tree":
                pending.append(child_oid)
        trees[oid] = entries
    return {"schema": "pdc.stage2b.c6-source-provenance/v1", "source_head": head,
            "baseline_parent": BASELINE_HEAD, "commit_content_utf8": commit_content.decode("utf-8"), "trees": trees}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="_c6_packages")
    parser.add_argument("--ci-run-id", required=True)
    parser.add_argument("--ci-head-sha", required=True)
    parser.add_argument("--ci-run-url", required=True)
    parser.add_argument("--final-test-results", required=True, type=Path)
    args = parser.parse_args(argv)
    branch, head = git("branch", "--show-current"), git("rev-parse", "HEAD")
    if branch != EXPECTED_BRANCH: raise SystemExit(f"refusing unexpected branch: {branch}")
    if git("status", "--porcelain"): raise SystemExit("refusing dirty or untracked source tree")
    upstream = git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    remote_head = git("rev-parse", "@{upstream}")
    if remote_head != head: raise SystemExit("refusing source HEAD that does not exactly match remote HEAD")
    if args.ci_head_sha != head: raise SystemExit("refusing CI result for a different source HEAD")
    expected_ci_url = f"https://github.com/BTNew/pdc-control-board/actions/runs/{args.ci_run_id}"
    if args.ci_run_url != expected_ci_url or not args.ci_run_id.isdigit(): raise SystemExit("refusing invalid CI run identity")
    status_short_branch = git("status", "--short", "--branch")
    tracked = set(git("ls-tree", "-r", "--name-only", head).splitlines())
    migrations = sorted(Path(path).name[:3] for path in tracked if path.startswith("supabase/migrations/") and Path(path).name[:3].isdigit())
    if migrations[-1:] != ["031"] or "032" in migrations: raise SystemExit("migration inventory is not capped through 031")
    selected = EXACT_FILES | EVIDENCE_FILES
    missing = sorted(selected - tracked)
    if missing: raise SystemExit(f"review source is not committed: {missing}")
    c4_bytes = committed_bytes(head, C4_PACKAGE_PATH)
    if sha256(c4_bytes) != APPROVED_C4_SHA256:
        raise SystemExit("approved C4 package hash mismatch")
    c4_blob_oid = git("rev-parse", f"{head}:{C4_PACKAGE_PATH}")
    final_test_results = json.loads(args.final_test_results.read_text(encoding="utf-8"))
    final_gates = final_test_results.get("gates", [])
    final_totals = final_test_results.get("test_totals", {})
    if (final_test_results.get("schema") != "pdc.stage2b.c6-final-test-results/v1"
            or final_test_results.get("source_head") != head
            or final_test_results.get("remote_head") != head
            or final_test_results.get("overall") != "passed"
            or not REQUIRED_FINAL_GATES.issubset({gate.get("name") for gate in final_gates})
            or any(gate.get("exit_code") != 0 or gate.get("result") != "passed" for gate in final_gates)
            or final_totals.get("failed") != 0):
        raise SystemExit("final test results are incomplete or bound to a different source HEAD")
    final_evidence_sources = {}
    for gate in final_gates:
        raw_refs = gate.get("evidence")
        raw_refs = [raw_refs] if isinstance(raw_refs, str) else raw_refs
        if not isinstance(raw_refs, list) or not raw_refs or any(not isinstance(ref, str) for ref in raw_refs):
            raise SystemExit(f"final gate evidence is missing: {gate.get('name')}")
        packaged_refs = []
        for index, raw_ref in enumerate(raw_refs, 1):
            relative = PurePosixPath(raw_ref)
            if relative.is_absolute() or ".." in relative.parts or "\\" in raw_ref or relative.as_posix() != raw_ref:
                raise SystemExit(f"unsafe final gate evidence path: {raw_ref}")
            source = (args.final_test_results.parent / Path(*relative.parts)).resolve()
            evidence_root = args.final_test_results.parent.resolve()
            if evidence_root not in source.parents or not source.is_file() or source.is_symlink():
                raise SystemExit(f"final gate evidence is unavailable: {raw_ref}")
            suffix = source.suffix.lower() if source.suffix else ".log"
            packaged = f"{FINAL_TEST_EVIDENCE_PREFIX}{gate['name']}-{index}{suffix}"
            data = source.read_bytes()
            try:
                scan_text(packaged, data.decode("utf-8"))
            except UnicodeDecodeError as exc:
                raise SystemExit(f"non-UTF-8 final gate evidence: {raw_ref}") from exc
            final_evidence_sources[packaged] = data
            packaged_refs.append(packaged)
        gate["evidence"] = packaged_refs[0] if len(packaged_refs) == 1 else packaged_refs
    package_name = f"PDC-Stage2B-C6-Operational-Staging-Rehearsal-Review-{head[:12]}"
    out_dir = (ROOT / args.output_dir).resolve(); out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / f"{package_name}.zip"
    with tempfile.TemporaryDirectory(prefix="pdc-c6-review-") as temp:
        package_root = Path(temp) / package_name
        for relative in sorted(selected):
            data = committed_bytes(head, relative)
            if Path(relative).suffix.lower() not in BINARY_SOURCE_SUFFIXES:
                try: scan_text(relative, data.decode("utf-8"))
                except UnicodeDecodeError as exc: raise SystemExit(f"non-UTF-8 review source: {relative}") from exc
            destination = package_root / relative; destination.parent.mkdir(parents=True, exist_ok=True); destination.write_bytes(data)
        provenance = (json.dumps(source_provenance(head), sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        (package_root / "SOURCE-PROVENANCE.json").write_bytes(provenance)
        final_results_bytes = (json.dumps(final_test_results, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        scan_text("FINAL-TEST-RESULTS.json", final_results_bytes.decode("utf-8"))
        (package_root / "FINAL-TEST-RESULTS.json").write_bytes(final_results_bytes)
        for relative, data in sorted(final_evidence_sources.items()):
            destination = package_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        build_provenance = {
            "schema": "pdc.stage2b.c6-review-build-provenance/v1",
            "source_branch": branch,
            "source_head": head,
            "upstream_ref": upstream,
            "remote_head": remote_head,
            "remote_head_match": remote_head == head,
            "clean_worktree": True,
            "git_status_short_branch": status_short_branch,
            "cross_platform_ci": {"workflow": "Stage 2B C6 final portable verification", "run_id": args.ci_run_id,
                                  "run_url": args.ci_run_url, "head_sha": args.ci_head_sha,
                                  "conclusion": "success", "operating_systems": ["Windows", "Ubuntu", "macOS"]},
            "approved_c4_provenance": {"path": C4_PACKAGE_PATH, "sha256": APPROVED_C4_SHA256,
                                       "git_blob_oid": c4_blob_oid, "included_as_nested_archive": False},
            "final_test_results_sha256": sha256(final_results_bytes),
            "final_test_evidence": {relative: sha256(data) for relative, data in sorted(final_evidence_sources.items())},
            "included_source_files": sorted(EXACT_FILES),
        }
        (package_root / "REVIEW-BUILD-PROVENANCE.json").write_bytes(
            (json.dumps(build_provenance, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))
        files = {path.relative_to(package_root).as_posix(): sha256(path.read_bytes()) for path in sorted(p for p in package_root.rglob("*") if p.is_file())}
        manifest = {"schema_version": "pdc.stage2b.c6-review-package/v1", "source_branch": branch,
                    "source_head": head, "baseline_head": BASELINE_HEAD,
                    "migration_032_required": False, "migration_inventory": ["028", "029", "030", "031"],
                    "files": files}
        manifest_bytes = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode()
        (package_root / "REVIEW-MANIFEST.json").write_bytes(manifest_bytes)
        if zip_path.exists(): zip_path.unlink()
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(p for p in package_root.rglob("*") if p.is_file()):
                relative = f"{package_name}/{path.relative_to(package_root).as_posix()}"
                info = zipfile.ZipInfo(relative, (1980, 1, 1, 0, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED; info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes())
        with zipfile.ZipFile(zip_path) as archive:
            names = archive.namelist()
            expected = {f"{package_name}/{path}" for path in files} | {f"{package_name}/REVIEW-MANIFEST.json"}
            if len(names) != len(set(names)) or set(names) != expected: raise SystemExit("built ZIP inventory is unsafe")
    print(json.dumps({"path": str(zip_path), "size_bytes": zip_path.stat().st_size,
                      "sha256": sha256(zip_path.read_bytes()), "source_head": head,
                      "file_count": len(files) + 1}, sort_keys=True))


if __name__ == "__main__":
    main()
