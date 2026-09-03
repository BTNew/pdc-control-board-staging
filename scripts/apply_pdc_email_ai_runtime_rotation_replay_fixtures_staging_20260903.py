#!/usr/bin/env python3
"""Apply and verify the STAGING-only Email AI rotation/fixture repair."""
from __future__ import annotations

import hashlib
import ctypes
import json
import os
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any
from ctypes import wintypes



ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260903020000_pdc_email_ai_runtime_rotation_replay_fixtures_20260903.sql"
HARDENING_MIGRATION = ROOT / "supabase/staging_only/20260903030000_pdc_email_ai_runtime_rotation_fixture_hardening_20260903.sql"
EVIDENCE_HARDENING_MIGRATION = ROOT / "supabase/staging_only/20260903040000_pdc_email_ai_legacy_success_evidence_immutability_20260903.sql"
ATTESTATION_MIGRATION = ROOT / "supabase/staging_only/20260903050000_pdc_email_ai_legacy_attachment_attestation_20260903.sql"
FINAL_BINDING_MIGRATION = ROOT / "supabase/staging_only/20260903060000_pdc_email_ai_final_replay_binding_20260903.sql"
FINAL_GUARD_MIGRATION = ROOT / "supabase/staging_only/20260903070000_pdc_email_ai_final_replay_input_guard_20260903.sql"
EVIDENCE = ROOT / "review-evidence/t_1f52181d/final-replay-binding-proof.json"
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
CREDENTIAL_TARGET = "Supabase CLI:supabase"
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903020000"
HARDENING_APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903030000"
EVIDENCE_HARDENING_APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903040000"
ATTESTATION_APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903050000"
FINAL_BINDING_APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903060000"
FINAL_GUARD_APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260903070000"
TARGET = ("20260903020000", "pdc_email_ai_runtime_rotation_replay_fixtures_20260903")
HARDENING_TARGET = ("20260903030000", "pdc_email_ai_runtime_rotation_fixture_hardening_20260903")
EVIDENCE_HARDENING_TARGET = ("20260903040000", "pdc_email_ai_legacy_success_evidence_immutability_20260903")
ATTESTATION_TARGET = ("20260903050000", "pdc_email_ai_legacy_attachment_attestation_20260903")
FINAL_BINDING_TARGET = ("20260903060000", "pdc_email_ai_final_replay_binding_20260903")
FINAL_GUARD_TARGET = ("20260903070000", "pdc_email_ai_final_replay_input_guard_20260903")
RUNTIME_ENV = Path.home() / "AppData/Local/hermes/profiles/pdc-email-ai-lead/.env"
LEDGER_SQL = """SELECT EXISTS(
  SELECT 1 FROM supabase_migrations.schema_migrations
  WHERE version='20260903020000'
    AND name='pdc_email_ai_runtime_rotation_replay_fixtures_20260903'
) AS applied;\n"""

