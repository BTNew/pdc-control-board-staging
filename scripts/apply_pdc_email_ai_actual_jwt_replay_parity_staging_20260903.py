#!/usr/bin/env python3
"""Apply and prove actual-JWT safe-inbox replay parity on STAGING."""
from __future__ import annotations

import copy
import ctypes
import hashlib
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from ctypes import wintypes
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903080000_pdc_email_ai_actual_jwt_replay_parity_20260903.sql"
FINAL_MIGRATION = ROOT / "supabase/staging_only/20260903090000_pdc_email_ai_actual_jwt_legacy_receipt_parity_20260903.sql"
LOCKDOWN_MIGRATION = ROOT / "supabase/staging_only/20260903100000_pdc_email_ai_actual_jwt_replay_lockdown_20260903.sql"
PROJECTION_MIGRATION = ROOT / "supabase/staging_only/20260903110000_pdc_email_ai_safe_projection_freeze_20260903.sql"
EVIDENCE = ROOT / "review-evidence/t_d2e0fb9b/actual-jwt-replay-parity-proof.json"
RUNTIME_ENV = Path.home() / "AppData/Local/hermes/profiles/pdc-email-ai-lead/.env"
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
EXPECTED_USER_ID = "e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8"
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903080000"
FINAL_APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903090000"
LOCKDOWN_APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903100000"
PROJECTION_APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903110000"
TARGET = ("20260903110000", "pdc_email_ai_safe_projection_freeze_20260903")
LOCKDOWN = ("20260903100000", "pdc_email_ai_actual_jwt_replay_lockdown_20260903")
FINAL = ("20260903090000", "pdc_email_ai_actual_jwt_legacy_receipt_parity_20260903")
INTERMEDIATE = ("20260903080000", "pdc_email_ai_actual_jwt_replay_parity_20260903")
PREDECESSOR = ("20260903070000", "pdc_email_ai_final_replay_input_guard_20260903")
TRANSACTION_IDS = (
    "0fec3e2a-bd49-4d98-a83d-42770edd9b23",
    "35726910-42d6-4c7a-aa54-71e75dd67083",
    "541657d7-ef0b-4323-884c-2a1edc29aa2f",
)


class Credential(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD), ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPWSTR), ("Comment", wintypes.LPWSTR),
        ("LastWritten", wintypes.FILETIME), ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(ctypes.c_ubyte)),
        ("Persist", wintypes.DWORD), ("AttributeCount", wintypes.DWORD),
        ("Attributes", ctypes.c_void_p), ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPWSTR),
    ]


def management_token() -> str:
    pointer = ctypes.POINTER(Credential)()
    advapi = ctypes.WinDLL("Advapi32.dll")
    if not advapi.CredReadW("Supabase CLI:supabase", 1, 0, ctypes.byref(pointer)):
        raise ctypes.WinError()
    try:
        raw = ctypes.string_at(pointer.contents.CredentialBlob, pointer.contents.CredentialBlobSize)
        for encoding in ("utf-8", "utf-16-le"):
            try:
                value = raw.decode(encoding).rstrip("\x00")
            except UnicodeDecodeError:
                continue
            if value:
                return value
        raise RuntimeError("SUPABASE_MANAGEMENT_CREDENTIAL_DECODE_FAILED")
    finally:
        advapi.CredFree(pointer)


