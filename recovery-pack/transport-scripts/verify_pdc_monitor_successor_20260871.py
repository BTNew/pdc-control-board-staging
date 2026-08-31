#!/usr/bin/env python3
"""Verify the installed .71 bundle, controls, trust and venv readback."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

VERSION = "2026.08.71"
PARENT = "2026.08.69"
HEAD = "20260831380000"
PROJECT = "cdsmnqxtyyoeoznmbidd"


def fail(code: str, **extra: object) -> int:
    payload = {"ok": False, "code": code, "task_started": False, "mailbox_contacted": False, "production_contacted": False, **extra}
    print(json.dumps(payload, sort_keys=True))
    return 1


def sha(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        raise FileNotFoundError(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_lines(path: Path) -> list[str]:
    return [
        f"{p.relative_to(path).as_posix()}\t{sha(p)}\t{p.stat().st_size}"
        for p in sorted(path.rglob("*")) if p.is_file()
    ]


def tree_hash(path: Path) -> str:
    return hashlib.sha256(("\n".join(tree_lines(path)) + "\n").encode()).hexdigest()


def query_task(name: str) -> str:
    result = subprocess.run(["schtasks.exe", "/Query", "/TN", name, "/FO", "LIST", "/V"], capture_output=True, text=True, check=False)
    return result.stdout + result.stderr


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-root", type=Path, required=True)
    parser.add_argument("--expected-manifest-sha256", required=True)
    parser.add_argument("--expected-parent-manifest-sha256", required=True)
    parser.add_argument("--expected-storage-bridge-sha256", required=True)
    parser.add_argument("--expected-processor-sha256", required=True)
    parser.add_argument("--expected-control-sha256", required=True)
    parser.add_argument("--expected-trust-sha256", required=True)
    parser.add_argument("--expected-venv-sha256", required=True)
    parser.add_argument("--require-enabled", action="store_true")
    args = parser.parse_args()
    root = args.install_root.resolve()
    if not str(root).lower().endswith("\\pdcmonitor\\staging"):
        return fail("PDC_MONITOR_071_VERIFY_ROOT_MISMATCH")
    current = root / "CURRENT"
    if not current.is_file() or current.read_text(encoding="ascii").strip() != VERSION:
        return fail("PDC_MONITOR_071_VERIFY_CURRENT_MISMATCH")
    release = root / "releases" / VERSION
    control = root / "control" / VERSION
    trust = root / "trust" / VERSION
    venv = root / "venvs" / VERSION
    manifest = release / "release-manifest.json"
    parent_manifest = root / "releases" / PARENT / "release-manifest.json"
    try:
        manifest_sha = sha(manifest)
        parent_sha = sha(parent_manifest)
        storage_sha = sha(release / "backend" / "imap_bridge.py")
        processor_sha = sha(release / "backend" / "email_intake_processor.py")
        control_sha = tree_hash(control)
        trust_sha = sha(trust / "TRUST-VALUES.json")
        venv_sha = tree_hash(venv)
    except (FileNotFoundError, OSError) as exc:
        return fail("PDC_MONITOR_071_VERIFY_FILE_MISSING", detail=Path(str(exc)).name)
    if manifest_sha != args.expected_manifest_sha256.lower(): return fail("PDC_MONITOR_071_VERIFY_MANIFEST_HASH")
    if parent_sha != args.expected_parent_manifest_sha256.lower(): return fail("PDC_MONITOR_071_VERIFY_PARENT_HASH")
    if storage_sha != args.expected_storage_bridge_sha256.lower(): return fail("PDC_MONITOR_071_VERIFY_STORAGE_BRIDGE_HASH")
    if processor_sha != args.expected_processor_sha256.lower(): return fail("PDC_MONITOR_071_VERIFY_PROCESSOR_HASH")
    if control_sha != args.expected_control_sha256.lower(): return fail("PDC_MONITOR_071_VERIFY_CONTROL_HASH")
    if trust_sha != args.expected_trust_sha256.lower(): return fail("PDC_MONITOR_071_VERIFY_TRUST_HASH")
    if venv_sha != args.expected_venv_sha256.lower(): return fail("PDC_MONITOR_071_VERIFY_VENV_HASH")
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if data.get("release_version") != VERSION or data.get("current_staging_migration_head") != HEAD or data.get("expected_staging_project_ref") != PROJECT:
        return fail("PDC_MONITOR_071_VERIFY_MANIFEST_ASSERTION")
    if data.get("outbound_email_enabled") is not False or data.get("mark_read_enabled") is not False:
        return fail("PDC_MONITOR_071_VERIFY_SIDE_EFFECTS_ENABLED")
    task = query_task(r"\PDC-PMB-Email-Monitor-Staging")
    required = ("Run As User: LOCAL SERVICE", "Repeat: Every: 0 Hour(s), 5 Minute(s)", "control\\bootstrap.ps1")
    if any(marker not in task for marker in required):
        return fail("PDC_MONITOR_071_VERIFY_TASK_BINDING")
    enabled = "Status:                              Ready" in task or "Status:                              Running" in task
    if args.require_enabled and not enabled:
        return fail("PDC_MONITOR_071_VERIFY_TASK_NOT_ENABLED")
    print(json.dumps({
        "ok": True, "release_version": VERSION, "parent_release_version": PARENT,
        "manifest_sha256": manifest_sha, "parent_manifest_sha256": parent_sha,
        "storage_bridge_sha256": storage_sha, "processor_sha256": processor_sha,
        "venv_sha256": venv_sha, "control_sha256": control_sha, "trust_sha256": trust_sha,
        "current_staging_migration_head": HEAD, "task_enabled": enabled,
        "task_started": False, "mailbox_contacted": False, "production_contacted": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
