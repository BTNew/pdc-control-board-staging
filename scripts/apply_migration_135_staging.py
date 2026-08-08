from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import assert_staging_target, load_local_env

MIGRATION = ROOT / "supabase" / "staging_only" / "135_ai_intake_verified_stock_auto_activation.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_SHA = "812811ebb359cf95fa154d440b5b3094a226fcbc8bd2e337679ae93b40e70cf4"
CORE = "public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean)"
PREVIOUS_SUBMIT = "public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamp with time zone,text,text,text,text,jsonb)"
SUBMIT = "public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamp with time zone,text,text,text,text,jsonb)"
EXPECTED_PENDING_STOCKS = {
    "12666946", "13017926", "13045139", "13047224", "13047225", "13047346",
    "13052117", "13056859", "13056892", "13080531", "13086228", "13086231",
}
EXPECTED_NEW_STOCKS = EXPECTED_PENDING_STOCKS - {"13017926", "13056892"}


def scalar(cur, sql, params=()):
    cur.execute(sql, params)
    return cur.fetchone()[0]


def migration_body(source: str) -> str:
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("Migration 135 transaction wrapper missing")
    return source[begin.end():commits[-1].start()]


def state(cur):
    result = {}
    for key, query in {
        "pending_activation": "select count(*) from public.pdc_ai_intake_proposals where status='pending' and action_type='board_activate_only'",
        "pending_activation_stocks": "select count(distinct stock_number) from public.pdc_ai_intake_proposals where status='pending' and action_type='board_activate_only'",
        "pending_review": "select count(*) from public.pdc_ai_intake_proposals where status='pending' and action_type='review_only'",
        "inbox_revision": "select revision from public.pdc_ai_intake_revision where singleton",
        "navision_revision": "select revision from public.navision_backend_revision where singleton",
        "active_activations": "select count(*) from public.navision_board_activations where active",
        "visible_vehicles": "select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board",
        "work_items": "select count(*) from public.vehicle_work_items",
        "parts_updates": "select count(*) from public.vehicle_parts_updates",
        "bookings": "select count(*) from public.workshop_bookings",
    }.items():
        result[key] = scalar(cur, query)
    cur.execute("select distinct stock_number from public.pdc_ai_intake_proposals where status='pending' and action_type='board_activate_only'")
    result["pending_stock_set"] = {row[0] for row in cur.fetchall()}
    return result


def verify_install(cur):
    ledger = scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version='135' and name='ai_intake_verified_stock_auto_activation'")
    exists = {name: scalar(cur, "select to_regprocedure(%s) is not null", (signature,)) for name, signature in {"core": CORE, "pre135": PREVIOUS_SUBMIT, "submit": SUBMIT}.items()}
    acls = {
        name: {role: scalar(cur, "select has_function_privilege(%s,%s,'EXECUTE')", (role, signature)) for role in ("public", "anon", "authenticated", "service_role")}
        for name, signature in {"core": CORE, "pre135": PREVIOUS_SUBMIT, "submit": SUBMIT}.items()
    }
    source = scalar(cur, "select pg_get_functiondef(%s::regprocedure)", (SUBMIT,)).lower()
    receipt_tables = ("pdc_ai_intake_auto_activation_receipts", "pdc_ai_intake_auto_backlog_receipts")
    receipt_rls = {table: scalar(cur, "select relrowsecurity from pg_class where oid=(%s)::regclass", ("public." + table,)) for table in receipt_tables}
    receipt_acls = {
        table: {role: scalar(cur, "select has_table_privilege(%s,%s,'SELECT,INSERT,UPDATE,DELETE')", (role, "public." + table)) for role in ("public", "anon", "authenticated", "service_role")}
        for table in receipt_tables
    }
    ok = (
        ledger == 1
        and all(exists.values())
        and not any(acls["core"].values())
        and not any(acls["pre135"].values())
        and acls["submit"] == {"public": False, "anon": False, "authenticated": True, "service_role": False}
        and "pdc_auto_apply_ai_intake_activation_internal" in source
        and "v_actor_id,lower(btrim(v_actor_email)),false" in source
        and "board_activate_only" in source
        and all(receipt_rls.values())
        and not any(any(role_acls.values()) for role_acls in receipt_acls.values())
    )
    return ok, {"ledger": ledger, "exists": exists, "acls": acls, "runtime_refresh_disabled": "v_actor_id,lower(btrim(v_actor_email)),false" in source, "receipt_rls": receipt_rls, "receipt_acls": receipt_acls}


