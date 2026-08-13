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
TOOLS = Path.home() / "pdc-control-board" / "_staging_test_tools"
sys.path.insert(0, str(TOOLS))
from staging_env import assert_staging_target, load_local_env  # noqa: E402

EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
MIGRATION_PATH = "supabase/staging_only/253_ai_auditor_typed_operation_control.sql"
VERSION = "253"
NAME = "ai_auditor_typed_operation_control"
PUBLIC_RPCS = (
    "public.plan_pdc_auditor_typed_instruction_253(text,text,jsonb,jsonb)",
    "public.compose_pdc_auditor_typed_plan_253(uuid[],jsonb)",
    "public.apply_pdc_auditor_typed_plan_253(uuid,integer,text,text,text,text,jsonb)",
    "public.undo_last_pdc_auditor_typed_run_253(jsonb)",
    "public.query_pdc_auditor_typed_253(text,jsonb,jsonb)",
)
PRIVATE_TABLES = (
    "pdc_auditor_gateway_keys_253",
    "pdc_auditor_signed_deliveries_253",
    "pdc_auditor_signed_delivery_results_253",
    "pdc_auditor_typed_plans_253",
    "pdc_auditor_typed_plan_items_253",
    "pdc_auditor_typed_runs_253",
    "pdc_auditor_typed_scope_receipts_253",
    "pdc_auditor_typed_change_receipts_253",
    "pdc_auditor_typed_undo_receipts_253",
)


def scalar(cur, sql, params=()):
    cur.execute(sql, params)
    return cur.fetchone()[0]


def git(*args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True).stdout


def exact_blob(commit: str, path: str) -> bytes:
    return git("show", f"{commit}:{path}")


def transaction_body(source: str) -> str:
    start = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not start or not commits:
        raise RuntimeError("migration transaction markers missing")
    return source[start.end():commits[-1].start()]


def operational_signature(cur) -> dict:
    queries = {
        "vehicles": "select count(*),coalesce(max(version),0) from public.vehicles",
        "work_items": "select count(*),coalesce(max(updated_at),'epoch') from public.vehicle_work_items",
        "operation_lines": "select count(*),coalesce(max(created_at),'epoch') from public.pdc_authenticated_email_operation_lines",
        "adjustments": "select count(*),coalesce(max(version),0) from public.vehicle_workshop_line_adjustments",
        "bookings": "select count(*),coalesce(max(version),0) from public.workshop_bookings",
        "revisions": "select count(*),coalesce(max(revision_id),0) from public.pdc_auditor_workshop_revisions",
    }
    result = {}
    for name, query in queries.items():
        cur.execute(query)
        result[name] = [str(value) for value in cur.fetchone()]
    return result


def preflight(cur, migration_250: bytes) -> dict:
    if scalar(cur, "select project_ref from public.pdc_staging_environment_sentinel where singleton") != EXPECTED_REF:
        raise RuntimeError("staging project sentinel mismatch")
    if scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
        raise RuntimeError("production sentinel present")
    cur.execute("select version,name,statements from supabase_migrations.schema_migrations order by version::integer desc limit 1")
    head = cur.fetchone()
    expected_statement = ["staging-only forward closure: legacy scheduling RPCs denied to public, anon, authenticated and service_role"]
    if head != ("250", "revoke_service_role_legacy_workshop_rpc", expected_statement):
        raise RuntimeError(f"exact migration-250 ledger predecessor mismatch: {head!r}")
    if scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version in('251','252','253'))"):
        raise RuntimeError("migration 251, 252 or 253 is already installed")
    legacy = (
        "public.schedule_vehicle_work(uuid,integer,text,integer,timestamp with time zone,integer,uuid,text,jsonb)",
        "public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)",
        "public.move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb)",
        "public.resize_workshop_booking(uuid,integer,integer,jsonb)",
        "public.change_booking_bay(uuid,integer,integer,jsonb)",
    )
    for signature in legacy:
        for role in ("public", "anon", "authenticated", "service_role"):
            if scalar(cur, "select has_function_privilege(%s,%s,'EXECUTE')", (role, signature)):
                raise RuntimeError(f"migration-250 closure missing: {role} can execute {signature}")
    return {
        "head": "250",
        "head_name": head[1],
        "canonical_250_sha256": hashlib.sha256(migration_250).hexdigest(),
        "canonical_250_blob_bytes": len(migration_250),
        "installed_250_acl_closure": True,
    }


