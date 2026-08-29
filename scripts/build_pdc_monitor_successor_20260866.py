#!/usr/bin/env python3
"""Build the append-only .65 -> .66 staging runtime successor."""
from __future__ import annotations
import argparse, hashlib, json, shutil
from pathlib import Path

VERSION = "2026.08.66"
RELEASE = "pdc-monitor-staging-m502-2026.08.66"
PARENT_VERSION = "2026.08.65"
PARENT_RELEASE = "pdc-monitor-staging-m502-2026.08.65"

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inventory(root: Path) -> dict[str, dict[str, int | str]]:
    return {p.relative_to(root).as_posix(): {"bytes": p.stat().st_size, "sha256": sha(p)} for p in sorted(root.rglob("*")) if p.is_file() and p.name != "release-manifest.json"}

def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--parent-root", type=Path, required=True)
    p.add_argument("--output-root", type=Path, required=True)
    p.add_argument("--built-at-utc", required=True)
    a = p.parse_args()
    parent = a.parent_root.resolve(strict=True)
    parent_manifest_path = parent / "release-manifest.json"
    parent_manifest = json.loads(parent_manifest_path.read_text(encoding="utf-8"))
    if parent_manifest.get("release_version") != PARENT_VERSION or parent_manifest.get("release_name") != PARENT_RELEASE:
        raise SystemExit("exact .65 parent release required")
    output = a.output_root.resolve()
    if output.exists(): shutil.rmtree(output)
    shutil.copytree(parent, output, symlinks=False)
    manifest = dict(parent_manifest)
    manifest.update({
        "release_series": "pdc-monitor-staging-m502-successor",
        "release_name": RELEASE,
        "release_version": VERSION,
        "parent_release_name": PARENT_RELEASE,
        "parent_release_version": PARENT_VERSION,
        "parent_manifest_sha256": sha(parent_manifest_path),
        "built_at_utc": a.built_at_utc,
        "successor_patch": {"path": "backend/imap_bridge.py", "source_path": "backend/imap_bridge.py", "sha256": sha(output / "backend/imap_bridge.py"), "contract": "payload unchanged from verified .65; unattended refresh is sealed control-only"},
        "scheduler_successor": {"control_version": VERSION, "preflight_config": "config/2026.08.44/runtime.env", "monitor_config": "config/2026.08.66/runtime.env", "token_refresh_script": "control/pdc_monitor_refresh_20260866.py", "token_refresh_store": "secrets/2026.08.66/monitor-refresh.dpapi", "token_sync_required": False, "token_refresh_per_cycle": True, "task_identity": "LOCAL SERVICE/ServiceAccount/Limited/PT5M"},
    })
    files = inventory(output)
    manifest["files"] = files
    manifest["bundle_hash_definition"] = "sha256(canonical JSON complete internal file inventory, excluding release-manifest.json)"
    manifest["bundle_sha256"] = hashlib.sha256((json.dumps(files, sort_keys=True, separators=(",", ":")) + "\n").encode()).hexdigest()
    (output / "release-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    receipt = {"ok": True, "release_root": str(output), "release_version": VERSION, "parent_release_version": PARENT_VERSION, "parent_manifest_sha256": manifest["parent_manifest_sha256"], "manifest_sha256": sha(output / "release-manifest.json"), "files": len(files), "payload_byte_copy": True, "production_contacted": False}
    (output.parent / f"{output.name}.build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(receipt, sort_keys=True))

if __name__ == "__main__": main()
