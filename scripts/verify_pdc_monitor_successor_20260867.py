#!/usr/bin/env python3
"""Credential-free verifier for the parent-bound .67 attachment successor."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_RELEASE = "pdc-monitor-staging-m502-2026.08.67"
EXPECTED_PARENT = "pdc-monitor-staging-m502-2026.08.65"
EXPECTED_VERSION = "2026.08.67"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--expected-manifest-sha256", required=True)
    parser.add_argument("--expected-parent-manifest-sha256", required=True)
    parser.add_argument("--expected-attachment-source-sha256", required=True)
    args = parser.parse_args()
    root = args.bundle.resolve(strict=True)
    manifest_path = root / "release-manifest.json"
    for value, label in ((args.expected_manifest_sha256, "manifest"), (args.expected_parent_manifest_sha256, "parent manifest"), (args.expected_attachment_source_sha256, "attachment source")):
        if not HEX64.fullmatch(value.lower()):
            raise ValueError(f"{label} hash is invalid")
    if sha(manifest_path) != args.expected_manifest_sha256.lower():
        raise ValueError("successor manifest hash mismatch")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected = {
        "release_series": "pdc-monitor-staging-m502-successor",
        "release_name": EXPECTED_RELEASE,
        "release_version": EXPECTED_VERSION,
        "parent_release_name": EXPECTED_PARENT,
        "parent_release_version": "2026.08.65",
        "parent_manifest_sha256": args.expected_parent_manifest_sha256.lower(),
        "expected_staging_project_ref": EXPECTED_REF,
        "outbound_email_enabled": False,
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise ValueError(f"successor manifest binding mismatch: {key}")
    patch = manifest.get("successor_patch")
    attachment = root / "backend" / "attachment_content.py"
    if (not isinstance(patch, dict) or patch.get("path") != "backend/attachment_content.py"
            or patch.get("sha256") != args.expected_attachment_source_sha256.lower()
            or sha(attachment) != args.expected_attachment_source_sha256.lower()):
        raise ValueError("successor attachment source binding mismatch")
    text = attachment.read_text(encoding="utf-8")
    for marker in (
        "preserved_jpeg_name = ext == \".png\" and detected == \".jpg\" and reported == \"image/jpeg\"",
        "canonical = \"image/jpeg\" if preserved_jpeg_name else CANONICAL_MIME_BY_EXTENSION[ext]",
        "unsupported_attachment_type: HEIC",
        "attachment_content_unknown",
    ):
        if marker not in text:
            raise ValueError(f"attachment validator marker missing: {marker}")
    scheduler = manifest.get("scheduler_successor")
    if not isinstance(scheduler, dict) or scheduler.get("task_must_remain_disabled") is not True or scheduler.get("mailbox_contacted") is not False or scheduler.get("uid514_processed") is not False or scheduler.get("production_contacted") is not False:
        raise ValueError("successor staging safety binding missing")
    files = manifest.get("files")
    if not isinstance(files, dict) or not files:
        raise ValueError("successor inventory missing")
    actual = {path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file() and path.name != "release-manifest.json"}
    if actual != set(files):
        raise ValueError("successor complete inventory mismatch")
    for rel, metadata in files.items():
        path = (root / rel).resolve(strict=True)
        if root not in path.parents or not isinstance(metadata, dict) or not HEX64.fullmatch(str(metadata.get("sha256", ""))):
            raise ValueError("successor inventory path or digest invalid")
        if path.stat().st_size != metadata.get("bytes") or sha(path) != metadata["sha256"]:
            raise ValueError(f"successor member changed: {rel}")
    print(json.dumps({"ok": True, "release": EXPECTED_RELEASE, "files": len(files), "manifest_sha256": args.expected_manifest_sha256.lower(), "parent_manifest_sha256": args.expected_parent_manifest_sha256.lower(), "attachment_source_sha256": args.expected_attachment_source_sha256.lower(), "production_contacted": False, "mailbox_contacted": False}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "production_contacted": False, "mailbox_contacted": False}, sort_keys=True))
        raise SystemExit(1)
