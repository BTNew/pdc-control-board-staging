#!/usr/bin/env python3
"""Fail-closed validation for the migration-045 staging backup/restore gate."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
from datetime import datetime, timezone
from pathlib import Path

from pdc_backup import decrypt_backup
from pdc_restore import validate_backup_contract


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _timestamp(value: str, label: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError) as exc:
        raise RuntimeError(f"Invalid {label} timestamp") from exc
    if parsed.tzinfo is None:
        raise RuntimeError(f"{label} timestamp must be timezone-aware")
    return parsed.astimezone(timezone.utc)


def validate_release_backup(
    conn,
    backup_path,
    expected_sha256,
    restore_schema,
    *,
    expected_migration="044",
    max_age_seconds=7200,
):
    """Validate encryption, payload, manifest, DB run and dropped restore proof."""
    path = Path(backup_path).resolve()
    if not path.is_file():
        raise RuntimeError("Encrypted backup file is missing")
    actual_sha = _sha256(path)
    if not hmac.compare_digest(actual_sha.lower(), str(expected_sha256).lower()):
        raise RuntimeError("Encrypted backup SHA-256 mismatch")

    key = os.environ.get("PDC_BACKUP_ENCRYPTION_KEY")
    if not key:
        raise RuntimeError("PDC_BACKUP_ENCRYPTION_KEY is required to validate the backup")
    try:
        payload = decrypt_backup(path, key.encode())
    except Exception as exc:
        raise RuntimeError("Backup decryption/authentication failed") from exc
    validate_backup_contract(payload)
    if payload.get("environment") != "staging":
        raise RuntimeError("Backup provenance is not staging")
    if str(payload.get("migration_version")) != expected_migration:
        raise RuntimeError("Backup migration version does not match the pre-apply ledger")

    now = datetime.now(timezone.utc)
    started_at = _timestamp(payload.get("started_at"), "backup started_at")
    finished_at = _timestamp(payload.get("finished_at"), "backup finished_at")
    age = (now - finished_at).total_seconds()
    if finished_at < started_at or age < 0 or age > max_age_seconds:
        raise RuntimeError(f"Backup is not fresh (age_seconds={int(age)})")

    manifest_path = Path(str(path) + ".manifest.json")
    if not manifest_path.is_file():
        raise RuntimeError("Backup manifest sidecar is missing")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    schema_hashes = {
        table: details["sha256"] for table, details in payload["schema_objects"].items()
    }
    manifest_expectations = {
        "backup_run_id": payload.get("backup_run_id"),
        "environment": "staging",
        "migration_version": expected_migration,
        "file_name": path.name,
        "file_size_bytes": path.stat().st_size,
        "file_sha256": actual_sha,
        "row_counts": payload.get("row_counts"),
        "table_hashes": payload.get("table_hashes"),
        "schema_object_hashes": schema_hashes,
        "authority_contracts": payload.get("authority_contracts", {}),
        "encrypted": True,
    }
    for key_name, expected in manifest_expectations.items():
        if manifest.get(key_name) != expected:
            raise RuntimeError(f"Backup manifest mismatch: {key_name}")

    cur = conn.cursor()
    cur.execute(
        """select environment,status,migration_version,file_size_bytes,file_sha256,encrypted,
                  started_at,finished_at
           from public.backup_runs where id=%s::uuid""",
        (payload["backup_run_id"],),
    )
    run = cur.fetchone()
    if not run:
        raise RuntimeError("Backup run provenance row is missing")
    if tuple(run[:6]) != (
        "staging", "success", expected_migration, path.stat().st_size, actual_sha, True
    ):
        raise RuntimeError("Backup run provenance row does not match the encrypted artifact")
    if run[6] is None or run[7] is None or run[7] < run[6]:
        raise RuntimeError("Backup run timing/status evidence is incomplete")

    cur.execute(
        """select status,finished_at,verification_report,row_count_matches
           from public.restore_test_runs
           where environment='staging' and target_schema=%s
             and verification_report->>'backup_run_id'=%s
           order by finished_at desc nulls last limit 1""",
        (restore_schema, payload["backup_run_id"]),
    )
    restore = cur.fetchone()
    if not restore:
        raise RuntimeError("Matching isolated restore proof is missing")
    report = restore[2] or {}
    if restore[0] != "success" or restore[1] is None or restore[3] is not True:
        raise RuntimeError("Isolated restore did not finish successfully")
    if (
        report.get("all_checks_passed") is not True
        or report.get("backup_environment") != "staging"
        or str(report.get("migration_version")) != expected_migration
        or report.get("row_count_mismatches") not in ({}, [])
        or report.get("format_evidence", {}).get("all_hashes_match") is not True
        or report.get("format_evidence", {}).get("all_schema_objects_match") is not True
        or report.get("foreign_keys_skipped") not in ({}, [])
    ):
        raise RuntimeError("Isolated restore verification report is incomplete or failed")
    if restore[1].astimezone(timezone.utc) < finished_at:
        raise RuntimeError("Isolated restore proof predates the backup")
    cur.execute("select count(*) from information_schema.schemata where schema_name=%s", (restore_schema,))
    if cur.fetchone()[0] != 0:
        raise RuntimeError("Isolated restore schema was not removed")

    return {
        "backup_run_id": payload["backup_run_id"],
        "backup_sha256": actual_sha,
        "backup_migration": expected_migration,
        "backup_finished_at": finished_at.isoformat(),
        "restore_schema": restore_schema,
        "restore_finished_at": restore[1].astimezone(timezone.utc).isoformat(),
        "restore_checks_passed": True,
        "restore_schema_removed": True,
    }
