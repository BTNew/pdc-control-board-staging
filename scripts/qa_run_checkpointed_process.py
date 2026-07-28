#!/usr/bin/env python3
"""Run a QA subprocess with durable checkpoints and bounded process-tree cleanup."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from typing import Any


def atomic_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def process_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def terminate_tree(proc: subprocess.Popen[Any]) -> None:
    if proc.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--timeout-seconds", type=int, required=True)
    parser.add_argument("--heartbeat-seconds", type=float, default=2.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a command is required after --")
    if args.timeout_seconds < 1 or args.heartbeat_seconds <= 0:
        parser.error("timeouts must be positive")

    root = Path(args.evidence_dir).resolve()
    root.mkdir(parents=True, exist_ok=True)
    state_path = root / f"{args.name}.supervisor.json"
    log_path = root / f"{args.name}.log"
    prior = None
    if state_path.exists():
        prior = json.loads(state_path.read_text(encoding="utf-8"))
        prior_pid = int(prior.get("childPid") or 0)
        if prior.get("status") == "running" and process_alive(prior_pid):
            raise SystemExit(f"refusing concurrent live child {prior_pid}")

    started_monotonic = time.monotonic()
    started_utc = utc_now()
    stop_reason: str | None = None
    child: subprocess.Popen[Any] | None = None

    def request_stop(signum: int, _frame: Any) -> None:
        nonlocal stop_reason
        stop_reason = f"signal_{signum}"
        if child is not None:
            terminate_tree(child)

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    with log_path.open("ab", buffering=0) as log:
        child = subprocess.Popen(
            command,
            cwd=os.getcwd(),
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=(os.name != "nt"),
        )
        base = {
            "schema": "pdc.qa-checkpointed-process/v1",
            "name": args.name,
            "command": command,
            "supervisorPid": os.getpid(),
            "childPid": child.pid,
            "startedAtUtc": started_utc,
            "timeoutSeconds": args.timeout_seconds,
            "priorInterruptedRun": prior if prior and prior.get("status") == "running" else None,
        }
        atomic_json(state_path, {**base, "status": "running", "heartbeatAtUtc": utc_now()})
        timed_out = False
        while child.poll() is None and stop_reason is None:
            elapsed = time.monotonic() - started_monotonic
            if elapsed >= args.timeout_seconds:
                timed_out = True
                stop_reason = "timeout"
                terminate_tree(child)
                break
            atomic_json(
                state_path,
                {**base, "status": "running", "heartbeatAtUtc": utc_now(), "elapsedSeconds": round(elapsed, 3)},
            )
            time.sleep(min(args.heartbeat_seconds, max(0.05, args.timeout_seconds - elapsed)))
        if child.poll() is None:
            terminate_tree(child)
        return_code = child.wait(timeout=10)

    elapsed = round(time.monotonic() - started_monotonic, 3)
    status = "passed" if return_code == 0 and stop_reason is None else "failed"
    final = {
        **base,
        "status": status,
        "finishedAtUtc": utc_now(),
        "elapsedSeconds": elapsed,
        "returnCode": return_code,
        "stopReason": stop_reason,
        "timedOut": timed_out,
        "logPath": str(log_path),
    }
    atomic_json(state_path, final)
    print(json.dumps(final, sort_keys=True))
    return 0 if status == "passed" else (124 if timed_out else return_code or 1)


if __name__ == "__main__":
    raise SystemExit(main())
