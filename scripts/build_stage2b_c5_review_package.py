#!/usr/bin/env python3
"""Build a commit-exact, credential-scanned Stage 2B C5 review ZIP."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

from verify_stage2b_c5_review_package import scan_text

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BRANCH = "feature/stage2b-shared-vehicle-master"
BASELINE_HEAD = "1a73e3a1d1bf6c3abd2b8a349e2f1c2e0f7490ac"
EXACT_FILES = {
    ".gitignore",
    "STAGE-2B-C5-CONTROLLED-STAGING-PILOT.md",
    "backend/test_stage2b_c5_real_data_pilot.py",
    "scripts/stage2b_c4_assessment.py",
    "scripts/stage2b_c5_real_data_pilot.py",
    "scripts/build_stage2b_c5_review_package.py",
    "scripts/verify_stage2b_c5_review_package.py",
    "scripts/workshop_legacy_import.py",
    "scripts/workshop_vehicle_reference_artifact.py",
    "scripts/workshop_planner_legacy_validate.js",
    "scripts/pdc_backup.py", "scripts/pdc_restore.py",
    "supabase/migrations/028_stage2b_vehicle_master_foundation.sql",
    "supabase/migrations/029_stage2b_vehicle_master_operations.sql",
    "supabase/migrations/030_stage2b_lifecycle_identity_resolver.sql",
    "supabase/migrations/031_stage2b_importer_identity_export.sql",
}
EVIDENCE_FILES = {
    "review-evidence/stage2b-c5/selected-record-manifest.json",
    "review-evidence/stage2b-c5/approval-manifest.md",
    "review-evidence/stage2b-c5/preview-result.json",
    "review-evidence/stage2b-c5/apply-result.json",
    "review-evidence/stage2b-c5/replay-evidence.json",
    "review-evidence/stage2b-c5/reconciliation-report.json",
    "review-evidence/stage2b-c5/rollback-export.json",
    "review-evidence/stage2b-c5/rollback-report.json",
    "review-evidence/stage2b-c5/before-after-row-counts.json",
    "review-evidence/stage2b-c5/backup-restore-evidence.json",
    "review-evidence/stage2b-c5/safety.json",
    "review-evidence/stage2b-c5/pilot-summary.json",
    "review-evidence/stage2b-c5/operational-proof.json",
    "review-evidence/stage2b-c5/approved-c4-sanitized-assessment.json",
    "review-evidence/stage2b-c5/approved-c4-package.zip",
}
APPROVED_C4_SHA256 = "980bab0cc0bf79a8156fb78b2587df165406d3fd7d92929468fda66e2ba81016"
C4_PACKAGE_PATH = "review-evidence/stage2b-c5/approved-c4-package.zip"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def committed_bytes(head, path):
    return subprocess.check_output(["git", "show", f"{head}:{path}"], cwd=ROOT)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="_c5_packages")
    args = parser.parse_args(argv)
    branch, head = git("branch", "--show-current"), git("rev-parse", "HEAD")
    if branch != EXPECTED_BRANCH: raise SystemExit(f"refusing unexpected branch: {branch}")
    if git("status", "--porcelain"): raise SystemExit("refusing dirty or untracked source tree")
    tracked = set(git("ls-tree", "-r", "--name-only", head).splitlines())
    migrations = sorted(Path(path).name[:3] for path in tracked if path.startswith("supabase/migrations/") and Path(path).name[:3].isdigit())
    if migrations[-1:] != ["031"] or "032" in migrations: raise SystemExit("migration inventory is not capped through 031")
    selected = EXACT_FILES | EVIDENCE_FILES
    missing = sorted(selected - tracked)
    if missing: raise SystemExit(f"review source is not committed: {missing}")
    package_name = f"PDC-Stage2B-C5-Controlled-Staging-Pilot-Review-{head[:12]}"
    out_dir = (ROOT / args.output_dir).resolve(); out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / f"{package_name}.zip"
    with tempfile.TemporaryDirectory(prefix="pdc-c5-review-") as temp:
        package_root = Path(temp) / package_name
        for relative in sorted(selected):
            data = committed_bytes(head, relative)
            if relative == C4_PACKAGE_PATH:
                if sha256(data) != APPROVED_C4_SHA256: raise SystemExit("approved C4 package hash mismatch")
                with zipfile.ZipFile(io.BytesIO(data)) as nested:
                    for info in nested.infolist():
                        if info.is_dir(): continue
                        try: scan_text(f"{relative}!/{info.filename}", nested.read(info).decode("utf-8"))
                        except UnicodeDecodeError as exc: raise SystemExit(f"non-UTF-8 C4 member: {info.filename}") from exc
            else:
                try: scan_text(relative, data.decode("utf-8"))
                except UnicodeDecodeError as exc: raise SystemExit(f"non-UTF-8 review source: {relative}") from exc
            destination = package_root / relative; destination.parent.mkdir(parents=True, exist_ok=True); destination.write_bytes(data)
        files = {path.relative_to(package_root).as_posix(): sha256(path.read_bytes()) for path in sorted(p for p in package_root.rglob("*") if p.is_file())}
        manifest = {"schema_version": "pdc.stage2b.c5-review-package/v1", "source_branch": branch,
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
