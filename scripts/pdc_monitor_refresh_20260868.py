#!/usr/bin/env python3
"""Refresh exact staging actor JWTs for one .68 unattended cycle.

The machine-DPAPI store is read only. Bearer tokens are written only to a
short-lived LOCAL SERVICE-readable handoff and are never printed or persisted
in the release bundle.
"""
from __future__ import annotations

import argparse
import base64
import ctypes
import ctypes.wintypes as wt
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

PROJECT = "cdsmnqxtyyoeoznmbidd"
URL = f"https://{PROJECT}.supabase.co"
ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
ACTOR_EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
SEALED_RELEASE = "pdc-monitor-staging-m502-2026.08.44"


class BLOB(ctypes.Structure):
    _fields_ = [("cbData", wt.DWORD), ("pbData", ctypes.POINTER(ctypes.c_byte))]


def dpapi_unprotect(data: bytes) -> bytes:
    source = BLOB(len(data), ctypes.cast(ctypes.create_string_buffer(data), ctypes.POINTER(ctypes.c_byte)))
    result = BLOB()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(source), None, None, None, None, 0, ctypes.byref(result)):
        raise OSError("machine DPAPI decryption failed")
    try:
        return ctypes.string_at(result.pbData, result.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(result.pbData)


def claims(token: str) -> dict[str, object]:
    try:
        parts = token.split(".")
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        value = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
        if len(parts) != 3 or not isinstance(value, dict):
            raise ValueError
        return value
    except (IndexError, ValueError, TypeError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("auth response contained an invalid JWT") from exc


def login(anon_key: str, password: str) -> str:
    request = urllib.request.Request(
        URL + "/auth/v1/token?grant_type=password",
        data=json.dumps({"email": ACTOR_EMAIL, "password": password}, separators=(",", ":")).encode(),
        method="POST", headers={"apikey": anon_key, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.loads(response.read(1_048_576).decode())
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise RuntimeError("same-actor staging login failed") from exc
    token = body.get("access_token") if isinstance(body, dict) else None
    if not isinstance(token, str) or not token:
        raise RuntimeError("same-actor staging login returned no access token")
    value = claims(token)
    if value.get("sub") != ACTOR_ID or str(value.get("email", "")).lower() != ACTOR_EMAIL \
            or value.get("iss") != URL + "/auth/v1" or value.get("aud") != "authenticated" \
            or value.get("role") != "authenticated" or not isinstance(value.get("exp"), (int, float)) \
            or value["exp"] <= int(time.time()):
        raise RuntimeError("fresh JWT exact actor claim gate failed")
    return token


def protect(path: Path) -> None:
    result = __import__("subprocess").run(
        ["icacls.exe", str(path), "/inheritance:r", "/grant:r", "*S-1-5-18:(F)", "*S-1-5-32-544:(F)", "*S-1-5-19:(RX)"],
        stdout=__import__("subprocess").DEVNULL, stderr=__import__("subprocess").DEVNULL, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("runtime handoff ACL setup failed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--machine-store", required=True, type=Path)
    parser.add_argument("--base-config", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        values = json.loads(dpapi_unprotect(args.machine_store.read_bytes()).decode())
        expected = {"project_ref", "supabase_url", "anon_key", "password", "actor_id", "actor_email", "gateway", "release_name"}
        if set(values) != expected or values["project_ref"] != PROJECT or values["supabase_url"] != URL \
                or values["actor_id"] != ACTOR_ID or str(values["actor_email"]).lower() != ACTOR_EMAIL \
                or values["gateway"] != GATEWAY or values["release_name"] != SEALED_RELEASE \
                or not isinstance(values["anon_key"], str) or not values["anon_key"] \
                or not isinstance(values["password"], str) or not values["password"] \
                or re.search(r"service_role|sb_secret_|production|vjdtsswhroyguxyfjdkt", json.dumps(values, sort_keys=True), re.I):
            raise RuntimeError("machine refresh store exact staging scope failed")
        base = args.base_config.read_text(encoding="utf-8")
        for marker in ("PDC_MONITOR_ACCESS_TOKEN", "PDC_SUPERVISED_MONITOR_JWT", "PDC_AGENTIC_PLANNER_COMMAND", "PDC_AGENTIC_PLANNER_TRUST_RECEIPT"):
            if marker not in base:
                raise RuntimeError("base runtime config binding is incomplete")
        access = login(values["anon_key"], values["password"])
        supervised = login(values["anon_key"], values["password"])
        if access == supervised:
            raise RuntimeError("independent JWT issuance failed")
        lines = base.splitlines(keepends=True)
        output: list[str] = []
        seen: set[str] = set()
        for line in lines:
            body = line.rstrip("\r\n")
            ending = line[len(body):]
            key = body.split("=", 1)[0].strip() if "=" in body else ""
            if key == "PDC_MONITOR_ACCESS_TOKEN":
                output.append(key + "=" + access + ending); seen.add(key)
            elif key == "PDC_SUPERVISED_MONITOR_JWT":
                output.append(key + "=" + supervised + ending); seen.add(key)
            else:
                output.append(line)
        if seen != {"PDC_MONITOR_ACCESS_TOKEN", "PDC_SUPERVISED_MONITOR_JWT"}:
            raise RuntimeError("runtime config token handoff lines are incomplete")
        args.state_dir.mkdir(parents=True, exist_ok=True)
        handoff = args.state_dir / f"active-runtime-{os.getpid()}.env"
        handoff.write_text("".join(output), encoding="utf-8", newline="")
        protect(handoff)
        print(json.dumps({"ok": True, "handoff": str(handoff), "actor_id": ACTOR_ID, "actor_email": ACTOR_EMAIL, "gateway": GATEWAY, "access_unexpired": True, "supervised_unexpired": True, "secrets_printed": False, "production_contacted": False}, sort_keys=True))
    except SystemExit:
        raise
    except Exception as exc:
        print(json.dumps({"ok": False, "code": "PDC_MONITOR_REFRESH_MACHINE_DENIED", "error": str(exc), "secrets_printed": False, "production_contacted": False}, sort_keys=True), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
