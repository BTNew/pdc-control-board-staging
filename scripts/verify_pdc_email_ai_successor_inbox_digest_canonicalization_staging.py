#!/usr/bin/env python3
"""Read-only live proof for the STAGING v2 inbox digest contract."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
TARGET = ("20260901140000", "pdc_email_ai_successor_inbox_digest_canonicalization_20260901")
INBOX = "public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)"
TABLES = (
    "public.ai_email_intake",
    "public.ai_email_attachments",
    "public.pdc_email_ai_successor_transaction_receipts",
    "public.pdc_email_ai_successor_action_receipts",
)


def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()[0]


def main() -> None:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging connector bootstrap unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    credentials = json.loads(module.unprotect(SECRETS.read_bytes()).decode("utf-8"))
    module.validate(credentials)
    if STAGING_REF not in credentials["PDC_STAGING_DATABASE_URL"] or PRODUCTION_REF in credentials["PDC_STAGING_DATABASE_URL"]:
        raise RuntimeError("unexpected non-staging target")

    import psycopg2

    conn = psycopg2.connect(
        credentials["PDC_STAGING_DATABASE_URL"],
        sslmode="verify-full",
        sslrootcert=credentials["PDC_STAGING_SSLROOTCERT"],
        application_name="pdc-email-ai-successor-inbox-digest-live-proof",
    )
    try:
        cur = conn.cursor()
        cur.execute("select version,name from supabase_migrations.schema_migrations where version='20260901140000'")
        head = tuple(cur.fetchone() or ())
        definition = one(cur, "select pg_get_functiondef(%s::regprocedure)", (INBOX,)) or ""
        helper_present = bool(one(cur, "select to_regprocedure('public.pdc_email_ai_successor_source_evidence_digest_20260901(text,text,text,text,timestamptz,text,text,text,text,jsonb)') is not null"))
        cur.execute("select auth_user_id::text from public.pdc_user_roles where role::text in ('viewer','operator') and active and account_status='approved' order by auth_user_id limit 1")
        actor = cur.fetchone()
        if not actor:
            raise RuntimeError("no approved staging read identity")
        cur.execute("select set_config('request.jwt.claim.role','authenticated',true),set_config('request.jwt.claim.sub',%s,true)", actor)
        payload = one(cur, "select public.get_pdc_email_ai_transaction_successor_inbox_v2(null::jsonb,100)")
        items = payload.get("items", []) if isinstance(payload, dict) else []
        cur.execute("select has_function_privilege('authenticated',%s,'execute'),has_function_privilege('public',%s,'execute'),has_function_privilege('anon',%s,'execute'),has_function_privilege('service_role',%s,'execute')", (INBOX,) * 4)
        acl = tuple(cur.fetchone())
        cur.execute("select has_table_privilege('authenticated',x,'select') from unnest(%s::text[]) x", ([*TABLES],))
        table_denied = [not bool(row[0]) for row in cur.fetchall()]
        production = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"))
        protected = [
            int(one(cur, "select count(*) from public.pdc_email_ai_successor_transaction_receipts")),
            int(one(cur, "select count(*) from public.pdc_email_ai_successor_action_receipts")),
        ]
        source_count = sum(1 for item in items if isinstance(item, dict) and item.get("source_digest"))
        evidence_count = sum(1 for item in items if isinstance(item, dict) and item.get("evidence_digest"))
        keys_present = bool(items) and all("source_digest" in item and "evidence_digest" in item for item in items)
        result = {
            "ok": head == TARGET and helper_present and "pdc_email_ai_successor_source_evidence_digest_20260901" in definition and isinstance(payload, dict) and payload.get("ok") is True and keys_present and source_count == len(items) and evidence_count == len(items) and acl == (True, False, False, False) and all(table_denied) and not production and protected == [0, 0],
            "environment": "STAGING",
            "project_ref": STAGING_REF,
            "ledger_head": head,
            "inbox_rpc": INBOX,
            "items": len(items),
            "items_with_source_digest": source_count,
            "items_with_evidence_digest": evidence_count,
            "digest_keys_present": keys_present,
            "canonical_helper_present": helper_present,
            "inbox_acl_authenticated_public_anon_service_role": acl,
            "authenticated_direct_table_select_denied": table_denied,
            "successor_receipt_counts": protected,
            "production_sentinel_present": production,
            "mailbox_contacted": False,
            "outbound_email": False,
            "business_mutation": False,
        }
        print(json.dumps(result, sort_keys=True))
        if not result["ok"]:
            raise RuntimeError("live inbox digest proof failed")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
