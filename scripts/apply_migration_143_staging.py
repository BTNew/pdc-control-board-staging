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

EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_SHA = "6897735c1a018505d81df6f8910a06b7cb272de70b22350ed7c90bb35c8eb12b"
VERSION = "143"
NAME = "authenticated_operation_parts_allowance"
MIGRATION = ROOT / "supabase" / "staging_only" / "143_authenticated_operation_parts_allowance.sql"
SIGNATURE = "public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)"
FUNCTION = "public.import_pdc_authenticated_email_operations_with_hours"
OLD_ALLOW = "('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection')"
NEW_ALLOW = "('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','parts')"


def scalar(cur, query: str, params=()):
    cur.execute(query, params)
    return cur.fetchone()[0]


def migration_body(source: str) -> str:
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("Migration 143 transaction wrapper missing")
    return source[begin.end():commits[-1].start()]


def data_signature(cur) -> tuple:
    return (
        scalar(cur, "select count(*) from public.pdc_authenticated_email_operation_lines"),
        scalar(cur, "select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.pdc_authenticated_email_operation_lines t"),
        scalar(cur, "select count(*) from public.vehicle_work_items"),
        scalar(cur, "select md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.vehicle_work_items t"),
        scalar(cur, "select revision from public.pdc_email_vehicle_revision where singleton"),
    )


def function_definition(cur) -> str:
    return scalar(cur, "select pg_get_functiondef(%s::regprocedure)", (SIGNATURE,))


def verify_repair(cur, before_data: tuple) -> dict:
    definition = function_definition(cur)
    if OLD_ALLOW in definition or definition.count(NEW_ALLOW) != 1:
        raise RuntimeError("Migration 143 Parts allow-list was not installed exactly once")
    for marker in (
        "pdc_monitor_staging_guard()", "jsonb_array_length(v_operations) not between 1 and 50",
        "source_receipt_not_found", "operation_identity_conflict", "estimated_hours_conflict",
        "operation_lines_and_hours_already_imported", "'booking_created',false",
        "'completed_work_reopened',false",
    ):
        if marker not in definition:
            raise RuntimeError(f"Migration 143 safety marker missing: {marker}")
    privileges = {
        role: scalar(cur, "select has_function_privilege(%s,%s,'EXECUTE')", (role, SIGNATURE))
        for role in ("public", "anon", "authenticated")
    }
    if privileges != {"public": False, "anon": False, "authenticated": True}:
        raise RuntimeError(f"Migration 143 privilege mismatch: {privileges}")
    cur.execute("""select w.user_id,r.email from public.pdc_monitor_stage_activation_writers w
      join public.pdc_user_roles r on r.auth_user_id=w.user_id
      where w.active and w.revoked_at is null and r.active and r.account_status='approved' and r.role='viewer'
      order by r.created_at limit 1""")
    actor = cur.fetchone()
    if not actor:
        raise RuntimeError("Migration 143 enrolled Viewer rehearsal identity missing")
    scalar(cur, "select set_config('request.jwt.claims',%s,true)",
           (json.dumps({"sub": str(actor[0]), "email": actor[1], "role": "authenticated"}),))
    payload = [
        {"operation_no": "OP901", "work_key": "fitting", "description": "Migration 143 fitting validation probe", "estimated_hours": None, "estimated_hours_source": None},
        {"operation_no": "OP902", "work_key": "parts", "description": "Migration 143 Parts validation probe", "estimated_hours": None, "estimated_hours_source": None},
    ]
    result = scalar(cur, f"select {FUNCTION}(%s,%s,%s::jsonb)",
                    ("a" * 64, "migration-143-validation-probe", json.dumps(payload)))
    if result.get("ok") is not False or result.get("code") != "source_receipt_not_found":
        raise RuntimeError(f"Mixed Fitting + Parts payload remains blocked: {result}")
    after_data = data_signature(cur)
    if after_data != before_data:
        raise RuntimeError("Migration 143 rehearsal changed operation/work data or revision")
    return {
        "parts_validation": result.get("code"),
        "privileges": privileges,
        "operation_rows": before_data[0],
        "work_item_rows": before_data[2],
        "revision_unchanged": True,
        "booking_created": False,
        "completed_work_reopened": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    args = parser.parse_args()
    if args.apply and (not args.expected_commit or not re.fullmatch(r"[a-f0-9]{40}", args.expected_commit)):
        raise RuntimeError("--apply requires exact reviewed --expected-commit")
    raw = MIGRATION.read_bytes()
    source_sha = hashlib.sha256(raw).hexdigest()
    if source_sha != EXPECTED_SHA:
        raise RuntimeError(f"Migration 143 digest mismatch: {source_sha}")
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    if args.apply:
        actual = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        if actual != args.expected_commit or dirty:
            raise RuntimeError("refusing Migration 143 apply from unreviewed or dirty worktree")
    with psycopg2.connect(dsn) as conn:
        try:
            with conn.cursor() as cur:
                if scalar(cur, "select project_ref from public.pdc_staging_environment_sentinel where singleton") != EXPECTED_REF:
                    raise RuntimeError("staging sentinel mismatch")
                if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                    raise RuntimeError("production sentinel present")
                head = scalar(cur, "select version from supabase_migrations.schema_migrations order by version::integer desc limit 1")
                installed = scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version=%s", (VERSION,))
                if args.apply and (head != "142" or installed):
                    raise RuntimeError(f"unexpected Migration 143 ledger pre-state: head={head}, installed={installed}")
                if not args.apply and installed:
                    raise RuntimeError("Migration 143 is already installed")
                original = function_definition(cur)
                before_data = data_signature(cur)
                cur.execute(migration_body(raw.decode("utf-8")))
                outcome = verify_repair(cur, before_data)
                if args.apply:
                    cur.execute("insert into supabase_migrations.schema_migrations(version,name,statements) values(%s,%s,array[%s]::text[])",
                                (VERSION, NAME, raw.decode("utf-8")))
                    conn.commit()
                else:
                    conn.rollback()
                    with conn.cursor() as check:
                        if function_definition(check) != original or data_signature(check) != before_data:
                            raise RuntimeError("Migration 143 rehearsal rollback leaked state")
                    print(json.dumps({"ok": True, "mode": "rehearsal", "migration": VERSION, "sha256": source_sha,
                                      "outcome": outcome, "rollback_restored": True, "production_changed": False}, sort_keys=True))
                    return
            with conn.cursor() as cur:
                if scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version=%s and name=%s", (VERSION, NAME)) != 1:
                    raise RuntimeError("Migration 143 ledger verification failed")
                persisted = verify_repair(cur, data_signature(cur))
            print(json.dumps({"ok": True, "mode": "apply", "migration": VERSION, "sha256": source_sha,
                              "outcome": persisted, "production_changed": False}, sort_keys=True))
        except Exception:
            conn.rollback()
            raise


if __name__ == "__main__":
    main()
