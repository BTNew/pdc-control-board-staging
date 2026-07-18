#!/usr/bin/env python3
"""Build a commit-exact, credential-free Stage 2B C3 review ZIP."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BRANCH = "feature/stage2b-shared-vehicle-master"

EXACT_FILES = {
    ".github/workflows/stage2b-c3-cross-platform.yml",
    "STAGE-2B-C3-SYNTHETIC-PILOT.md",
    "backend/fixtures/stage2b_c2b_vehicle_reference_semantics.json",
    "backend/fixtures/stage2b_c3_synthetic_pilot.json",
    "backend/test_stage2b_offline_vehicle_reference_artifact.py",
    "backend/test_stage2b_importer_identity_export_foundation.py",
    "backend/test_stage2b_importer_identity_export_adapter.py",
    "backend/test_stage2b_c3_reconciliation.py",
    "backend/test_stage2b_c3_synthetic_pilot.py",
    "scripts/workshop_vehicle_reference_artifact.js",
    "scripts/workshop_vehicle_reference_artifact.py",
    "scripts/workshop_planner_legacy_validate.js",
    "scripts/workshop_legacy_import.py",
    "scripts/stage2b_c3_reconciliation.py",
    "scripts/stage2b_c3_synthetic_pilot.py",
    "scripts/build_stage2b_c3_review_package.py",
    "scripts/verify_stage2b_c3_review_package.py",
    "supabase/migrations/028_stage2b_vehicle_master_foundation.sql",
    "supabase/migrations/029_stage2b_vehicle_master_operations.sql",
    "supabase/migrations/030_stage2b_lifecycle_identity_resolver.sql",
    "supabase/migrations/031_stage2b_importer_identity_export.sql",
}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def committed_bytes(head, path):
    return subprocess.check_output(["git", "show", f"{head}:{path}"], cwd=ROOT)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="_review_packages")
    args = parser.parse_args(argv)
    branch = git("branch", "--show-current")
    head = git("rev-parse", "HEAD")
    if branch != EXPECTED_BRANCH:
        raise SystemExit(f"refusing unexpected branch: {branch}")
    if git("status", "--porcelain"):
        raise SystemExit("refusing dirty or untracked source tree")
    tracked = set(git("ls-tree", "-r", "--name-only", head).splitlines())
    selected = set(EXACT_FILES)
    selected.update(path for path in tracked if path.startswith("review-evidence/stage2b-c3/"))
    missing = sorted(selected - tracked)
    if missing:
        raise SystemExit(f"review source is not committed: {missing}")

    package_name = f"PDC-Stage2B-C3-Synthetic-Pilot-Review-{head[:12]}"
    out_dir = (ROOT / args.output_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / f"{package_name}.zip"
    with tempfile.TemporaryDirectory(prefix="pdc-c3-review-") as temp:
        package_root = Path(temp) / package_name
        for relative in sorted(selected):
            destination = package_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(committed_bytes(head, relative))
        files = {}
        for path in sorted(p for p in package_root.rglob("*") if p.is_file()):
            relative = path.relative_to(package_root).as_posix()
            files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        manifest = {
            "schema_version": "pdc.stage2b.c3-review-package/v1",
            "source_branch": branch,
            "source_head": head,
            "baseline_head": "8239a5db128fb9ccf181232a5a442408cb2ecaf5",
            "migration_032_required": False,
            "files": files,
        }
        (package_root / "REVIEW-MANIFEST.json").write_text(
            json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
        if zip_path.exists():
            zip_path.unlink()
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(p for p in package_root.rglob("*") if p.is_file()):
                relative = f"{package_name}/{path.relative_to(package_root).as_posix()}"
                info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes())
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    print(json.dumps({"path": str(zip_path), "size_bytes": zip_path.stat().st_size,
                      "sha256": digest, "source_head": head,
                      "file_count": len(files) + 1}, sort_keys=True))


if __name__ == "__main__":
    main()
