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
sys.path.insert(0, str(ROOT / "scripts"))
from staging_env import assert_staging_target, load_local_env
from verify_pdc_staging_backup_restore import BACKUP, EXPECTED_MANIFEST_SHA, EXPECTED_REF, EXPECTED_WORKBOOK_SHA, sha256_file, validate_backup

MIGRATION = ROOT / "supabase" / "staging_only" / "137_harden_reset_136_authority_and_evidence.sql"
EXPECTED_SHA = "842df2e12dd913a0e63ef8c7fc382590093e6e55a7bdbcf95a8a8fd0544fefc6"
EXPECTED_RECEIPT_SHA = "7f7d027f1a0da08982241b9d6f7a553b09908fed93c56f1e934e60a4cee1b439"
EXPECTED_EXCEPTION_SHA = "c6450f3b6a43aa05f3ef80441d8f2ece265b05a9c424eb4a834fb60a8e423c88"
VERSION = "137"
NAME = "harden_reset_136_authority_and_evidence"


def scalar(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()[0]


def migration_body(source: str) -> str:
    begin = re.search(r"(?im)^\s*begin;\s*$", source)
    commits = list(re.finditer(r"(?im)^\s*commit;\s*$", source))
    if not begin or not commits:
        raise RuntimeError("Migration 137 transaction wrapper missing")
    return source[begin.end():commits[-1].start()]


def validate_restore_receipt() -> dict:
    manifest, total_rows = validate_backup()
    receipt_path = BACKUP / "restore_verification" / "isolated_restore_receipt.json"
    checksum_path = BACKUP / "restore_verification" / "isolated_restore_receipt.sha256"
    if not receipt_path.is_file() or not checksum_path.is_file():
        raise RuntimeError("isolated restore receipt missing")
    actual_sha = sha256_file(receipt_path)
    checksum_sha = checksum_path.read_text(encoding="ascii").split()[0]
    if actual_sha != EXPECTED_RECEIPT_SHA or checksum_sha != EXPECTED_RECEIPT_SHA:
        raise RuntimeError("isolated restore receipt digest mismatch")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    expected = {
        "ok": True,
        "contract": "pdc-staging-backup-isolated-restore-v1",
        "project_ref": EXPECTED_REF,
        "manifest_sha256": EXPECTED_MANIFEST_SHA,
        "workbook_sha256": EXPECTED_WORKBOOK_SHA,
        "table_count": 111,
        "restored_row_count": 27356,
        "foreign_key_violations": 0,
        "transaction_rolled_back": True,
        "cleanup_verified": True,
        "production_changed": False,
    }
    if any(receipt.get(key) != value for key, value in expected.items()):
        raise RuntimeError("isolated restore receipt contract mismatch")
    if int(receipt.get("foreign_keys_checked") or 0) < 145 or not str(receipt.get("verified_at_utc") or "").startswith("2026-08-08T"):
        raise RuntimeError("isolated restore receipt freshness/FK evidence mismatch")
    if len(manifest["tables"]) != 111 or total_rows != 27356:
        raise RuntimeError("backup manifest inventory mismatch")
    return receipt


def table_signature(cur, table: str) -> str:
    return scalar(cur, f"select count(*)::text||':'||md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")


def pre_state(cur) -> dict:
    return {
        "vehicles": table_signature(cur, "vehicles"),
        "audit_events": table_signature(cur, "audit_events"),
        "qc_function": scalar(cur, "select pg_get_functiondef('public.pdc_enforce_qc_then_rft()'::regprocedure)"),
        "helper": scalar(cur, "select to_regprocedure('public.pdc_vehicle_has_current_navision_dealer_delivery(uuid)')::text"),
        "attestation_table": scalar(cur, "select to_regclass('public.pdc_staging_reset_attestations')::text"),
        "ledger": scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version='137'"),
    }


def verify(cur) -> dict:
    function_def = scalar(cur, "select pg_get_functiondef('public.pdc_enforce_qc_then_rft()'::regprocedure)").lower()
    helper_def = scalar(cur, "select pg_get_functiondef('public.pdc_vehicle_has_current_navision_dealer_delivery(uuid)'::regprocedure)").lower()
    exception_sha = scalar(cur, """select public.pdc_bulk_workbook_canonical_payload_sha256(
      coalesce(jsonb_agg(jsonb_build_object('row_no',source_row_no,'job_card_number',job_card_number,
        'stock_number',stock_number,'reason',reason,'operation_count',operation_count) order by source_row_no),'[]'::jsonb))
      from public.pdc_staging_reset_rows where not accepted""")
    counts = {
        "ledger137": scalar(cur, "select count(*) from supabase_migrations.schema_migrations where version='137' and name=%s", (NAME,)),
        "attestation": scalar(cur, "select count(*) from public.pdc_staging_reset_attestations where contract='pdc_staging_reset_hardening_137'"),
        "mutable_markers": scalar(cur, "select count(*) from public.vehicles where source_payload ? 'reset_location_authority'"),
        "reset_updated_by": scalar(cur, "select count(*) from public.vehicles where (source_payload->>'authority'='pdc_staging_workbook_reset_136' or deleted_reason='Staging clean reset 136: not in accepted workbook authority set') and updated_by is not null"),
        "active": scalar(cur, "select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board"),
        "rft": scalar(cur, "select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board and current_location='RFT'"),
        "rft_current_authority": scalar(cur, "select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board and current_location='RFT' and public.pdc_vehicle_has_current_navision_dealer_delivery(id)"),
        "correction_audit": scalar(cur, "select count(*) from public.audit_events where table_name='pdc_staging_reset_attestations' and metadata->>'source'='pdc_staging_reset_hardening_137' and metadata->>'corrects_actor_attribution'='true'"),
    }
    cur.execute("select exception_payload_sha256,claimed_backup_manifest_sha256,actual_backup_manifest_sha256,isolated_restore_receipt_sha256,execution_identity,authorization_context from public.pdc_staging_reset_attestations")
    attestation = cur.fetchone()
    expected_attestation = (
        EXPECTED_EXCEPTION_SHA,
        "b624e19411f00eabf9128ea166dd75bb3c43945a2edc9ef716419ce60b6d930a",
        EXPECTED_MANIFEST_SHA,
        EXPECTED_RECEIPT_SHA,
        "database_owner_migration_runner",
        "explicit_user_authorized_staging_reset_2026-08-08",
    )
    grants = {role: scalar(cur, "select has_function_privilege(%s,'public.pdc_vehicle_has_current_navision_dealer_delivery(uuid)','EXECUTE')", (role,)) for role in ("public", "anon", "authenticated", "service_role")}
    expected_counts = {"ledger137": 1, "attestation": 1, "mutable_markers": 0, "reset_updated_by": 0, "active": 325, "rft": 3, "rft_current_authority": 3, "correction_audit": 1}
    if counts != expected_counts:
        raise RuntimeError(f"Migration 137 count mismatch: {counts}")
    if exception_sha != EXPECTED_EXCEPTION_SHA or attestation != expected_attestation:
        raise RuntimeError("Migration 137 attestation mismatch")
    if "reset_location_authority" in function_def or "pdc_vehicle_has_current_navision_dealer_delivery" not in function_def:
        raise RuntimeError("Migration 137 QC function still trusts mutable payload")
    if "navision_backend_records" not in helper_def or "is_current" not in helper_def or "record_status" not in helper_def or "navision_operational_location" not in helper_def:
        raise RuntimeError("Migration 137 current Navision authority helper incomplete")
    if any(grants.values()):
        raise RuntimeError(f"Migration 137 helper ACL mismatch: {grants}")
    return {"counts": counts, "exception_payload_sha256": exception_sha, "attestation": attestation, "helper_private": True, "production_changed": False}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    parser.add_argument("--fault-inject-postcheck-failure", action="store_true")
    args = parser.parse_args()
    if args.apply and (not args.expected_commit or not re.fullmatch(r"[a-f0-9]{40}", args.expected_commit)):
        raise RuntimeError("--apply requires exact reviewed --expected-commit")
    receipt = validate_restore_receipt()
    raw = MIGRATION.read_bytes()
    source_sha = hashlib.sha256(raw).hexdigest()
    if source_sha != EXPECTED_SHA:
        raise RuntimeError(f"Migration 137 digest mismatch: {source_sha}")
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    if args.apply:
        actual = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        if actual != args.expected_commit:
            raise RuntimeError(f"reviewed commit mismatch: {actual}")
        if dirty:
            raise RuntimeError("refusing Migration 137 apply from dirty worktree")
    with psycopg2.connect(dsn) as conn:
        try:
            with conn.cursor() as cur:
                if scalar(cur, "select project_ref from public.pdc_staging_environment_sentinel where singleton") != EXPECTED_REF or scalar(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null"):
                    raise RuntimeError("staging sentinel mismatch")
                head = scalar(cur, "select version from supabase_migrations.schema_migrations order by version::integer desc limit 1")
                if head != "136" or scalar(cur, "select exists(select 1 from supabase_migrations.schema_migrations where version='137')"):
                    raise RuntimeError(f"unexpected Migration 137 ledger pre-state: {head}")
                before = pre_state(cur)
                cur.execute(migration_body(raw.decode("utf-8")))
                cur.execute("insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)", (VERSION, [raw.decode("utf-8")], NAME))
                outcome = verify(cur)
                if args.fault_inject_postcheck_failure:
                    raise RuntimeError("intentional Migration 137 postcheck failure before commit")
                if not args.apply:
                    conn.rollback()
                    with conn.cursor() as check:
                        after = pre_state(check)
                    if after != before:
                        raise RuntimeError("Migration 137 rehearsal rollback leaked state")
                    print(json.dumps({"ok": True, "migration": VERSION, "mode": "rehearsal", "sha256": source_sha, "backup_receipt": receipt, "outcome": outcome, "rollback_restored": True, "production_changed": False}, sort_keys=True, default=str))
                    return
                conn.commit()
            with conn.cursor() as cur:
                persisted = verify(cur)
            print(json.dumps({"ok": True, "migration": VERSION, "mode": "apply", "sha256": source_sha, "backup_receipt_sha256": EXPECTED_RECEIPT_SHA, "outcome": persisted, "production_changed": False}, sort_keys=True, default=str))
        except Exception:
            conn.rollback()
            raise


if __name__ == "__main__":
    main()
