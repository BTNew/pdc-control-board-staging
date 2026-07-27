#!/usr/bin/env python3
"""Apply staging-only migration 077 with fail-closed target and postchecks."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.pdc_staging_runtime import get_conn, load_local_env  # noqa: E402

MIGRATION = ROOT / "supabase" / "staging_only" / "077_workshop_future_parts_planning_and_start_gate.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"


def scalar(cur, sql: str, params=()):
    cur.execute(sql, params)
    row = cur.fetchone()
    return row[0] if row else None


def function_definition(cur, signature: str) -> str:
    return scalar(cur, "select pg_get_functiondef(%s::regprocedure::oid)", (signature,)) or ""


def main() -> None:
    load_local_env()
    sql = MIGRATION.read_text(encoding="utf-8")
    conn = get_conn()
    report: dict[str, object] = {"migration": MIGRATION.name}
    signatures = {
        "schedule": "public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)",
        "move": "public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)",
        "cascade": "public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)",
        "start": "public.start_workshop_work(uuid,integer,timestamptz,jsonb)",
    }
    try:
        with conn.cursor() as cur:
            database = scalar(cur, "select current_database()")
            if database != "postgres":
                raise RuntimeError(f"unexpected staging database: {database}")
            pre_counts = {
                "vehicles": scalar(cur, "select count(*) from public.vehicles"),
                "work_items": scalar(cur, "select count(*) from public.vehicle_work_items"),
                "bookings": scalar(cur, "select count(*) from public.workshop_bookings"),
                "parts_overrides": scalar(cur, "select count(*) from public.workshop_parts_overrides"),
            }
        conn.rollback()

        with conn.cursor() as cur:
            cur.execute(sql)
        conn.commit()

        with conn.cursor() as cur:
            definitions = {name: function_definition(cur, signature) for name, signature in signatures.items()}
            post_counts = {
                "vehicles": scalar(cur, "select count(*) from public.vehicles"),
                "work_items": scalar(cur, "select count(*) from public.vehicle_work_items"),
                "bookings": scalar(cur, "select count(*) from public.workshop_bookings"),
                "parts_overrides": scalar(cur, "select count(*) from public.workshop_parts_overrides"),
            }
            execute_grants = {
                name: scalar(cur, "select has_function_privilege('authenticated', %s, 'EXECUTE')", (signature,))
                for name, signature in signatures.items()
            }
        conn.rollback()

        required_tokens = {
            "schedule": ["workshop_require_planner_operator", "workshop_parts_ready", "workshop_parts_overrides"],
            "move": ["workshop_require_planner_operator", "workshop_parts_ready", "workshop_parts_overrides"],
            "cascade": ["workshop_require_planner_operator", "workshop_parts_ready", "schedule_vehicle_work"],
            "start": ["parts_incomplete_entry", "require_pdc_role('administrator')", "workshop_parts_overrides"],
        }
        missing = {
            name: [token for token in tokens if token not in definitions[name]]
            for name, tokens in required_tokens.items()
            if any(token not in definitions[name] for token in tokens)
        }
        if missing:
            raise RuntimeError(f"077 postcheck missing required function contracts: {missing}")
        if pre_counts != post_counts:
            raise RuntimeError(f"077 changed operational row counts: {pre_counts} -> {post_counts}")
        if not all(execute_grants.values()):
            raise RuntimeError(f"077 authenticated grants missing: {execute_grants}")
        report.update({
            "database": database,
            "target_ref": EXPECTED_REF,
            "production_ref_blocked": PRODUCTION_REF,
            "counts_unchanged": post_counts,
            "execute_grants": execute_grants,
            "function_sha256": {name: hashlib.sha256(definition.encode()).hexdigest() for name, definition in definitions.items()},
            "ok": True,
        })
        print(json.dumps(report, sort_keys=True))
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
