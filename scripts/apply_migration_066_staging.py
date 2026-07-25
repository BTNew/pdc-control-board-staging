#!/usr/bin/env python3
"""Apply staging-only migration 066 with preflight and structural postchecks."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / "_staging_test_tools")]

from staging_env import load_local_env  # noqa: E402
from staging_conn import get_conn  # noqa: E402

MIGRATION = ROOT / "supabase" / "staging_only" / "066_pdc_authenticated_email_canonical_import.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"


def scalar(cur, sql: str, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def main() -> None:
    load_local_env()
    sql = MIGRATION.read_text(encoding="utf-8")
    if EXPECTED_REF not in sql:
        raise RuntimeError("migration staging guard is missing")

    conn = get_conn()
    report: dict[str, object] = {"migration": MIGRATION.name}
    try:
        with conn.cursor() as cur:
            database = scalar(cur, "select current_database()")
            if database != "postgres":
                raise RuntimeError(f"unexpected staging database: {database}")
            report["database"] = database
            report["preflight"] = {
                "vehicles": scalar(cur, "select count(*) from public.vehicles"),
                "work_items": scalar(cur, "select count(*) from public.vehicle_work_items"),
                "bookings": scalar(cur, "select count(*) from public.workshop_bookings"),
                "pending_ai_intake": scalar(cur, "select count(*) from public.pdc_ai_intake_proposals where status='pending'"),
                "import_function_present": scalar(cur, "select to_regprocedure('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)') is not null"),
            }
        conn.rollback()

        with conn.cursor() as cur:
            cur.execute(sql)
        conn.commit()

        with conn.cursor() as cur:
            post = {
                "import_function_present": scalar(cur, "select to_regprocedure('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)') is not null"),
                "snapshot_function_present": scalar(cur, "select to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') is not null"),
                "receipt_table_present": scalar(cur, "select to_regclass('public.pdc_authenticated_email_import_receipts') is not null"),
                "revision_table_present": scalar(cur, "select to_regclass('public.pdc_email_vehicle_revision') is not null"),
                "receipt_rls": scalar(cur, "select relrowsecurity from pg_class where oid='public.pdc_authenticated_email_import_receipts'::regclass"),
                "revision_rls": scalar(cur, "select relrowsecurity from pg_class where oid='public.pdc_email_vehicle_revision'::regclass"),
                "import_execute_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb,jsonb)','EXECUTE')"),
                "snapshot_execute_authenticated": scalar(cur, "select has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')"),
                "submit_execute_authenticated_preserved": scalar(cur, "select has_function_privilege('authenticated','public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamp with time zone,text,text,text,text,jsonb)','EXECUTE')"),
                "realtime_revision_published": scalar(cur, "select exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='pdc_email_vehicle_revision')"),
                "vehicles": scalar(cur, "select count(*) from public.vehicles"),
                "work_items": scalar(cur, "select count(*) from public.vehicle_work_items"),
                "bookings": scalar(cur, "select count(*) from public.workshop_bookings"),
            }
        conn.rollback()
        required_true = (
            "import_function_present", "snapshot_function_present", "receipt_table_present",
            "revision_table_present", "receipt_rls", "revision_rls",
            "import_execute_authenticated", "snapshot_execute_authenticated",
            "submit_execute_authenticated_preserved", "realtime_revision_published",
        )
        missing = [key for key in required_true if post.get(key) is not True]
        if missing:
            raise RuntimeError(f"066 postcheck failed: {missing}")
        pre = report["preflight"]
        for key in ("vehicles", "work_items", "bookings"):
            if post[key] != pre[key]:
                raise RuntimeError(f"migration unexpectedly changed {key}: {pre[key]} -> {post[key]}")
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