def verify_install(cur, owner: str, source: str) -> dict:
    cur.execute("select name,statements from supabase_migrations.schema_migrations where version=%s", (VERSION,))
    ledger = cur.fetchone()
    if not ledger or ledger[0] != NAME or not ledger[1] or "global migration-230 Telegram" not in " ".join(ledger[1]):
        raise RuntimeError(f"migration-253 ledger mismatch: {ledger!r}")
    for table in PRIVATE_TABLES:
        cur.execute("select pg_get_userbyid(relowner),relrowsecurity from pg_class where oid=(%s)::regclass", ("public." + table,))
        row = cur.fetchone()
        if row != (owner, True):
            raise RuntimeError(f"owner/RLS mismatch for {table}: {row!r}")
        for role in ("public", "anon", "authenticated", "service_role"):
            if scalar(cur, "select has_table_privilege(%s,%s,'SELECT,INSERT,UPDATE,DELETE')", (role, "public." + table)):
                raise RuntimeError(f"private-table privilege leak: {role} {table}")
    for signature in PUBLIC_RPCS:
        cur.execute("select pg_get_userbyid(proowner),prosecdef,proconfig from pg_proc where oid=%s::regprocedure", (signature,))
        row = cur.fetchone()
        if not row or row[0] != owner or not row[1] or not row[2] or not any(value.startswith("search_path=pg_catalog, public") for value in row[2]):
            raise RuntimeError(f"owner/security-definer/search-path mismatch: {signature} {row!r}")
        acl = {role: scalar(cur, "select has_function_privilege(%s,%s,'EXECUTE')", (role, signature)) for role in ("public", "anon", "authenticated", "service_role")}
        if acl != {"public": False, "anon": False, "authenticated": True, "service_role": False}:
            raise RuntimeError(f"RPC ACL mismatch: {signature} {acl}")
    if scalar(cur, "select count(*) from public.pdc_auditor_gateway_keys_253") != 0:
        raise RuntimeError("gateway key table was not empty after structural installation")
    if not scalar(cur, "select exists(select 1 from pg_constraint where conrelid='public.pdc_auditor_telegram_deliveries_230'::regclass and contype='c' and pg_get_constraintdef(oid) like '%pdc_auditor_signed_deliveries_253%')"):
        raise RuntimeError("global Telegram delivery source constraint was not extended")
    if not scalar(cur, "select exists(select 1 from pg_policies where schemaname='public' and tablename='pdc_auditor_workshop_revisions' and policyname='pdc_auditor_workshop_revisions_admin_read_253')"):
        raise RuntimeError("Administrator Realtime policy missing")
    if not scalar(cur, "select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_auditor_workshop_revisions')"):
        raise RuntimeError("revision table is absent from supabase_realtime publication")
    immutable_count = scalar(cur, "select count(*) from pg_trigger where not tgisinternal and tgname like '%253%immutable%'")
    if immutable_count < 9:
        raise RuntimeError(f"immutable trigger coverage too small: {immutable_count}")
    if "PDC_253_TELEGRAM_DELIVERY_ALREADY_CONSUMED" not in scalar(cur, "select pg_get_functiondef('public.pdc_auditor_verify_envelope_253(text,jsonb)'::regprocedure)"):
        raise RuntimeError("global Telegram replay denial missing from verifier")
    return {"owner": owner, "private_tables": len(PRIVATE_TABLES), "public_rpcs": len(PUBLIC_RPCS), "immutable_triggers": immutable_count, "gateway_keys_empty": True, "realtime_publication": True}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--change-id")
    parser.add_argument("--window-id")
    parser.add_argument("--operator")
    parser.add_argument("--observer")
    parser.add_argument("--stop-authority")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{40}", args.expected_commit):
        raise RuntimeError("exact reviewed 40-character commit is required")
    resolved = git("rev-parse", f"{args.expected_commit}^{{commit}}").decode().strip()
    head = git("rev-parse", "HEAD").decode().strip()
    tracked_dirty = git("status", "--porcelain=v1", "--untracked-files=no").decode().strip()
    staged_dirty = git("diff", "--cached", "--name-only").decode().strip()
    if resolved != args.expected_commit or head != args.expected_commit or tracked_dirty or staged_dirty:
        raise RuntimeError("exact reviewed commit/clean tracked worktree required")
    if args.apply:
        required = {name: getattr(args, name) for name in ("change_id", "window_id", "operator", "observer", "stop_authority")}
        if any(not str(value or "").strip() for value in required.values()):
            raise RuntimeError("apply requires change/window/operator/observer/stop-authority metadata")
        expected_confirmation = f"{EXPECTED_REF}:253:{args.expected_commit}"
        if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_253") != expected_confirmation:
            raise RuntimeError("exact one-window staging migration confirmation is required")
    raw = exact_blob(args.expected_commit, MIGRATION_PATH)
    migration_250 = exact_blob(args.expected_commit, "supabase/staging_only/250_revoke_service_role_legacy_workshop_rpc.sql")
    source_sha = hashlib.sha256(raw).hexdigest()
    source = raw.decode("utf-8")
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    connection = psycopg2.connect(dsn)
    try:
        owner = None
        with connection.cursor() as cur:
            owner = scalar(cur, "select current_user")
            session_user = scalar(cur, "select session_user")
            database_owner = scalar(cur, "select pg_get_userbyid(datdba) from pg_database where datname=current_database()")
            if owner != session_user or owner != database_owner:
                raise RuntimeError(f"migration owner/session/database-owner mismatch: {owner!r}/{session_user!r}/{database_owner!r}")
            predecessor = preflight(cur, migration_250)
            before = operational_signature(cur)
            cur.execute(transaction_body(source))
            installed = verify_install(cur, owner, source)
            after = operational_signature(cur)
            if after != before:
                raise RuntimeError(f"structural install changed operational signature: {before!r} -> {after!r}")
            if args.apply:
                connection.commit()
            else:
                connection.rollback()
                with connection.cursor() as check:
                    if scalar(check, "select exists(select 1 from supabase_migrations.schema_migrations where version='253')") or scalar(check, "select to_regclass('public.pdc_auditor_gateway_keys_253') is not null") or operational_signature(check) != before:
                        raise RuntimeError("rollback-only rehearsal leaked migration or operational state")
                print(json.dumps({"ok": True, "mode": "rehearsal", "commit": args.expected_commit, "migration": VERSION, "source_sha256": source_sha, "predecessor": predecessor, "postconditions": installed, "rollback_verified": True, "production_changed": False}, sort_keys=True))
                return 0
        with connection.cursor() as cur:
            persisted = verify_install(cur, owner, source)
            if operational_signature(cur) != before:
                raise RuntimeError("persisted structural install changed operational signature")
        connection.rollback()
        print(json.dumps({"ok": True, "mode": "apply", "commit": args.expected_commit, "migration": VERSION, "source_sha256": source_sha, "predecessor": predecessor, "postconditions": persisted, "production_changed": False}, sort_keys=True))
        return 0
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    raise SystemExit(main())
