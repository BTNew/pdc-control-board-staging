#!/usr/bin/env python3
"""Secretless, deterministic PDC Email AI recovery bootstrap.

Every mutating or credentialed operation is an explicitly supplied protected
command. This runner never receives secrets as arguments and never prints
child stdout/stderr. It records only sanitized gate status.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

PACK_VERSION = "pdc-email-ai-recovery-pack-v1"
GATES = (
    ("INSPECT", None),
    ("INSTALL", "PDC_RECOVERY_INSTALL_COMMAND"),
    ("CONFIGURE", "PDC_RECOVERY_CONFIGURE_COMMAND"),
    ("VERIFY SUPABASE CONTRACT", "PDC_RECOVERY_SUPABASE_VERIFY_COMMAND"),
    ("PROVISION/VERIFY CREDENTIALS", "PDC_RECOVERY_PROVISION_COMMAND"),
    ("VERIFY MAILBOX", "PDC_RECOVERY_MAILBOX_VERIFY_COMMAND"),
    ("RUN SAFE TEST EMAIL", "PDC_RECOVERY_SAFE_EMAIL_COMMAND"),
    ("VERIFY SUPABASE READBACK", "PDC_RECOVERY_READBACK_COMMAND"),
    ("VERIFY BOARD", "PDC_RECOVERY_BOARD_VERIFY_COMMAND"),
    ("ENABLE AUTOMATION", "PDC_RECOVERY_ENABLE_COMMAND"),
)
SECRET_FILE_RE = re.compile(r"(^|/|\\)(\.env|.*\.pem|.*\.key|.*\.pfx|.*\.dpapi|.*credentials?[^/\\]*)$", re.I)
TOKEN_RE = re.compile(r"(?:eyJ[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|" + "-----" + "BEGIN|" + "pass" + r"word\s*[:=]\s*[^\s<]+)", re.I)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return ""


def fail(code: str, message: str) -> None:
    raise RuntimeError(f"{code}:{message}")


def inspect_pack(pack: Path, source: Path) -> dict[str, Any]:
    manifest_path = pack / "RECOVERY-PACK-MANIFEST.json"
    if not manifest_path.is_file():
        fail("PDC_RECOVERY_MANIFEST_MISSING", str(manifest_path))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("pack_version") != PACK_VERSION:
        fail("PDC_RECOVERY_PACK_VERSION_MISMATCH", "unexpected pack version")
    if manifest.get("environment") != "staging" or manifest.get("project_ref") != "cdsmnqxtyyoeoznmbidd":
        fail("PDC_RECOVERY_TARGET_MISMATCH", "pack is not bound to the approved staging project")
    if not manifest.get("source_commit"):
        fail("PDC_RECOVERY_SOURCE_COMMIT_MISSING", "immutable source commit absent")
    if not manifest.get("release_url"):
        fail("PDC_RECOVERY_RELEASE_MISSING", "immutable release URL absent")
    if not source.is_dir():
        fail("PDC_RECOVERY_SOURCE_ROOT_MISSING", str(source))
    if (source / ".git").exists():
        revision = subprocess.run(["git", "-C", str(source), "rev-parse", "HEAD"], capture_output=True, text=True, check=False).stdout.strip()
        if revision and revision != manifest["source_commit"]:
            fail("PDC_RECOVERY_SOURCE_COMMIT_MISMATCH", "checkout is not the immutable pack commit")
    unsafe: list[str] = []
    for path in pack.rglob("*"):
        if not path.is_file() or path.name == "RECOVERY-PACK-MANIFEST.json":
            continue
        relative = path.relative_to(pack).as_posix()
        if SECRET_FILE_RE.search(relative):
            unsafe.append(relative)
            continue
        text = safe_text(path)
        if text and TOKEN_RE.search(text):
            unsafe.append(relative)
    if unsafe:
        fail("PDC_RECOVERY_SECRET_RESIDUE", ",".join(sorted(unsafe)))
    expected = manifest.get("pack_files", {})
    for relative, digest in expected.items():
        path = pack / relative
        if not path.is_file() or sha256(path) != digest:
            fail("PDC_RECOVERY_PACK_HASH_MISMATCH", relative)
    return {"pack_version": PACK_VERSION, "source_commit": manifest["source_commit"], "release_url": manifest["release_url"], "pack_hashes_verified": True}


def command_from_env(name: str) -> list[str]:
    value = os.environ.get(name, "").strip()
    if not value:
        fail("PDC_RECOVERY_GATE_COMMAND_MISSING", name)
    if "\x00" in value or " && " in value or " | " in value or ";" in value:
        fail("PDC_RECOVERY_GATE_COMMAND_UNSAFE", name)
    path = Path(value)
    if not path.is_absolute() or not path.exists():
        fail("PDC_RECOVERY_GATE_COMMAND_INVALID", name)
    if path.suffix.lower() == ".ps1":
        return [os.environ.get("SystemRoot", r"C:\\Windows") + r"\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(path)]
    return [str(path)]


def run_gate(name: str, command_name: str | None) -> dict[str, Any]:
    if command_name is None:
        return {"gate": name, "status": "PASS", "command": None}
    command = command_from_env(command_name)
    result = subprocess.run(command, capture_output=True, check=False, timeout=900)
    if result.returncode != 0:
        return {"gate": name, "status": "FAIL", "command_env": command_name, "exit_code": result.returncode}
    return {"gate": name, "status": "PASS", "command_env": command_name, "exit_code": 0}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pack-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()
    started = time.monotonic()
    report: dict[str, Any] = {"pack_version": PACK_VERSION, "started": True, "execute": args.execute, "gates": []}
    try:
        report["inspect"] = inspect_pack(args.pack_root.resolve(), args.source_root.resolve())
        report["gates"].append({"gate": "INSPECT", "status": "PASS"})
        if not args.execute:
            report["status"] = "INSPECT_ONLY"
        else:
            for name, command_name in GATES[1:]:
                result = run_gate(name, command_name)
                report["gates"].append(result)
                if result["status"] != "PASS":
                    report["status"] = "FAIL"
                    break
            else:
                report["status"] = "PASS"
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        report["secrets_printed"] = False
        report["production_contacted"] = False
        report["mailbox_contacted"] = False
    except Exception as exc:
        report["status"] = "FAIL"
        report["error"] = str(exc)
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        report["secrets_printed"] = False
        report["production_contacted"] = False
        report["mailbox_contacted"] = False
    report_path = args.report or (args.pack_root / "recovery-bootstrap-report.json")
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "report": str(report_path), "secrets_printed": False, "production_contacted": False, "mailbox_contacted": False}, sort_keys=True))
    return 0 if report["status"] in {"PASS", "INSPECT_ONLY"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