def management_query(sql: str) -> list[dict[str, Any]]:
    path = f"/v1/projects/{STAGING_REF}/database/query"
    if PRODUCTION_REF in path or STAGING_REF not in path:
        raise RuntimeError("PDC_NON_STAGING_MANAGEMENT_TARGET_REFUSED")
    request = urllib.request.Request(
        "https://api.supabase.com" + path,
        data=json.dumps({"query": sql}, separators=(",", ":")).encode(),
        headers={
            "Authorization": "Bearer " + management_token(),
            "Content-Type": "application/json",
            "User-Agent": "SupabaseCLI/2 pdc-email-ai-actual-jwt-replay-parity",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            result = json.load(response)
    except urllib.error.HTTPError as exc:
        message = exc.read().decode(errors="replace")
        raise RuntimeError(f"SUPABASE_STAGING_MANAGEMENT_QUERY_FAILED:{exc.code}:{message[:500]}") from None
    if not isinstance(result, list):
        raise RuntimeError("SUPABASE_STAGING_MANAGEMENT_QUERY_RESULT_INVALID")
    return result


def load_runtime() -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in RUNTIME_ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    required = (
        "PDC_STAGING_SUPABASE_URL", "PDC_STAGING_SUPABASE_ANON_KEY",
        "PDC_EMAIL_AI_RUNTIME_EMAIL", "PDC_EMAIL_AI_RUNTIME_PASSWORD",
    )
    if any(not values.get(key) for key in required):
        raise RuntimeError("PDC_RUNTIME_PROFILE_CREDENTIALS_INCOMPLETE")
    parsed = urllib.parse.urlparse(values["PDC_STAGING_SUPABASE_URL"])
    if parsed.scheme != "https" or parsed.hostname != f"{STAGING_REF}.supabase.co" or parsed.port is not None:
        raise RuntimeError("PDC_RUNTIME_PROFILE_NON_STAGING_URL_REFUSED")
    return values


def http_json(url: str, headers: dict[str, str], payload: dict[str, Any]) -> tuple[int, Any]:
    request = urllib.request.Request(
        url, data=json.dumps(payload, separators=(",", ":")).encode(), headers=headers, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            body = json.loads(exc.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            body = {"code": "non_json_http_error"}
        return exc.code, body


def protected_get_status(url: str, headers: dict[str, str]) -> int:
    request = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        exc.read()
        return exc.code


def data_fingerprint() -> dict[str, Any]:
    quoted = ",".join("'" + value + "'::uuid" for value in TRANSACTION_IDS)
    rows = management_query(
        "SELECT jsonb_build_object("
        "'transactions',(SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts),"
        "'actions',(SELECT count(*) FROM public.pdc_email_ai_successor_action_receipts),"
        "'audit_events',(SELECT count(*) FROM public.audit_events),"
        "'vehicles',(SELECT count(*) FROM public.vehicles),"
        "'vehicle_versions',(SELECT coalesce(sum(version),0) FROM public.vehicles),"
        "'intakes',(SELECT count(*) FROM public.ai_email_intake),"
        "'attachments',(SELECT count(*) FROM public.ai_email_attachments),"
        "'all_transactions_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(x)::text,E'\\n' ORDER BY to_jsonb(x)::text) FROM public.pdc_email_ai_successor_transaction_receipts x),''),'UTF8'),'sha256'),'hex'),"
        "'all_actions_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(x)::text,E'\\n' ORDER BY to_jsonb(x)::text) FROM public.pdc_email_ai_successor_action_receipts x),''),'UTF8'),'sha256'),'hex'),"
        "'all_audit_events_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(x)::text,E'\\n' ORDER BY to_jsonb(x)::text) FROM public.audit_events x),''),'UTF8'),'sha256'),'hex'),"
        "'all_vehicles_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(x)::text,E'\\n' ORDER BY to_jsonb(x)::text) FROM public.vehicles x),''),'UTF8'),'sha256'),'hex'),"
        "'all_intakes_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(x)::text,E'\\n' ORDER BY to_jsonb(x)::text) FROM public.ai_email_intake x),''),'UTF8'),'sha256'),'hex'),"
        "'all_attachments_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(x)::text,E'\\n' ORDER BY to_jsonb(x)::text) FROM public.ai_email_attachments x),''),'UTF8'),'sha256'),'hex'),"
        "'selected_transactions_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(t)::text,E'\\n' ORDER BY t.transaction_id) FROM public.pdc_email_ai_successor_transaction_receipts t WHERE t.transaction_id IN (" + quoted + ")),''),'UTF8'),'sha256'),'hex'),"
        "'selected_actions_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(a)::text,E'\\n' ORDER BY a.transaction_id,a.created_at,a.action_receipt_id) FROM public.pdc_email_ai_successor_action_receipts a WHERE a.transaction_id IN (" + quoted + ")),''),'UTF8'),'sha256'),'hex'),"
        "'selected_sources_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(i)::text,E'\\n' ORDER BY i.id) FROM public.ai_email_intake i JOIN public.pdc_email_ai_successor_transaction_receipts t ON t.source_receipt_id=i.id WHERE t.transaction_id IN (" + quoted + ")),''),'UTF8'),'sha256'),'hex')"
        ") AS fingerprint"
    )
    return rows[0]["fingerprint"]


def original_action_ids() -> dict[str, list[str]]:
    quoted = ",".join("'" + value + "'::uuid" for value in TRANSACTION_IDS)
    rows = management_query(
        "SELECT t.transaction_id::text,coalesce(jsonb_agg(a.action_receipt_id ORDER BY a.created_at,a.action_receipt_id) FILTER (WHERE a.action_receipt_id IS NOT NULL),'[]'::jsonb) AS action_ids "
        "FROM public.pdc_email_ai_successor_transaction_receipts t LEFT JOIN public.pdc_email_ai_successor_action_receipts a ON a.transaction_id=t.transaction_id "
        "WHERE t.transaction_id IN (" + quoted + ") GROUP BY t.transaction_id ORDER BY t.transaction_id"
    )
    return {row["transaction_id"]: row["action_ids"] for row in rows}


def main() -> None:
    migration_sha256 = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    final_migration_sha256 = hashlib.sha256(FINAL_MIGRATION.read_bytes()).hexdigest()
    lockdown_migration_sha256 = hashlib.sha256(LOCKDOWN_MIGRATION.read_bytes()).hexdigest()
    projection_migration_sha256 = hashlib.sha256(PROJECTION_MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260903080000 pdc email ai actual jwt replay parity source {migration_sha256}"
    final_expected = f"apply migration 20260903090000 pdc email ai actual jwt legacy receipt parity source {final_migration_sha256}"
    lockdown_expected = f"apply migration 20260903100000 pdc email ai actual jwt replay lockdown source {lockdown_migration_sha256}"
    projection_expected = f"apply migration 20260903110000 pdc email ai safe projection freeze source {projection_migration_sha256}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_ACTUAL_JWT_REPLAY_PARITY_APPROVAL_MISSING_OR_HASH_MISMATCH")
    if os.environ.get(FINAL_APPROVAL_ENV) != final_expected:
        raise RuntimeError("PDC_ACTUAL_JWT_LEGACY_RECEIPT_PARITY_APPROVAL_MISSING_OR_HASH_MISMATCH")
    if os.environ.get(LOCKDOWN_APPROVAL_ENV) != lockdown_expected:
        raise RuntimeError("PDC_ACTUAL_JWT_REPLAY_LOCKDOWN_APPROVAL_MISSING_OR_HASH_MISMATCH")
    if os.environ.get(PROJECTION_APPROVAL_ENV) != projection_expected:
        raise RuntimeError("PDC_EMAIL_AI_SAFE_PROJECTION_FREEZE_APPROVAL_MISSING_OR_HASH_MISMATCH")

    head_row = management_query(
        "SELECT version,name FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version DESC LIMIT 1"
    )[0]
    head = (head_row["version"], head_row["name"])
    if head not in (PREDECESSOR, INTERMEDIATE, FINAL, LOCKDOWN, TARGET):
        raise RuntimeError(f"PDC_ACTUAL_JWT_REPLAY_PARITY_UNEXPECTED_HEAD:{head}")
    counts_before = data_fingerprint()
    action_ids_before = original_action_ids()
    intermediate_already_applied = head in (INTERMEDIATE, FINAL, LOCKDOWN, TARGET)
    if not intermediate_already_applied:
        management_query(MIGRATION.read_text(encoding="utf-8"))
    final_already_applied = head in (FINAL, LOCKDOWN, TARGET)
    if not final_already_applied:
        management_query(FINAL_MIGRATION.read_text(encoding="utf-8"))
    lockdown_already_applied = head in (LOCKDOWN, TARGET)
    if not lockdown_already_applied:
        management_query(LOCKDOWN_MIGRATION.read_text(encoding="utf-8"))
    already_applied = head == TARGET
    if not already_applied:
        management_query(PROJECTION_MIGRATION.read_text(encoding="utf-8"))

    ledger = management_query(
        "SELECT version,name FROM supabase_migrations.schema_migrations WHERE version IN('20260903080000','20260903090000','20260903100000','20260903110000') ORDER BY version"
    )
    helper = management_query(
        "SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex') AS sha256,"
        "encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_safe_plan(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS safe_plan_sha256,"
        "position('public.pdc_email_ai_successor_safe_plan(t.typed_plan)=p_plan' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0 AS safe_projection_match,"
        "position('t.transaction_id IN(' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0 AS transaction_allowlist,"
        "position('t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,''UTF8''),''sha256''),''hex'')' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0 AS canonical_hash_match,"
        "position('attachment_hashes.hashes@>coalesce(t.typed_plan->''attachment_digests'',''[]''::jsonb)' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0 AS canonical_attachment_match,"
        "(SELECT count(*) FROM public.pdc_email_ai_successor_runtime_rotations_20260903 WHERE predecessor_identity_id='a5be6642-a175-4abc-a7e2-45185b87d790'::uuid AND successor_identity_id='173c0d7f-8c36-4f73-a670-ee7fcf835af1'::uuid)=1 AS legacy_rotation_bound,"
        "has_function_privilege('authenticated','public.pdc_email_ai_successor_safe_plan(jsonb)','execute') AS safe_plan_authenticated_execute,"
        "has_function_privilege('service_role','public.pdc_email_ai_successor_safe_plan(jsonb)','execute') AS safe_plan_service_role_execute,"
        "has_function_privilege('anon','public.pdc_email_ai_successor_safe_plan(jsonb)','execute') AS safe_plan_anon_execute,"
        "has_function_privilege('authenticated','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute') AS authenticated_execute,"
        "has_function_privilege('service_role','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute') AS service_role_execute,"
        "has_function_privilege('anon','public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)','execute') AS anon_execute"
    )[0]

    values = load_runtime()
    base = values["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    anon = values["PDC_STAGING_SUPABASE_ANON_KEY"]
    auth_status, auth = http_json(
        f"{base}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json"},
        {"email": values["PDC_EMAIL_AI_RUNTIME_EMAIL"], "password": values["PDC_EMAIL_AI_RUNTIME_PASSWORD"]},
    )
    token = auth.get("access_token") if isinstance(auth, dict) else None
    user_id = (auth.get("user") or {}).get("id") if isinstance(auth, dict) else None
    if auth_status != 200 or not token or user_id != EXPECTED_USER_ID:
        raise RuntimeError("PDC_RUNTIME_PROFILE_IDENTITY_MISMATCH")
    headers = {"apikey": anon, "Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    readbacks: dict[str, Any] = {}
    rpc_calls = {
        "health": ("get_pdc_email_ai_successor_health", {}),
        "contract": ("get_pdc_email_ai_successor_action_contract_20260901", {}),
        "snapshot": ("get_pdc_email_vehicle_location_snapshot", {}),
        "fixtures": ("get_pdc_email_ai_v2_acceptance_fixtures_20260903", {}),
        "inbox": ("get_pdc_email_ai_transaction_successor_inbox_v2", {"p_cursor": None, "p_page_size": 250}),
    }
    expected_codes = {
        "health": "pdc_email_ai_successor_health",
        "contract": "typed_action_contract",
        "snapshot": "ok",
        "fixtures": "pdc_email_ai_v2_acceptance_fixtures_ready",
        "inbox": "successor_inbox_snapshot",
    }
    bodies: dict[str, Any] = {}
    for label, (rpc, payload) in rpc_calls.items():
        status, body = http_json(f"{base}/rest/v1/rpc/{rpc}", headers, payload)
        bodies[label] = body
        readbacks[label] = {
            "http_status": status,
            "ok": body.get("ok") if isinstance(body, dict) else None,
            "code": body.get("code") if isinstance(body, dict) else "invalid_response",
        }
        if (status != 200 or not isinstance(body, dict) or body.get("ok") is not True
                or readbacks[label]["code"] != expected_codes[label]):
            raise RuntimeError(f"PDC_RUNTIME_{label.upper()}_READBACK_FAILED:{status}:{readbacks[label]['code']}")
    fixtures = bodies["fixtures"]
    if fixtures.get("fixture_count") != 14:
        raise RuntimeError("PDC_RUNTIME_FIXTURE_COUNT_INVALID")
    inbox = bodies["inbox"]
    items = inbox.get("items") or (inbox.get("data") or {}).get("items") or []
    plans: dict[str, dict[str, Any]] = {}
    for item in items:
        transaction = item.get("transaction") or {}
        transaction_id = str(transaction.get("transaction_id") or "")
        if transaction_id in TRANSACTION_IDS:
            plan = transaction.get("typed_plan") or transaction.get("plan")
            if isinstance(plan, dict):
                plans[transaction_id] = plan
    if set(plans) != set(TRANSACTION_IDS):
        raise RuntimeError(f"PDC_RUNTIME_INBOX_TRANSACTIONS_MISSING:{sorted(set(TRANSACTION_IDS)-set(plans))}")

    replay_results: list[dict[str, Any]] = []
    for transaction_id in TRANSACTION_IDS:
        response = None
        status = 0
        for attempt in range(3):
            status, response = http_json(
                f"{base}/rest/v1/rpc/apply_pdc_email_ai_typed_action_surface_20260901_strict",
                headers, {"p_plan": plans[transaction_id]},
            )
            if isinstance(response, dict) and response.get("ok") is True:
                break
            if attempt < 2:
                time.sleep(2)
        replay_results.append({
            "transaction_id": transaction_id,
            "http_status": status,
            "ok": response.get("ok") if isinstance(response, dict) else None,
            "code": response.get("code") if isinstance(response, dict) else "invalid_response",
            "returned_transaction_id": response.get("transaction_id") if isinstance(response, dict) else None,
            "action_receipt_ids": response.get("action_receipt_ids") if isinstance(response, dict) else None,
            "exact_successful_replay": response.get("exact_successful_replay") if isinstance(response, dict) else None,
            "runtime_rotation_replay": response.get("runtime_rotation_replay") if isinstance(response, dict) else None,
        })

    probe_plan = plans[TRANSACTION_IDS[0]]
    changed = copy.deepcopy(probe_plan)
    changed["created_at"] = "2099-01-01T00:00:00+00:00"
    altered = copy.deepcopy(probe_plan)
    altered["evidence_digest"] = "0" * 64
    hostile = {"environment": "production", "instructions": [{"action_type": "sql", "payload": "DROP TABLE vehicles"}]}
    rejection_results = {}
    for label, plan in (("changed_plan_rejected", changed), ("altered_evidence_rejected", altered), ("hostile_plan_rejected", hostile)):
        status, response = http_json(
            f"{base}/rest/v1/rpc/apply_pdc_email_ai_typed_action_surface_20260901_strict",
            headers, {"p_plan": plan},
        )
        rejection_results[label] = {
            "http_status": status,
            "ok": response.get("ok") if isinstance(response, dict) else None,
            "code": response.get("code") if isinstance(response, dict) else "invalid_response",
        }

    protected_table_http_statuses = {
        table: protected_get_status(f"{base}/rest/v1/{table}?select=*&limit=1", headers)
        for table in ("pdc_email_ai_successor_transaction_receipts", "pdc_email_ai_v2_acceptance_fixtures_20260903")
    }
    arbitrary_sql_http_status, _ = http_json(
        f"{base}/rest/v1/rpc/execute_sql", headers, {"query": "select 1"}
    )
    counts_after = data_fingerprint()
    action_ids_after = original_action_ids()

    stable_transaction_ids = all(
        row["http_status"] == 200
        and row["ok"] is True
        and row["code"] == "pdc_email_ai_typed_action_surface_verified"
        and row["returned_transaction_id"] == row["transaction_id"]
        and row["runtime_rotation_replay"] is True
        for row in replay_results
    )
    stable_action_receipt_ids = all(
        row["action_receipt_ids"] == action_ids_before[row["transaction_id"]]
        for row in replay_results
    ) and action_ids_before == action_ids_after
    zero_mutations = counts_before == counts_after
    rejections_ok = all(
        row["http_status"] == 200 and row["ok"] is False
        and row["code"] in ("typed_v2_plan_invalid", "source_reuse_conflict")
        for row in rejection_results.values()
    )
    acl_ok = all(status in (401, 403, 404) for status in protected_table_http_statuses.values()) and arbitrary_sql_http_status == 404
    helper_ok = (
        helper["safe_projection_match"] and helper["canonical_hash_match"]
        and helper["canonical_attachment_match"] and helper["legacy_rotation_bound"]
        and helper["transaction_allowlist"]
        and helper["safe_plan_sha256"] == "9fd1d2786357633045468abe13d7aaf1430de5444c1f7117fb904f41cbb5c086"
        and not helper["safe_plan_authenticated_execute"]
        and not helper["safe_plan_service_role_execute"]
        and not helper["safe_plan_anon_execute"]
        and not helper["authenticated_execute"] and not helper["service_role_execute"] and not helper["anon_execute"]
    )
    ok = all((
        len(ledger) == 4,
        helper_ok,
        stable_transaction_ids,
        stable_action_receipt_ids,
        zero_mutations,
        rejections_ok,
        acl_ok,
        all(row["exact_successful_replay"] is True for row in replay_results),
    ))
    proof = {
        "ok": ok,
        "environment": "staging",
        "project_ref": STAGING_REF,
        "authenticated_user_id": user_id,
        "migration_identity": TARGET,
        "migration_sha256": migration_sha256,
        "final_migration_sha256": final_migration_sha256,
        "lockdown_migration_sha256": lockdown_migration_sha256,
        "projection_migration_sha256": projection_migration_sha256,
        "intermediate_migration_already_applied": intermediate_already_applied,
        "final_migration_already_applied": final_already_applied,
        "lockdown_migration_already_applied": lockdown_already_applied,
        "migration_already_applied": already_applied,
        "ledger_readback": ledger,
        "helper_readback": helper,
        "runtime_readbacks": readbacks,
        "fixture_count": fixtures.get("fixture_count"),
        "replay_results": replay_results,
        "stable_transaction_ids": stable_transaction_ids,
        "stable_action_receipt_ids": stable_action_receipt_ids,
        "changed_plan_rejected": rejection_results["changed_plan_rejected"],
        "altered_evidence_rejected": rejection_results["altered_evidence_rejected"],
        "hostile_plan_rejected": rejection_results["hostile_plan_rejected"],
        "protected_table_http_statuses": protected_table_http_statuses,
        "arbitrary_sql_http_status": arbitrary_sql_http_status,
        "zero_mutations": zero_mutations,
        "counts_before": counts_before,
        "counts_after": counts_after,
        "production_contacted": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }
    if not ok:
        raise RuntimeError(f"PDC_ACTUAL_JWT_REPLAY_PARITY_READBACK_FAILED:{json.dumps(proof, sort_keys=True)}")
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_text(json.dumps(proof, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "ok": True,
        "evidence": str(EVIDENCE),
        "migration_sha256": migration_sha256,
        "final_migration_sha256": final_migration_sha256,
        "lockdown_migration_sha256": lockdown_migration_sha256,
        "projection_migration_sha256": projection_migration_sha256,
        "replay_count": len(replay_results),
        "stable_transaction_ids": stable_transaction_ids,
        "stable_action_receipt_ids": stable_action_receipt_ids,
        "zero_mutations": zero_mutations,
        "production_contacted": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({
            "ok": False,
            "error": str(exc),
            "production_contacted": False,
            "mailbox_contacted": False,
            "outbound_email_sent": False,
        }, sort_keys=True))
        raise SystemExit(1)
