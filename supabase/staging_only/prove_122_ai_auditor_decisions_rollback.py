#!/usr/bin/env python3
"""Rollback-only live staging proof for migration 122 human review decisions."""
from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[2]
M121 = ROOT / "supabase/staging_only/121_beta_ai_auditor_foundation.sql"
M122 = ROOT / "supabase/staging_only/122_ai_auditor_human_review_decisions.sql"
OUT = ROOT / "review-evidence/stage-a-ai-auditor/rollback-proof-122.json"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
OPERATIONAL = [
    "vehicles", "vehicle_work_items", "workshop_bookings", "workshop_booking_assignments",
    "vehicle_parts_updates", "vehicle_movements", "audit_events", "pdc_user_roles",
]


def body(source: str) -> str:
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("migration wrapper missing")
    return source[begin.end():commits[-1].start()]


def signatures(cur) -> dict:
    result = {}
    for table in OPERATIONAL:
        cur.execute(f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")
        result[table] = cur.fetchone()
    return result


def claims(cur, uid, email):
    cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({"sub": str(uid), "email": email, "role": "authenticated"}),))


def reject(cur, sql, params, token):
    cur.execute("savepoint expected_rejection")
    try:
        cur.execute(sql, params)
    except psycopg.Error as exc:
        message = str(exc)
        cur.execute("rollback to savepoint expected_rejection")
        if token not in message:
            raise AssertionError(f"expected {token}, got {message.splitlines()[0]}")
        return message.splitlines()[0]
    cur.execute("rollback to savepoint expected_rejection")
    raise AssertionError(f"expected rejection containing {token}")