def verify_outcome(cur, before):
    after = state(cur)
    if before["pending_activation"] != 28 or before["pending_activation_stocks"] != 12 or before["pending_stock_set"] != EXPECTED_PENDING_STOCKS:
        raise RuntimeError(f"reviewed AI Intake pre-state changed: {before}")
    expected_deltas = {
        "pending_activation": -28,
        "pending_activation_stocks": -12,
        "pending_review": 0,
        "inbox_revision": 28,
        "navision_revision": 10,
        "active_activations": 10,
        "visible_vehicles": 10,
        "work_items": 0,
        "parts_updates": 0,
        "bookings": 0,
    }
    actual_deltas = {key: after[key] - before[key] for key in expected_deltas}
    if actual_deltas != expected_deltas or after["pending_stock_set"]:
        raise RuntimeError(f"Migration 135 outcome mismatch: {actual_deltas}; pending={sorted(after['pending_stock_set'])}")
    cur.execute("select status,count(*) from public.pdc_ai_intake_proposals where decision_reason like 'Automatically %%' group by status")
    transitions = dict(cur.fetchall())
    receipts = scalar(cur, "select count(*) from public.pdc_ai_intake_auto_activation_receipts")
    authority_refreshed = scalar(cur, "select count(*) from public.pdc_ai_intake_proposals where decision_reason like 'Automatically %%' and result->'data'->>'authority_refreshed'='true'")
    audits = scalar(cur, "select count(*) from public.navision_backend_audit where action='board_activate' and evidence->>'contract'='pdc_ai_intake_auto_135'")
    cur.execute("select proposal_count,stock_count,applied_count,rejected_count,response->>'code',response->'data'->>'executor' from public.pdc_ai_intake_auto_backlog_receipts where policy_version='135.1'")
    batch_receipt = cur.fetchone()
    cur.execute("""select distinct a.activated_stock_number from public.navision_board_activations a join public.vehicles v on v.id=a.canonical_vehicle_id where a.active and a.completed_at is null and v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board and a.activated_stock_number=any(%s)""", (list(EXPECTED_NEW_STOCKS),))
    active_stocks = {row[0] for row in cur.fetchall()}
    expected_batch = (28, 12, 10, 18, "backlog_applied", "migration_135_staging_ledger_runner")
    if transitions != {"applied": 10, "rejected": 18} or receipts != 12 or authority_refreshed != 12 or audits != 10 or active_stocks != EXPECTED_NEW_STOCKS or batch_receipt != expected_batch:
        raise RuntimeError(f"Migration 135 evidence mismatch: transitions={transitions}, receipts={receipts}, refreshed={authority_refreshed}, audits={audits}, active={sorted(active_stocks)}, batch={batch_receipt}")
    return {"after": after, "deltas": actual_deltas, "transitions": transitions, "receipts": receipts, "authority_refreshed": authority_refreshed, "audits": audits, "active_stocks": sorted(active_stocks), "batch_receipt": batch_receipt}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    parser.add_argument("--fault-inject-postcheck-failure", action="store_true")
    args = parser.parse_args()
    if args.apply and (not args.expected_commit or not re.fullmatch(r"[a-f0-9]{40}", args.expected_commit)):
        raise RuntimeError("--apply requires exact reviewed --expected-commit")
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    raw = MIGRATION.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SHA:
        raise RuntimeError(f"Migration 135 digest mismatch: {digest}")
    if args.apply:
        actual = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        if actual != args.expected_commit:
            raise RuntimeError(f"reviewed commit mismatch: {actual}")
        if dirty:
            raise RuntimeError("refusing Migration 135 apply from dirty worktree")
    with psycopg2.connect(dsn) as conn:
        try:
            with conn.cursor() as cur:
                if scalar(cur, "select project_ref from public.pdc_staging_environment_sentinel where singleton") != EXPECTED_REF or scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                    raise RuntimeError("staging sentinel mismatch")
                if not scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='134' and name='navision_preserve_deleted_canonical_identity')") or scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='135')"):
                    raise RuntimeError("unexpected 134/135 ledger pre-state")
                before = state(cur)
                if before["pending_activation"] != 28 or before["pending_activation_stocks"] != 12 or before["pending_stock_set"] != EXPECTED_PENDING_STOCKS:
                    raise RuntimeError(f"reviewed AI Intake pre-state changed: {before}")
                cur.execute(migration_body(raw.decode("utf-8")))
                ok, install = verify_install(cur)
                if not ok:
                    raise RuntimeError(f"Migration 135 install postcheck failed: {install}")
                outcome = verify_outcome(cur, before)
                if args.fault_inject_postcheck_failure:
                    raise RuntimeError("intentional postcheck failure before commit")
                if not args.apply:
                    conn.rollback()
                    with conn.cursor() as check:
                        if state(check) != before or scalar(check, "select exists(select 1 from supabase_migrations.schema_migrations where version='135')"):
                            raise RuntimeError("Migration 135 rehearsal rollback leaked state")
                    print(json.dumps({"ok": True, "migration": "135", "mode": "rehearsal", "sha256": digest, "install": install, "outcome": outcome, "rollback_restored": True}, sort_keys=True, default=list))
                    return
                conn.commit()
            with conn.cursor() as cur:
                ok, install = verify_install(cur)
                if not ok:
                    raise RuntimeError(f"Migration 135 persisted install postcheck failed: {install}")
                final = state(cur)
                if final["pending_activation"] != 0 or final["pending_review"] != before["pending_review"]:
                    raise RuntimeError(f"Migration 135 persisted outcome changed: {final}")
            print(json.dumps({"ok": True, "migration": "135", "mode": "apply", "sha256": digest, "install": install, "outcome": outcome}, sort_keys=True, default=list))
        except Exception:
            conn.rollback()
            raise


if __name__ == "__main__":
    main()
