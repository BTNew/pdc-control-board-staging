#!/usr/bin/env python3
"""Apply and prove the v2 inbox digest projection in STAGING only."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260901130000_pdc_email_ai_successor_inbox_digest_projection_20260901.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREDECESSOR = ("20260901120000", "pdc_email_ai_typed_action_field_executor_identity_20260901")
TARGET = ("20260901130000", "pdc_email_ai_successor_inbox_digest_projection_20260901")
APPROVAL_ENV = "PDC_APPROVE_STAGING_MIGRATION_20260901130000"
INBOX_SIGNATURE = "public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)"


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()


def bundle() -> dict:
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError("PDC_INBOX_DIGEST_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("PDC_INBOX_DIGEST_STAGING_CONNECTOR_INVALID")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(data)
    url = data.get("PDC_STAGING_DATABASE_URL", "")
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError("PDC_INBOX_DIGEST_NON_STAGING_TARGET")
    return data


def acl(cur) -> tuple[bool, bool, bool, bool]:
    return tuple(one(cur, "select has_function_privilege('authenticated',%s,'execute'), has_function_privilege('service_role',%s,'execute'), has_function_privilege('public',%s,'execute'), has_function_privilege('anon',%s,'execute')", (INBOX_SIGNATURE,) * 4))


def direct_table_select_denied(cur) -> bool:
    tables = (
        "public.ai_email_intake",
        "public.ai_email_attachments",
        "public.pdc_email_ai_successor_transaction_receipts",
        "public.pdc_email_ai_successor_action_receipts",
    )
    return all(not bool(one(cur, "select has_table_privilege('authenticated',%s,'select')", (table,))[0]) for table in tables)


def projection_readback(cur) -> dict:
    """Invoke the read RPC with claims only; do not print source values."""
    identity = one(cur, "select auth_user_id from public.pdc_user_roles where role::text in ('viewer','operator') and active and account_status='approved' order by auth_user_id limit 1")
    if not identity:
        return {"ok": False, "items": 0, "items_with_source_digest": 0, "items_with_evidence_digest": 0, "field_keys_present": False}
    cur.execute("select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub',%s,true)", (str(identity[0]),))
    payload = one(cur, "select public.get_pdc_email_ai_transaction_successor_inbox_v2(null::jsonb,100)")[0]
    items = payload.get("items", []) if isinstance(payload, dict) else []
    forbidden = ("raw_body", "parsed_text", "storage_path", "access_token", "refresh_token", "password", "secret")
    source_count = sum(1 for item in items if item.get("source_digest"))
    evidence_count = sum(1 for item in items if item.get("evidence_digest"))
    field_keys_present = bool(items) and all("source_digest" in item and "evidence_digest" in item for item in items)
    return {
        "ok": isinstance(payload, dict) and payload.get("ok") is True and bool(items) and field_keys_present and not any(token in json.dumps(payload).lower() for token in forbidden),
        "items": len(items),
        "items_with_source_digest": source_count,
        "items_with_evidence_digest": evidence_count,
        "field_keys_present": field_keys_present,
    }


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f"apply migration 20260901130000 pdc email ai successor inbox digest projection source {digest}"
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError("PDC_INBOX_DIGEST_STAGING_APPROVAL_MISSING_OR_HASH_MISMATCH")
    credentials = bundle()
    import psycopg2

    conn = psycopg2.connect(
        credentials["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-successor-inbox-digest-staging-controller",
    )
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        already_applied = head == TARGET
        if head not in {PREDECESSOR, TARGET}:
            raise RuntimeError(f"PDC_INBOX_DIGEST_UNEXPECTED_LIVE_HEAD:{head}")
        if bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]):
            raise RuntimeError("PDC_INBOX_DIGEST_PRODUCTION_SENTINEL_PRESENT")
        before_counts = tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts),(select revision from public.pdc_email_ai_successor_ui_revision where singleton)"))
        if not already_applied:
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
        # Keep the migration and its catalog/readback proof in one transaction;
        # commit only after every guard below has passed.
        ledger = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901130000'") or ())
        inbox_source = one(cur, "select pg_get_functiondef(%s::regprocedure)", (INBOX_SIGNATURE,))[0] or ""
        source_digest_present = "'source_digest'" in inbox_source and "p.source_hash" in inbox_source and "^[a-f0-9]{64}$" in inbox_source
        evidence_digest_present = "'evidence_digest'" in inbox_source and "p.extracted_data->>'pdc_email_ai_evidence_digest'" in inbox_source and "^[a-f0-9]{64}$" in inbox_source
        source_receipt_bound = "'source_receipt_id',p.id" in inbox_source and source_digest_present and evidence_digest_present
        projection_forbidden = any(token in inbox_source.lower() for token in ("raw_body", "parsed_text", "storage_path", "access_token", "refresh_token", "password"))
        after_counts = tuple(one(cur, "select (select count(*) from public.pdc_email_ai_successor_transaction_receipts),(select count(*) from public.pdc_email_ai_successor_action_receipts),(select revision from public.pdc_email_ai_successor_ui_revision where singleton)"))
        production = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        projection = projection_readback(cur)
        proof = {
            "ok": ledger == TARGET and source_receipt_bound and not projection_forbidden and projection["ok"] and acl(cur) == (True, False, False, False) and direct_table_select_denied(cur) and before_counts == after_counts and not production,
            "environment": "staging",
            "project_ref": STAGING_REF,
            "migration_sha256": digest,
            "ledger_head": ledger,
            "source_digest_present": source_digest_present,
            "evidence_digest_present": evidence_digest_present,
            "source_receipt_bound": source_receipt_bound,
            "projection_forbidden_fields_absent": not projection_forbidden,
            "projection_readback": projection["ok"],
            "projection_items": projection["items"],
            "projection_items_with_source_digest": projection["items_with_source_digest"],
            "projection_items_with_evidence_digest": projection["items_with_evidence_digest"],
            "projection_field_keys_present": projection["field_keys_present"],
            "inbox_rpc_acl": acl(cur),
            "direct_table_select_denied": direct_table_select_denied(cur),
            "protected_counts_before": before_counts,
            "protected_counts_after": after_counts,
            "production_sentinel_present": production,
            "mailbox_contacted": False,
            "outbound_email": False,
            "business_mutation": False,
        }
        if not proof["ok"]:
            raise RuntimeError("PDC_INBOX_DIGEST_POST_APPLY_READBACK_FAILED")
        conn.commit()
        print(json.dumps(proof, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "environment": "staging", "error": str(exc), "production_contacted": False, "mailbox_contacted": False, "outbound_email": False}, sort_keys=True))
        raise SystemExit(1)
