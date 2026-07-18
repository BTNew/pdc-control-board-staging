#!/usr/bin/env python3
"""Verify a focused Stage 2B C3 review extraction and optional source ZIP."""
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
EXPECTED_SCHEMA = "pdc.stage2b.c3-review-package/v1"
EXPECTED_BRANCH = "feature/stage2b-shared-vehicle-master"
EXPECTED_BASELINE = "8239a5db128fb9ccf181232a5a442408cb2ecaf5"
MANIFEST_KEYS = {"schema_version", "source_branch", "source_head", "baseline_head", "migration_032_required", "migration_inventory", "files"}
REQUIRED_FILES = {
    "scripts/stage2b_c3_reconciliation.py",
    "scripts/stage2b_c3_synthetic_pilot.py",
    "scripts/build_stage2b_c3_review_package.py",
    "scripts/verify_stage2b_c3_review_package.py",
    "backend/fixtures/stage2b_c3_synthetic_pilot.json",
    "backend/test_stage2b_c3_reconciliation.py",
    "backend/test_stage2b_c3_synthetic_pilot.py",
    "review-evidence/stage2b-c3/c3-backup.json",
    "review-evidence/stage2b-c3/c3-cleanup.json",
    "review-evidence/stage2b-c3/c3-safety.json",
    "review-evidence/stage2b-c3/c3-test-results.json",
    "supabase/migrations/028_stage2b_vehicle_master_foundation.sql",
    "supabase/migrations/029_stage2b_vehicle_master_operations.sql",
    "supabase/migrations/030_stage2b_lifecycle_identity_resolver.sql",
    "supabase/migrations/031_stage2b_importer_identity_export.sql",
}
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
    if relative.startswith("review-evidence/stage2b-c3/"):
        lowered = text.lower()
        forbidden = ("://", "password", "database_url", "customer_name", "customer_email",
                     "source_payload", "ai_analysis", "parts_status", "workshop_status")
        hits = [value for value in forbidden if value in lowered]
        if hits:
            raise SystemExit(f"prohibited evidence content in {relative}: {hits}")


def load_and_verify_extraction():
    manifest_path = ROOT / "REVIEW-MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
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
    if any("/032_" in f"/{relative}" for relative in expected):
        raise SystemExit("migration 032 is present despite the manifest assertion")
    actual = set()
    for path in ROOT.rglob("*"):
        if path.is_symlink():
            raise SystemExit(f"symlink is forbidden: {path}")
        if path.is_file():
            actual.add(path.relative_to(ROOT).as_posix())
    if actual != expected | {"REVIEW-MANIFEST.json"}:
        raise SystemExit(f"unmanifested or missing files: extra={sorted(actual-expected-{'REVIEW-MANIFEST.json'})} missing={sorted(expected-actual)}")
    for relative, expected_hash in files.items():
        if not re.fullmatch(r"[0-9a-f]{64}", str(expected_hash)):
            raise SystemExit(f"invalid manifest hash: {relative}")
        data = (ROOT / relative).read_bytes()
        if sha256(data) != expected_hash:
            raise SystemExit(f"checksum mismatch: {relative}")
        try:
            scan_text(relative, data.decode("utf-8"))
        except UnicodeDecodeError as exc:
            raise SystemExit(f"non-UTF-8 package file: {relative}") from exc
    return manifest, actual


def verify_zip(zip_path: Path, manifest, extracted_files):
    with zipfile.ZipFile(zip_path) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            raise SystemExit("duplicate ZIP members")
        root_name = ROOT.name
        expected_names = {f"{root_name}/{relative}" for relative in extracted_files}
        if set(names) != expected_names:
            raise SystemExit("ZIP inventory differs from the pristine extraction")
        for info in infos:
            relative = info.filename.removeprefix(root_name + "/")
            safe_relative(relative)
            if ((info.external_attr >> 16) & 0o170000) == 0o120000:
                raise SystemExit(f"ZIP symlink is forbidden: {info.filename}")
            data = archive.read(info)
            expected_hash = (sha256((ROOT / "REVIEW-MANIFEST.json").read_bytes())
                             if relative == "REVIEW-MANIFEST.json" else manifest["files"][relative])
            if sha256(data) != expected_hash:
                raise SystemExit(f"ZIP byte mismatch: {info.filename}")


def run(command):
    completed = subprocess.run(command, cwd=ROOT, env={**os.environ, "PYTHONPATH": str(ROOT / "scripts")}, check=False)
    if completed.returncode:
        raise SystemExit(completed.returncode)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip", dest="zip_path")
    args = parser.parse_args(argv)
    manifest, extracted_files = load_and_verify_extraction()
    if args.zip_path:
        verify_zip(Path(args.zip_path).resolve(), manifest, extracted_files)
    run([sys.executable, "-m", "unittest",
         "backend.test_stage2b_offline_vehicle_reference_artifact",
         "backend.test_stage2b_importer_identity_export_foundation",
         "backend.test_stage2b_importer_identity_export_adapter",
         "backend.test_stage2b_c3_reconciliation",
         "backend.test_stage2b_c3_synthetic_pilot", "-v"])
    run([sys.executable, "-m", "py_compile",
         "scripts/workshop_vehicle_reference_artifact.py",
         "scripts/workshop_legacy_import.py",
         "scripts/stage2b_c3_reconciliation.py",
         "scripts/stage2b_c3_synthetic_pilot.py"])
    run(["node", "--check", "scripts/workshop_vehicle_reference_artifact.js"])
    run(["node", "--check", "scripts/workshop_planner_legacy_validate.js"])
    print(json.dumps({"manifest_files": len(manifest["files"]), "package_scan": "passed",
                      "non_secret_tests": "passed", "source_head": manifest["source_head"]}, sort_keys=True))


if __name__ == "__main__":
    main()
