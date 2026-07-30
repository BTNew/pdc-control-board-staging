#!/usr/bin/env python3
"""Rollback-only live staging proof for migration 123 AI Auditor hardening."""
from __future__ import annotations

import hashlib
import json
import os
import re
import uuid
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[2]
M123 = ROOT / "supabase/staging_only/123_harden_ai_auditor_human_review_binding.sql"
OUT = ROOT / "review-evidence/stage-a-ai-auditor/rollback-proof-123.json"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
OPERATIONAL = ["vehicles", "vehicle_work_items", "workshop_bookings", "workshop_booking_assignments", "vehicle_parts_updates", "vehicle_movements", "audit_events", "pdc_user_roles"]


def body(source: str) -> str:
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("migration wrapper missing")
    return source[begin.end():commits[-1].start()]


def signatures(cur):
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
        return
    cur.execute("rollback to savepoint expected_rejection")
    raise AssertionError(f"expected rejection containing {token}")


def run():
    dsn = os.environ.get("PDC_STAGING_DATABASE_URL", "")
    admin_email = os.environ.get("PDC_STAGING_ADMIN_EMAIL", "").strip().lower()
    if not dsn or not admin_email:
        raise RuntimeError("staging proof environment incomplete")
    source = M123.read_text("utf-8")
    result = {"passed": False, "committed": False, "migration": 123, "migration_name": "harden_ai_auditor_human_review_binding", "migration_sha256": hashlib.sha256(source.encode()).hexdigest(), "project_ref": "[REDACTED]"}
    with psycopg.connect(dsn, autocommit=True) as probe:
        with probe.cursor() as cur:
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            if cur.fetchone()[0] != PROJECT_REF:
                raise AssertionError("staging sentinel mismatch")
            cur.execute("select exists(select 1 from supabase_migrations.schema_migrations where version='122' and name='ai_auditor_human_review_decisions'),not exists(select 1 from supabase_migrations.schema_migrations where version='123')")
            if cur.fetchone() != (True, True):
                raise AssertionError("migration ledger precondition failed")
            before = signatures(cur)
            cur.execute("select count(*) from public.pdc_auditor_decisions")
            decisions_before = cur.fetchone()[0]
    with psycopg.connect(dsn, autocommit=False) as conn:
        try:
            cur = conn.cursor()
            cur.execute("set local statement_timeout='180s'")
            cur.execute(body(source))
            cur.execute("select id,email,role::text,auth_user_id from public.pdc_user_roles where lower(email)=%s and active and account_status='approved' and role::text='administrator'", (admin_email,))
            role_id, email, role, uid = cur.fetchone()
            if uid is None:
                raise AssertionError("administrator is not auth-bound")
            claims(cur, uid, email.lower())
            snapshot = cur.execute("select public.get_pdc_auditor_snapshot(null,1)").fetchone()[0]
            op_revision, rule_hash = snapshot["operational_revision"], snapshot["rule_set_hash"]
            finding_id, entity_id = uuid.uuid4(), uuid.uuid4()
            evidence, stable = "b" * 64, "a" * 64

            def add_run(run_id, rule_set_hash=rule_hash):
                request_hash = hashlib.sha256((str(run_id) + ':request').encode()).hexdigest()
                payload_hash = hashlib.sha256((str(run_id) + ':payload').encode()).hexdigest()
                cur.execute("""insert into public.pdc_auditor_runs(run_id,dealer_code,environment,request_hash,snapshot_generated_at,snapshot_response_revision,operational_revision,rule_set_hash,snapshot_manifest_hash,payload_hash,snapshot_page_count,snapshot_vehicle_count,snapshot_complete,model_key,status,finding_count)
                values(%s,'14450','staging',%s,clock_timestamp(),%s,%s,%s,%s,%s,1,1,true,'deterministic-stage-a-rules','completed',1)""", (run_id, request_hash, "e"*64, op_revision, rule_set_hash, "f"*64, payload_hash))

            run1 = uuid.uuid4()
            add_run(run1)
            cur.execute("""insert into public.pdc_auditor_findings(finding_id,dealer_code,environment,stable_fingerprint,evidence_fingerprint,rule_key,category,severity,summary_code,entity_type,entity_id,first_seen_run_id,last_seen_run_id,first_detected_at,last_detected_at,last_evidence_change_at,lifecycle_status)
            values(%s,'14450','staging',%s,%s,'proof_rule','data_quality','high','proof_summary','vehicle',%s,%s,%s,clock_timestamp(),clock_timestamp(),clock_timestamp(),'current')""", (finding_id, stable, evidence, entity_id, run1, run1))
            queue = cur.execute("select public.get_pdc_auditor_review_queue(200)").fetchone()[0]
            item = next(row for row in queue["items"] if str(row["finding_id"]) == str(finding_id))
            if item["run_operational_revision"] != op_revision or item["run_rule_set_hash"] != rule_hash or item["decision"] is not None:
                raise AssertionError("queue source binding failed")
            args = (finding_id, evidence, run1, "approved", "Reviewed")
            first = cur.execute("select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", args).fetchone()[0]
            replay = cur.execute("select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", args).fetchone()[0]
            if not first["ok"] or first["idempotent"] or not replay["idempotent"] or replay["decision_id"] != first["decision_id"]:
                raise AssertionError("exact replay failed")
            reject(cur, "select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", (finding_id, evidence, run1, "approved", "Changed note"), "pdc_auditor_already_decided")
            cur.execute("update public.pdc_auditor_findings set lifecycle_status='resolved',resolved_at=clock_timestamp() where finding_id=%s", (finding_id,))
            resolved_replay = cur.execute("select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", args).fetchone()[0]
            if not resolved_replay["idempotent"]:
                raise AssertionError("exact replay after resolution failed")

            run2 = uuid.uuid4()
            add_run(run2)
            cur.execute("update public.pdc_auditor_findings set lifecycle_status='current',resolved_at=null,last_seen_run_id=%s where finding_id=%s", (run2, finding_id))
            second = cur.execute("select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", (finding_id, evidence, run2, "approved", "Reviewed again")).fetchone()[0]
            if second["decision_id"] == first["decision_id"] or second["idempotent"]:
                raise AssertionError("new run silently inherited old decision")

            run3 = uuid.uuid4()
            add_run(run3, "1"*64)
            cur.execute("update public.pdc_auditor_findings set last_seen_run_id=%s where finding_id=%s", (run3, finding_id))
            reject(cur, "select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", (finding_id, evidence, run3, "approved", None), "pdc_auditor_finding_stale")
            cur.execute("savepoint viewer_role")
            cur.execute("update public.pdc_user_roles set role='viewer' where id=%s", (role_id,))
            reject(cur, "select public.record_pdc_auditor_decision(%s,%s,%s,%s,%s)", (finding_id, evidence, run3, "approved", None), "pdc_auditor_decision_forbidden")
            cur.execute("rollback to savepoint viewer_role")
            if signatures(cur) != before:
                raise AssertionError("operational signatures changed")
            result.update({"passed": True, "exact_replay": True, "changed_reason_rejected": True, "resolved_replay": True, "same_evidence_new_run_separate": True, "rule_change_stale": True, "viewer_rejected": True, "operational_signatures_unchanged": True, "operational_change": False})
        finally:
            conn.rollback()
    with psycopg.connect(dsn, autocommit=True) as verify:
        with verify.cursor() as cur:
            cur.execute("select not exists(select 1 from supabase_migrations.schema_migrations where version='123'),count(*) from public.pdc_auditor_decisions")
            ledger_absent, decisions_after = cur.fetchone()
            after = signatures(cur)
    if not ledger_absent or decisions_after != decisions_before or after != before:
        raise AssertionError("rollback restoration failed")
    result["rollback_restored"] = True
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", "utf-8")
    return result


if __name__ == "__main__":
    print(json.dumps(run(), indent=2, sort_keys=True))
