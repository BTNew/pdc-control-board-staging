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

MIGRATION = ROOT / "supabase" / "staging_only" / "134_navision_preserve_deleted_canonical_identity.sql"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_SHA = "d33c9969a1a10b870f528ef246a00852d95905a44a8bd9df4657029b3d335382"
WRAPPER = "public.reconcile_navision_operational_record(uuid,uuid,text)"
RETAINED = "public.reconcile_navision_operational_record_pre134(uuid,uuid,text)"


def scalar(cur, sql, params=()):
    cur.execute(sql, params)
    return cur.fetchone()[0]


def migration_body(source: str) -> str:
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("Migration 134 transaction wrapper missing")
    return source[begin.end() : commits[-1].start()]


def operational_state(cur):
    tables = (
        "vehicles",
        "vehicle_work_items",
        "workshop_bookings",
        "vehicle_parts_updates",
        "vehicle_movements",
        "vehicle_notifications",
        "navision_board_activations",
        "navision_backend_audit",
        "audit_events",
    )
    result = {table: scalar(cur, f"select count(*) from public.{table}") for table in tables}
    result["navision_revision"] = scalar(
        cur, "select revision from public.navision_backend_revision where singleton"
    )
    result["email_revision"] = scalar(
        cur, "select revision from public.pdc_email_vehicle_revision where singleton"
    )
    return result


def verify_install(cur):
    ledger = scalar(
        cur,
        "select count(*) from supabase_migrations.schema_migrations "
        "where version='134' and name='navision_preserve_deleted_canonical_identity'",
    )
    wrapper_exists = scalar(cur, "select to_regprocedure(%s) is not null", (WRAPPER,))
    retained_exists = scalar(cur, "select to_regprocedure(%s) is not null", (RETAINED,))
    wrapper_acl = {
        role: scalar(cur, "select has_function_privilege(%s,%s,'EXECUTE')", (role, WRAPPER))
        for role in ("public", "anon", "authenticated")
    }
    retained_acl = {
        role: scalar(cur, "select has_function_privilege(%s,%s,'EXECUTE')", (role, RETAINED))
        for role in ("public", "anon", "authenticated")
    }
    wrapper_source = scalar(
        cur,
        "select pg_get_functiondef(%s::regprocedure)",
        (WRAPPER,),
    )
    trigger_count = scalar(
        cur,
        """select count(*) from pg_trigger t
        where not t.tgisinternal and t.tgname in (
          'navision_record_operational_reconcile','navision_activation_operational_reconcile'
        ) and t.tgfoid='public.trigger_reconcile_navision_operational_record()'::regprocedure""",
    )
    wrapper_source_lower = wrapper_source.lower()
    source_has_code = "historical_vehicle_retained" in wrapper_source_lower
    source_has_deleted_guard = "deleted_at is not null" in wrapper_source_lower
    ok = (
        ledger == 1
        and wrapper_exists
        and retained_exists
        and not any(wrapper_acl.values())
        and not any(retained_acl.values())
        and source_has_code
        and source_has_deleted_guard
        and trigger_count == 2
    )
    return ok, {
        "ledger": ledger,
        "wrapper_exists": wrapper_exists,
        "retained_exists": retained_exists,
        "wrapper_acl": wrapper_acl,
        "retained_acl": retained_acl,
        "source_has_code": source_has_code,
        "source_has_deleted_guard": source_has_deleted_guard,
        "trigger_count": trigger_count,
    }


def risky_records(cur):
    cur.execute(
        """
        select r.id,r.dealer_code
        from public.navision_backend_records r
        join public.navision_board_activations a on a.backend_record_id=r.id and a.active
        where r.is_current and r.record_status='current'
          and exists(
            select 1 from public.vehicles v
            where v.deleted_at is not null and (
              v.id=r.canonical_vehicle_id
              or v.stock_number_normalized=public.normalize_vehicle_stock_number(r.normalized_data->>'batch')
              or (
                public.is_valid_vehicle_vin(r.normalized_data->>'vin')
                and v.vin_normalized=public.normalize_vehicle_vin(r.normalized_data->>'vin')
              )
            )
          )
        order by r.dealer_code,r.id
        """
    )
    return [(row[0], row[1]) for row in cur.fetchall()]


