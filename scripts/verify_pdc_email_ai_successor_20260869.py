#!/usr/bin/env python3
"""Read-only observer for the commissioned STAGING successor runtime."""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE_ENV = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/.env")
STORE = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/secrets/pdc-email-ai-successor-runtime.dpapi")
EXPECTED = {
    "project_ref": "cdsmnqxtyyoeoznmbidd",
    "gateway_instance_id": "pdc-email-ai-successor-069",
    "mailbox_scope": "pdc-emails",
    "transport_release_version": "pdc-email-ai-transport-v1",
    "model_version": "pdc-email-ai-model-v1",
    "prompt_version": "pdc-email-ai-prompt-v1",
    "taxonomy_version": "pdc-work-taxonomy-v1",
    "rule_version": "pdc-business-rules-v1",
    "action_contract_version": "pdc-email-ai-actions-v1",
}


def load_env() -> None:
    if not PROFILE_ENV.is_file():
        raise RuntimeError("PDC_SUCCESSOR_PROFILE_ENV_MISSING")
    for line in PROFILE_ENV.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key, value.strip().strip('"').strip("'"))


def read_store() -> dict:
    if not STORE.is_file():
        raise RuntimeError("PDC_SUCCESSOR_RUNTIME_STORE_MISSING")
    import importlib.util
    spec = importlib.util.spec_from_file_location("commission", ROOT / "scripts" / "provision_pdc_email_ai_successor_staging.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_SUCCESSOR_COMMISSIONER_IMPORT_FAILED")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    payload = module.read_store()
    if not isinstance(payload, dict):
        raise RuntimeError("PDC_SUCCESSOR_RUNTIME_STORE_INVALID")
    return payload


def rpc(url: str, anon: str, token: str, name: str, params: dict) -> tuple[int, object]:
    request = urllib.request.Request(url.rstrip("/") + "/rest/v1/rpc/" + name, data=json.dumps(params).encode(), method="POST")
    request.add_header("Content-Type", "application/json")
    request.add_header("apikey", anon)
    request.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read(); return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try: body = json.loads(raw)
        except Exception: body = None
        return exc.code, body


def main() -> None:
    load_env()
    store = read_store()
    mismatches = [key for key, value in EXPECTED.items() if store.get(key) != value]
    if mismatches or store.get("environment") != "staging" or store.get("service_key_persisted") is True or store.get("runtime_service_role") is True:
        raise RuntimeError("PDC_SUCCESSOR_RUNTIME_BINDING_MISMATCH")
    url = os.environ.get("PDC_STAGING_SUPABASE_URL", "").strip()
    anon = os.environ.get("PDC_STAGING_ANON_KEY", "").strip()
    if EXPECTED["project_ref"] not in url or not anon:
        raise RuntimeError("PDC_SUCCESSOR_NON_STAGING_TARGET")
    password = store.get("runtime_password")
    if not isinstance(password, str) or not password:
        raise RuntimeError("PDC_SUCCESSOR_RUNTIME_CREDENTIAL_MISSING")
    login = urllib.request.Request(url.rstrip("/") + "/auth/v1/token?grant_type=password", data=json.dumps({"email": store["email"], "password": password}).encode(), method="POST")
    login.add_header("Content-Type", "application/json"); login.add_header("apikey", anon)
    with urllib.request.urlopen(login, timeout=20) as response:
        body = json.loads(response.read()); token = body.get("access_token")
    if not token: raise RuntimeError("PDC_SUCCESSOR_RUNTIME_LOGIN_FAILED")
    results = {}
    for name, params in (("health", ("get_pdc_email_ai_successor_health", {})), ("query", ("get_pdc_email_ai_transaction_successor_inbox_v2", {"p_cursor": None, "p_page_size": 2})), ("readback", ("get_pdc_email_vehicle_location_snapshot", {}))):
        status, result = rpc(url, anon, token, params[0], params[1]); results[name] = {"status": status, "ok": bool(isinstance(result, dict) and result.get("ok")), "code": result.get("code") if isinstance(result, dict) else None}
    if not all(item["status"] == 200 and item["ok"] for item in results.values()): raise RuntimeError("PDC_SUCCESSOR_RUNTIME_HEALTH_FAILED")
    print(json.dumps({"ok": True, "environment": "staging", "runtime_login_ok": True, "binding_exact": True, "credential_store_present": STORE.is_file(), "service_key_used": False, "runtime_service_role": False, "approved_rpc_health": results["health"], "approved_rpc_query": results["query"], "approved_rpc_readback": results["readback"], "business_mutation": False, "mailbox_contacted": False, "production_contacted": False}, sort_keys=True))


if __name__ == "__main__":
    try: main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "service_key_used": False, "runtime_service_role": False, "business_mutation": False, "mailbox_contacted": False, "production_contacted": False}, sort_keys=True)); raise SystemExit(1)
