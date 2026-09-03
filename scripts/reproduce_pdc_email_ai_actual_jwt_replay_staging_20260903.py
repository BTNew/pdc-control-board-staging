#!/usr/bin/env python3
"""Reproduce exact-success replay through the real STAGING JWT/PostgREST path."""
from __future__ import annotations

import hashlib
import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

STAGING_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_USER_ID = "e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8"
RUNTIME_ENV = Path.home() / "AppData/Local/hermes/profiles/pdc-email-ai-lead/.env"
TRANSACTION_IDS = {
    "541657d7-ef0b-4323-884c-2a1edc29aa2f",
    "35726910-42d6-4c7a-aa54-71e75dd67083",
    "0fec3e2a-bd49-4d98-a83d-42770edd9b23",
}


def load_runtime() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in RUNTIME_ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    required = (
        "PDC_STAGING_SUPABASE_URL",
        "PDC_STAGING_SUPABASE_ANON_KEY",
        "PDC_EMAIL_AI_RUNTIME_EMAIL",
        "PDC_EMAIL_AI_RUNTIME_PASSWORD",
    )
    if any(not values.get(key) for key in required):
        raise RuntimeError("PDC_RUNTIME_PROFILE_CREDENTIALS_INCOMPLETE")
    parsed = urllib.parse.urlparse(values["PDC_STAGING_SUPABASE_URL"])
    if parsed.scheme != "https" or parsed.hostname != f"{STAGING_REF}.supabase.co" or parsed.port is not None:
        raise RuntimeError("PDC_RUNTIME_PROFILE_NON_STAGING_URL_REFUSED")
    return values


def request_json(url: str, headers: dict[str, str], payload: dict[str, Any]) -> tuple[int, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            body = json.loads(exc.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            body = {"code": "non_json_http_error"}
        return exc.code, body


def main() -> None:
    values = load_runtime()
    base = values["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    anon = values["PDC_STAGING_SUPABASE_ANON_KEY"]
    auth_status, auth = request_json(
        f"{base}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json"},
        {"email": values["PDC_EMAIL_AI_RUNTIME_EMAIL"], "password": values["PDC_EMAIL_AI_RUNTIME_PASSWORD"]},
    )
    token = auth.get("access_token") if isinstance(auth, dict) else None
    user_id = (auth.get("user") or {}).get("id") if isinstance(auth, dict) else None
    if auth_status != 200 or not token or user_id != EXPECTED_USER_ID:
        raise RuntimeError("PDC_RUNTIME_PROFILE_IDENTITY_MISMATCH")
    headers = {"apikey": anon, "Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    inbox_status, inbox = request_json(
        f"{base}/rest/v1/rpc/get_pdc_email_ai_transaction_successor_inbox_v2",
        headers,
        {"p_cursor": None, "p_page_size": 250},
    )
    if inbox_status != 200 or not isinstance(inbox, dict) or inbox.get("ok") is not True:
        raise RuntimeError(f"PDC_RUNTIME_INBOX_FAILED:{inbox_status}:{inbox.get('code') if isinstance(inbox, dict) else 'invalid'}")
    items = inbox.get("items") or (inbox.get("data") or {}).get("items") or []
    plans: dict[str, dict[str, Any]] = {}
    for item in items:
        transaction = item.get("transaction") or {}
        transaction_id = str(transaction.get("transaction_id") or "")
        if transaction_id in TRANSACTION_IDS:
            plan = transaction.get("typed_plan") or transaction.get("plan")
            if isinstance(plan, dict):
                plans[transaction_id] = plan
    if set(plans) != TRANSACTION_IDS:
        raise RuntimeError(f"PDC_RUNTIME_INBOX_TRANSACTIONS_MISSING:{sorted(TRANSACTION_IDS-set(plans))}")

    results = []
    for transaction_id in sorted(TRANSACTION_IDS):
        plan = plans[transaction_id]
        status, body = request_json(
            f"{base}/rest/v1/rpc/apply_pdc_email_ai_typed_action_surface_20260901_strict",
            headers,
            {"p_plan": plan},
        )
        results.append({
            "transaction_id": transaction_id,
            "http_status": status,
            "ok": body.get("ok") if isinstance(body, dict) else None,
            "code": body.get("code") if isinstance(body, dict) else "invalid_response",
            "returned_transaction_id": body.get("transaction_id") if isinstance(body, dict) else None,
            "exact_successful_replay": body.get("exact_successful_replay") if isinstance(body, dict) else None,
            "runtime_rotation_replay": body.get("runtime_rotation_replay") if isinstance(body, dict) else None,
            "plan_sha256": hashlib.sha256(json.dumps(plan, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        })
    verified = all(
        row["http_status"] == 200
        and row["ok"] is True
        and row["code"] == "pdc_email_ai_typed_action_surface_verified"
        and row["returned_transaction_id"] == row["transaction_id"]
        and row["exact_successful_replay"] is True
        and row["runtime_rotation_replay"] is True
        for row in results
    )
    if not verified:
        raise RuntimeError("PDC_ACTUAL_JWT_REPLAY_VERIFICATION_FAILED")
    print(json.dumps({
        "ok": True,
        "environment": "staging",
        "project_ref": STAGING_REF,
        "authenticated_user_id": user_id,
        "inbox_http_status": inbox_status,
        "target_count": len(plans),
        "results": results,
        "production_contacted": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
