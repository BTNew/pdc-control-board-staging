#!/usr/bin/env python3
"""Guarded staging-only apply/rollback rehearsal for migration 103."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from pdc_staging_runtime import assert_staging_target, get_conn, load_local_env, required  # noqa: E402

EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
EXPECTED_BRANCH = "qa/workshop-bulletproof-20260728"
DEADLINE_UTC = datetime.fromisoformat("2026-07-28T21:01:02+00:00")
MIGRATION = ROOT / "supabase" / "staging_only" / "103_restore_pit_inspection_workshop_planner.sql"
VERSION = "103"
NAME = "restore_pit_inspection_workshop_planner"
ROLLBACK_ONLY = os.getenv("PDC_MIGRATION_ROLLBACK_ONLY", "1").lower() not in {"0", "false", "no"}
OPERATIONAL_TABLES = (
    "vehicles", "vehicle_work_items", "vehicle_parts_updates", "workshop_bookings",
    "workshop_booking_assignments", "workshop_booking_history", "vehicle_movements",
    "audit_events", "vehicle_notifications",
)


def scalar(cur, query, params=()):
    cur.execute(query, params)
    row = cur.fetchone()
    return row[0] if row else None


def transaction_body(source: str) -> str:
    source = source.strip()
    if source.lower().startswith("begin;"):
        source = source[6:].lstrip()
    if source.lower().endswith("commit;"):
        source = source[:-7].rstrip()
    return source


def table_signature(cur, table: str) -> tuple[int, str]:
    cur.execute(
        f"select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' "
        f"order by md5(to_jsonb(t)::text)),'')) from public.{table} t"
    )
    count, digest = cur.fetchone()
    return int(count), str(digest)


def assert_source_context() -> tuple[str, str]:
    branch = subprocess.check_output(["git", "-C", str(ROOT), "branch", "--show-current"], text=True).strip()
    if branch != EXPECTED_BRANCH:
        raise RuntimeError(f"refusing migration 103 from branch {branch!r}")
    if datetime.now(timezone.utc) >= DEADLINE_UTC:
        raise RuntimeError("QA campaign deadline has passed")
    return branch, subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()


def effective_checks(cur) -> dict[str, object]:
    cur.execute(
        "select active,planner_enabled,is_physical,is_sublet,work_key,"
        "(select count(*) from public.workshop_bays b where b.stage_id=s.id and b.is_active) "
        "from public.workshop_stages s where code='PIT_INSPECTION'"
    )
    row = cur.fetchone()
    if row != (True, True, True, False, "pitInspection", 1):
        raise RuntimeError(f"effective Pit station mismatch: {row!r}")
    definition = scalar(cur, "select pg_get_functiondef('public.pdc_qc_gate_issues(uuid)'::regprocedure)") or ""
    if "stage_code_for_work_key(wi.work_key) is distinct from 'PIT_INSPECTION'" in definition:
        raise RuntimeError("effective QC gate still excludes Pit Inspection")
    if "vehicle_still_in_workshop_stage:" not in definition:
        raise RuntimeError("effective QC gate does not require PMB unallocated")
    return {"pitPlannerEnabled": True, "pitActiveBays": 1, "pitQcGateRequired": True}


def main() -> int:
    branch, source_commit = assert_source_context()
    load_local_env()
    database_url = required("PDC_STAGING_DATABASE_URL")
    lowered = database_url.lower()
    if PRODUCTION_REF in lowered or EXPECTED_REF not in lowered:
        raise RuntimeError("refusing endpoint outside guarded staging")
    assert_staging_target(database_url=database_url)
    source = MIGRATION.read_text(encoding="utf-8")
    source_sha = hashlib.sha256(source.encode("utf-8")).hexdigest()
    conn = get_conn()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute("set local statement_timeout='120s'")
            cur.execute("lock table supabase_migrations.schema_migrations in exclusive mode")
            if scalar(cur, "select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s", (EXPECTED_REF,)) != 1:
                raise RuntimeError("PDC_STAGING_SENTINEL_MISMATCH")
            head = str(scalar(cur, "select version from supabase_migrations.schema_migrations order by version::int desc limit 1"))
            existing = scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version=%s", (VERSION,))
            if existing:
                cur.execute("select name,statements from supabase_migrations.schema_migrations where version=%s", (VERSION,))
                name, statements = cur.fetchone()
                recorded = (statements or [""])[0]
                if name != NAME or hashlib.sha256(recorded.encode("utf-8")).hexdigest() != source_sha:
                    raise RuntimeError("migration 103 ledger checksum/name mismatch")
                checks = effective_checks(cur)
                conn.rollback()
                print(json.dumps({"status": "already_applied", "migration": VERSION, **checks, "productionChanged": False}, sort_keys=True))
                return 0
            if head!='102':
                raise RuntimeError(f"ledger head mismatch: {head}")
            before = {table: table_signature(cur, table) for table in OPERATIONAL_TABLES}
            cur.execute(transaction_body(source))
            checks = effective_checks(cur)
            after = {table: table_signature(cur, table) for table in OPERATIONAL_TABLES}
            if before != after:
                raise RuntimeError("migration 103 changed operational table signatures")
            cur.execute(
                "insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",
                (VERSION, [source], NAME),
            )
            status = "rollback_dry_run" if ROLLBACK_ONLY else "applied"
            if ROLLBACK_ONLY:
                conn.rollback()
            else:
                conn.commit()
            print(json.dumps({
                "status": status, "migration": VERSION, "sourceSha256": source_sha,
                "sourceBranch": branch, "sourceCommit": source_commit,
                "operationalSignaturesUnchanged": True, **checks,
                "productionChanged": False,
            }, sort_keys=True))
            return 0
    except Exception as exc:
        conn.rollback()
        print(f"MIGRATION_103_FAILED: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
