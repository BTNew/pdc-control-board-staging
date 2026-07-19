"""Generate exact C6 46-table staging evidence from the retained encrypted backup fixtures."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import pdc_restore
import stage2b_c6_full_schema_verify as full
import stage2b_c6_operational_rehearsal as c6


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fixture(path: Path) -> dict:
    manifest_path = Path(str(path) + ".manifest.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    actual_sha = sha256_file(path)
    if manifest.get("environment") != "staging" or manifest.get("file_sha256") != actual_sha:
        raise c6.C6PilotRefusal("backup fixture manifest/environment mismatch")
    if len(manifest.get("row_counts", {})) != 46 or manifest.get("not_present_tables"):
        raise c6.C6PilotRefusal("backup fixture is not the complete 46-table staging inventory")
    return {
        "file_name": path.name,
        "file_size_bytes": path.stat().st_size,
        "file_sha256": actual_sha,
        "manifest_file_name": manifest_path.name,
        "manifest_sha256": sha256_file(manifest_path),
        "backup_run_id": manifest["backup_run_id"],
        "migration_version": manifest["migration_version"],
        "table_count": len(manifest["row_counts"]),
    }


def cleanup(conn, schema: str) -> None:
    conn.rollback()
    cur = conn.cursor()
    cur.execute(f'drop schema if exists "{schema}" cascade')
    conn.commit()


def sanitized_restore_report(report: dict) -> dict:
    return {
        "all_checks_passed": report.get("all_checks_passed"),
        "backup_environment": report.get("backup_environment"),
        "backup_run_id": report.get("backup_run_id"),
        "migration_version": report.get("migration_version"),
        "row_count_mismatches": report.get("row_count_mismatches"),
        "foreign_keys_discovered": report.get("foreign_keys_discovered"),
        "foreign_keys_added": report.get("foreign_keys_added"),
        "foreign_keys_skipped": report.get("foreign_keys_skipped"),
        "validated_table_count": report.get("validated_table_count"),
        "checks": report.get("checks"),
        "temporary_schema_removed": True,
    }


def run(pre_backup: Path, rollback_backup: Path, output_dir: Path) -> dict:
    if c6.STAGING_REF != "cdsmnqxtyyoeoznmbidd":
        raise c6.C6PilotRefusal("unexpected staging project constant")
    key = os.environ["PDC_BACKUP_ENCRYPTION_KEY"].encode("utf-8")
    conn = c6._connect_guarded(os.environ.get("PDC_STAGING_DATABASE_URL", ""))
    output_dir.mkdir(parents=True, exist_ok=True)
    pre_schema = "c6_full_audit_" + secrets.token_hex(4)
    rollback_schema = "c6_full_rollback_audit_" + secrets.token_hex(4)
    try:
        pre_restore = pdc_restore.restore_backup(conn, str(pre_backup), key, pre_schema)
        if not pre_restore.get("all_checks_passed"):
            raise c6.C6PilotRefusal("pre-rehearsal 46-table restore failed")
        unrelated = full.compare_public(
            conn, pre_schema, output_dir / "full-schema-unrelated-row-protection.json"
        )
        cleanup(conn, pre_schema)

        rollback_restore = pdc_restore.restore_backup(conn, str(rollback_backup), key, rollback_schema)
        if not rollback_restore.get("all_checks_passed"):
            raise c6.C6PilotRefusal("rollback 46-table restore failed")
        rollback = full.rollback(
            conn, rollback_schema, output_dir / "full-schema-rollback-verification.json"
        )
        cleanup(conn, rollback_schema)
    finally:
        try:
            cleanup(conn, pre_schema)
            cleanup(conn, rollback_schema)
        finally:
            conn.close()

    report = {
        "schema": "pdc.stage2b.c6-full-schema-live-run/v1",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "exact_staging_project_ref": c6.STAGING_REF,
        "pre_rehearsal_fixture": fixture(pre_backup),
        "rollback_fixture": fixture(rollback_backup),
        "pre_rehearsal_restore": sanitized_restore_report(pre_restore),
        "rollback_restore": sanitized_restore_report(rollback_restore),
        "unrelated_table_count": unrelated["table_count"],
        "unrelated_rows_equal": unrelated["all_unrelated_full_row_hashes_unchanged"],
        "rollback_table_count": rollback["table_count"],
        "rollback_unrelated_rows_equal": rollback["all_unrelated_full_row_hashes_unchanged"],
        "rollback_schema_objects_equal": rollback["schema_objects_equal_and_unchanged"],
        "foreign_keys_validated": rollback["foreign_keys_validated"],
        "dual_revision_refusal": (
            rollback["vehicle_master_independent_advance_test"]["saved_rollback_refused_after_advance"]
            and rollback["resolver_independent_advance_test"]["saved_rollback_refused_after_advance"]
        ),
        "temporary_schemas_removed": True,
        "all_checks_passed": (
            unrelated["all_checks_passed"]
            and rollback["all_checks_passed"]
            and rollback["foreign_keys_validated"] == 72
        ),
    }
    (output_dir / "full-schema-live-run.json").write_text(c6.canonical_json(report) + "\n", encoding="utf-8")
    if not report["all_checks_passed"]:
        raise c6.C6PilotRefusal("full-schema live evidence failed")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pre-rehearsal-backup", required=True, type=Path)
    parser.add_argument("--rollback-backup", required=True, type=Path)
    parser.add_argument("--output-dir", default=ROOT / "review-evidence" / "stage2b-c6", type=Path)
    args = parser.parse_args()
    report = run(args.pre_rehearsal_backup, args.rollback_backup, args.output_dir)
    print(c6.canonical_json({
        "table_count": report["rollback_table_count"],
        "unrelated_rows_equal": report["unrelated_rows_equal"],
        "rollback_rows_equal": report["rollback_unrelated_rows_equal"],
        "foreign_keys_validated": report["foreign_keys_validated"],
        "temporary_schemas_removed": report["temporary_schemas_removed"],
        "all_checks_passed": report["all_checks_passed"],
    }))


if __name__ == "__main__":
    main()
