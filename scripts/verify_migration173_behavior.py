#!/usr/bin/env python3
"""Rollback-only proof for Migration 173 enrolled-Importer attestation."""
from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from pathlib import Path

import psycopg2
from psycopg2.extras import Json

from scripts.pdc_staging_runtime import assert_staging_target

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "173_enrolled_importer_provider_attestation.sql"
SENDER = "craig.watson@broometoyota.com.au"
AUTH = {
    "dkim_aligned": True,
    "dmarc_aligned": True,
    "gmail_authentication_results": True,
    "sender_domain": "broometoyota.com.au",
    "spf_aligned": True,
}


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def claims(cur, role: str, actor_id: str | None = None, email: str | None = None) -> None:
    value = {"role": role}
    if actor_id:
        value["sub"] = actor_id
    if email:
        value["email"] = email
    cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps(value),))


def main() -> int:
    dsn = os.getenv("PDC_STAGING_DIRECT_DATABASE_URL") or os.getenv("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=dsn)
    sql = MIGRATION.read_text(encoding="utf-8")
    sql = re.sub(r"^begin;\s*", "", sql, count=1)
    sql = re.sub(r"commit;\s*$", "", sql, count=1)
    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
            cur.execute("""
              select r.auth_user_id::text,lower(r.email)
              from public.pdc_user_roles r
              join public.pdc_monitor_stage_activation_writers w on w.user_id=r.auth_user_id
              where r.role='importer' and r.active and r.account_status='approved'
                and w.active and w.revoked_at is null limit 1
            """)
            importer_id, importer_email = cur.fetchone()
            cur.execute("select auth_user_id::text,lower(email) from public.pdc_user_roles where role='administrator' and active and account_status='approved' limit 1")
            other_id, other_email = cur.fetchone()
            cur.execute("select id::text,mailbox_address from public.monitored_mailboxes where mailbox_key='pdc_pmb_email' and active")
            mailbox_id, mailbox = cur.fetchone()
            cur.execute("select exists(select 1 from public.pdc_monitor_exact_sender_enrollments where active and sender_sha256=%s)", (digest(SENDER),))
            assert cur.fetchone()[0]

            def evidence(label: str):
                intake, attachment = str(uuid.uuid4()), str(uuid.uuid4())
                parent, document = digest("173-parent-" + label), digest("173-document-" + label)
                message = f"<{label}-{uuid.uuid4()}@broometoyota.com.au>"
                cur.execute("""insert into public.ai_email_intake(id,status,subject,sender_email,received_at,graph_message_id,internet_message_id,attachment_names,raw_body,extracted_data,warnings,processing_result,source_hash,monitored_mailbox_id,recipient_mailbox) values(%s,'received','Migration173 proof',%s,clock_timestamp(),%s,%s,array['jobcard.pdf'],'','{}','{}','{}',%s,%s,%s)""", (intake,SENDER,message,message,parent,mailbox_id,mailbox))
                cur.execute("""insert into public.ai_email_attachments(id,intake_id,graph_attachment_id,file_name,content_type,size_bytes,storage_path,text_extraction_status,extracted_text,source_hash) values(%s,%s,%s,'jobcard.pdf','application/pdf',1024,%s,'extracted','proof',%s)""", (attachment,intake,'a-'+label,'proof/'+attachment,document))
                return intake, attachment, parent, document, message

            bound = evidence("importer")
            claims(cur, "authenticated", importer_id, importer_email)
            cur.execute("select public.attest_pdc_provider_email_observation(%s,%s,%s,%s,%s,'mx.google.com',%s)", (*bound, Json(AUTH)))
            result = cur.fetchone()[0]
            assert result.get("ok") is True and result.get("code") == "provider_observation_attested", result
            cur.execute("select attested_by::text,attested_authority from public.pdc_provider_email_observations where intake_id=%s", (bound[0],))
            assert cur.fetchone() == (importer_id, "authenticated")
            cur.execute("select public.attest_pdc_provider_email_observation(%s,%s,%s,%s,%s,'mx.google.com',%s)", (*bound, Json(AUTH)))
            replay = cur.fetchone()[0]
            assert replay.get("ok") is True and replay.get("code") == "provider_observation_already_attested", replay

            denied = evidence("administrator")
            claims(cur, "authenticated", other_id, other_email)
            cur.execute("select public.attest_pdc_provider_email_observation(%s,%s,%s,%s,%s,'mx.google.com',%s)", (*denied, Json(AUTH)))
            rejected = cur.fetchone()[0]
            assert rejected.get("ok") is False and rejected.get("code") == "provider_observation_invalid", rejected

            print(json.dumps({"ok": True, "importer_code": result["code"], "replay_code": replay["code"], "non_importer_code": rejected["code"], "attested_by_bound": True}, sort_keys=True))
    finally:
        conn.rollback()
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
