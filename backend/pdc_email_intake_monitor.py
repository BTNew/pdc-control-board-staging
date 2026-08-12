#!/usr/bin/env python
"""Independent one-cycle PDC mailbox watcher for Windows Task Scheduler.

This process is deliberately separate from Hermes chat. It imports retained
mail evidence and invokes the bounded idempotent processor. It never modifies,
commits, pushes or deploys website files.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
LOCK_PATH = BACKEND / ".pdc_email_intake_monitor.lock"
STATUS_PATH = BACKEND / ".pdc_email_intake_monitor_status.json"

if sys.platform == "win32":
    import msvcrt
    LOCK_BACKEND = "msvcrt"
else:
    import fcntl
    LOCK_BACKEND = "fcntl"


def acquire_lock(path: Path, timeout: float = 0.0):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+b")
    deadline = time.monotonic() + max(0.0, timeout)
    while True:
        try:
            handle.seek(0)
            if LOCK_BACKEND == "msvcrt":
                if path.stat().st_size == 0:
                    handle.write(b"0")
                    handle.flush()
                    handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except OSError:
            if time.monotonic() >= deadline:
                handle.close()
                raise TimeoutError("PDC email intake watcher is still running")
            time.sleep(0.1)


def release_lock(handle) -> None:
    try:
        handle.seek(0)
        if LOCK_BACKEND == "msvcrt":
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    finally:
        handle.close()


def atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    os.replace(temporary, path)


def run_step(argv: list[str], timeout: int) -> dict[str, Any]:
    completed = subprocess.run(
        argv,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        shell=False,
    )
    output = completed.stdout.strip()
    try:
        parsed = json.loads(output.splitlines()[-1]) if output else {}
    except json.JSONDecodeError:
        parsed = {"output": output[-2000:]}
    return {"ok": completed.returncode == 0, "returncode": completed.returncode, "result": parsed}


def run_cycle(import_timeout: int = 180, process_timeout: int = 300) -> int:
    started = datetime.now(timezone.utc).isoformat()
    try:
        lock = acquire_lock(LOCK_PATH)
    except TimeoutError as exc:
        atomic_json(STATUS_PATH, {"ok": True, "skipped": "already_running", "at": started, "detail": str(exc)})
        return 0
    try:
        importer = run_step([
            sys.executable, str(BACKEND / "imap_bridge.py"),
            "--env-file", str(BACKEND / ".env.staging"),
        ], import_timeout)
        if not importer["ok"]:
            status = {"ok": False, "at": started, "phase": "email_import", "email_import": importer}
            atomic_json(STATUS_PATH, status)
            print(json.dumps(status, sort_keys=True))
            return 1
        processor = run_step([
            sys.executable, str(BACKEND / "email_intake_processor.py"),
            "--env-file", str(BACKEND / ".env.staging"),
        ], process_timeout)
        status = {
            "ok": bool(processor["ok"]),
            "at": started,
            "finished_at": datetime.now(timezone.utc).isoformat(),
            "email_import": importer["result"],
            "email_processing": processor["result"],
            "deployment_attempted": False,
        }
        atomic_json(STATUS_PATH, status)
        print(json.dumps(status, sort_keys=True))
        return 0 if status["ok"] else 1
    finally:
        release_lock(lock)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run one independent PDC email watcher cycle")
    parser.add_argument("--import-timeout", type=int, default=180)
    parser.add_argument("--process-timeout", type=int, default=300)
    args = parser.parse_args()
    return run_cycle(args.import_timeout, args.process_timeout)


if __name__ == "__main__":
    raise SystemExit(main())
