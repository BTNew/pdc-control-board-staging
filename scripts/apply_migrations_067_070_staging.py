#!/usr/bin/env python3
"""Reconcile 066 and atomically apply staging-only migrations 067-070."""
from __future__ import annotations

import json
import os
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = [
    ("066", "pdc_authenticated_email_canonical_import", "066_pdc_authenticated_email_canonical_import.sql"),
    ("067", "pdc_email_vehicle_navision_reconciliation", "067_pdc_email_vehicle_navision_reconciliation.sql"),
    ("068", "pdc_email_work_station_queues", "068_pdc_email_work_station_queues.sql"),
    ("069", "pit_inspection_planner_removal_qc_rft_gate", "069_pit_inspection_planner_removal_qc_rft_gate.sql"),
    ("070", "vehicle_locations_pit_qc_signoff_rft", "070_vehicle_locations_pit_qc_signoff_rft.sql"),
]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"


def scalar(cur, sql: str, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def migration_sql(filename: str) -> str:
    return (ROOT / "supabase" / "staging_only" / filename).read_text(encoding="utf-8")


def transaction_body(sql: str) -> str:
    lines = sql.splitlines()
    begin_at = next((i for i, line in enumerate(lines) if line.strip().lower() == "begin;"), None)
    commit_at = next((i for i in range(len(lines) - 1, -1, -1) if lines[i].strip().lower() == "commit;"), None)
    if begin_at is None or commit_at is None or commit_at <= begin_at:
        raise RuntimeError("migration must contain one outer BEGIN/COMMIT pair")
    return "\n".join(lines[:begin_at] + lines[begin_at + 1 : commit_at] + lines[commit_at + 1 :])


def verify_066(cur) -> dict[str, bool]:
    checks = {
        "receipt_table": scalar(cur, "select to_regclass('public.pdc_authenticated_email_import_receipts') is not null"),
        "revision_table": scalar(cur, "select to_regclass('public.pdc_email_vehicle_revision') is not null"),
        "import_rpc": scalar(cur, "select to_regprocedure('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)') is not null"),
        "snapshot_rpc": scalar(cur, "select to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') is not null"),
        "receipt_rls": scalar(cur, "select coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.pdc_authenticated_email_import_receipts')),false)"),
        "revision_rls": scalar(cur, "select coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.pdc_email_vehicle_revision')),false)"),
        "revision_policy": scalar(cur, "select exists(select 1 from pg_policies where schemaname='public' and tablename='pdc_email_vehicle_revision' and policyname='pdc_email_vehicle_revision_staff_read')"),
        "import_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)','EXECUTE')"),
        "snapshot_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')"),
        "realtime_revision": scalar(cur, "select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_email_vehicle_revision')"),
    }
    missing = sorted(key for key, value in checks.items() if value is not True)
    if missing:
        raise RuntimeError(f"cannot reconcile migration 066; missing structural evidence: {missing}")
    return checks


def record_ledger(cur, version: str, name: str, sql: str) -> None:
    cur.execute(
        "insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",
        (version, [sql], name),
    )


def main() -> None:
    url = os.environ.get("PDC_STAGING_DATABASE_URL")
    if not url:
        raise RuntimeError("PDC_STAGING_DATABASE_URL is required")
    conn = psycopg2.connect(url, connect_timeout=15, application_name="pdc_staging_migrations_067_070")
    report: dict[str, object] = {"applied": [], "already_recorded": []}
    try:
        with conn.cursor() as cur:
            if scalar(cur, "select current_database()") != "postgres":
                raise RuntimeError("unexpected staging database")
            if not scalar(cur, "select exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref=%s)", (EXPECTED_REF,)):
                raise RuntimeError("PDC_STAGING_SENTINEL_MISMATCH")
            scalar(cur, "select pg_advisory_xact_lock(hashtextextended('pdc-staging-migrations-066-070',0))")
            latest = scalar(cur, "select version from supabase_migrations.schema_migrations order by version desc limit 1")
            if latest not in {"065", "066", "067", "068", "069", "070"}:
                raise RuntimeError(f"unexpected migration ledger head: {latest}")
            before = {
                "vehicles": scalar(cur, "select count(*) from public.vehicles"),
                "work_items": scalar(cur, "select count(*) from public.vehicle_work_items"),
                "bookings": scalar(cur, "select count(*) from public.workshop_bookings"),
            }
        conn.rollback()

        for version, name, filename in MIGRATIONS:
            sql = migration_sql(filename)
            if EXPECTED_REF not in sql:
                raise RuntimeError(f"{filename} is missing the exact staging guard")
            with conn.cursor() as cur:
                exists = scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version=%s)", (version,))
                if exists:
                    report["already_recorded"].append(version)
                    conn.rollback()
                    continue
                if version == "066":
                    report["reconciled_066"] = verify_066(cur)
                else:
                    cur.execute(transaction_body(sql))
                record_ledger(cur, version, name, sql)
            conn.commit()
            report["applied"].append(version)

        with conn.cursor() as cur:
            after = {
                "vehicles": scalar(cur, "select count(*) from public.vehicles"),
                "work_items": scalar(cur, "select count(*) from public.vehicle_work_items"),
                "bookings": scalar(cur, "select count(*) from public.workshop_bookings"),
            }
            if after != before:
                raise RuntimeError(f"migration unexpectedly changed protected inventory: {before} -> {after}")
            post = {
                "ledger_head": scalar(cur, "select version from supabase_migrations.schema_migrations order by version desc limit 1"),
                "pit_planner_disabled": scalar(cur, "select exists(select 1 from public.workshop_stages where code='PIT_INSPECTION' and not planner_enabled)"),
                "active_pit_bookings": scalar(cur, "select count(*) from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id where s.code='PIT_INSPECTION' and b.deleted_at is null and b.status not in('completed','cancelled')"),
                "qc_gate_rpc": scalar(cur, "select to_regprocedure('public.pdc_qc_gate_issues(uuid)') is not null"),
                "pit_transfer_rpc": scalar(cur, "select to_regprocedure('public.pit_transfer_vehicle(uuid,integer,text)') is not null"),
                "qc_to_rft_rpc": scalar(cur, "select to_regprocedure('public.qc_signoff_to_rft(uuid,integer,text,text)') is not null"),
                "pit_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.pit_transfer_vehicle(uuid,integer,text)','EXECUTE')"),
                "qc_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.qc_signoff_to_rft(uuid,integer,text,text)','EXECUTE')"),
            }
        conn.rollback()
        missing = sorted(key for key, value in post.items() if key not in {"ledger_head", "active_pit_bookings"} and value is not True)
        if post["ledger_head"] != "070" or post["active_pit_bookings"] != 0 or missing:
            raise RuntimeError(f"postcheck failed: {post}; missing={missing}")
        report["inventory"] = after
        report["postcheck"] = post
        report["ok"] = True
        print(json.dumps(report, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
