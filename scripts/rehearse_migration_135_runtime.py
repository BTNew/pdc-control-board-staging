from __future__ import annotations

import copy
import hashlib
import json
import os
import re
import sys
import uuid
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import assert_staging_target, load_local_env

MIGRATION = ROOT / "supabase" / "staging_only" / "135_ai_intake_verified_stock_auto_activation.sql"
SUBMIT = "public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamp with time zone,text,text,text,text,jsonb)"
CORE = "public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean)"
PRE135 = "public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamp with time zone,text,text,text,text,jsonb)"


def migration_without_backlog() -> str:
    source = MIGRATION.read_text(encoding="utf-8")
    source = re.sub(r"(?m)^begin;\s*$", "", source, count=1)
    commit = source.rfind("\ncommit;")
    if commit < 0:
        raise RuntimeError("Migration 135 commit wrapper missing")
    source = source[:commit] + source[commit + len("\ncommit;"):]
    source, count = re.subn(r"(?s)\n-- Process the exact reviewed staging backlog.*?\n\$backlog\$;\n", "\n", source, count=1)
    if count != 1:
        raise RuntimeError("Migration 135 backlog block not found")
    return source


def scalar(cur, sql, params=()):
    cur.execute(sql, params)
    return cur.fetchone()[0]


def operational_counts(cur):
    return {
        "active_activations": scalar(cur, "select count(*) from public.navision_board_activations where active"),
        "visible_vehicles": scalar(cur, "select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board"),
        "work_items": scalar(cur, "select count(*) from public.vehicle_work_items"),
        "parts_updates": scalar(cur, "select count(*) from public.vehicle_parts_updates"),
        "bookings": scalar(cur, "select count(*) from public.workshop_bookings"),
    }


def call_submit(cur, actor_id, actor_email, sender, authentication, stock, action, observations, minutes_ago):
    nonce = str(uuid.uuid4())
    source_hash = hashlib.sha256(("source:" + nonce).encode()).hexdigest()
    evidence_hash = hashlib.sha256(("evidence:" + nonce).encode()).hexdigest()
    claims = json.dumps({"sub": str(actor_id), "email": actor_email, "role": "authenticated"})
    cur.execute("set local role authenticated")
    cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))
    cur.execute(
        "select public.submit_pdc_ai_intake_observation(%s,%s,%s,%s,%s,clock_timestamp()-(%s * interval '1 minute'),%s,%s,%s,%s,%s)",
        (
            source_hash,
            evidence_hash,
            "migration-135-runtime-" + nonce,
            sender,
            json.dumps(authentication),
            minutes_ago,
            "Migration 135 transactional runtime proof",
            action,
            stock,
            "Transactional runtime proof for the bounded AI Intake contract.",
            json.dumps(observations),
        ),
    )
    response = cur.fetchone()[0]
    cur.execute("reset role")
    return response


def main():
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    results = {}
    with psycopg2.connect(dsn) as conn:
        conn.autocommit = False
        with conn.cursor() as cur:
            baseline = operational_counts(cur)
            try:
                cur.execute(migration_without_backlog())
                grants = (
                    scalar(cur, "select has_function_privilege('authenticated',%s,'EXECUTE')", (CORE,)),
                    scalar(cur, "select has_function_privilege('authenticated',%s,'EXECUTE')", (PRE135,)),
                    scalar(cur, "select has_function_privilege('authenticated',%s,'EXECUTE')", (SUBMIT,)),
                )
                if grants != (False, False, True):
                    raise RuntimeError(f"effective privilege mismatch: {grants}")
                cur.execute(
                    """select p.stock_number,p.sender_address,p.authentication,p.observations,
                              p.submitted_by,r.email
                       from public.pdc_ai_intake_proposals p
                       join public.pdc_user_roles r on r.auth_user_id=p.submitted_by
                       where p.status='pending' and p.action_type='board_activate_only'
                         and not exists(
                           select 1 from public.vehicles v
                           where v.deleted_at is null and v.stock_number_normalized=p.stock_number
                         )
                       order by p.source_received_at desc limit 1"""
                )
                stock, sender, authentication, observations, actor_id, actor_email = cur.fetchone()

                cases = [
                    ("review_only", "review_only", copy.deepcopy(observations), 4, None, "pending"),
                    ("structured_cancelled", "board_activate_only", {**copy.deepcopy(observations), "cancelled": True}, 3, "proposal_conflicted_or_cancelled", "pending"),
                    ("malformed_conflicts", "board_activate_only", {**copy.deepcopy(observations), "conflicts": {"unexpected": True}}, 2, "proposal_conflicted_or_cancelled", "pending"),
                ]
                for name, action, evidence, age, expected_auto_code, expected_status in cases:
                    cur.execute("savepoint runtime_case")
                    before = operational_counts(cur)
                    response = call_submit(cur, actor_id, actor_email, sender, authentication, stock if action == "board_activate_only" else None, action, evidence, age)
                    proposal_id = response.get("data", {}).get("proposal_id")
                    cur.execute("select status from public.pdc_ai_intake_proposals where proposal_id=%s", (proposal_id,))
                    row = cur.fetchone()
                    auto_code = response.get("data", {}).get("auto_activation", {}).get("code")
                    if not response.get("ok") or row != (expected_status,) or operational_counts(cur) != before or auto_code != expected_auto_code:
                        raise RuntimeError(f"{name} failed: response={response}, row={row}, before={before}, after={operational_counts(cur)}")
                    results[name] = {"status": row[0], "auto_code": auto_code, "operational_change": False}
                    cur.execute("rollback to savepoint runtime_case")

                cur.execute("savepoint runtime_case")
                before = operational_counts(cur)
                response = call_submit(cur, actor_id, actor_email, sender, authentication, stock, "board_activate_only", observations, 1)
                proposal_id = response.get("data", {}).get("proposal_id")
                cur.execute("select status from public.pdc_ai_intake_proposals where proposal_id=%s", (proposal_id,))
                row = cur.fetchone()
                after = operational_counts(cur)
                deltas = {key: after[key] - before[key] for key in before}
                auto_code = response.get("data", {}).get("auto_activation", {}).get("code")
                if not response.get("ok") or row != ("applied",) or auto_code != "automatically_applied" or deltas != {
                    "active_activations": 1,
                    "visible_vehicles": 1,
                    "work_items": 0,
                    "parts_updates": 0,
                    "bookings": 0,
                }:
                    raise RuntimeError(f"clean activation failed: response={response}, row={row}, deltas={deltas}")
                results["clean_activation"] = {"status": row[0], "auto_code": auto_code, "deltas": deltas}
                cur.execute("rollback to savepoint runtime_case")
            finally:
                conn.rollback()
    with psycopg2.connect(dsn) as conn, conn.cursor() as cur:
        if scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='135')"):
            raise RuntimeError("Migration 135 leaked after rollback")
        if operational_counts(cur) != baseline:
            raise RuntimeError("Runtime rehearsal leaked operational changes")
    print(json.dumps({"ok": True, "migration": "135", "mode": "runtime_rehearsal", "grants": grants, "results": results, "rollback_restored": True}, sort_keys=True))


if __name__ == "__main__":
    main()
