#!/usr/bin/env python3
"""Build the append-only .65 -> .67 staging runtime source successor.

The parent bundle is copied byte-for-byte except for the one reviewed
attachment_content.py source repair and release metadata. No mailbox or
Supabase operation is performed by this builder.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

VERSION = "2026.08.67"
RELEASE = "pdc-monitor-staging-m502-2026.08.67"
PARENT_VERSION = "2026.08.65"
PARENT_RELEASE = "pdc-monitor-staging-m502-2026.08.65"
ATTACHMENT_PATH = "backend/attachment_content.py"
EXPECTED_STAGING_REF = "cdsmnqxtyyoeoznmbidd"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root: Path) -> dict[str, dict[str, int | str]]:
    return {
        path.relative_to(root).as_posix(): {"bytes": path.stat().st_size, "sha256": sha(path)}
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.name != "release-manifest.json"
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent-root", type=Path, required=True)
    parser.add_argument("--attachment-source", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--built-at-utc", required=True)
    args = parser.parse_args()

    parent = args.parent_root.resolve(strict=True)
    attachment_source = args.attachment_source.resolve(strict=True)
    if not attachment_source.is_file() or attachment_source.is_symlink():
        raise SystemExit("attachment source must be one regular file")
    parent_manifest_path = parent / "release-manifest.json"
    parent_manifest = json.loads(parent_manifest_path.read_text(encoding="utf-8"))
    if parent_manifest.get("release_version") != PARENT_VERSION or parent_manifest.get("release_name") != PARENT_RELEASE:
        raise SystemExit("exact .65 parent release required")

    output = args.output_root.resolve()
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(parent, output, symlinks=False)
    shutil.copyfile(attachment_source, output / ATTACHMENT_PATH)

    manifest = dict(parent_manifest)
    manifest.update({
        "release_series": "pdc-monitor-staging-m502-successor",
        "release_name": RELEASE,
        "release_version": VERSION,
        "parent_release_name": PARENT_RELEASE,
        "parent_release_version": PARENT_VERSION,
        "parent_manifest_sha256": sha(parent_manifest_path),
        "built_at_utc": args.built_at_utc,
        "expected_staging_project_ref": EXPECTED_STAGING_REF,
        "outbound_email_enabled": False,
        "successor_patch": {
            "path": ATTACHMENT_PATH,
            "source_path": "backend/attachment_content.py",
            "sha256": sha(attachment_source),
            "contract": "only image.png plus structurally verified JPEG plus reported image/jpeg is accepted; original name/hash/path preserved",
        },
        "scheduler_successor": {
            "control_version": VERSION,
            "parent_runtime": PARENT_VERSION,
            "task_must_remain_disabled": True,
            "mailbox_contacted": False,
            "uid514_processed": False,
            "production_contacted": False,
        },
    })
    files = inventory(output)
    manifest["files"] = files
    manifest["bundle_hash_definition"] = "sha256(canonical JSON complete internal file inventory, excluding release-manifest.json)"
    manifest["bundle_sha256"] = hashlib.sha256(
        (json.dumps(files, sort_keys=True, separators=(",", ":")) + "\n").encode()
    ).hexdigest()
    (output / "release-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    receipt = {
        "ok": True,
        "release_root": str(output),
        "release_version": VERSION,
        "parent_release_version": PARENT_VERSION,
        "parent_manifest_sha256": manifest["parent_manifest_sha256"],
        "attachment_source_sha256": sha(attachment_source),
        "manifest_sha256": sha(output / "release-manifest.json"),
        "files": len(files),
        "payload_byte_copy_except_reviewed_attachment": True,
        "production_contacted": False,
        "mailbox_contacted": False,
    }
    (output.parent / f"{output.name}.build-receipt.json").write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(receipt, sort_keys=True))


if __name__ == "__main__":
    main()
