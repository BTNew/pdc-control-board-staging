#!/usr/bin/env python3
"""One-time STAGING-only commissioning of the dedicated successor runtime.

The owner service key is loaded from the website-development-lead profile .env
in process, used only for Auth admin/provisioning calls, and never persisted in
runtime state, receipts, command arguments, or output.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import importlib.util
import json
import os
import secrets
import string
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

PROFILE_ENV = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/.env")
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
STAGING_DPAPI = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
OWNER_TOOLS = Path(r"C:/Users/nwmgr/HermesWorkspaces/release-20260869/_staging_test_tools")
STORE = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/secrets/pdc-email-ai-successor-runtime.dpapi")
EMAIL = "pdc-email-ai-successor-staging@broometoyota.com.au"
GATEWAY = "pdc-email-ai-successor-069"
MAILBOX = "pdc-emails"
TRANSPORT = "pdc-email-ai-transport-v1"
MODEL = "pdc-email-ai-model-v1"
PROMPT = "pdc-email-ai-prompt-v1"
TAXONOMY = "pdc-work-taxonomy-v1"
RULES = "pdc-business-rules-v1"
ACTION_CONTRACT = "pdc-email-ai-actions-v1"
SERVICE_KEY_ENV = "PDC_STAGING_SERVICE_ROLE_KEY"
ALLOWED_RPCS = ["get_pdc_email_ai_transaction_successor_inbox_v2", "apply_pdc_email_ai_transaction_successor", "get_pdc_email_vehicle_location_snapshot", "get_pdc_email_ai_successor_health"]


def generate_password() -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*_-+="
    required = [secrets.choice(string.ascii_lowercase), secrets.choice(string.ascii_uppercase), secrets.choice(string.digits), secrets.choice("!@#$%^&*_-+=")]
    return ''.join(required + [secrets.choice(alphabet) for _ in range(60)])


class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", ctypes.c_uint32), ("pbData", ctypes.POINTER(ctypes.c_ubyte))]


def load_profile_env() -> None:
    if not PROFILE_ENV.is_file():
        raise RuntimeError("PDC_SUCCESSOR_PROFILE_ENV_MISSING")
    for raw in PROFILE_ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def protect(data: bytes) -> bytes:
    if os.name != "nt":
        raise RuntimeError("PDC_SUCCESSOR_DPAPI_REQUIRES_WINDOWS")
    source = ctypes.create_string_buffer(data)
    inp = DATA_BLOB(len(data), ctypes.cast(source, ctypes.POINTER(ctypes.c_ubyte)))
    out = DATA_BLOB()
    if not ctypes.windll.crypt32.CryptProtectData(ctypes.byref(inp), None, None, None, None, 1, ctypes.byref(out)):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(out.pbData, out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(out.pbData)


def unprotect(data: bytes) -> bytes:
    source = ctypes.create_string_buffer(data)
    inp = DATA_BLOB(len(data), ctypes.cast(source, ctypes.POINTER(ctypes.c_ubyte)))
    out = DATA_BLOB()
    if not ctypes.windll.crypt32.CryptUnprotectData(ctypes.byref(inp), None, None, None, None, 1, ctypes.byref(out)):
        raise ctypes.WinError()
    try:
        return ctypes.string_at(out.pbData, out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(out.pbData)


def protect_store(payload: dict) -> None:
    STORE.parent.mkdir(parents=True, exist_ok=True)
    user = os.environ.get("USERNAME") or os.environ.get("USER")
    if not user:
        raise RuntimeError("PDC_SUCCESSOR_CURRENT_USER_UNAVAILABLE")
    if STORE.exists():
        subprocess.run(["icacls.exe", str(STORE), "/grant:r", f"{user}:M", "*S-1-5-18:(F)", "*S-1-5-32-544:(F)"], check=True, capture_output=True)
    STORE.write_bytes(protect(json.dumps(payload, sort_keys=True).encode("utf-8")))
    subprocess.run(["icacls.exe", str(STORE), "/inheritance:r", "/grant:r", f"{user}:R", "*S-1-5-18:(F)", "*S-1-5-32-544:(F)"], check=True, capture_output=True)


def read_store() -> dict | None:
    if not STORE.is_file():
        return None
    return json.loads(unprotect(STORE.read_bytes()).decode("utf-8"))


def import_owner_tools():
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    sys.path.insert(0, str(OWNER_TOOLS))
    from staging_env import load_local_env  # noqa: F401
    load_local_env()
    import staging_rest
    return staging_rest


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"PDC_SUCCESSOR_MISSING_PROTECTED_VALUE:{name}")
    return value


def owner_rpc(rest, fn: str, params: dict):
    return rest._req("POST", f"/rest/v1/rpc/{fn}", headers={"apikey": rest.SERVICE_KEY, "Authorization": f"Bearer {rest.SERVICE_KEY}"}, body=params)


def read_identity_id(user_id: str) -> str | None:
    spec = importlib.util.spec_from_file_location('pdc_staging_bootstrap', BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError('PDC_SUCCESSOR_STAGING_CONNECTOR_INVALID')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    bundle = json.loads(module.unprotect(STAGING_DPAPI.read_bytes()).decode()); module.validate(bundle)
    import psycopg2
    conn = psycopg2.connect(bundle['PDC_STAGING_DATABASE_URL'], sslmode='verify-full', sslrootcert=bundle['PDC_STAGING_SSLROOTCERT'], application_name='pdc-successor-owner-identity-readback')
    try:
        q = conn.cursor(); q.execute("select identity_id from public.pdc_email_ai_successor_runtime_identities where auth_user_id=%s and normalized_email=%s and active and revoked_at is null", (user_id, EMAIL)); row = q.fetchone()
        return str(row[0]) if row else None
    finally: conn.close()


def runtime_plan_hostile() -> dict:
    return {
        'schema_version': 'pdc-email-ai-plan-v1',
        'source': {},
        'versions': {},
        'instructions': [{'action_type': 'table_write'}],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rollback", action="store_true")
    args = parser.parse_args()
    load_profile_env()
    rest = import_owner_tools()
    url = require_env("PDC_STAGING_SUPABASE_URL")
    if "cdsmnqxtyyoeoznmbidd" not in url or "vjdtsswhroyguxyfjdkt" in url:
        raise RuntimeError("PDC_SUCCESSOR_NON_STAGING_TARGET")
    admin_email = require_env("PDC_STAGING_ADMIN_EMAIL")
    admin_password = require_env("PDC_STAGING_ADMIN_PASSWORD")
    admin_status, admin_body = rest.sign_in(admin_email, admin_password)
    if admin_status != 200 or not isinstance(admin_body, dict) or not admin_body.get("access_token"):
        raise RuntimeError("PDC_SUCCESSOR_OWNER_LOGIN_FAILED")
    admin_token = admin_body["access_token"]
    role_status, roles = rest.rest_select(admin_token, "pdc_user_roles", "?email=eq." + quote(admin_email, safe="") + "&select=auth_user_id,role,active,account_status")
    approver = next((row for row in (roles if isinstance(roles, list) else []) if row.get("role") == "administrator" and row.get("active") and row.get("account_status") == "approved"), None)
    if role_status != 200 or not approver or not approver.get("auth_user_id"):
        raise RuntimeError("PDC_SUCCESSOR_OWNER_APPROVER_NOT_FOUND")
    saved = read_store()
    user_id = saved.get("auth_user_id") if saved else None
    runtime_password = saved.get("runtime_password") if saved else None
    created_here = False
    credential_digest = saved.get("credential_digest") if saved else None
    provision = None
    if args.rollback:
        if not saved or not saved.get("provisioning_id") or not saved.get("auth_user_id"):
            raise RuntimeError("PDC_SUCCESSOR_ROLLBACK_STORE_MISSING")
        rollback_status, rollback_body = owner_rpc(rest, "rollback_pdc_email_ai_successor_runtime", {"p_provisioning_id": saved["provisioning_id"]})
        delete_status, _ = rest.admin_delete_user(saved["auth_user_id"])
        if rollback_status not in (200, 201) or not isinstance(rollback_body, dict) or not rollback_body.get("ok") or delete_status not in (200, 204):
            raise RuntimeError("PDC_SUCCESSOR_ROLLBACK_FAILED")
        STORE.unlink(missing_ok=True)
        print(json.dumps({"ok": True, "rolled_back": True, "auth_user_deleted": True, "service_key_persisted": False, "runtime_service_role": False}, sort_keys=True))
        return
    if not user_id or not runtime_password:
        runtime_password = generate_password()
        user_status, users = rest._req("GET", "/auth/v1/admin/users?per_page=1000", headers={"apikey": rest.SERVICE_KEY, "Authorization": f"Bearer {rest.SERVICE_KEY}"})
        existing = next((row for row in (users.get("users", []) if isinstance(users, dict) else []) if str(row.get("email", "")).lower() == EMAIL.lower()), None)
        if existing:
            user_id = existing.get("id")
            update_status, _ = rest._req("PUT", f"/auth/v1/admin/users/{user_id}", headers={"apikey": rest.SERVICE_KEY, "Authorization": f"Bearer {rest.SERVICE_KEY}"}, body={"password": runtime_password, "email_confirm": True})
            if user_status != 200 or update_status not in (200, 201) or not user_id:
                raise RuntimeError(f"PDC_SUCCESSOR_DEDICATED_USER_RESET_FAILED:list={user_status}:update={update_status}:found={bool(existing)}:id={bool(user_id)}")
            credential_digest = hashlib.sha256(runtime_password.encode("utf-8")).hexdigest()
            provision_status, provision = owner_rpc(rest, "rotate_pdc_email_ai_successor_runtime_credential", {"p_auth_user_id": user_id, "p_credential_digest": credential_digest, "p_approved_by": approver["auth_user_id"]})
        else:
            create_status, created = rest.admin_create_user(EMAIL, runtime_password, email_confirm=True)
            if create_status not in (200, 201) or not isinstance(created, dict) or not created.get("id"):
                raise RuntimeError("PDC_SUCCESSOR_AUTH_USER_CREATE_FAILED")
            user_id = created["id"]
            created_here = True
    if saved and user_id and runtime_password:
        provision_status = 200
        provision = {"provisioning_id": saved.get("provisioning_id"), "identity_id": saved.get("identity_id"), "code": "successor_already_provisioned", "ok": True}
    elif provision is None:
        credential_digest = hashlib.sha256(runtime_password.encode("utf-8")).hexdigest()
        params = {"p_auth_user_id": user_id, "p_normalized_email": EMAIL, "p_credential_digest": credential_digest, "p_gateway_instance_id": GATEWAY, "p_mailbox_scope": MAILBOX, "p_transport_release_version": TRANSPORT, "p_model_version": MODEL, "p_prompt_version": PROMPT, "p_taxonomy_version": TAXONOMY, "p_rule_version": RULES, "p_action_contract_version": ACTION_CONTRACT, "p_approved_by": approver["auth_user_id"]}
        provision_status, provision = owner_rpc(rest, "commission_pdc_email_ai_successor_runtime", params)
    if provision_status not in (200, 201) or not isinstance(provision, dict) or not provision.get("ok"):
        if created_here:
            rest.admin_delete_user(user_id)
        raise RuntimeError("PDC_SUCCESSOR_OWNER_PROVISIONING_FAILED")
    if provision.get("code") == "successor_provisioning_conflict":
        raise RuntimeError("PDC_SUCCESSOR_OWNER_PROVISIONING_CONFLICT")
    runtime_status, runtime = rest.sign_in(EMAIL, runtime_password)
    if runtime_status != 200 or not isinstance(runtime, dict) or not runtime.get("access_token"):
        raise RuntimeError("PDC_SUCCESSOR_RUNTIME_LOGIN_FAILED")
    runtime_token = runtime["access_token"]
    health_status, health = rest.rpc(runtime_token, "get_pdc_email_ai_successor_health", {})
    query_status, query = rest.rpc(runtime_token, "get_pdc_email_ai_transaction_successor_inbox_v2", {"p_cursor": None, "p_page_size": 2})
    readback_status, readback = rest.rpc(runtime_token, "get_pdc_email_vehicle_location_snapshot", {})
    pdc_plan = {"p_plan": runtime_plan_hostile()}
    hostile_status, hostile = rest.rpc(runtime_token, "apply_pdc_email_ai_transaction_successor", pdc_plan)
    wrong_actor_status, wrong_actor = rest.rpc(admin_token, "apply_pdc_email_ai_transaction_successor", pdc_plan)
    wrong_gateway_params = {"p_auth_user_id": user_id, "p_normalized_email": EMAIL, "p_credential_digest": credential_digest, "p_gateway_instance_id": "wrong-gateway", "p_mailbox_scope": MAILBOX, "p_transport_release_version": TRANSPORT, "p_model_version": MODEL, "p_prompt_version": PROMPT, "p_taxonomy_version": TAXONOMY, "p_rule_version": RULES, "p_action_contract_version": ACTION_CONTRACT, "p_approved_by": approver["auth_user_id"]}
    wrong_gateway_status, wrong_gateway = owner_rpc(rest, "commission_pdc_email_ai_successor_runtime", wrong_gateway_params)
    table_status, _ = rest.rest_select(runtime_token, "pdc_email_ai_successor_transaction_receipts", "?select=transaction_id&limit=1")
    sql_status, _ = rest.rpc(runtime_token, "pg_execute_sql", {"query": "select 1"})
    if not (health_status == 200 and isinstance(health, dict) and health.get("ok") and query_status == 200 and isinstance(query, dict) and query.get("ok") and readback_status == 200 and isinstance(readback, dict) and readback.get("ok") and hostile_status == 200 and isinstance(hostile, dict) and hostile.get("code") == "typed_instruction_invalid" and wrong_actor_status == 200 and isinstance(wrong_actor, dict) and wrong_actor.get("code") == "successor_runtime_identity_denied" and wrong_gateway_status == 200 and isinstance(wrong_gateway, dict) and wrong_gateway.get("code") == "successor_owner_provisioning_denied" and table_status in (401, 403) and sql_status in (404, 401, 403)):
        raise RuntimeError("PDC_SUCCESSOR_COMMISSIONING_PROBE_FAILED")
    identity_id = provision.get("identity_id") or read_identity_id(user_id)
    stored = {"schema_version": "pdc-email-ai-successor-runtime-secret-v1", "environment": "staging", "project_ref": "cdsmnqxtyyoeoznmbidd", "auth_user_id": user_id, "email": EMAIL, "runtime_password": runtime_password, "credential_digest": credential_digest, "provisioning_id": provision.get("provisioning_id"), "identity_id": identity_id, "gateway_instance_id": GATEWAY, "mailbox_scope": MAILBOX, "allowed_rpc_scope": ALLOWED_RPCS, "transport_release_version": TRANSPORT, "model_version": MODEL, "prompt_version": PROMPT, "taxonomy_version": TAXONOMY, "rule_version": RULES, "action_contract_version": ACTION_CONTRACT, "service_key_persisted": False}
    protect_store(stored)
    roundtrip = read_store() or {}
    print(json.dumps({"ok": True, "created_or_reused": "reused" if saved else "created", "auth_user_present": bool(user_id), "runtime_login_ok": True, "credential_store_present": STORE.is_file(), "credential_store_digest_matches": roundtrip.get("credential_digest") == credential_digest, "provisioning_receipt_present": bool(provision.get("provisioning_id")), "identity_id_present": bool(identity_id), "gateway_scope_exact": GATEWAY == roundtrip.get("gateway_instance_id"), "mailbox_scope_exact": MAILBOX == roundtrip.get("mailbox_scope"), "allowed_rpc_scope_exact": roundtrip.get("allowed_rpc_scope") == ALLOWED_RPCS, "approved_rpc_query": query_status == 200 and bool(query.get("ok")), "approved_rpc_health": health_status == 200 and bool(health.get("ok")), "approved_rpc_readback": readback_status == 200 and bool(readback.get("ok")), "hostile_action_rejected": hostile.get("code") == "typed_instruction_invalid", "wrong_actor_rejected": wrong_actor.get("code") == "successor_runtime_identity_denied", "wrong_gateway_rejected": wrong_gateway.get("code") == "successor_owner_provisioning_denied", "direct_table_rejected": table_status in (401, 403), "arbitrary_sql_rejected": sql_status in (404, 401, 403), "service_key_persisted": False, "runtime_service_role": False, "business_mutation": False, "production_contacted": False}, sort_keys=True))


if __name__ == "__main__":
    try: main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "service_key_persisted": False, "runtime_service_role": False, "production_contacted": False}, sort_keys=True)); raise SystemExit(1)
