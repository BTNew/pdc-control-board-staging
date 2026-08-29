#!/usr/bin/env python3
"""Refresh the exact staging Monitor actor for one unattended cycle.

The machine-DPAPI store contains the existing actor password and public staging
key. It never contains or prints bearer tokens; tokens exist only in the
short-lived protected env handoff returned to the sealed PowerShell runner.
"""
from __future__ import annotations

import argparse
import base64
import ctypes
import ctypes.wintypes as wt
import json
import os
import re
import subprocess
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
EXPECTED_RELEASE = "pdc-monitor-staging-m502-2026.08.44"
LOCAL_MACHINE = 4  # CRYPTPROTECT_LOCAL_MACHINE, used only by provisioning.


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


def parse_jwt(token: str) -> dict[str, object]:
    parts = token.split(".")
    if len(parts) != 3:
        raise RuntimeError("auth response was not a JWT")
    raw = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        value = json.loads(base64.urlsafe_b64decode(raw.encode()).decode("utf-8"))
    except Exception as exc:
        raise RuntimeError("auth response contained an invalid JWT") from exc
    if not isinstance(value, dict):
        raise RuntimeError("JWT payload was not an object")
    return value


def require_claims(token: str) -> dict[str, object]:
    claims = parse_jwt(token)
    if (
        claims.get("sub") != ACTOR_ID
        or str(claims.get("email", "")).lower() != ACTOR_EMAIL
        or claims.get("iss") != URL + "/auth/v1"
        or claims.get("aud") != "authenticated"
        or claims.get("role") != "authenticated"
        or not isinstance(claims.get("exp"), (int, float))
        or claims["exp"] <= int(time.time())
    ):
        raise RuntimeError("fresh JWT exact actor claim gate failed")
    return claims


def request_login(anon: str) -> dict[str, object]:
    payload = json.dumps({"email": ACTOR_EMAIL, "password": PASSWORD}, separators=(",", ":")).encode()
    request = urllib.request.Request(
        URL + "/auth/v1/token?grant_type=password",
        data=payload,
        method="POST",
        headers={"apikey": anon, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.loads(response.read(1_048_576).decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"same-actor staging login failed HTTP {exc.code}") from exc
    if not isinstance(body, dict) or not body.get("access_token"):
        raise RuntimeError("same-actor staging login returned no access token")
    return body


def set_read_acl(path: Path) -> None:
    result = subprocess.run(
        ["icacls.exe", str(path), "/inheritance:r", "/grant:r", "*S-1-5-18:(F)", "*S-1-5-32-544:(F)", "*S-1-5-19:(RX)"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError("runtime handoff ACL setup failed")


def write_handoff(base_config: Path, state_dir: Path, access: str, supervised: str) -> Path:
    raw = base_config.read_text(encoding="utf-8")
    lines = raw.splitlines(keepends=True)
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
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / f"active-runtime-{os.getpid()}.env"
    path.write_text("".join(output), encoding="utf-8", newline="")
    set_read_acl(path)
    return path


def fail(message: str) -> None:
    print(json.dumps({"ok": False, "code": "PDC_MONITOR_REFRESH_MACHINE_DENIED", "error": message, "secrets_printed": False, "production_contacted": False}, sort_keys=True), file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--machine-store", required=True, type=Path)
    parser.add_argument("--base-config", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    args = parser.parse_args()
    global PASSWORD
    try:
        values = json.loads(dpapi_unprotect(args.machine_store.read_bytes()).decode("utf-8"))
        required = {"project_ref", "supabase_url", "anon_key", "password", "actor_id", "actor_email", "gateway", "release_name"}
        if set(values) != required or values["project_ref"] != PROJECT or values["supabase_url"] != URL or values["actor_id"] != ACTOR_ID or str(values["actor_email"]).lower() != ACTOR_EMAIL or values["gateway"] != GATEWAY or values["release_name"] != EXPECTED_RELEASE or not isinstance(values["password"], str) or not values["password"] or not isinstance(values["anon_key"], str) or not values["anon_key"] or re.search(r"service_role|sb_secret_|production|vjdtsswhroyguxyfjdkt", json.dumps(values, sort_keys=True), re.I):
            raise RuntimeError("machine refresh store exact staging scope failed")
        if "PDC_MONITOR_ACCESS_TOKEN" not in args.base_config.read_text(encoding="utf-8") or "PDC_SUPERVISED_MONITOR_JWT" not in args.base_config.read_text(encoding="utf-8"):
            raise RuntimeError("base runtime config token fields missing")
        PASSWORD = values["password"]
        first = request_login(values["anon_key"])
        second = request_login(values["anon_key"])
        access = str(first["access_token"]); supervised = str(second["access_token"])
        if access == supervised:
            raise RuntimeError("independent JWT issuance failed")
        access_claims = require_claims(access); supervised_claims = require_claims(supervised)
        handoff = write_handoff(args.base_config, args.state_dir, access, supervised)
        print(json.dumps({"ok": True, "handoff": str(handoff), "actor_id": ACTOR_ID, "actor_email": ACTOR_EMAIL, "gateway": GATEWAY, "access_unexpired": access_claims["exp"] > int(time.time()), "supervised_unexpired": supervised_claims["exp"] > int(time.time()), "secrets_printed": False, "production_contacted": False}, sort_keys=True))
    except SystemExit:
        raise
    except Exception as exc:
        fail(str(exc))


if __name__ == "__main__":
    main()