VERIFY_SQL = r"""
BEGIN;
CREATE TEMP TABLE pdc_rotation_verify(
  typed_plan jsonb,
  original_transaction_id uuid,
  original_action_receipt_ids jsonb,
  counts_before jsonb,
  replay_response jsonb,
  changed_response jsonb,
  cross_source_response jsonb,
  altered_evidence_response jsonb,
  malformed_source_receipt_response jsonb,
  hostile_response jsonb,
  fixture_response jsonb,
  counts_after jsonb
) ON COMMIT DROP;

INSERT INTO pdc_rotation_verify(typed_plan,original_transaction_id,original_action_receipt_ids,counts_before)
SELECT t.typed_plan,t.transaction_id,
  (SELECT coalesce(jsonb_agg(a.action_receipt_id ORDER BY a.created_at,a.action_receipt_id),'[]'::jsonb)
   FROM public.pdc_email_ai_successor_action_receipts a WHERE a.transaction_id=t.transaction_id),
  jsonb_build_object(
    'transactions',(SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts),
    'actions',(SELECT count(*) FROM public.pdc_email_ai_successor_action_receipts),
    'audit_events',(SELECT count(*) FROM public.audit_events),
    'vehicles',(SELECT count(*) FROM public.vehicles),
    'vehicle_versions',(SELECT coalesce(sum(version),0) FROM public.vehicles),
    'intakes',(SELECT count(*) FROM public.ai_email_intake),
    'attachments',(SELECT count(*) FROM public.ai_email_attachments),
    'selected_transaction_sha256',encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex'),
    'selected_source_sha256',encode(extensions.digest(convert_to(to_jsonb(i)::text,'UTF8'),'sha256'),'hex'),
    'selected_actions_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(a)::text,E'\n' ORDER BY to_jsonb(a)::text) FROM public.pdc_email_ai_successor_action_receipts a WHERE a.transaction_id=t.transaction_id),''),'UTF8'),'sha256'),'hex')
  )
FROM public.pdc_email_ai_successor_transaction_receipts t
JOIN public.pdc_email_ai_successor_runtime_identities predecessor ON predecessor.identity_id=t.identity_id
JOIN public.ai_email_intake i ON i.id=t.source_receipt_id
WHERE predecessor.identity_purpose='pdc_email_ai_transaction_successor'
  AND predecessor.environment='staging' AND NOT predecessor.active AND predecessor.revoked_at IS NOT NULL
  AND t.aggregate_disposition::text='SUCCESS' AND t.readback_parity
  AND i.duplicate_of IS NULL AND lower(coalesce(i.source_hash,''))=t.source_digest
  AND coalesce(i.extracted_data->>'pdc_email_ai_evidence_digest','')=t.evidence_digest
  AND coalesce(nullif(btrim(i.internet_message_id),''),btrim(i.graph_message_id))=btrim(t.typed_plan->>'source_message_id')
  AND coalesce(btrim(i.graph_thread_id),'')=btrim(t.typed_plan->>'source_thread_id')
ORDER BY t.created_at DESC LIMIT 1;

SELECT set_config('request.jwt.claims',jsonb_build_object(
  'sub',i.auth_user_id,'email',i.normalized_email,'role','authenticated','aud','authenticated'
)::text,true)
FROM public.pdc_email_ai_successor_runtime_identities i
WHERE i.auth_user_id='e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8'::uuid
  AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor'
  AND i.active AND i.revoked_at IS NULL;

UPDATE pdc_rotation_verify SET
  replay_response=public.apply_pdc_email_ai_typed_action_surface_20260901_strict(typed_plan),
  changed_response=public.apply_pdc_email_ai_typed_action_surface_20260901_strict(typed_plan||jsonb_build_object('created_at','2099-01-01T00:00:00+00:00')),
  cross_source_response=public.apply_pdc_email_ai_typed_action_surface_20260901_strict(typed_plan||jsonb_build_object('source_message_id','cross-source-reuse@invalid')),
  altered_evidence_response=public.apply_pdc_email_ai_typed_action_surface_20260901_strict(typed_plan||jsonb_build_object('evidence_digest',repeat('0',64))),
  malformed_source_receipt_response=public.apply_pdc_email_ai_typed_action_surface_20260901_strict(typed_plan||jsonb_build_object('source_receipt_id','not-a-uuid')),
  hostile_response=public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb_build_object('environment','production','instructions',jsonb_build_array(jsonb_build_object('action_type','sql','payload','DROP TABLE vehicles')))),
  fixture_response=public.get_pdc_email_ai_v2_acceptance_fixtures_20260903();

UPDATE pdc_rotation_verify v SET counts_after=jsonb_build_object(
  'transactions',(SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts),
  'actions',(SELECT count(*) FROM public.pdc_email_ai_successor_action_receipts),
  'audit_events',(SELECT count(*) FROM public.audit_events),
  'vehicles',(SELECT count(*) FROM public.vehicles),
  'vehicle_versions',(SELECT coalesce(sum(version),0) FROM public.vehicles),
  'intakes',(SELECT count(*) FROM public.ai_email_intake),
  'attachments',(SELECT count(*) FROM public.ai_email_attachments),
  'selected_transaction_sha256',encode(extensions.digest(convert_to((SELECT to_jsonb(t)::text FROM public.pdc_email_ai_successor_transaction_receipts t WHERE t.transaction_id=v.original_transaction_id),'UTF8'),'sha256'),'hex'),
  'selected_source_sha256',encode(extensions.digest(convert_to((SELECT to_jsonb(i)::text FROM public.ai_email_intake i JOIN public.pdc_email_ai_successor_transaction_receipts t ON t.source_receipt_id=i.id WHERE t.transaction_id=v.original_transaction_id),'UTF8'),'sha256'),'hex'),
  'selected_actions_sha256',encode(extensions.digest(convert_to(coalesce((SELECT string_agg(to_jsonb(a)::text,E'\n' ORDER BY to_jsonb(a)::text) FROM public.pdc_email_ai_successor_action_receipts a WHERE a.transaction_id=v.original_transaction_id),''),'UTF8'),'sha256'),'hex')
);

SELECT jsonb_build_object(
  'ok',
    (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903020000' AND name='pdc_email_ai_runtime_rotation_replay_fixtures_20260903')=1
    AND (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903030000' AND name='pdc_email_ai_runtime_rotation_fixture_hardening_20260903')=1
    AND (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903040000' AND name='pdc_email_ai_legacy_success_evidence_immutability_20260903')=1
    AND (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903050000' AND name='pdc_email_ai_legacy_attachment_attestation_20260903')=1
    AND (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903060000' AND name='pdc_email_ai_final_replay_binding_20260903')=1
    AND (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903070000' AND name='pdc_email_ai_final_replay_input_guard_20260903')=1
    AND position('t.source_receipt_id=(p_plan->>''source_receipt_id'')::uuid' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0
    AND position('t.source_digest=lower(p_plan->>''source_digest'')' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0
    AND position('t.evidence_digest=lower(p_plan->>''evidence_digest'')' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0
    AND position('coalesce(p_plan->>''source_receipt_id'','''') !~ ''^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$''' IN pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure))>0
    AND replay_response->>'ok'='true'
    AND replay_response->>'runtime_rotation_replay'='true'
    AND (replay_response->>'transaction_id')::uuid=original_transaction_id
    AND replay_response->'action_receipt_ids'=original_action_receipt_ids
    AND changed_response->>'ok'='false'
    AND changed_response->>'code' IN('typed_v2_plan_invalid','source_reuse_conflict')
    AND cross_source_response->>'ok'='false' AND cross_source_response->>'code' IN('typed_v2_plan_invalid','source_reuse_conflict')
    AND altered_evidence_response->>'ok'='false' AND altered_evidence_response->>'code' IN('typed_v2_plan_invalid','source_reuse_conflict')
    AND malformed_source_receipt_response->>'ok'='false' AND malformed_source_receipt_response->>'code'='typed_v2_plan_invalid'
    AND hostile_response->>'ok'='false' AND hostile_response->>'code'='typed_v2_plan_invalid'
    AND fixture_response->>'ok'='true' AND (fixture_response->>'fixture_count')::integer=14
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(fixture_response->'fixtures') f WHERE coalesce((f->>'consumed')::boolean,false))
    AND NOT has_table_privilege('authenticated','public.pdc_email_ai_successor_transaction_receipts','SELECT')
    AND NOT has_table_privilege('authenticated','public.pdc_email_ai_successor_transaction_receipts','INSERT,UPDATE,DELETE')
    AND NOT has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_20260903','INSERT,UPDATE,DELETE')
    AND NOT has_table_privilege('authenticated','public.pdc_email_ai_successor_runtime_rotations_20260903','INSERT,UPDATE,DELETE')
    AND counts_before=counts_after,
  'migration_ledger',(SELECT to_jsonb(m) FROM supabase_migrations.schema_migrations m WHERE version='20260903020000'),
  'hardening_migration_ledger',(SELECT to_jsonb(m) FROM supabase_migrations.schema_migrations m WHERE version='20260903030000'),
  'evidence_hardening_migration_ledger',(SELECT to_jsonb(m) FROM supabase_migrations.schema_migrations m WHERE version='20260903040000'),
  'attestation_migration_ledger',(SELECT to_jsonb(m) FROM supabase_migrations.schema_migrations m WHERE version='20260903050000'),
  'final_binding_migration_ledger',(SELECT to_jsonb(m) FROM supabase_migrations.schema_migrations m WHERE version='20260903060000'),
  'final_guard_migration_ledger',(SELECT to_jsonb(m) FROM supabase_migrations.schema_migrations m WHERE version='20260903070000'),
  'final_function_definition',pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),
  'final_function_sha256',encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_exact_success_replay_20260903(jsonb,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
  'predecessor_successor_exact_replay',jsonb_build_object(
    'ok',replay_response->>'ok'='true',
    'code',replay_response->>'code',
    'exact_successful_replay',replay_response->>'exact_successful_replay'='true',
    'runtime_rotation_replay',replay_response->>'runtime_rotation_replay'='true',
    'transaction_id',replay_response->>'transaction_id',
    'action_receipt_ids',replay_response->'action_receipt_ids',
    'original_identity_id',replay_response->>'original_identity_id',
    'current_identity_id',replay_response->>'current_identity_id',
    'production_writes',false,'mailbox_contacted',false,'outbound_email',false
  ),
  'stable_transaction_id',(replay_response->>'transaction_id')::uuid=original_transaction_id,
  'stable_action_receipt_ids',replay_response->'action_receipt_ids'=original_action_receipt_ids,
  'zero_mutations',counts_before=counts_after,
  'counts_before',counts_before,'counts_after',counts_after,
  'changed_plan_rejected',jsonb_build_object('ok',changed_response->>'ok'='false','code',changed_response->>'code'),
  'cross_source_rejected',jsonb_build_object('ok',cross_source_response->>'ok'='false','code',cross_source_response->>'code'),
  'altered_evidence_rejected',jsonb_build_object('ok',altered_evidence_response->>'ok'='false','code',altered_evidence_response->>'code'),
  'malformed_source_receipt_rejected',jsonb_build_object('ok',malformed_source_receipt_response->>'ok'='false','code',malformed_source_receipt_response->>'code'),
  'hostile_plan_rejected',jsonb_build_object('ok',hostile_response->>'ok'='false','code',hostile_response->>'code'),
  'fixture_count',(fixture_response->>'fixture_count')::integer,
  'fresh_fixture_count',(SELECT count(*) FROM jsonb_array_elements(fixture_response->'fixtures') f WHERE NOT coalesce((f->>'consumed')::boolean,false)),
  'fixture_scenarios',(SELECT jsonb_agg(f->>'scenario_key' ORDER BY (f->>'scenario_no')::integer) FROM jsonb_array_elements(fixture_response->'fixtures') f),
  'protected_table_access_denied',NOT has_table_privilege('authenticated','public.pdc_email_ai_successor_transaction_receipts','SELECT'),
  'generic_dml_denied',NOT has_table_privilege('authenticated','public.pdc_email_ai_successor_transaction_receipts','INSERT,UPDATE,DELETE')
    AND NOT has_table_privilege('authenticated','public.pdc_email_ai_v2_acceptance_fixtures_20260903','INSERT,UPDATE,DELETE')
    AND NOT has_table_privilege('authenticated','public.pdc_email_ai_successor_runtime_rotations_20260903','INSERT,UPDATE,DELETE'),
  'production_contacted',false,'production_writes',false,'mailbox_contacted',false,'outbound_email_sent',false
) AS proof
FROM pdc_rotation_verify;
ROLLBACK;
"""


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
    if not advapi.CredReadW(CREDENTIAL_TARGET, 1, 0, ctypes.byref(pointer)):
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


