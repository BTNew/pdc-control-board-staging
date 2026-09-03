#!/usr/bin/env python3
"""Compare redacted runtime inbox plans with canonical STAGING receipts."""
from __future__ import annotations

import ctypes
import json
import urllib.error
import urllib.parse
import urllib.request
from ctypes import wintypes
from pathlib import Path
from typing import Any

STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
TARGETS = (
    "541657d7-ef0b-4323-884c-2a1edc29aa2f",
    "35726910-42d6-4c7a-aa54-71e75dd67083",
    "0fec3e2a-bd49-4d98-a83d-42770edd9b23",
)
RUNTIME_ENV = Path.home() / "AppData/Local/hermes/profiles/pdc-email-ai-lead/.env"


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
            "User-Agent": "SupabaseCLI/2 pdc-email-ai-jwt-parity-diagnostic",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        result = json.load(response)
    if not isinstance(result, list):
        raise RuntimeError("SUPABASE_STAGING_MANAGEMENT_QUERY_RESULT_INVALID")
    return result


def runtime_values() -> dict[str, str]:
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


def post(url: str, headers: dict[str, str], payload: dict[str, Any]) -> Any:
    request = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def differences(left: Any, right: Any, path: str = "$") -> list[dict[str, Any]]:
    if type(left) is not type(right):
        return [{"path": path, "kind": "type", "runtime_type": type(left).__name__, "canonical_type": type(right).__name__}]
    if isinstance(left, dict):
        output: list[dict[str, Any]] = []
        for key in sorted(set(left) | set(right)):
            child = f"{path}.{key}"
            if key not in left:
                output.append({"path": child, "kind": "missing_runtime"})
            elif key not in right:
                output.append({"path": child, "kind": "runtime_only"})
            else:
                output.extend(differences(left[key], right[key], child))
        return output
    if isinstance(left, list):
        if len(left) != len(right):
            return [{"path": path, "kind": "length", "runtime_length": len(left), "canonical_length": len(right)}]
        output = []
        for index, (a, b) in enumerate(zip(left, right)):
            output.extend(differences(a, b, f"{path}[{index}]"))
        return output
    return [] if left == right else [{"path": path, "kind": "value"}]


