#!/usr/bin/env python3
"""Fail-closed preflight for the .71 monitor against staging head 20260831380000."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

RELEASE = "2026.08.71"
CURRENT_HEAD = "20260831380000"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"


def fail(code: str, detail: str = "") -> None:
    print(json.dumps({
        "ok": False,
        "code": code,
        "detail": detail[:500],
        "release": RELEASE,
        "current_staging_migration_head": CURRENT_HEAD,
        "mailbox_contacted": False,
        "production_contacted": False,
    }, sort_keys=True))
    raise SystemExit(1)


def sha(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        fail("PDC_MONITOR_071_PREFLIGHT_FILE_READ_FAILED", path.name)
        raise AssertionError from exc


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-root", type=Path, required=True)
    parser.add_argument("--release-root", type=Path, required=True)
    parser.add_argument("--venv-root", type=Path, required=True)
    parser.add_argument("--expected-head", default=CURRENT_HEAD)
    args = parser.parse_args()

    if args.expected_head != CURRENT_HEAD:
        fail("PDC_MONITOR_071_PREFLIGHT_HEAD_EXPECTATION_MISMATCH")
    install_root = args.install_root.resolve()
    release_root = args.release_root.resolve()
    venv_root = args.venv_root.resolve()
    if release_root != install_root / "releases" / RELEASE:
        fail("PDC_MONITOR_071_PREFLIGHT_RELEASE_ROOT_MISMATCH")
    if venv_root != install_root / "venvs" / RELEASE:
        fail("PDC_MONITOR_071_PREFLIGHT_VENV_ROOT_MISMATCH")
    current_path = install_root / "CURRENT"
    if not current_path.is_file() or current_path.read_text(encoding="ascii").strip() != RELEASE:
        fail("PDC_MONITOR_071_PREFLIGHT_CURRENT_MISMATCH")
    manifest_path = release_root / "release-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("release_version") != RELEASE or manifest.get("release_name") != "pdc-monitor-staging-m502-2026.08.71":
        fail("PDC_MONITOR_071_PREFLIGHT_MANIFEST_RELEASE_MISMATCH")
    if manifest.get("current_staging_migration_head") != CURRENT_HEAD:
        fail("PDC_MONITOR_071_PREFLIGHT_MANIFEST_HEAD_MISMATCH")
    if manifest.get("expected_staging_project_ref") != PROJECT_REF:
        fail("PDC_MONITOR_071_PREFLIGHT_PROJECT_MISMATCH")
    if manifest.get("outbound_email_enabled") is not False or manifest.get("mark_read_enabled") is not False:
        fail("PDC_MONITOR_071_PREFLIGHT_SIDE_EFFECTS_ENABLED")
    cfg = venv_root / "pyvenv.cfg"
    if not cfg.is_file() or "include-system-site-packages = false" not in cfg.read_text(encoding="ascii"):
        fail("PDC_MONITOR_071_PREFLIGHT_VENV_ISOLATION_MISMATCH")
    controls = [release_root.parent.parent / "control" / RELEASE / name for name in ("active-bootstrap.ps1", "active-dispatch.ps1", "current-head-preflight.py")]
    missing = [path.name for path in controls if not path.is_file()]
    if missing:
        fail("PDC_MONITOR_071_PREFLIGHT_CONTROL_MISSING", ",".join(missing))
    print(json.dumps({
        "ok": True,
        "release": RELEASE,
        "current_staging_migration_head": CURRENT_HEAD,
        "project_ref": PROJECT_REF,
        "manifest_sha256": sha(manifest_path),
        "mailbox_contacted": False,
        "production_contacted": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