def management_request(sql: str) -> Any:
    path = f"/v1/projects/{STAGING_REF}/database/query"
    if PRODUCTION_REF in path or STAGING_REF not in path:
        raise RuntimeError("PDC_NON_STAGING_MANAGEMENT_TARGET_REFUSED")
    request = urllib.request.Request(
        "https://api.supabase.com" + path,
        data=json.dumps({"query": sql}, separators=(",", ":")).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + management_token(),
            "Content-Type": "application/json",
            "User-Agent": "SupabaseCLI/2 pdc-email-ai-final-replay-binding",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            raw = response.read()
            return json.loads(raw) if raw else []
    except urllib.error.HTTPError as exc:
        message = exc.read().decode(errors="replace")
        raise RuntimeError(f"SUPABASE_STAGING_MANAGEMENT_QUERY_FAILED:{exc.code}:{message[:500]}") from None


def run_query(path: Path) -> dict:
    result = management_request(path.read_text(encoding="utf-8"))
    if not isinstance(result, list):
        raise RuntimeError("SUPABASE_STAGING_MANAGEMENT_QUERY_RESULT_INVALID")
    return {"rows": result}


def linked_staging() -> None:
    if STAGING_REF == PRODUCTION_REF:
        raise RuntimeError("PDC_STAGING_AND_PRODUCTION_REFS_COLLIDE")
    management_request("SELECT true AS staging_management_ready")


def runtime_rest_readback() -> dict:
    values: dict[str, str] = {}
    for raw in RUNTIME_ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    url = values.get("PDC_STAGING_SUPABASE_URL")
    anon = values.get("PDC_STAGING_SUPABASE_ANON_KEY")
    email = values.get("PDC_EMAIL_AI_RUNTIME_EMAIL")
    password = values.get("PDC_EMAIL_AI_RUNTIME_PASSWORD")
    if not all((url, anon, email, password)):
        raise RuntimeError("PDC_RUNTIME_PROFILE_CREDENTIALS_INCOMPLETE")
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != f"{STAGING_REF}.supabase.co" or parsed.port is not None:
        raise RuntimeError("PDC_RUNTIME_PROFILE_NON_STAGING_URL_REFUSED")

    auth_request = urllib.request.Request(
        f"{url.rstrip('/')}/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email, "password": password}).encode(),
        headers={"apikey": anon, "Authorization": f"Bearer {anon}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(auth_request, timeout=30) as response:
        auth = json.load(response)
    token = auth.get("access_token")
    user_id = (auth.get("user") or {}).get("id")
    if not token or user_id != "e9ed1fa6-f569-41b5-8d83-08f76bf4d8c8":
        raise RuntimeError("PDC_RUNTIME_PROFILE_IDENTITY_MISMATCH")
    headers = {"apikey": anon, "Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    fixture_request = urllib.request.Request(
        f"{url.rstrip('/')}/rest/v1/rpc/get_pdc_email_ai_v2_acceptance_fixtures_20260903",
        data=b"{}", headers=headers, method="POST",
    )
    with urllib.request.urlopen(fixture_request, timeout=30) as response:
        fixtures = json.load(response)
    rows = fixtures.get("fixtures") if isinstance(fixtures, dict) else None
    if fixtures.get("ok") is not True or fixtures.get("fixture_count") != 14 or not isinstance(rows, list):
        raise RuntimeError("PDC_RUNTIME_FIXTURE_RPC_READBACK_FAILED")
    if any(row.get("consumed") for row in rows):
        raise RuntimeError("PDC_RUNTIME_FIXTURES_NOT_FRESH")

    protected_statuses: dict[str, int] = {}
    for table in (
        "pdc_email_ai_successor_transaction_receipts",
        "pdc_email_ai_v2_acceptance_fixtures_20260903",
    ):
        request = urllib.request.Request(
            f"{url.rstrip('/')}/rest/v1/{table}?select=*&limit=1", headers=headers, method="GET"
        )
        try:
            urllib.request.urlopen(request, timeout=30)
        except urllib.error.HTTPError as exc:
            protected_statuses[table] = exc.code
        else:
            raise RuntimeError(f"PDC_RUNTIME_PROTECTED_TABLE_EXPOSED:{table}")
    if any(status not in (401, 403, 404) for status in protected_statuses.values()):
        raise RuntimeError("PDC_RUNTIME_PROTECTED_TABLE_DENIAL_UNEXPECTED")
    return {
        "authenticated_profile": "pdc-email-ai-lead",
        "authenticated_identity_id": user_id,
        "fixture_rpc_ok": True,
        "fixture_count": 14,
        "fresh_fixture_count": 14,
        "protected_table_http_statuses": protected_statuses,
        "production_contacted": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }


def main() -> None:
    linked_staging()
    migration_sha256 = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    hardening_sha256 = hashlib.sha256(HARDENING_MIGRATION.read_bytes()).hexdigest()
    evidence_hardening_sha256 = hashlib.sha256(EVIDENCE_HARDENING_MIGRATION.read_bytes()).hexdigest()
    attestation_sha256 = hashlib.sha256(ATTESTATION_MIGRATION.read_bytes()).hexdigest()
    final_binding_sha256 = hashlib.sha256(FINAL_BINDING_MIGRATION.read_bytes()).hexdigest()
    final_guard_sha256 = hashlib.sha256(FINAL_GUARD_MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260903020000 pdc email ai runtime rotation fixtures source {migration_sha256}"
    hardening_expected = f"apply migration 20260903030000 pdc email ai runtime rotation hardening source {hardening_sha256}"
    evidence_hardening_expected = f"apply migration 20260903040000 pdc email ai success evidence immutability source {evidence_hardening_sha256}"
    attestation_expected = f"apply migration 20260903050000 pdc email ai legacy attachment attestation source {attestation_sha256}"
    final_binding_expected = f"apply migration 20260903060000 pdc email ai final replay binding source {final_binding_sha256}"
    final_guard_expected = f"apply migration 20260903070000 pdc email ai final replay input guard source {final_guard_sha256}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_RUNTIME_ROTATION_APPROVAL_MISSING_OR_HASH_MISMATCH")
    if os.environ.get(HARDENING_APPROVAL_ENV) != hardening_expected:
        raise RuntimeError("PDC_RUNTIME_ROTATION_HARDENING_APPROVAL_MISSING_OR_HASH_MISMATCH")
    if os.environ.get(EVIDENCE_HARDENING_APPROVAL_ENV) != evidence_hardening_expected:
        raise RuntimeError("PDC_SUCCESS_EVIDENCE_HARDENING_APPROVAL_MISSING_OR_HASH_MISMATCH")
    if os.environ.get(ATTESTATION_APPROVAL_ENV) != attestation_expected:
        raise RuntimeError("PDC_ATTACHMENT_ATTESTATION_APPROVAL_MISSING_OR_HASH_MISMATCH")
    if os.environ.get(FINAL_BINDING_APPROVAL_ENV) != final_binding_expected:
        raise RuntimeError("PDC_FINAL_REPLAY_BINDING_APPROVAL_MISSING_OR_HASH_MISMATCH")
    if os.environ.get(FINAL_GUARD_APPROVAL_ENV) != final_guard_expected:
        raise RuntimeError("PDC_FINAL_REPLAY_INPUT_GUARD_APPROVAL_MISSING_OR_HASH_MISMATCH")

    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False, dir=EVIDENCE.parent) as handle:
        handle.write(LEDGER_SQL)
        ledger_path = Path(handle.name)
    try:
        ledger_result = run_query(ledger_path)
    finally:
        ledger_path.unlink(missing_ok=True)
    ledger_rows = ledger_result.get("rows") or []
    already_applied = bool(ledger_rows and ledger_rows[0].get("applied"))
    apply_result = {"already_applied": True} if already_applied else run_query(MIGRATION)

    hardening_ledger_sql = LEDGER_SQL.replace("20260903020000", "20260903030000").replace(
        "pdc_email_ai_runtime_rotation_replay_fixtures_20260903",
        "pdc_email_ai_runtime_rotation_fixture_hardening_20260903",
    )
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False, dir=EVIDENCE.parent) as handle:
        handle.write(hardening_ledger_sql)
        hardening_ledger_path = Path(handle.name)
    try:
        hardening_ledger_result = run_query(hardening_ledger_path)
    finally:
        hardening_ledger_path.unlink(missing_ok=True)
    hardening_rows = hardening_ledger_result.get("rows") or []
    hardening_already_applied = bool(hardening_rows and hardening_rows[0].get("applied"))
    hardening_apply_result = {"already_applied": True} if hardening_already_applied else run_query(HARDENING_MIGRATION)

    evidence_ledger_sql = LEDGER_SQL.replace("20260903020000", "20260903040000").replace(
        "pdc_email_ai_runtime_rotation_replay_fixtures_20260903",
        "pdc_email_ai_legacy_success_evidence_immutability_20260903",
    )
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False, dir=EVIDENCE.parent) as handle:
        handle.write(evidence_ledger_sql)
        evidence_ledger_path = Path(handle.name)
    try:
        evidence_ledger_result = run_query(evidence_ledger_path)
    finally:
        evidence_ledger_path.unlink(missing_ok=True)
    evidence_rows = evidence_ledger_result.get("rows") or []
    evidence_hardening_already_applied = bool(evidence_rows and evidence_rows[0].get("applied"))
    evidence_hardening_apply_result = (
        {"already_applied": True}
        if evidence_hardening_already_applied
        else run_query(EVIDENCE_HARDENING_MIGRATION)
    )

    attestation_ledger_sql = LEDGER_SQL.replace("20260903020000", "20260903050000").replace(
        "pdc_email_ai_runtime_rotation_replay_fixtures_20260903",
        "pdc_email_ai_legacy_attachment_attestation_20260903",
    )
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False, dir=EVIDENCE.parent) as handle:
        handle.write(attestation_ledger_sql)
        attestation_ledger_path = Path(handle.name)
    try:
        attestation_ledger_result = run_query(attestation_ledger_path)
    finally:
        attestation_ledger_path.unlink(missing_ok=True)
    attestation_rows = attestation_ledger_result.get("rows") or []
    attestation_already_applied = bool(attestation_rows and attestation_rows[0].get("applied"))
    attestation_apply_result = {"already_applied": True} if attestation_already_applied else run_query(ATTESTATION_MIGRATION)

    final_ledger_sql = LEDGER_SQL.replace("20260903020000", "20260903060000").replace(
        "pdc_email_ai_runtime_rotation_replay_fixtures_20260903",
        "pdc_email_ai_final_replay_binding_20260903",
    )
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False, dir=EVIDENCE.parent) as handle:
        handle.write(final_ledger_sql)
        final_ledger_path = Path(handle.name)
    try:
        final_ledger_result = run_query(final_ledger_path)
    finally:
        final_ledger_path.unlink(missing_ok=True)
    final_rows = final_ledger_result.get("rows") or []
    final_binding_already_applied = bool(final_rows and final_rows[0].get("applied"))
    final_binding_apply_result = {"already_applied": True} if final_binding_already_applied else run_query(FINAL_BINDING_MIGRATION)

    final_guard_ledger_sql = LEDGER_SQL.replace("20260903020000", "20260903070000").replace(
        "pdc_email_ai_runtime_rotation_replay_fixtures_20260903",
        "pdc_email_ai_final_replay_input_guard_20260903",
    )
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False, dir=EVIDENCE.parent) as handle:
        handle.write(final_guard_ledger_sql)
        final_guard_ledger_path = Path(handle.name)
    try:
        final_guard_ledger_result = run_query(final_guard_ledger_path)
    finally:
        final_guard_ledger_path.unlink(missing_ok=True)
    final_guard_rows = final_guard_ledger_result.get("rows") or []
    final_guard_already_applied = bool(final_guard_rows and final_guard_rows[0].get("applied"))
    final_guard_apply_result = {"already_applied": True} if final_guard_already_applied else run_query(FINAL_GUARD_MIGRATION)

    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False, dir=ROOT / "review-evidence") as handle:
        handle.write(VERIFY_SQL)
        verify_path = Path(handle.name)
    try:
        verify_result = run_query(verify_path)
    finally:
        verify_path.unlink(missing_ok=True)

    rows = verify_result.get("rows") or []
    proof = rows[0].get("proof") if rows else None
    if not isinstance(proof, dict) or proof.get("ok") is not True:
        raise RuntimeError(f"PDC_RUNTIME_ROTATION_READBACK_FAILED:{json.dumps(proof, sort_keys=True)}")
    runtime_rpc = runtime_rest_readback()
    proof.update({
        "environment": "staging",
        "project_ref": STAGING_REF,
        "migration_identity": TARGET,
        "migration_sha256": migration_sha256,
        "hardening_migration_identity": HARDENING_TARGET,
        "hardening_migration_sha256": hardening_sha256,
        "evidence_hardening_migration_identity": EVIDENCE_HARDENING_TARGET,
        "evidence_hardening_migration_sha256": evidence_hardening_sha256,
        "attestation_migration_identity": ATTESTATION_TARGET,
        "attestation_migration_sha256": attestation_sha256,
        "final_binding_migration_identity": FINAL_BINDING_TARGET,
        "final_binding_migration_sha256": final_binding_sha256,
        "final_guard_migration_identity": FINAL_GUARD_TARGET,
        "final_guard_migration_sha256": final_guard_sha256,
        "management_apply_returned": isinstance(apply_result, dict),
        "migration_already_applied": already_applied,
        "hardening_management_apply_returned": isinstance(hardening_apply_result, dict),
        "hardening_migration_already_applied": hardening_already_applied,
        "evidence_hardening_management_apply_returned": isinstance(evidence_hardening_apply_result, dict),
        "evidence_hardening_migration_already_applied": evidence_hardening_already_applied,
        "attestation_management_apply_returned": isinstance(attestation_apply_result, dict),
        "attestation_migration_already_applied": attestation_already_applied,
        "final_binding_management_apply_returned": isinstance(final_binding_apply_result, dict),
        "final_binding_migration_already_applied": final_binding_already_applied,
        "final_guard_management_apply_returned": isinstance(final_guard_apply_result, dict),
        "final_guard_migration_already_applied": final_guard_already_applied,
        "runtime_rest_readback": runtime_rpc,
        "production_contacted": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    })
    EVIDENCE.write_text(json.dumps(proof, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "ok": True,
        "evidence": str(EVIDENCE),
        "migration_sha256": migration_sha256,
        "fixture_count": proof["fixture_count"],
        "stable_transaction_id": proof["stable_transaction_id"],
        "stable_action_receipt_ids": proof["stable_action_receipt_ids"],
        "zero_mutations": proof["zero_mutations"],
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
