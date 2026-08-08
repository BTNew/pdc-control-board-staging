from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from decimal import Decimal
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import assert_staging_target, load_local_env

MIGRATION = ROOT / "supabase" / "staging_only" / "136_clean_workbook_board_reset.sql"
PREVIEW = ROOT / "artifacts" / "reset_136_preview.json"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_SHA = "2a6416aac34f7b01e5688d7e61a24c48ae964c85f3eaaa4d021863dbac753032"
EXPECTED_BACKUP_SHA = "b624e19411f00eabf9128ea166dd75bb3c43945a2edc9ef716419ce60b6d930a"
EXPECTED_WORKBOOK_SHA = "d89a36dce52994acf34c234a6fc988c11b3ca1aa76a11123fdbacd8d507ffaa3"
VERSION = "136"
NAME = "clean_workbook_board_reset"
OPERATIONAL_TABLES = (
    "vehicles", "vehicle_work_items", "workshop_bookings", "workshop_booking_assignments",
    "workshop_booking_history", "workshop_parts_overrides", "workshop_transition_authorizations",
    "vehicle_parts_updates", "vehicle_workshop_line_adjustments", "pdc_authenticated_email_operation_lines",
    "pdc_authenticated_email_import_receipts", "pdc_sublet_bookings", "vehicle_sublet_providers",
    "navision_board_activations", "audit_events",
)