def run() -> dict:
    dsn = os.environ.get("PDC_STAGING_DATABASE_URL", "")
    admin_email = os.environ.get("PDC_STAGING_ADMIN_EMAIL", "").strip().lower()
    if not dsn or not admin_email:
        raise RuntimeError("staging proof environment incomplete")
    source121 = M121.read_text("utf-8")
    source122 = M122.read_text("utf-8")
    result = {
        "passed": False,
        "committed": False,
        "migration": 122,
        "migration_name": "ai_auditor_human_review_decisions",
        "migration_sha256": hashlib.sha256(source122.encode()).hexdigest(),
        "project_ref": "[REDACTED]",
    }
    with psycopg.connect(dsn, autocommit=True) as probe:
        with probe.cursor() as cur:
            cur.execute("select (select project_ref from public.pdc_staging_environment_sentinel where singleton),to_regclass('public.pdc_auditor_decisions') is null")
            sentinel, absent = cur.fetchone()
            if sentinel != PROJECT_REF or not absent:
                raise AssertionError("staging sentinel/object precondition failed")
            before = signatures(cur)
    with psycopg.connect(dsn, autocommit=False) as conn:
        try:
            cur = conn.cursor()
            cur.execute("set local statement_timeout='180s'")
            cur.execute(body(source121))
            cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values('121',%s,'beta_ai_auditor_foundation')", ([source121],))
            cur.execute(body(source122))
            cur.execute("select id,email,role::text from public.pdc_user_roles where lower(email)=%s and active and account_status='approved' and role::text='administrator'", (admin_email,))
            role_id, email, role = cur.fetchone()
            cur.execute("select auth_user_id from public.pdc_user_roles where id=%s", (role_id,))
            uid = cur.fetchone()[0]
            if uid is None:
                raise AssertionError("admin role is not auth-bound")
            cur.execute("insert into public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,'14450','staging')", (uid, email.lower()))
            claims(cur, uid, email.lower())
            cur.execute("select public.pdc_auditor_operational_revision('14450')")
            operational_revision = cur.fetchone()[0]
            run_id = uuid.uuid4()
            finding_id = uuid.uuid4()
            digest = "a" * 64
            evidence = "b" * 64
            cur.execute("""insert into public.pdc_auditor_runs(
              run_id,dealer_code,environment,request_hash,snapshot_generated_at,snapshot_response_revision,
              operational_revision,rule_set_hash,snapshot_manifest_hash,payload_hash,snapshot_page_count,
              snapshot_vehicle_count,snapshot_complete,model_key,status,finding_count)
              values(%s,'14450','staging',%s,clock_timestamp(),%s,%s,%s,%s,%s,1,1,true,'decision-proof','completed',1)""",
              (run_id, digest, digest, operational_revision, digest, digest, digest))
            cur.execute("""insert into public.pdc_auditor_findings(
              finding_id,dealer_code,environment,stable_fingerprint,evidence_fingerprint,rule_key,category,severity,
              summary_code,entity_type,entity_id,first_seen_run_id,last_seen_run_id,first_detected_at,last_detected_at,
              last_evidence_change_at,lifecycle_status)
              values(%s,'14450','staging',%s,%s,'proof_rule','data_quality','high','proof_summary','vehicle',%s,%s,%s,
              clock_timestamp(),clock_timestamp(),clock_timestamp(),'current')""",
              (finding_id, digest, evidence, uuid.uuid4(), run_id, run_id))
            cur.execute("select public.get_pdc_auditor_review_queue(200)")
            queue = cur.fetchone()[0]
            if queue.get("can_decide") is not True or len(queue.get("items", [])) != 1:
                raise AssertionError("review queue did not expose exact current finding")
            args = (finding_id, evidence, run_id, "approved", None)
            cur.execute("select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", args)
            first = cur.fetchone()[0]
            if first.get("ok") is not True or first.get("idempotent") is not False or first.get("operational_change") is not False or first.get("execution_reference") is not None:
                raise AssertionError("unsafe first decision receipt")
            cur.execute("select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", args)
            replay = cur.fetchone()[0]
            if replay.get("idempotent") is not True or replay.get("decision_id") != first.get("decision_id"):
                raise AssertionError("same decision was not idempotent")
            conflict = reject(cur, "select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", (finding_id, evidence, run_id, "denied", "Not accepted"), "pdc_auditor_already_decided")
            immutable = reject(cur, "update public.pdc_auditor_decisions set reason='changed' where decision_id=%s", (first["decision_id"],), "pdc_auditor_history_is_append_only")
            cur.execute("savepoint viewer_role")
            cur.execute("update public.pdc_user_roles set role='viewer' where id=%s", (role_id,))
            forbidden = reject(cur, "select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", (finding_id, evidence, run_id, "approved", None), "pdc_auditor_decision_forbidden")
            cur.execute("rollback to savepoint viewer_role")
            after = signatures(cur)
            if before != after:
                raise AssertionError("decision proof changed operational signatures")
            cur.execute("select count(*) from public.pdc_auditor_decisions where operational_change or execution_reference is not null")
            if cur.fetchone()[0] != 0:
                raise AssertionError("decision row gained execution authority")
            result.update({
                "passed": True,
                "role": role,
                "queue_items": len(queue["items"]),
                "idempotent_replay": True,
                "conflicting_decision_rejected": "already_decided" in conflict,
                "viewer_rejected": "forbidden" in forbidden,
                "history_immutable": "append_only" in immutable,
                "operational_signatures_unchanged": True,
                "operational_change": False,
                "execution_reference": None,
            })
        finally:
            conn.rollback()
    with psycopg.connect(dsn, autocommit=True) as verify:
        with verify.cursor() as cur:
            cur.execute("select to_regclass('public.pdc_auditor_decisions') is null,not exists(select 1 from supabase_migrations.schema_migrations where version in ('121','122'))")
            absent, ledger_absent = cur.fetchone()
            after_rollback = signatures(cur)
    if not absent or not ledger_absent or before != after_rollback:
        raise AssertionError("rollback restoration failed")
    result["rollback_restored"] = True
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, sort_keys=True, default=str) + "\n", "utf-8")
    return result


if __name__ == "__main__":
    print(json.dumps(run(), indent=2, sort_keys=True, default=str))
