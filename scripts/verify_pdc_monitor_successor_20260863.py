#!/usr/bin/env python3
"""Credential-free verifier for the parent-bound 2026.08.63 successor."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> None:
    raise ValueError(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--expected-manifest-sha256", required=True)
    parser.add_argument("--expected-parent-manifest-sha256", required=True)
    parser.add_argument("--expected-bridge-sha256", required=True)
    parser.add_argument("--expected-processor-sha256", required=True)
    parser.add_argument("--expected-jobcard-sha256", required=True)
    args = parser.parse_args()
    root = args.bundle.resolve(strict=True)
    manifest_path = root / "release-manifest.json"
    if not HEX64.fullmatch(args.expected_manifest_sha256) or sha(manifest_path) != args.expected_manifest_sha256:
        fail("successor manifest hash mismatch")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected = {
        "release_series": "pdc-monitor-staging-m502-successor",
        "release_name": "pdc-monitor-staging-m502-2026.08.63",
        "release_version": "2026.08.63",
        "expected_staging_project_ref": "cdsmnqxtyyoeoznmbidd",
        "supported_migration_head": 503,
        "outbound_email_enabled": False,
        "parent_manifest_sha256": args.expected_parent_manifest_sha256,
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            fail(f"successor manifest binding mismatch: {key}")
    for key in ("source_sha", "source_tree", "staging_deployment_sha"):
        if not HEX40.fullmatch(str(manifest.get(key, ""))):
            fail(f"successor provenance invalid: {key}")
    patch = manifest.get("successor_patch")
    if not isinstance(patch, dict) or patch.get("path") != "backend/imap_bridge.py" or patch.get("sha256") != args.expected_bridge_sha256:
        fail("successor patch binding mismatch")
    inventory = manifest.get("files")
    if not isinstance(inventory, dict) or not inventory:
        fail("successor inventory missing")
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and p.name != "release-manifest.json"}
    if actual != set(inventory):
        fail("successor complete inventory mismatch")
    for rel, metadata in inventory.items():
        path = (root / rel).resolve(strict=True)
        if root not in path.parents or not isinstance(metadata, dict) or not HEX64.fullmatch(str(metadata.get("sha256", ""))):
            fail("successor inventory path or digest invalid")
        if path.stat().st_size != metadata.get("bytes") or sha(path) != metadata["sha256"]:
            fail(f"successor member changed: {rel}")
    if sha(root / "backend" / "imap_bridge.py") != args.expected_bridge_sha256:
        fail("successor bridge hash mismatch")
    processor = manifest.get("successor_processor")
    if (not isinstance(processor, dict) or processor.get("path") != "backend/email_intake_processor.py"
            or processor.get("sha256") != args.expected_processor_sha256
            or sha(root / "backend" / "email_intake_processor.py") != args.expected_processor_sha256):
        fail("successor processor hash mismatch")
    jobcard = manifest.get("successor_jobcard_client")
    if (not isinstance(jobcard, dict) or jobcard.get("path") != "backend/pdc_jobcard_runtime_client.py"
            or jobcard.get("sha256") != args.expected_jobcard_sha256
            or sha(root / "backend" / "pdc_jobcard_runtime_client.py") != args.expected_jobcard_sha256):
        fail("successor jobcard client hash mismatch")
    if manifest.get("storage_path_contract", "").startswith("pdc-email-intake-private/") is False:
        fail("successor storage path contract missing")
    if manifest.get("storage_reconciliation_contract", "").find("append-only") < 0:
        fail("successor reconciliation contract missing")
    if manifest.get("admin_requeue_contract", "").find("admin_requeue_pdc_email_intake_735") < 0:
        fail("successor requeue contract missing")
    print(json.dumps({"ok": True, "release": manifest["release_name"], "files": len(inventory), "manifest_sha256": args.expected_manifest_sha256, "parent_manifest_sha256": args.expected_parent_manifest_sha256, "production_contacted": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
