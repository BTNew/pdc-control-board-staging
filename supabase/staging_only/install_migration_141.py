#!/usr/bin/env python3
"""Preview/apply staging migration 141 with pinned source and recovery evidence."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import json
import os
from pathlib import Path
import subprocess

import psycopg2

MIGRATION = Path(__file__).with_name("141_sublet_queued_rebind_and_concurrency_corrections.sql")
EXPECTED_SQL_SHA256 = "39eae0c00b6e0008acdd626cf651efcced5a6e3354c7f71feccd9535404d5666"
EXPECTED_BACKUP_RECEIPT_SHA256 = "fe95c9c2740cde0295719a437c1f5be9be81107029baa596cb5130b619ac853c"
EXPECTED_SOURCE_BUNDLE_SHA256 = "785decf5a9b2b4e5c6c4ec84bae3ddd89865b543ed89c6ada9fa921924cec005"
EXPECTED_MANIFEST_SHA256 = "4b6f96416bb73794fe1a6afbacb10993df82ee0ca6386b5d9eb4aa86d02ae773"
EXPECTED_WORKBOOK_SHA256 = "d89a36dce52994acf34c234a6fc988c11b3ca1aa76a11123fdbacd8d507ffaa3"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
BRANCH = "feat/staging-sublet-return-drag-conflicts-20260808"
PREDECESSOR = ("140", "sublet_return_calendar_and_workshop_availability")
TARGET = ("141", "sublet_queued_rebind_and_concurrency_corrections")
APPLY_CONFIRMATION = "APPLY-STAGING-MIGRATION-141"
SOURCE_BUNDLE = (
    "app.js",
    "pdc-email-vehicle-location-service.js",
    "supabase/staging_only/141_sublet_queued_rebind_and_concurrency_corrections.sql",
    "scripts/verify_migration_141_backup.py",
    "test_sublet_concurrency_retry.js",
    "test_sublet_review_corrections_141.js",
)
ROOT = MIGRATION.parents[2]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_bundle_sha256() -> str:
    digest = hashlib.sha256()
    for relative in SOURCE_BUNDLE:
        path = ROOT / relative
        body = path.read_bytes()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(hashlib.sha256(body).digest())
    return digest.hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def guarded_sql() -> str:
    lines = MIGRATION.read_text(encoding="utf-8").splitlines()
    wrappers = [line.strip().lower() for line in lines]
    if "begin;" not in wrappers or wrappers[-1] != "commit;":
        raise RuntimeError("migration transaction wrapper missing")
    start = wrappers.index("begin;")
    return "\n".join(lines[start + 1 : -1])


def verify_receipt(path: Path) -> dict:
    if not path.is_file() or sha256(path) != EXPECTED_BACKUP_RECEIPT_SHA256:
        raise RuntimeError("pinned restore-verification receipt mismatch")
    receipt = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "ok": True,
        "contract": "pdc-staging-migration-141-backup-data-integrity-v1",
        "project_ref": PROJECT_REF,
        "manifest_sha256": EXPECTED_MANIFEST_SHA256,
        "workbook_sha256": EXPECTED_WORKBOOK_SHA256,
        "backupRelations": 115,
        "backupRows": 28594,
        "foreignKeysChecked": 150,
        "foreignKeyViolations": 0,
        "restoreTransactionRolledBack": True,
        "restoreSchemaCleanupVerified": True,
        "production_changed": False,
    }
    for key, value in expected.items():
        if receipt.get(key) != value:
            raise RuntimeError(f"restore-verification receipt field mismatch: {key}")
    verified = datetime.fromisoformat(str(receipt["verified_at_utc"]).replace("Z", "+00:00"))
    now = datetime.now(timezone.utc)
    if verified > now + timedelta(minutes=5) or now - verified > timedelta(hours=24):
        raise RuntimeError("restore-verification receipt is not fresh")
    backup = Path(receipt["backup_path"])
    manifest = backup / "manifest.json"
    if not manifest.is_file() or sha256(manifest) != EXPECTED_MANIFEST_SHA256:
        raise RuntimeError("receipt-bound backup manifest mismatch")
    if path.resolve().parent.parent != backup.resolve():
        raise RuntimeError("receipt is not bound to its declared backup")
    return receipt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("preview", "apply"))
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--confirm", default="")
    args = parser.parse_args()

    if sha256(MIGRATION) != EXPECTED_SQL_SHA256:
        raise RuntimeError("migration digest mismatch")
    if source_bundle_sha256() != EXPECTED_SOURCE_BUNDLE_SHA256:
        raise RuntimeError("reviewed source bundle mismatch")
    receipt = verify_receipt(args.receipt)
    if args.mode == "apply" and args.confirm != APPLY_CONFIRMATION:
        raise RuntimeError("explicit staging apply confirmation missing")

    head = git("rev-parse", "HEAD")
    if git("status", "--porcelain"):
        raise RuntimeError("source worktree is not clean")
    if git("rev-parse", "--abbrev-ref", "HEAD") != BRANCH:
        raise RuntimeError("unexpected source branch")
    remote_head = git("ls-remote", "origin", f"refs/heads/{BRANCH}").split()[0]
    if remote_head != head:
        raise RuntimeError("local/remote source commit mismatch")

    database_url = os.environ.get("PDC_STAGING_DATABASE_URL", "").strip()
    if not database_url:
        raise RuntimeError("PDC_STAGING_DATABASE_URL is required")
    connection = psycopg2.connect(database_url)
    connection.set_session(isolation_level="SERIALIZABLE", autocommit=False)
    cursor = connection.cursor()
    try:
        cursor.execute(
            "select exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref=%s), "
            "to_regclass('public.pdc_production_environment_sentinel') is null",
            (PROJECT_REF,),
        )
        if tuple(cursor.fetchone()) != (True, True):
            raise RuntimeError("staging sentinel mismatch")
        cursor.execute("select version,name from supabase_migrations.schema_migrations order by version::integer desc limit 1")
        if tuple(cursor.fetchone()) != PREDECESSOR:
            raise RuntimeError("migration predecessor is not exact 140")
        cursor.execute("select count(*) from supabase_migrations.schema_migrations where version=%s", (TARGET[0],))
        if cursor.fetchone()[0] != 0:
            raise RuntimeError("migration 141 is already present")

        cursor.execute(guarded_sql())
        cursor.execute("select version,name from supabase_migrations.schema_migrations where version='141'")
        if tuple(cursor.fetchone()) != TARGET:
            raise RuntimeError("migration 141 ledger postcondition failed")
        cursor.execute("select pg_get_functiondef('public.pdc_workshop_booking_sublet_away_guard()'::regprocedure), pg_get_functiondef('public.pdc_sublet_booking_workshop_overlap_guard()'::regprocedure), pg_get_functiondef('public.update_pdc_sublet_booking_field(uuid,bigint,text,text)'::regprocedure), pg_get_triggerdef((select oid from pg_trigger where tgrelid='public.pdc_sublet_bookings'::regclass and tgname='pdc_sublet_booking_workshop_overlap_guard' and not tgisinternal))")
        workshop_guard, reverse_guard, update_rpc, trigger_def = cursor.fetchone()
        if "'queued'" not in workshop_guard or "'queued'" not in reverse_guard or "'queued'" not in update_rpc or "UPDATE OF vehicle_id" not in trigger_def:
            raise RuntimeError("migration 141 object postcondition failed")
        cursor.execute(
            "select count(*) from public.pdc_sublet_bookings s join public.workshop_bookings b on b.vehicle_id=s.vehicle_id "
            "where s.booking_date is not null and b.deleted_at is null and b.status::text in ('queued','planned','started','stoppage') "
            "and daterange(s.booking_date,s.actual_return_date,'[)') && daterange((b.scheduled_start_at at time zone 'Australia/Perth')::date, "
            "((b.scheduled_end_at-interval '1 microsecond') at time zone 'Australia/Perth')::date+1,'[)')"
        )
        overlaps = cursor.fetchone()[0]
        if overlaps != 0:
            raise RuntimeError("active Workshop/Sublet overlap postcondition failed")

        summary = {
            "mode": args.mode,
            "project_ref": PROJECT_REF,
            "source_commit": head,
            "migration_sha256": EXPECTED_SQL_SHA256,
            "receipt_sha256": EXPECTED_BACKUP_RECEIPT_SHA256,
            "backup_manifest_sha256": receipt["manifest_sha256"],
            "target": ":".join(TARGET),
            "overlaps": overlaps,
        }
        if args.mode == "apply":
            connection.commit()
            summary["committed"] = True
        else:
            connection.rollback()
            summary["committed"] = False
        print(json.dumps(summary, sort_keys=True))
        return 0
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


if __name__ == "__main__":
    raise SystemExit(main())
