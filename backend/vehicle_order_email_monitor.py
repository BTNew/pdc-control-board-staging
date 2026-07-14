#!/usr/bin/env python
"""Persistent, serialized vehicle-order mailbox monitor with Telegram alerts.

This wrapper is intended for Windows Task Scheduler. It serializes imports with
an inter-process file lock, runs the existing bounded email updater, records a
small local status file, and sends Telegram alerts only for new intake or
failure. Mail content remains untrusted data and is never interpreted as an
instruction.
"""
from __future__ import annotations

import argparse
import json
import msvcrt
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
LOCK_PATH = BACKEND / ".vehicle_order_email_monitor.lock"
STATUS_PATH = BACKEND / ".vehicle_order_email_monitor_status.json"
HERMES_ENV_PATH = Path.home() / "AppData" / "Local" / "hermes" / ".env"
UPDATER = BACKEND / "update_website_from_email.py"
DEFAULT_CHAT_ID = "7828138290"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_env_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def acquire_lock(path: Path, wait_seconds: float):
    """Acquire an exclusive Windows byte lock, waiting FIFO-style if occupied."""
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+b")
    handle.seek(0, os.SEEK_END)
    if handle.tell() == 0:
        handle.write(b"0")
        handle.flush()
    deadline = time.monotonic() + max(0.0, wait_seconds)
    while True:
        try:
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            return handle
        except OSError:
            if time.monotonic() >= deadline:
                handle.close()
                raise TimeoutError("another vehicle-order import is still running")
            time.sleep(1.0)


def release_lock(handle) -> None:
    try:
        handle.seek(0)
        msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
    finally:
        handle.close()


def parse_json_object(text: str) -> dict[str, Any]:
    text = (text or "").strip()
    if not text:
        return {}
    try:
        value = json.loads(text)
        return value if isinstance(value, dict) else {}
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            try:
                value = json.loads(text[start : end + 1])
                return value if isinstance(value, dict) else {}
            except json.JSONDecodeError:
                return {}
        return {}


def summarize_updater(output: str) -> dict[str, Any]:
    outer = parse_json_object(output)
    bridge = parse_json_object(str(outer.get("email_bridge") or ""))
    publisher = parse_json_object(str(outer.get("website_publish") or ""))
    return {
        "posted": int(bridge.get("posted") or 0),
        "skipped_processed": int(bridge.get("skipped_processed") or 0),
        "changed": bool(publisher.get("changed")),
        "vehicles_generated": int(publisher.get("vehicles_generated") or 0),
        "committed_and_pushed": bool(publisher.get("committed_and_pushed")),
    }


def send_telegram(text: str, *, env_path: Path = HERMES_ENV_PATH, chat_id: str = "") -> None:
    values = load_env_values(env_path)
    token = values.get("TELEGRAM_BOT_TOKEN", "")
    target = chat_id or values.get("TELEGRAM_HOME_CHANNEL", "") or DEFAULT_CHAT_ID
    if not token or not target:
        raise RuntimeError("Telegram bot token or destination is not configured")
    payload = urllib.parse.urlencode({"chat_id": target, "text": text}).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"Telegram notification returned HTTP {response.status}")


def write_status(payload: dict[str, Any]) -> None:
    STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = STATUS_PATH.with_suffix(STATUS_PATH.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    os.replace(temporary, STATUS_PATH)


def run_monitor(limit: int, wait_seconds: float, timeout_seconds: float) -> int:
    started_at = utc_now()
    lock_handle = None
    try:
        lock_handle = acquire_lock(LOCK_PATH, wait_seconds)
        proc = subprocess.run(
            [sys.executable, str(UPDATER), "--limit", str(limit)],
            cwd=str(ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
        )
        output = (proc.stdout or "").strip()
        if proc.returncode != 0:
            raise RuntimeError(f"updater exited {proc.returncode}: {output[-800:]}")
        summary = summarize_updater(output)
        status = {"ok": True, "started_at": started_at, "finished_at": utc_now(), **summary}
        write_status(status)
        print(json.dumps(status, sort_keys=True))
        if summary["posted"]:
            if summary["changed"]:
                detail = "vehicle-order data was published"
            else:
                detail = "no new parseable vehicle order was published"
            send_telegram(
                f"✅ Vehicle-order email monitor: imported {summary['posted']} new email(s); {detail}."
            )
        return 0
    except Exception as exc:
        status = {
            "ok": False,
            "started_at": started_at,
            "finished_at": utc_now(),
            "error": str(exc)[:800],
        }
        write_status(status)
        print(json.dumps(status, sort_keys=True))
        try:
            send_telegram(f"❌ Vehicle-order email monitor failed: {str(exc)[:500]}")
        except Exception as notify_exc:
            print(json.dumps({"telegram_notification_error": str(notify_exc)[:500]}, sort_keys=True))
        return 1
    finally:
        if lock_handle is not None:
            release_lock(lock_handle)


def main() -> int:
    parser = argparse.ArgumentParser(description="Serialized vehicle-order mailbox monitor")
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--lock-wait-seconds", type=float, default=1800)
    parser.add_argument("--timeout-seconds", type=float, default=1200)
    parser.add_argument("--test-notification", action="store_true")
    args = parser.parse_args()
    if args.test_notification:
        send_telegram("✅ Vehicle-order email monitor test notification succeeded.")
        print(json.dumps({"ok": True, "test_notification": True}))
        return 0
    return run_monitor(args.limit, args.lock_wait_seconds, args.timeout_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