def main() -> None:
    values = runtime_values()
    base = values["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    anon = values["PDC_STAGING_SUPABASE_ANON_KEY"]
    auth = post(
        f"{base}/auth/v1/token?grant_type=password",
        {"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json"},
        {"email": values["PDC_EMAIL_AI_RUNTIME_EMAIL"], "password": values["PDC_EMAIL_AI_RUNTIME_PASSWORD"]},
    )
    token = auth["access_token"]
    headers = {"apikey": anon, "Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    inbox = post(
        f"{base}/rest/v1/rpc/get_pdc_email_ai_transaction_successor_inbox_v2",
        headers,
        {"p_cursor": None, "p_page_size": 250},
    )
    runtime_plans = {}
    for item in inbox.get("items", []):
        transaction = item.get("transaction") or {}
        transaction_id = str(transaction.get("transaction_id") or "")
        if transaction_id in TARGETS:
            runtime_plans[transaction_id] = transaction.get("typed_plan") or transaction.get("plan")

    quoted = ",".join("'" + value + "'::uuid" for value in TARGETS)
    rows = management_query(
        "SELECT transaction_id::text,typed_plan,"
        "encode(extensions.digest(convert_to(typed_plan::text,'UTF8'),'sha256'),'hex') AS server_plan_sha256 "
        "FROM public.pdc_email_ai_successor_transaction_receipts WHERE transaction_id IN (" + quoted + ") ORDER BY transaction_id"
    )
    report = []
    for row in rows:
        transaction_id = row["transaction_id"]
        runtime_plan = runtime_plans.get(transaction_id)
        canonical_plan = row["typed_plan"]
        plan_sql = json.dumps(runtime_plan, separators=(",", ":")).replace("$json$", "")
        predicates = management_query(
            "WITH supplied AS (SELECT $json$" + plan_sql + "$json$::jsonb AS p) "
            "SELECT t.typed_plan=s.p AS canonical_equal,"
            "public.pdc_email_ai_successor_safe_plan(t.typed_plan)=s.p AS safe_equal,"
            "t.plan_hash=encode(extensions.digest(convert_to(t.typed_plan::text,'UTF8'),'sha256'),'hex') AS stored_hash_valid,"
            "t.source_receipt_id=(s.p->>'source_receipt_id')::uuid AS receipt_equal,"
            "t.source_digest=lower(s.p->>'source_digest') AS source_digest_equal,"
            "t.evidence_digest=lower(s.p->>'evidence_digest') AS evidence_digest_equal,"
            "i.duplicate_of IS NULL AS source_not_duplicate,"
            "lower(btrim(i.source_hash))=t.source_digest AS intake_source_digest_equal,"
            "coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(s.p->>'source_message_id') AS message_equal,"
            "coalesce(btrim(i.graph_thread_id),'')=btrim(s.p->>'source_thread_id') AS thread_equal,"
            "coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=t.evidence_digest AS intake_evidence_digest_equal,"
            "jsonb_typeof(coalesce(i.extracted_data->'attachment_digests','[]'::jsonb))='array' AS attachment_attestation_is_array,"
            "coalesce(i.extracted_data->'attachment_digests','[]'::jsonb)@>attachment_hashes.hashes AS attachments_attested,"
            "coalesce(t.typed_plan->'attachment_digests','[]'::jsonb)=attachment_hashes.hashes AS plan_attachments_exact,"
            "coalesce(t.typed_plan->'attachment_digests','[]'::jsonb)@>attachment_hashes.hashes AS plan_contains_stored_attachments,"
            "attachment_hashes.hashes@>coalesce(t.typed_plan->'attachment_digests','[]'::jsonb) AS stored_contains_plan_attachments,"
            "jsonb_typeof(coalesce(t.typed_plan->'attachment_digests','[]'::jsonb)->0) AS plan_attachment_item_type,"
            "jsonb_array_length(coalesce(t.typed_plan->'attachment_digests','[]'::jsonb)) AS plan_attachment_count,"
            "jsonb_array_length(coalesce(i.extracted_data->'attachment_digests','[]'::jsonb)) AS intake_attested_attachment_count,"
            "jsonb_array_length(attachment_hashes.hashes) AS stored_attachment_count,"
            "predecessor.identity_id::text AS receipt_identity_id,predecessor.active AS receipt_identity_active,"
            "predecessor.revoked_at IS NOT NULL AS receipt_identity_revoked,"
            "successor.identity_id::text AS current_identity_id,rotation.rotation_id IS NOT NULL AS direct_rotation_exists,"
            "(predecessor.identity_id=successor.identity_id OR (rotation.rotation_id IS NOT NULL AND NOT predecessor.active AND predecessor.revoked_at IS NOT NULL AND predecessor.revoked_at=rotation.predecessor_revoked_at AND predecessor.created_at<successor.created_at)) AS identity_route_valid "
            "FROM public.pdc_email_ai_successor_transaction_receipts t "
            "JOIN public.pdc_email_ai_successor_runtime_identities predecessor ON predecessor.identity_id=t.identity_id "
            "JOIN public.ai_email_intake i ON i.id=t.source_receipt_id "
            "CROSS JOIN LATERAL(SELECT coalesce(jsonb_agg(lower(btrim(a.source_hash)) ORDER BY a.created_at,a.id),'[]'::jsonb) hashes FROM public.ai_email_attachments a WHERE a.intake_id=i.id AND a.source_hash IS NOT NULL) attachment_hashes "
            "CROSS JOIN public.pdc_email_ai_successor_runtime_identities successor "
            "LEFT JOIN public.pdc_email_ai_successor_runtime_rotations_20260903 rotation ON rotation.predecessor_identity_id=predecessor.identity_id AND rotation.successor_identity_id=successor.identity_id AND rotation.environment=successor.environment AND rotation.identity_purpose=successor.identity_purpose "
            "CROSS JOIN supplied s "
            "WHERE t.transaction_id='" + transaction_id + "'::uuid"
            " AND successor.auth_user_id='e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8'::uuid AND successor.active AND successor.revoked_at IS NULL"
        )[0]
        report.append({
            "transaction_id": transaction_id,
            "runtime_plan_present": isinstance(runtime_plan, dict),
            "jsonb_equal": runtime_plan == canonical_plan,
            "differences": differences(runtime_plan, canonical_plan),
            "server_plan_sha256": row["server_plan_sha256"],
            "match_predicates": predicates,
        })
    definition = management_query(
        "SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex') AS helper_sha256, "
        "encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_safe_plan(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS safe_plan_sha256, "
        "position('t.typed_plan=p_plan' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0 AS exact_jsonb_required"
    )[0]
    health_functions = management_query(
        "SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS identity_arguments "
        "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
        "WHERE n.nspname='public' AND p.proname ILIKE '%email_ai%health%' ORDER BY p.proname"
    )

    print(json.dumps({
        "environment": "staging",
        "project_ref": STAGING_REF,
        "authenticated_user_id": (auth.get("user") or {}).get("id"),
        "comparisons": report,
        "installed_helper": definition,
        "health_functions": health_functions,

        "production_contacted": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
