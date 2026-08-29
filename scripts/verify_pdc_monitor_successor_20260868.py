#!/usr/bin/env python3
"""Credential-free verifier for the .66 -> .68 current-head successor."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")
PROJECT = "cdsmnqxtyyoeoznmbidd"
VERSION = "2026.08.68"
RELEASE = "pdc-monitor-staging-m502-2026.08.68"
PARENT = "pdc-monitor-staging-m502-2026.08.66"
SEALED = "pdc-monitor-staging-m502-2026.08.44"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--expected-manifest-sha256", required=True)
    parser.add_argument("--expected-parent-manifest-sha256", required=True)
    parser.add_argument("--expected-processor-sha256", required=True)
    args = parser.parse_args()
    root = args.bundle.resolve(strict=True)
    for value in (args.expected_manifest_sha256, args.expected_parent_manifest_sha256, args.expected_processor_sha256):
        if not HEX64.fullmatch(value.lower()):
            raise ValueError("expected digest is invalid")
    manifest_path = root / "release-manifest.json"
    if sha(manifest_path) != args.expected_manifest_sha256.lower():
        raise ValueError("successor manifest hash mismatch")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected = {
        "release_version": VERSION, "release_name": RELEASE,
        "parent_release_version": "2026.08.66", "parent_release_name": PARENT,
        "parent_manifest_sha256": args.expected_parent_manifest_sha256.lower(),
        "expected_staging_project_ref": PROJECT, "current_staging_migration_head": 766,
        "supported_migration_head": 766, "sealed_parent_release_name": SEALED,
        "outbound_email_enabled": False,
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise ValueError(f"successor manifest binding mismatch: {key}")
    processor = root / "backend/email_intake_processor.py"
    if sha(processor) != args.expected_processor_sha256.lower():
        raise ValueError("successor processor digest mismatch")
    processor_text = processor.read_text(encoding="utf-8")
    for marker in (
        "attest_pdc_monitor_provider_email_observation_current_766",
        '"p_gateway_instance_id": self.gateway_instance_id',
        '"p_claim_token": str(record.get("claim_token") or "")',
        "claim_pdc_email_intake_authenticated_exact_732",
        "process_claimed_pdc_email_intake_work",
    ):
        if marker not in processor_text:
            raise ValueError(f"processor compatibility marker missing: {marker}")
    migration = root / "supabase/staging_only/20260830050000_766_monitor_current_head_compatibility.sql"
    sql = migration.read_text(encoding="utf-8").lower()
    for marker in (
        "20260830040000", "20260830050000", "766_monitor_current_head_compatibility",
        "verify_pdc_monitor_runtime_binding_authenticated_766",
        "attest_pdc_monitor_provider_email_observation_current_766",
        "claim_pdc_email_intake_authenticated_exact_732",
        "process_claimed_pdc_email_intake_work", "minimum_uid=640",
        "force row level security", "pdc_production_environment_sentinel",
        "mailbox_contacted", "uid514_processed", "production_writes",
    ):
        if marker not in sql:
            raise ValueError(f"current-head migration marker missing: {marker}")
    for relative, expected_digest in (
        ("trusted-control/pdc_active_semantic_planner.py", "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348"),
        ("trusted-control/pdc-active-semantic-planner-trust-receipt.json", "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227"),
    ):
        if sha(root / relative) != expected_digest:
            raise ValueError(f"planner trust digest mismatch: {relative}")
    files = manifest.get("files")
    if not isinstance(files, dict) or not files:
        raise ValueError("successor inventory missing")
    actual = {path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file() and path.name != "release-manifest.json"}
    if actual != set(files):
        raise ValueError("successor complete inventory mismatch")
    for relative, metadata in files.items():
        path = (root / relative).resolve(strict=True)
        if root not in path.parents or not isinstance(metadata, dict) or sha(path) != metadata.get("sha256") or path.stat().st_size != metadata.get("bytes"):
            raise ValueError(f"successor member changed: {relative}")
        raw = path.read_bytes()
        if relative != "scripts/verify_pdc_monitor_successor_20260868.py" and b"BEGIN PRIVATE KEY" in raw:
            raise ValueError(f"credential material signature found: {relative}")
    print(json.dumps({"ok": True, "release": RELEASE, "files": len(files), "manifest_sha256": args.expected_manifest_sha256.lower(), "parent_manifest_sha256": args.expected_parent_manifest_sha256.lower(), "processor_sha256": args.expected_processor_sha256.lower(), "current_staging_migration_head": 766, "mailbox_contacted": False, "production_contacted": False}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "mailbox_contacted": False, "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
