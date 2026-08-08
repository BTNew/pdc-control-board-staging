#!/usr/bin/env python3
"""Preview/apply staging migration 140 with source, backup and environment guards."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys

import psycopg2

MIGRATION = Path(__file__).with_name("140_sublet_return_calendar_and_workshop_availability.sql")
EXPECTED_SQL_SHA256 = "26aa53ed08f72d1a10e46ffedbdd49cfc00d24b7374774e05e9bc60608ad524c"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
PREDECESSOR = ("139", "navision_from_twa_it_parity")
TARGET = ("140", "sublet_return_calendar_and_workshop_availability")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=MIGRATION.parents[2], text=True).strip()


def guarded_sql() -> str:
    text = MIGRATION.read_text(encoding="utf-8")
    lines = text.splitlines()
    if "begin;" not in [line.strip().lower() for line in lines] or lines[-1].strip().lower() != "commit;":
        raise RuntimeError("migration transaction wrapper missing")
    start = next(i for i, line in enumerate(lines) if line.strip().lower() == "begin;")
    return "\n".join(lines[start + 1 : -1])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preview", "apply"))
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--backup", required=True, type=Path)
    parser.add_argument("--backup-sha256", required=True)
    args = parser.parse_args()

    actual_sql_sha = sha256(MIGRATION)
    if actual_sql_sha != EXPECTED_SQL_SHA256:
        raise RuntimeError(f"migration digest mismatch: {actual_sql_sha}")
    if not args.backup.is_file() or sha256(args.backup) != args.backup_sha256.lower():
        raise RuntimeError("verified backup artifact mismatch")
    head = git("rev-parse", "HEAD")
    if head != args.expected_commit:
        raise RuntimeError(f"unexpected source commit: {head}")
    if git("status", "--porcelain"):
        raise RuntimeError("source worktree is not clean")

    database_url = os.environ.get("PDC_STAGING_DATABASE_URL", "").strip()
    if not database_url:
        raise RuntimeError("PDC_STAGING_DATABASE_URL is required")

    connection = psycopg2.connect(database_url)
    connection.set_session(isolation_level="SERIALIZABLE", autocommit=False)
    cursor = connection.cursor()
    try:
        cursor.execute("select current_database(), current_user")
        database_name, database_user = cursor.fetchone()
        cursor.execute(
            "select exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref=%s), "
            "to_regclass('public.pdc_production_environment_sentinel') is null",
            (PROJECT_REF,),
        )
        staging_ok, production_absent = cursor.fetchone()
        if not staging_ok or not production_absent:
            raise RuntimeError("staging sentinel mismatch")
        cursor.execute("select version,name from supabase_migrations.schema_migrations order by version::integer desc limit 1")
        if tuple(cursor.fetchone()) != PREDECESSOR:
            raise RuntimeError("migration predecessor is not exact 139")
        cursor.execute("select count(*) from supabase_migrations.schema_migrations where version=%s", (TARGET[0],))
        if cursor.fetchone()[0] != 0:
            raise RuntimeError("migration 140 is already present")

        cursor.execute(guarded_sql())
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version='140'")
        if tuple(cursor.fetchone()) != TARGET:
            raise RuntimeError("migration 140 ledger postcondition failed")
        cursor.execute(
            "select to_regprocedure('public.pdc_sublet_away_on_date(uuid,date)') is not null, "
            "exists(select 1 from pg_trigger where tgrelid='public.workshop_bookings'::regclass and tgname='pdc_workshop_booking_sublet_away_guard'), "
            "exists(select 1 from pg_trigger where tgrelid='public.pdc_sublet_bookings'::regclass and tgname='pdc_sublet_booking_workshop_overlap_guard')"
        )
        if tuple(cursor.fetchone()) != (True, True, True):
            raise RuntimeError("migration 140 object postcondition failed")
        cursor.execute(
            "select count(*) from public.pdc_sublet_bookings s join public.workshop_bookings b on b.vehicle_id=s.vehicle_id "
            "where s.booking_date is not null and b.deleted_at is null and b.status::text in ('planned','started','stoppage') "
            "and daterange(s.booking_date,s.actual_return_date,'[)') && daterange((b.scheduled_start_at at time zone 'Australia/Perth')::date, "
            "((b.scheduled_end_at-interval '1 microsecond') at time zone 'Australia/Perth')::date+1,'[)')"
        )
        if cursor.fetchone()[0] != 0:
            raise RuntimeError("Sublet/workshop overlap postcondition failed")

        summary = {
            "mode": args.mode,
            "database": database_name,
            "database_user": database_user,
            "project_ref": PROJECT_REF,
            "source_commit": head,
            "migration_sha256": actual_sql_sha,
            "backup_sha256": args.backup_sha256.lower(),
            "target": ":".join(TARGET),
            "overlaps": 0,
        }
        if args.mode == "apply":
            connection.commit()
            summary["committed"] = True
        else:
            connection.rollback()
            summary["committed"] = False
        print(summary)
        return 0
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
