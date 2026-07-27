#!/usr/bin/env python3
"""Apply staging-only migration 071 with sentinel, inventory and snapshot checks."""
from __future__ import annotations

import json
import os
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "071_human_ai_intake_change_summary.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
VERSION = "071"
NAME = "human_ai_intake_change_summary"


def scalar(cur, sql: str, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def transaction_body(sql: str) -> str:
    lines = sql.splitlines()
    begin_at = next((i for i, line in enumerate(lines) if line.strip().lower() == "begin;"), None)
    commit_at = next((i for i in range(len(lines) - 1, -1, -1) if lines[i].strip().lower() == "commit;"), None)
    if begin_at is None or commit_at is None or commit_at <= begin_at:
        raise RuntimeError("migration must contain one outer BEGIN/COMMIT pair")
    return "\n".join(lines[:begin_at] + lines[begin_at + 1:commit_at] + lines[commit_at + 1:])


def inventory(cur) -> dict[str, int]:
    return {
        "vehicles": scalar(cur, "select count(*) from public.vehicles"),
        "work_items": scalar(cur, "select count(*) from public.vehicle_work_items"),
        "parts_updates": scalar(cur, "select count(*) from public.vehicle_parts_updates"),
        "bookings": scalar(cur, "select count(*) from public.workshop_bookings"),
        "proposals": scalar(cur, "select count(*) from public.pdc_ai_intake_proposals"),
        "history": scalar(cur, "select count(*) from public.pdc_ai_intake_history"),
    }


def main() -> None:
    url = os.environ.get("PDC_STAGING_DATABASE_URL")
    if not url:
        raise RuntimeError("PDC_STAGING_DATABASE_URL is required")
    sql = MIGRATION.read_text(encoding="utf-8")
    if EXPECTED_REF not in sql:
        raise RuntimeError("migration is missing the exact staging guard")

    conn = psycopg2.connect(url, connect_timeout=15, application_name="pdc_staging_migration_071")
    report: dict[str, object] = {"version": VERSION}
    try:
        with conn.cursor() as cur:
            if not scalar(cur, "select exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref=%s)", (EXPECTED_REF,)):
                raise RuntimeError("PDC_STAGING_SENTINEL_MISMATCH")
            scalar(cur, "select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-071',0))")
            head = scalar(cur, "select version from supabase_migrations.schema_migrations order by version desc limit 1")
            if head not in {"070", "071"}:
                raise RuntimeError(f"unexpected migration ledger head: {head}")
            before = inventory(cur)
            exists = scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version=%s)", (VERSION,))
            if not exists:
                cur.execute(transaction_body(sql))
                cur.execute(
                    "insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",
                    (VERSION, [sql], NAME),
                )
                report["applied"] = True
            else:
                report["applied"] = False
        conn.commit()

        with conn.cursor() as cur:
            after = inventory(cur)
            if after != before:
                raise RuntimeError(f"migration unexpectedly changed protected inventory: {before} -> {after}")
            head = scalar(cur, "select version from supabase_migrations.schema_migrations order by version desc limit 1")
            if head != VERSION:
                raise RuntimeError(f"unexpected post-migration ledger head: {head}")
            cur.execute("select auth_user_id::text,email from public.pdc_user_roles where role='administrator' and active and account_status='approved' and auth_user_id is not null order by email limit 1")
            admin = cur.fetchone()
            if not admin:
                raise RuntimeError("no approved Administrator available for snapshot verification")
            claims = json.dumps({"sub": admin[0], "email": admin[1], "role": "authenticated"})
            cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))
            result = scalar(cur, "select public.get_pdc_ai_intake_snapshot('all',150)")
            if not result.get("ok"):
                raise RuntimeError(f"snapshot verification failed: {result}")
            items = result.get("data", {}).get("items", [])
            if not all("change_events" in item and "board_activation_created" in item for item in items):
                raise RuntimeError("snapshot is missing human change evidence")
            report.update({
                "ledger_head": head,
                "inventory": after,
                "items_checked": len(items),
                "items_with_change_events": sum(bool(item.get("change_events")) for item in items),
                "navision_revision": result.get("data", {}).get("navision_revision"),
                "ok": True,
            })
        conn.rollback()
        print(json.dumps(report, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