def exercise_fix(cur):
    records = risky_records(cur)
    scopes = {dealer for _, dealer in records}
    if not records or not {"14450", "37047"}.issubset(scopes):
        raise RuntimeError(f"expected historical collision fixtures in both scopes, found {sorted(scopes)}")
    before = operational_state(cur)
    responses = []
    for record_id, dealer in records:
        response = scalar(
            cur,
            "select public.reconcile_navision_operational_record(%s,null,'migration-134-rollback-proof')",
            (record_id,),
        )
        if (
            not response.get("ok")
            or response.get("code") != "historical_vehicle_retained"
            or response.get("data", {}).get("operational_change") is not False
        ):
            raise RuntimeError(f"historical identity was not retained for dealer {dealer}: {response}")
        cur.execute(
            "update public.navision_backend_records set normalized_data=normalized_data where id=%s",
            (record_id,),
        )
        responses.append({"dealer": dealer, "code": response.get("code")})
    after = operational_state(cur)
    if after != before:
        raise RuntimeError(f"historical reconciliation changed operational state: {before} -> {after}")
    return responses


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    args = parser.parse_args()
    if args.apply and (
        not args.expected_commit or not re.fullmatch(r"[a-f0-9]{40}", args.expected_commit)
    ):
        raise RuntimeError("--apply requires exact reviewed --expected-commit")

    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get(
        "PDC_STAGING_DATABASE_URL"
    )
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)

    raw = MIGRATION.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    if sha != EXPECTED_SHA:
        raise RuntimeError(f"Migration 134 digest mismatch: {sha}")
    source = raw.decode("utf-8")

    if args.apply:
        actual = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "status", "--porcelain", "--untracked-files=all"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if actual != args.expected_commit:
            raise RuntimeError(f"reviewed commit mismatch: {actual}")
        if dirty:
            raise RuntimeError("refusing Migration 134 apply from dirty worktree")

    with psycopg2.connect(dsn) as conn:
        try:
            with conn.cursor() as cur:
                if scalar(
                    cur,
                    "select project_ref from public.pdc_staging_environment_sentinel where singleton",
                ) != EXPECTED_REF or scalar(
                    cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"
                ):
                    raise RuntimeError("staging sentinel mismatch")
                if not scalar(
                    cur,
                    "select exists(select 1 from supabase_migrations.schema_migrations "
                    "where version='133' and name='close_email_receipt_table_direct_authority')",
                ) or scalar(
                    cur,
                    "select exists(select 1 from supabase_migrations.schema_migrations where version='134')",
                ):
                    raise RuntimeError("unexpected 133/134 ledger pre-state")
                before = operational_state(cur)
                cur.execute(migration_body(source))
                ok, details = verify_install(cur)
                if not ok:
                    raise RuntimeError(f"Migration 134 postcheck failed: {details}")
                responses = exercise_fix(cur)
                after = operational_state(cur)
                if before != after:
                    raise RuntimeError("Migration 134 changed operational counts or revisions")
                if not args.apply:
                    conn.rollback()
                    with conn.cursor() as check:
                        if operational_state(check) != before or scalar(
                            check,
                            "select exists(select 1 from supabase_migrations.schema_migrations where version='134')",
                        ):
                            raise RuntimeError("Migration 134 rehearsal rollback leaked state")
                    print(
                        json.dumps(
                            {
                                "ok": True,
                                "migration": "134",
                                "mode": "rehearsal",
                                "sha256": sha,
                                "historical_records_exercised": responses,
                                "operational_counts_and_revisions_unchanged": True,
                                "rollback_restored": True,
                            },
                            sort_keys=True,
                        )
                    )
                    return
                conn.commit()
            with conn.cursor() as cur:
                ok, details = verify_install(cur)
                if not ok:
                    raise RuntimeError(f"Migration 134 persisted postcheck failed: {details}")
            print(
                json.dumps(
                    {
                        "ok": True,
                        "migration": "134",
                        "mode": "apply",
                        "sha256": sha,
                        "historical_records_exercised": responses,
                        "operational_counts_and_revisions_unchanged": True,
                    },
                    sort_keys=True,
                )
            )
        except Exception:
            conn.rollback()
            raise


if __name__ == "__main__":
    main()
