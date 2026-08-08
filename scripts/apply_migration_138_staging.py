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

EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_MIGRATION_SHA = "1a6638951e9982886afdfc47d0b4362b57a15539a1abbaddf8d37e5dcfbc21a3"
EXPECTED_RECEIPT_SHA = "a46427bc6ac0df0a0bfac5b2ed48ad11fe2eb0a92a714076b61df5e27de93bdb"
MIGRATION = ROOT / "supabase" / "staging_only" / "138_correct_reset_backup_evidence_scope.sql"
RECEIPT = Path.home() / "pdc-control-board" / "_staging_backups" / "pdc_staging_pre_reset_20260808_p00H245014_763" / "data_integrity_verification" / "data_integrity_receipt.json"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(cur) -> dict:
    cur.execute("select count(*) from supabase_migrations.schema_migrations where version='138'")
    if cur.fetchone()[0] != 1:
        raise RuntimeError("Migration 138 ledger mismatch")
    cur.execute("""select superseded_receipt_sha256,data_integrity_receipt_sha256,exact_csv_headers_verified,
      full_schema_restore_verified,disaster_recovery_receipt,corrected_by
      from public.pdc_staging_reset_evidence_corrections""")
    row = cur.fetchone()
    expected = (
        "7f7d027f1a0da08982241b9d6f7a553b09908fed93c56f1e934e60a4cee1b439",
        EXPECTED_RECEIPT_SHA, True, False, False, "database_owner_migration_runner",
    )
    if row != expected:
        raise RuntimeError(f"Migration 138 correction mismatch: {row}")
    cur.execute("select relrowsecurity from pg_class where oid='public.pdc_staging_reset_evidence_corrections'::regclass")
    if cur.fetchone() != (True,):
        raise RuntimeError("Migration 138 RLS missing")
    cur.execute("select has_table_privilege(%s,'public.pdc_staging_reset_evidence_corrections','SELECT,INSERT,UPDATE,DELETE')", ("anon",))
    if cur.fetchone()[0]:
        raise RuntimeError("Migration 138 table privilege exposed")
    cur.execute("select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board")
    active = cur.fetchone()[0]
    cur.execute("select count(*) from public.pdc_authenticated_email_operation_lines")
    operations = cur.fetchone()[0]
    if (active, operations) != (325, 2943):
        raise RuntimeError(f"reset state drifted: active={active} operations={operations}")
    return {"ledger": 1, "correction": row, "rls": True, "active": active, "operations": operations}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--expected-commit")
    args = parser.parse_args()
    if args.apply and (not args.expected_commit or not re.fullmatch(r"[a-f0-9]{40}", args.expected_commit)):
        raise RuntimeError("--apply requires exact reviewed --expected-commit")
    if sha256_file(MIGRATION) != EXPECTED_MIGRATION_SHA:
        raise RuntimeError("Migration 138 digest mismatch")
    if not RECEIPT.is_file() or sha256_file(RECEIPT) != EXPECTED_RECEIPT_SHA:
        raise RuntimeError("data-integrity receipt digest mismatch")
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    if receipt.get("contract") != "pdc-staging-backup-data-integrity-v2" or receipt.get("full_schema_restore_verified") is not False \
       or receipt.get("disaster_recovery_receipt") is not False or receipt.get("schema_ddl_applied") is not False \
       or receipt.get("table_count") != 111 or receipt.get("restored_row_count") != 27356 \
       or receipt.get("foreign_key_violations") != 0 or receipt.get("foreign_keys_checked") != 145:
        raise RuntimeError("data-integrity receipt contract mismatch")
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    if not dsn:
        raise RuntimeError("staging database URL is not configured")
    assert_staging_target(database_url=dsn)
    if args.apply:
        actual = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
        if actual != args.expected_commit or dirty:
            raise RuntimeError("refusing Migration 138 apply from unreviewed or dirty worktree")
    with psycopg2.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            if cur.fetchone() != (EXPECTED_REF,):
                raise RuntimeError("staging sentinel mismatch")
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
            if cur.fetchone()[0]:
                raise RuntimeError("production sentinel present")
            if args.apply:
                cur.execute("select count(*) from supabase_migrations.schema_migrations where version='138'")
                if cur.fetchone()[0]:
                    raise RuntimeError("Migration 138 already applied")
                cur.execute(MIGRATION.read_text(encoding="utf-8"))
                cur.execute("insert into supabase_migrations.schema_migrations(version,name,statements) values('138','correct_reset_backup_evidence_scope',array[%s]::text[])", (MIGRATION.read_text(encoding="utf-8"),))
            result = verify(cur)
        conn.commit()
    print(json.dumps({"ok": True, "applied": args.apply, "migration_sha256": EXPECTED_MIGRATION_SHA, "receipt_sha256": EXPECTED_RECEIPT_SHA, "verification": result}, sort_keys=True, default=str))


if __name__ == "__main__":
    main()
