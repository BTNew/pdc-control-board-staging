#!/usr/bin/env python3
"""Build a deterministic .44-derived staging runtime successor.

The parent release is copied byte-for-byte except for the reviewed IMAP bridge
successor. The output manifest inventories every copied member and records the
parent manifest and patch hashes so installation can fail closed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

HEX64 = set("0123456789abcdef")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_inventory_bytes(inventory: dict[str, dict[str, int | str]]) -> bytes:
    return (json.dumps(inventory, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent-root", type=Path, required=True)
    parser.add_argument("--parent-manifest-sha256", required=True)
    parser.add_argument("--bridge-source", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--source-tree-sha", required=True)
    parser.add_argument("--staging-deployment-sha", required=True)
    parser.add_argument("--built-at-utc", required=True)
    args = parser.parse_args()

    if any(len(value) != 64 or any(ch not in HEX64 for ch in value.lower()) for value in (args.parent_manifest_sha256,)):
        raise SystemExit("parent manifest SHA-256 is invalid")
    if any(len(value) != 40 or any(ch not in HEX64 for ch in value.lower()) for value in (args.source_sha, args.source_tree_sha, args.staging_deployment_sha)):
        raise SystemExit("source provenance SHA is invalid")
    parent = args.parent_root.resolve(strict=True)
    bridge = args.bridge_source.resolve(strict=True)
    output = args.output_root.resolve()
    parent_manifest = parent / "release-manifest.json"
    if sha(parent_manifest) != args.parent_manifest_sha256.lower():
        raise SystemExit("parent manifest hash mismatch")
    if not bridge.is_file() or bridge.is_symlink():
        raise SystemExit("successor bridge must be one regular file")
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(parent, output, symlinks=False)
    target = output / "backend" / "imap_bridge.py"
    shutil.copyfile(bridge, target)
    manifest = json.loads(parent_manifest.read_text(encoding="utf-8"))
    manifest.update({
        "release_series": "pdc-monitor-staging-m502-successor",
        "release_name": "pdc-monitor-staging-m502-2026.08.46",
        "release_version": "2026.08.46",
        "source_sha": args.source_sha.lower(),
        "source_tree": args.source_tree_sha.lower(),
        "staging_deployment_sha": args.staging_deployment_sha.lower(),
        "built_at_utc": args.built_at_utc,
        "parent_release_name": manifest.get("release_name"),
        "parent_release_version": manifest.get("release_version"),
        "parent_manifest_sha256": args.parent_manifest_sha256.lower(),
        "successor_patch": {
            "path": "backend/imap_bridge.py",
            "source_path": "backend/imap_bridge_successor_20260846.py",
            "sha256": sha(bridge),
            "contract": "HTTP 400 body code KeyAlreadyExists and statusCode 409 only",
        },
        "storage_existing_object_response": {
            "http_status": 400,
            "code": "KeyAlreadyExists",
            "statusCode": 409,
            "idempotent": True,
        },
        "verifyonly_anchor_contract": "successor-specific VERIFYONLY_BOOTSTRAP_SHA256 and VERIFYONLY_RUNNER_SHA256; no legacy shared bootstrap anchor",
    })
    inventory: dict[str, dict[str, int | str]] = {}
    for path in sorted(p for p in output.rglob("*") if p.is_file() and p.name != "release-manifest.json"):
        rel = path.relative_to(output).as_posix()
        inventory[rel] = {"bytes": path.stat().st_size, "sha256": sha(path)}
    manifest["files"] = inventory
    manifest["bundle_hash_definition"] = "sha256(canonical JSON complete internal file inventory, excluding release-manifest.json)"
    manifest["bundle_sha256"] = hashlib.sha256(canonical_inventory_bytes(inventory)).hexdigest()
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    receipt = {
        "ok": True,
        "release_root": str(output),
        "release_version": manifest["release_version"],
        "manifest_sha256": sha(output / "release-manifest.json"),
        "parent_manifest_sha256": args.parent_manifest_sha256.lower(),
        "successor_patch_sha256": sha(bridge),
        "files": len(inventory),
    }
    (output.parent / (output.name + ".build-receipt.json")).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
