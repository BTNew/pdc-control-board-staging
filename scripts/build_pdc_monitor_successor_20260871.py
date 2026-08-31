#!/usr/bin/env python3
"""Build the immutable .69 -> .71 STAGING monitor successor.

The parent release is copied byte-for-byte except for the two reviewed repair
sources. Current-head controls are rendered into a separate protected control
set. No ProgramData or mailbox operation is performed by this builder.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

VERSION = "2026.08.71"
RELEASE = "pdc-monitor-staging-m502-2026.08.71"
PARENT_VERSION = "2026.08.69"
PARENT_RELEASE = "pdc-monitor-staging-m502-2026.08.69"
CURRENT_HEAD = "20260831380000"
PROJECT = "cdsmnqxtyyoeoznmbidd"
TEXT_SUFFIXES = {".json", ".md", ".py", ".ps1", ".txt", ".cfg", ".env", ""}
DYNAMIC_TRUST = {"MANIFEST_SHA256", "TRUST_SHA256", "VENV_SHA256.tsv"}


def digest_bytes(raw: bytes, path: Path) -> str:
    # Windows transport hashes are raw-byte hashes; the Recovery Pack's
    # cross-checkout canonicalization is a separate contract.
    return hashlib.sha256(raw).hexdigest()


def sha(path: Path) -> str:
    return digest_bytes(path.read_bytes(), path)


def canonical_inventory(root: Path, *, exclude: set[str] | None = None) -> dict[str, dict[str, int | str]]:
    excluded = exclude or set()
    return {
        path.relative_to(root).as_posix(): {"bytes": path.stat().st_size, "sha256": sha(path)}
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.relative_to(root).as_posix() not in excluded
    }


def inventory_hash(inventory: dict[str, dict[str, int | str]]) -> str:
    return hashlib.sha256((json.dumps(inventory, sort_keys=True, separators=(",", ":")) + "\n").encode()).hexdigest()


def render_control(source: Path, destination: Path) -> None:
    text = source.read_text(encoding="utf-8-sig")
    text = text.replace("2026.08.69", VERSION).replace("20260869", "20260871")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent-root", type=Path, required=True)
    parser.add_argument("--storage-bridge-source", type=Path, required=True)
    parser.add_argument("--processor-source", type=Path, required=True)
    parser.add_argument("--active-bootstrap-source", type=Path, required=True)
    parser.add_argument("--active-dispatch-source", type=Path, required=True)
    parser.add_argument("--current-head-preflight-source", type=Path, required=True)
    parser.add_argument("--installer-source", type=Path, required=True)
    parser.add_argument("--verifier-source", type=Path, required=True)
    parser.add_argument("--receipt-schema-source", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--built-at-utc", required=True)
    args = parser.parse_args()

    parent = args.parent_root.resolve(strict=True)
    sources = [
        args.storage_bridge_source.resolve(strict=True),
        args.processor_source.resolve(strict=True),
        args.active_bootstrap_source.resolve(strict=True),
        args.active_dispatch_source.resolve(strict=True),
        args.current_head_preflight_source.resolve(strict=True),
        args.installer_source.resolve(strict=True),
        args.verifier_source.resolve(strict=True),
        args.receipt_schema_source.resolve(strict=True),
    ]
    if any(not p.is_file() or p.is_symlink() for p in sources):
        raise SystemExit("all successor sources must be regular files")
    parent_manifest_path = parent / "release-manifest.json"
    parent_manifest = json.loads(parent_manifest_path.read_text(encoding="utf-8"))
    if parent_manifest.get("release_version") != PARENT_VERSION or parent_manifest.get("release_name") != PARENT_RELEASE:
        raise SystemExit("exact .69 parent release required")

    output = args.output_root.resolve()
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(parent, output, symlinks=False)

    storage_bridge, processor, active_bootstrap, active_dispatch, preflight, installer, verifier, receipt_schema = sources
    shutil.copyfile(storage_bridge, output / "backend/imap_bridge.py")
    shutil.copyfile(processor, output / "backend/email_intake_processor.py")
    render_control(active_bootstrap, output / f"control/{VERSION}/active-bootstrap.ps1")
    render_control(active_dispatch, output / f"control/{VERSION}/active-dispatch.ps1")
    render_control(preflight, output / f"control/{VERSION}/current-head-preflight.py")

    root_bootstrap = f'''[CmdletBinding()]\nparam([string]$InstallRoot="$env:ProgramData\\PDCMonitor\\Staging",[switch]$DryRun)\n$ErrorActionPreference='Stop'\n$Version='{VERSION}'\n$CurrentHead='{CURRENT_HEAD}'\n$root=[IO.Path]::GetFullPath($InstallRoot)\n$current=(Get-Content -LiteralPath (Join-Path $root 'CURRENT') -Raw).Trim()\nif($current -ne $Version){{throw 'PDC_MONITOR_071_BOOTSTRAP_CURRENT_MISMATCH'}}\n$runner=Join-Path $root "control\\$Version\\active-bootstrap.ps1"\nif(-not(Test-Path -LiteralPath $runner -PathType Leaf)){{throw 'PDC_MONITOR_071_BOOTSTRAP_CONTROL_MISSING'}}\n& $runner -InstallRoot $root -DryRun:$DryRun\nexit $LASTEXITCODE\n'''
    (output / "control-root/bootstrap.ps1").parent.mkdir(parents=True, exist_ok=True)
    (output / "control-root/bootstrap.ps1").write_text(root_bootstrap, encoding="utf-8", newline="\n")

    control_root = output / f"control/{VERSION}"
    control_inventory = canonical_inventory(control_root)
    control_sha = inventory_hash(control_inventory)
    trust_root = output / f"trust/{VERSION}"
    trust_root.mkdir(parents=True, exist_ok=True)
    trust_values = {
        "CURRENT_HEAD": CURRENT_HEAD,
        "RELEASE_VERSION": VERSION,
        "PARENT_RELEASE_VERSION": PARENT_VERSION,
        "STORAGE_BRIDGE_SHA256": sha(storage_bridge),
        "PROCESSOR_SHA256": sha(processor),
        "CONTROL_SHA256": control_sha,
        "VENV_SEED_SHA256": inventory_hash(canonical_inventory(output / "python-runtime")),
        "PARENT_MANIFEST_SHA256": sha(parent_manifest_path),
        "PROJECT_REF": PROJECT,
        "OUTBOUND_EMAIL_ENABLED": "false",
        "TASK_IDENTITY": "LOCAL SERVICE|ServiceAccount|Limited|PT5M",
    }
    (trust_root / "TRUST-VALUES.json").write_text(json.dumps(trust_values, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output / "venv-contract.json").write_text(json.dumps({
        "source_parent_version": PARENT_VERSION,
        "source_parent_path": "C:/ProgramData/PDCMonitor/Staging/venvs/2026.08.69",
        "copy_required_at_install": True,
        "include_system_site_packages": False,
        "hash_written_at_install": "trust/2026.08.71/VENV_SHA256.tsv",
        "seed_sha256": trust_values["VENV_SEED_SHA256"],
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for source, relative in ((installer, "installer/install_pdc_monitor_successor_20260871.ps1"), (verifier, "installer/verify_pdc_monitor_successor_20260871.py"), (receipt_schema, "installer/pdc_monitor_successor_20260871_receipt.schema.json")):
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    excluded = {f"trust/{VERSION}/MANIFEST_SHA256", f"trust/{VERSION}/TRUST_SHA256", f"trust/{VERSION}/VENV_SHA256.tsv"}
    files = canonical_inventory(output, exclude=excluded | {"release-manifest.json"})
    manifest = dict(parent_manifest)
    manifest.update({
        "release_series": "pdc-monitor-staging-m502-successor",
        "release_name": RELEASE,
        "release_version": VERSION,
        "parent_release_name": PARENT_RELEASE,
        "parent_release_version": PARENT_VERSION,
        "parent_manifest_sha256": sha(parent_manifest_path),
        "built_at_utc": args.built_at_utc,
        "expected_staging_project_ref": PROJECT,
        "migration_head": CURRENT_HEAD,
        "supported_migration_head": CURRENT_HEAD,
        "current_staging_migration_head": CURRENT_HEAD,
        "outbound_email_enabled": False,
        "mark_read_enabled": False,
        "production_contacted": False,
        "storage_readback_contract": "HTTP 400 + NoSuchKey + statusCode 404 + Object not found only; bounded three-attempt verified byte/size/hash/MIME readback",
        "successor_patch": {
            "storage_bridge_path": "backend/imap_bridge.py",
            "storage_bridge_sha256": sha(storage_bridge),
            "processor_path": "backend/email_intake_processor.py",
            "processor_sha256": sha(processor),
        },
        "active_current_head_controls": {
            "head": CURRENT_HEAD,
            "bootstrap": f"control/{VERSION}/active-bootstrap.ps1",
            "dispatch": f"control/{VERSION}/active-dispatch.ps1",
            "preflight": f"control/{VERSION}/current-head-preflight.py",
            "control_sha256": control_sha,
        },
        "venv_contract": json.loads((output / "venv-contract.json").read_text(encoding="utf-8")),
        "trust_contract": {
            "trust_values_sha256": sha(trust_root / "TRUST-VALUES.json"),
            "manifest_anchor": f"trust/{VERSION}/MANIFEST_SHA256",
            "venv_hash_manifest": f"trust/{VERSION}/VENV_SHA256.tsv",
        },
        "manifest_excluded_dynamic_files": sorted(excluded),
        "files": files,
    })
    manifest["bundle_hash_definition"] = "sha256(canonical JSON complete internal file inventory, excluding release-manifest.json and dynamic trust anchors)"
    manifest["bundle_sha256"] = inventory_hash(files)
    manifest_path = output / "release-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    manifest_sha = sha(manifest_path)
    (trust_root / "MANIFEST_SHA256").write_text(manifest_sha + "\n", encoding="ascii")
    trust_sha = sha(trust_root / "TRUST-VALUES.json")
    (trust_root / "TRUST_SHA256").write_text(trust_sha + "\n", encoding="ascii")
    receipt = {
        "ok": True,
        "release_version": VERSION,
        "parent_release_version": PARENT_VERSION,
        "manifest_sha256": manifest_sha,
        "parent_manifest_sha256": trust_values["PARENT_MANIFEST_SHA256"],
        "storage_bridge_sha256": trust_values["STORAGE_BRIDGE_SHA256"],
        "processor_sha256": trust_values["PROCESSOR_SHA256"],
        "control_sha256": control_sha,
        "trust_sha256": trust_sha,
        "venv_seed_sha256": trust_values["VENV_SEED_SHA256"],
        "current_staging_migration_head": CURRENT_HEAD,
        "files": len(files),
        "task_enabled": False,
        "task_started": False,
        "mailbox_contacted": False,
        "production_contacted": False,
    }
    (output.parent / f"{output.name}.build-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
