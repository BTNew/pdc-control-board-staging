from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path.home() / "pdc-control-board" / "_staging_test_tools"
sys.path.insert(0, str(TOOLS))
from staging_env import assert_staging_target, load_local_env  # noqa: E402

MIGRATION = ROOT / "supabase" / "staging_only" / "132_stock_only_authenticated_email_batch_fanout.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
SIGNATURE = "public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb)"


def state(cur) -> dict:
    cur.execute("""
      select
        (select count(*) from public.vehicles),
        (select count(*) from public.navision_board_activations),
        (select count(*) from public.workshop_bookings),
        (select count(*) from public.vehicle_work_items),
        (select revision from public.navision_backend_revision where singleton),
        (select count(*) from public.navision_backend_audit),
        (select count(*) from public.pdc_authenticated_email_batch_receipts)
    """)
    row = cur.fetchone()
    return dict(zip(("vehicles", "activations", "bookings", "work_items", "navision_revision", "navision_audit", "batch_receipts"), row))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    sql = MIGRATION.read_text(encoding="utf-8")
    sha = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    conn = psycopg.connect(dsn)
    try:
        with conn.cursor() as cur:
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            if cur.fetchone()[0] != EXPECTED_REF:
                raise RuntimeError("wrong staging project")
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
            if cur.fetchone()[0]:
                raise RuntimeError("production sentinel present")
            cur.execute("select exists(select 1 from supabase_migrations.schema_migrations where version='131'),exists(select 1 from supabase_migrations.schema_migrations where version='132'),has_function_privilege('authenticated',%s,'EXECUTE')", (SIGNATURE,))
            predecessor, installed, executable = cur.fetchone()
            if not predecessor:
                raise RuntimeError("Migration 131 is required")
            if installed:
                raise RuntimeError("Migration 132 is already installed")
            if executable:
                raise RuntimeError("disabled Migration 130 RPC unexpectedly has execute authority")
            before = state(cur)
            rehearsal = sql.replace("begin;", "", 1).rsplit("commit;", 1)[0]
            cur.execute(rehearsal)
            during = state(cur)
            if during != before:
                raise RuntimeError(f"structural rehearsal changed operational rows: {before} -> {during}")
            conn.rollback()
        if not args.apply:
            print(json.dumps({"ok": True, "mode": "rehearsal", "migration": "132", "sha256": sha, "operational_counts_unchanged": True}, sort_keys=True))
            return
        with conn.cursor() as cur:
            cur.execute(sql)
        conn.commit()
        with conn.cursor() as cur:
            cur.execute("select exists(select 1 from supabase_migrations.schema_migrations where version='132' and name='stock_only_authenticated_email_batch_fanout'),has_function_privilege('authenticated',%s,'EXECUTE'),has_function_privilege('anon',%s,'EXECUTE'),has_function_privilege('service_role',%s,'EXECUTE')", (SIGNATURE, SIGNATURE, SIGNATURE))
            ledger, auth_exec, anon_exec, service_exec = cur.fetchone()
            after = state(cur)
            if not ledger or not auth_exec or anon_exec or service_exec or after != before:
                raise RuntimeError(f"postcheck failed: ledger={ledger}, privileges={(auth_exec, anon_exec, service_exec)}, counts={before}->{after}")
        conn.rollback()
        print(json.dumps({"ok": True, "mode": "apply", "migration": "132", "sha256": sha, "authenticated_execute": True, "anon_execute": False, "service_role_execute": False, "operational_counts_unchanged": True}, sort_keys=True))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
