#!/usr/bin/env python3
"""Rehearse or apply staging-only Migration 130 with structural safety gates."""
from __future__ import annotations
import argparse, hashlib, json, os, sys
from pathlib import Path
import psycopg

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, r"C:\Users\nwmgr\pdc-control-board\_staging_test_tools")
from staging_env import assert_staging_target, load_local_env  # noqa: E402

MIGRATION = ROOT / "supabase" / "staging_only" / "130_authenticated_email_backend_batch_fanout.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
SIGNATURE = "public.import_pdc_authenticated_backend_batches(text,text,text,text,text,jsonb,timestamp with time zone,text,jsonb)"


def scalar(cur, sql, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Commit Migration 130 to staging; default is rollback rehearsal")
    args = parser.parse_args()
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    sql = MIGRATION.read_text(encoding="utf-8")
    if EXPECTED_REF not in sql or "pdc_production_environment_sentinel" not in sql:
        raise RuntimeError("staging guard missing")
    sha = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    conn = psycopg.connect(dsn)
    try:
        with conn.cursor() as cur:
            pre = {
                "database": scalar(cur, "select current_database()"),
                "staging_ref": scalar(cur, "select project_ref from public.pdc_staging_environment_sentinel where singleton"),
                "production_sentinel": scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"),
                "migration_129": scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='129' and name='bulk_stock_only_vehicle_privacy_guard')"),
                "migration_130": scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='130')"),
                "vehicles": scalar(cur, "select count(*) from public.vehicles"),
                "activations": scalar(cur, "select count(*) from public.navision_board_activations"),
            }
        conn.rollback()
        if pre["database"] != "postgres" or pre["staging_ref"] != EXPECTED_REF or pre["production_sentinel"] or not pre["migration_129"]:
            raise RuntimeError(f"staging preflight failed: {pre}")
        if pre["migration_130"]:
            raise RuntimeError("Migration 130 is already installed")

        execution_sql = sql if args.apply else sql.rsplit("commit;", 1)[0] + "rollback;\n"
        with conn.cursor() as cur:
            cur.execute(execution_sql)
        conn.commit()

        with conn.cursor() as cur:
            post = {
                "migration_130": scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='130')"),
                "function_present": scalar(cur, "select to_regprocedure(%s) is not null", (SIGNATURE,)),
                "receipt_table_present": scalar(cur, "select to_regclass('public.pdc_authenticated_email_batch_receipts') is not null"),
                "execute_authenticated": scalar(cur, "select has_function_privilege('authenticated',%s,'EXECUTE')", (SIGNATURE,)) if args.apply else False,
                "execute_anon": scalar(cur, "select has_function_privilege('anon',%s,'EXECUTE')", (SIGNATURE,)) if args.apply else False,
                "receipt_rls": scalar(cur, "select relrowsecurity from pg_class where oid='public.pdc_authenticated_email_batch_receipts'::regclass") if args.apply else False,
                "vehicles": scalar(cur, "select count(*) from public.vehicles"),
                "activations": scalar(cur, "select count(*) from public.navision_board_activations"),
            }
        conn.rollback()
        if args.apply:
            expected = post["migration_130"] and post["function_present"] and post["receipt_table_present"] and post["execute_authenticated"] and not post["execute_anon"] and post["receipt_rls"]
        else:
            expected = not post["migration_130"] and not post["function_present"] and not post["receipt_table_present"]
        if not expected or post["vehicles"] != pre["vehicles"] or post["activations"] != pre["activations"]:
            raise RuntimeError(f"Migration 130 postcheck failed: {post}")
        print(json.dumps({"ok": True, "mode": "apply" if args.apply else "rehearsal", "sha256": sha, "pre": pre, "post": post}, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
