#!/usr/bin/env python3
"""Build a complete byte-copied .68 -> .69 staging bundle."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

VERSION = "2026.08.69"
RELEASE = "pdc-monitor-staging-m502-2026.08.69"
PARENT_VERSION = "2026.08.68"
PARENT_RELEASE = "pdc-monitor-staging-m502-2026.08.68"
PROJECT = "cdsmnqxtyyoeoznmbidd"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root: Path) -> dict[str, dict[str, int | str]]:
    return {
        p.relative_to(root).as_posix(): {"bytes": p.stat().st_size, "sha256": sha(p)}
        for p in sorted(root.rglob("*"))
        if p.is_file() and p.name != "release-manifest.json"
    }


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--parent-root", type=Path, required=True)
    p.add_argument("--bridge-source", type=Path, required=True)
    p.add_argument("--output-root", type=Path, required=True)
    p.add_argument("--built-at-utc", required=True)
    a = p.parse_args()
    parent = a.parent_root.resolve(strict=True)
    source = a.bridge_source.resolve(strict=True)
    if not source.is_file() or source.is_symlink():
        raise SystemExit("bridge source must be one regular file")
    parent_manifest_path = parent / "release-manifest.json"
    parent_manifest = json.loads(parent_manifest_path.read_text(encoding="utf-8"))
    if parent_manifest.get("release_version") != PARENT_VERSION or parent_manifest.get("release_name") != PARENT_RELEASE:
        raise SystemExit("exact .68 parent release required")
    output = a.output_root.resolve()
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(parent, output, symlinks=False)
    shutil.copyfile(source, output / "backend/imap_bridge.py")
    manifest = dict(parent_manifest)
    manifest.update({
        "release_series": "pdc-monitor-staging-m502-successor",
        "release_name": RELEASE,
        "release_version": VERSION,
        "parent_release_name": PARENT_RELEASE,
        "parent_release_version": PARENT_VERSION,
        "parent_manifest_sha256": sha(parent_manifest_path),
        "built_at_utc": a.built_at_utc,
        "expected_staging_project_ref": PROJECT,
        "outbound_email_enabled": False,
        "successor_patch": {
            "path": "backend/imap_bridge.py",
            "source_path": str(source),
            "sha256": sha(source),
            "contract": "exact NoSuchKey/404/Object not found only; three readback attempts; all other errors fail closed",
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
    manifest["bundle_sha256"] = hashlib.sha256((json.dumps(files, sort_keys=True, separators=(",", ":")) + "\n").encode()).hexdigest()
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    receipt = {"ok": True, "release_root": str(output), "release_version": VERSION, "parent_release_version": PARENT_VERSION, "parent_manifest_sha256": manifest["parent_manifest_sha256"], "bridge_source_sha256": sha(source), "manifest_sha256": sha(output / "release-manifest.json"), "files": len(files), "payload_byte_copy_except_reviewed_bridge": True, "task_enabled": False, "mailbox_contacted": False, "production_contacted": False}
    (output.parent / f"{output.name}.build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(receipt, sort_keys=True))


if __name__ == "__main__":
    main()
