#!/usr/bin/env python3
"""Build a commit-exact, credential-scanned Stage 2B C3 review ZIP."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

from verify_stage2b_c3_review_package import scan_text

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BRANCH = "feature/stage2b-shared-vehicle-master"
BASELINE_HEAD = "8239a5db128fb9ccf181232a5a442408cb2ecaf5"

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
EVIDENCE_FILES = {
    "review-evidence/stage2b-c3/c3-artifact-metadata.json",
    "review-evidence/stage2b-c3/c3-backup.json",
    "review-evidence/stage2b-c3/c3-cleanup.json",
    "review-evidence/stage2b-c3/c3-pilot-summary.json",
    "review-evidence/stage2b-c3/c3-preview-actions.json",
    "review-evidence/stage2b-c3/c3-reconciliation.json",
    "review-evidence/stage2b-c3/c3-rollback.json",
    "review-evidence/stage2b-c3/c3-safety.json",
    "review-evidence/stage2b-c3/c3-test-results.json",
}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def committed_bytes(head, path):
    return subprocess.check_output(["git", "show", f"{head}:{path}"], cwd=ROOT)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


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
    migration_names = sorted(Path(path).name[:3] for path in tracked if path.startswith("supabase/migrations/") and Path(path).name[:3].isdigit())
    required_c3_migrations = {"028", "029", "030", "031"}
    missing_c3_migrations = sorted(required_c3_migrations - set(migration_names))
    if missing_c3_migrations:
        raise SystemExit(f"required C3 migration inventory is incomplete: {missing_c3_migrations}")
    selected = EXACT_FILES | EVIDENCE_FILES
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
            data = committed_bytes(head, relative)
            try:
                scan_text(relative, data.decode("utf-8"))
            except UnicodeDecodeError as exc:
                raise SystemExit(f"non-UTF-8 review source: {relative}") from exc
            destination = package_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
        files = {
            path.relative_to(package_root).as_posix(): sha256(path.read_bytes())
            for path in sorted(p for p in package_root.rglob("*") if p.is_file())
        }
        manifest = {
            "schema_version": "pdc.stage2b.c3-review-package/v1",
            "source_branch": branch,
            "source_head": head,
            "baseline_head": BASELINE_HEAD,
            "migration_032_required": False,
            "migration_inventory": ["028", "029", "030", "031"],
            "files": files,
        }
        manifest_bytes = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        (package_root / "REVIEW-MANIFEST.json").write_bytes(manifest_bytes)
        if zip_path.exists():
            zip_path.unlink()
        expected_members = set()
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(p for p in package_root.rglob("*") if p.is_file()):
                relative = f"{package_name}/{path.relative_to(package_root).as_posix()}"
                expected_members.add(relative)
                info = zipfile.ZipInfo(relative, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes())
        with zipfile.ZipFile(zip_path) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)) or set(names) != expected_members:
                raise SystemExit("built ZIP member inventory is unsafe")
            for name in names:
                relative = name.removeprefix(package_name + "/")
                expected_hash = sha256(manifest_bytes) if relative == "REVIEW-MANIFEST.json" else files[relative]
                if sha256(archive.read(name)) != expected_hash:
                    raise SystemExit(f"built ZIP byte mismatch: {name}")
    digest = sha256(zip_path.read_bytes())
    print(json.dumps({"path": str(zip_path), "size_bytes": zip_path.stat().st_size,
                      "sha256": digest, "source_head": head,
                      "file_count": len(files) + 1}, sort_keys=True))


if __name__ == "__main__":
    main()