def scalar(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()[0]


def migration_body(source: str) -> str:
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("Migration 136 transaction wrapper missing")
    return source[begin.end():commits[-1].start()]


def table_signature(cur, table: str):
    return scalar(cur, f"select count(*)::text||':'||md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")


def pre_state(cur):
    return {
        "tables": {table: table_signature(cur, table) for table in OPERATIONAL_TABLES},
        "qc_function": scalar(cur, "select pg_get_functiondef('public.pdc_enforce_qc_then_rft()'::regprocedure)"),
        "snapshot_function": scalar(cur, "select pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure)"),
        "activation_trigger": scalar(cur, "select pg_get_triggerdef(oid,true) from pg_trigger where tgrelid='public.navision_board_activations'::regclass and tgname='navision_activation_operational_reconcile'"),
        "reset_batch_table": scalar(cur, "select to_regclass('public.pdc_staging_reset_batches')::text"),
        "reset_row_table": scalar(cur, "select to_regclass('public.pdc_staging_reset_rows')::text"),
        "job_card_column": scalar(cur, "select count(*) from information_schema.columns where table_schema='public' and table_name='pdc_authenticated_email_operation_lines' and column_name='job_card_number'"),
        "ledger_136": scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version='136'"),
    }


def expected_sets(preview):
    stock_rows = {}
    operations = []
    work_items = set()
    for pair in preview["accepted_pairs"]:
        stock = pair["stock_number"]
        stock_rows[stock] = (stock, pair["location"], pair["backend_record_id"], pair["existing_vehicle_id"])
        for op in pair["operations"]:
            hours = None if op["estimated_hours"] is None else Decimal(str(op["estimated_hours"]))
            operations.append((pair["row_no"], pair["job_card_number"], stock, op["operation_no"], op["work_key"], op["description"], hours, op["estimated_hours_source"]))
            work_items.add((stock, op["work_key"]))
    return set(stock_rows.values()), sorted(operations), work_items


def verify(cur, preview, result=None):
    expected_stocks, expected_operations, expected_work = expected_sets(preview)
    ledger = scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version='136' and name=%s", (NAME,))
    cur.execute("""select public.normalize_vehicle_stock_number(v.stock_number),v.current_location,
      r.id::text,v.id::text from public.vehicles v join public.navision_backend_records r on r.canonical_vehicle_id=v.id
      where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
        and r.is_current and r.record_status='current' and r.source_system='microsoft_navision' order by 1""")
    actual_stocks = set(cur.fetchall())
    cur.execute("""select rr.source_row_no,ol.job_card_number,rr.stock_number,ol.operation_no,ol.work_key,ol.description,
      ol.estimated_hours,ol.estimated_hours_source
      from public.pdc_authenticated_email_operation_lines ol
      join public.pdc_staging_reset_rows rr on rr.source_hash=ol.source_hash and rr.accepted
      where ol.source_contract='pdc_staging_workbook_reset_136'
      order by rr.source_row_no,ol.operation_no,ol.operation_line_id""")
    actual_operations = sorted(cur.fetchall())
    cur.execute("""select public.normalize_vehicle_stock_number(v.stock_number),wi.work_key
      from public.vehicle_work_items wi join public.vehicles v on v.id=wi.vehicle_id order by 1,2""")
    actual_work = set(cur.fetchall())
    counts = {}
    for key, query in {
        "active": "select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board",
        "active_unique_stock": "select count(distinct public.normalize_vehicle_stock_number(stock_number)) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board",
        "inactive_visible": "select count(*) from public.vehicles where visible_on_board and (deleted_at is not null or lifecycle_state<>'active')",
        "operation_lines": "select count(*) from public.pdc_authenticated_email_operation_lines",
        "completed_work": "select count(*) from public.vehicle_work_items where completed",
        "bookings": "select count(*) from public.workshop_bookings",
        "parts_updates": "select count(*) from public.vehicle_parts_updates",
        "adjustments": "select count(*) from public.vehicle_workshop_line_adjustments",
        "sublets": "select count(*) from public.pdc_sublet_bookings",
        "accepted_receipts": "select count(*) from public.pdc_staging_reset_rows where accepted",
        "exception_receipts": "select count(*) from public.pdc_staging_reset_rows where not accepted",
        "reset_batches": "select count(*) from public.pdc_staging_reset_batches",
        "rft": "select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board and current_location='RFT'",
        "rft_fake_qc": "select count(*) from public.vehicles where deleted_at is null and current_location='RFT' and qc_completed_at is not null",
        "rft_authority_marker": "select count(*) from public.vehicles where deleted_at is null and current_location='RFT' and source_payload->>'reset_location_authority'='navision_delivered_dealer'",
        "active_activation": "select count(*) from public.navision_board_activations where active",
        "active_activation_mismatch": "select count(*) from public.navision_board_activations a left join public.vehicles v on v.id=a.canonical_vehicle_id where a.active and (v.id is null or v.deleted_at is not null or v.lifecycle_state<>'active' or not v.visible_on_board)",
    }.items():
        counts[key] = scalar(cur, query)
    cur.execute("select current_location,count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board group by current_location order by current_location")
    locations = dict(cur.fetchall())
    install = {
        "columns": {column: scalar(cur, "select count(*) from information_schema.columns where table_schema='public' and table_name='pdc_authenticated_email_operation_lines' and column_name=%s", (column,)) for column in ("job_card_number", "source_row_no", "source_contract")},
        "tables": {table: scalar(cur, "select to_regclass(%s)::text", ("public." + table,)) for table in ("pdc_staging_reset_batches", "pdc_staging_reset_rows")},
        "rls": {table: scalar(cur, "select relrowsecurity from pg_class where oid=(%s)::regclass", ("public." + table,)) for table in ("pdc_staging_reset_batches", "pdc_staging_reset_rows")},
        "function_private": {role: scalar(cur, "select has_function_privilege(%s,'public.apply_pdc_staging_workbook_reset_136(jsonb,text)','EXECUTE')", (role,)) for role in ("public", "anon", "authenticated", "service_role")},
        "trigger_restored": scalar(cur, "select count(*) from pg_trigger where tgrelid='public.navision_board_activations'::regclass and tgname='navision_activation_operational_reconcile' and not tgisinternal"),
        "snapshot_job_card": "'job_card_number',ol.job_card_number" in scalar(cur, "select pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure)").lower(),
        "qc_authority_narrow": "navision_delivered_dealer" in scalar(cur, "select pg_get_functiondef('public.pdc_enforce_qc_then_rft()'::regprocedure)").lower(),
    }
    if ledger != 1:
        raise RuntimeError(f"Migration 136 ledger mismatch: {ledger}")
    if actual_stocks != expected_stocks:
        raise RuntimeError(f"active stock/location/authority mismatch: expected={len(expected_stocks)} actual={len(actual_stocks)}")
    if actual_operations != expected_operations:
        raise RuntimeError(f"exact operation mismatch: expected={len(expected_operations)} actual={len(actual_operations)}")
    if actual_work != expected_work:
        raise RuntimeError(f"work-item set mismatch: expected={len(expected_work)} actual={len(actual_work)}")
    expected_counts = {"active": 325, "active_unique_stock": 325, "inactive_visible": 0, "operation_lines": 2943,
        "completed_work": 0, "bookings": 0, "parts_updates": 0, "adjustments": 0, "sublets": 0,
        "accepted_receipts": 330, "exception_receipts": 81, "reset_batches": 1, "rft": 3,
        "rft_fake_qc": 0, "rft_authority_marker": 3, "active_activation": 325, "active_activation_mismatch": 0}
    if counts != expected_counts:
        raise RuntimeError(f"postcondition counts mismatch: {counts}")
    if locations != {"IT": 72, "Other": 79, "PMB": 121, "RFT": 3, "YH": 50}:
        raise RuntimeError(f"location split mismatch: {locations}")
    if not all(value == 1 for value in install["columns"].values()) or not all(install["tables"].values()) or not all(install["rls"].values()) or any(install["function_private"].values()) or install["trigger_restored"] != 1 or not install["snapshot_job_card"] or not install["qc_authority_narrow"]:
        raise RuntimeError(f"install/ACL postcondition failed: {install}")
    if result is not None and not result.get("ok"):
        raise RuntimeError(f"apply function response failed: {result}")
    return {"counts": counts, "locations": locations, "install": install,
            "exact_stock_rows": len(actual_stocks), "exact_operation_rows": len(actual_operations), "exact_work_items": len(actual_work)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    parser.add_argument("--fault-inject-postcheck-failure", action="store_true")
    args = parser.parse_args()
    if args.apply and (not args.expected_commit or not re.fullmatch(r"[a-f0-9]{40}", args.expected_commit)):
        raise RuntimeError("--apply requires exact reviewed --expected-commit")
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    raw = MIGRATION.read_bytes()
    source_sha = hashlib.sha256(raw).hexdigest()
    if source_sha != EXPECTED_SHA:
        raise RuntimeError(f"Migration 136 digest mismatch: {source_sha}")
    preview = json.loads(PREVIEW.read_text(encoding="utf-8"))
    if preview["summary"]["workbook_sha256"] != EXPECTED_WORKBOOK_SHA:
        raise RuntimeError("workbook preview digest mismatch")
    if args.apply:
        actual = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        if actual != args.expected_commit:
            raise RuntimeError(f"reviewed commit mismatch: {actual}")
        if dirty:
            raise RuntimeError("refusing Migration 136 apply from dirty worktree")
    with psycopg2.connect(dsn) as conn:
        try:
            with conn.cursor() as cur:
                if scalar(cur, "select project_ref from public.pdc_staging_environment_sentinel where singleton") != EXPECTED_REF or scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                    raise RuntimeError("staging sentinel mismatch")
                head = scalar(cur, "select version from supabase_migrations.schema_migrations order by version::integer desc limit 1")
                if head != "135" or scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='136')"):
                    raise RuntimeError(f"unexpected Migration 136 ledger pre-state: {head}")
                before = pre_state(cur)
                cur.execute(migration_body(raw.decode("utf-8")))
                cur.execute("select public.apply_pdc_staging_workbook_reset_136(%s::jsonb,%s)", (json.dumps(preview, separators=(",", ":")), EXPECTED_BACKUP_SHA))
                result = cur.fetchone()[0]
                cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)", (VERSION, [raw.decode("utf-8")], NAME))
                outcome = verify(cur, preview, result)
                if args.fault_inject_postcheck_failure:
                    raise RuntimeError("intentional Migration 136 postcheck failure before commit")
                if not args.apply:
                    conn.rollback()
                    with conn.cursor() as check:
                        after_rollback = pre_state(check)
                    if after_rollback != before:
                        raise RuntimeError("Migration 136 rehearsal rollback leaked data or schema state")
                    print(json.dumps({"ok": True, "migration": VERSION, "mode": "rehearsal", "sha256": source_sha,
                        "result": result, "outcome": outcome, "rollback_restored": True, "production_changed": False}, sort_keys=True, default=str))
                    return
                conn.commit()
            with conn.cursor() as cur:
                persisted = verify(cur, preview)
            print(json.dumps({"ok": True, "migration": VERSION, "mode": "apply", "sha256": source_sha,
                "result": result, "outcome": persisted, "production_changed": False}, sort_keys=True, default=str))
        except Exception:
            conn.rollback()
            raise


if __name__ == "__main__":
    main()
