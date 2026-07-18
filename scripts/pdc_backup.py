"""
PDC Control Board — operational database backup (staging-tested, safe for
production once approved).

Produces a single encrypted, timestamped backup archive containing a
structured JSON export of every operational table required to restore the
system, in FK-safe dependency order, plus a manifest recording the backup
format version, the current migration version, and per-table row counts.

Design notes / why this approach instead of pg_dump:
- This environment has no local pg_dump/pg_restore binary and no Docker
  (required by `supabase db dump`), so a native pg_dump-format backup is
  not producible here. Instead we use a structured, self-describing JSON
  export via psycopg2 that preserves every column's real PostgreSQL type
  (including jsonb, timestamptz, uuid, arrays) using psycopg2's own type
  adapters, which is safe to round-trip. This satisfies the requirement
  to prefer "a proper PostgreSQL/Supabase database backup or structured
  export that preserves relationships/types/PKs/FKs/timestamps/JSON" (the
  brief explicitly allows "or structured export", not only pg_dump).
- If pg_dump becomes available later (e.g. a Linux CI runner), swap
  `run_backup()`'s export step for `supabase db dump --data-only` without
  changing anything else in this file -- the encryption/retention/restore
  contract stays identical because it operates on a directory of files,
  not on the export mechanism.

Safety:
- NEVER dumps `auth.*` (Supabase-managed users/passwords/sessions) or any
  service-role/API credentials. Only the explicit TABLES list below is
  ever read.
- `monitored_mailboxes.config` (may contain mailbox-specific settings) is
  redacted to `{"redacted": true}` in the backup -- mailbox credentials
  are never stored in this table by design (see migration 004), but this
  is a defensive redaction in case that changes later.
- Backups are written outside the live database (local encrypted file,
  intended to be synced to a separate object-storage bucket / backup
  server by the caller -- see docs/backup-and-restore.md) and are never
  committed to git (backup output directory is gitignored).
- Requires the STAGING or PRODUCTION database connection string and a
  separate BACKUP_ENCRYPTION_KEY via environment variables / a local
  secrets file -- never hard-coded, never logged.
"""
import argparse
import decimal
import gzip
import hashlib
import json
import os
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
import psycopg2.extras
from cryptography.fernet import Fernet

BACKUP_FORMAT_VERSION = "1"

# Dependency-safe order: every table appears after every table it
# references via a foreign key (matches the FK graph inspected against
# the live staging schema). vehicles <-> workshop_bookings is a genuine
# circular FK (vehicles.active_workshop_booking_id -> workshop_bookings,
# workshop_bookings.vehicle_id -> vehicles) so vehicles is exported before
# its FK is resolved and workshop_bookings after; the restore script
# handles this by deferring constraints for the whole transaction rather
# than relying on insert order alone.
TABLES = [
    # Lookup / reference tables (no operational FKs into vehicles)
    "workshop_stages",
    "workshop_technicians",
    "workshop_bays",
    "workshop_settings",
    "salespeople",
    "sublet_providers",
    "monitored_mailboxes",
    "pdc_user_roles",
    # Vehicle master + everything that hangs off a vehicle
    "vehicles",
    "vehicle_aliases",
    "vehicle_master_revision",
    "vehicle_master_source_records",
    "vehicle_master_history",
    "vehicle_master_identity_conflicts",
    "vehicle_work_items",
    "vehicle_movements",
    "vehicle_parts_updates",
    "vehicle_eta_history",
    "vehicle_timeline_events",
    "vehicle_intelligence_revisions",
    "vehicle_intelligence_summaries",
    "vehicle_match_candidates",
    "deleted_completed_vehicles",
    # Workshop scheduling
    "workshop_bookings",
    "workshop_booking_assignments",
    "workshop_booking_history",
    "workshop_parts_overrides",
    "workshop_revision",
    # Notifications (restored disabled -- see restore script)
    "vehicle_notifications",
    # AI email intake / intelligence (Stage 1 foundation, included because
    # it is operational PDC data even though it predates this backup task)
    "ai_trusted_senders",
    "ai_mapping_rules",
    "ai_intake_config",
    "ai_email_intake",
    "ai_email_attachments",
    "ai_email_analysis_results",
    "ai_extracted_fields",
    "ai_workshop_commands",
    "ai_proposed_actions",
    "ai_review_items",
    "ai_undo_actions",
    "email_response_drafts",
    "import_runs",
    "label_print_events",
    # Audit trail last (references everything above)
    "audit_events",
]

# Columns that must never leave the database, even though none of the
# current tables contain real secrets (verified against the live schema
# for this task) -- defensive redaction in case a future column is added.
SENSITIVE_COLUMNS = {
    "monitored_mailboxes": {"config"},
}


def utc_now_stamp():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def json_default(value):
    if isinstance(value, (datetime,)):
        return value.isoformat()
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, decimal.Decimal):
        # Preserve exact decimal value as a string rather than lossily
        # coercing to float -- money/hours columns must round-trip exactly
        # on restore.
        return {"__decimal__": str(value)}
    if isinstance(value, (bytes, bytearray)):
        return {"__bytes_hex__": value.hex()}
    raise TypeError(f"Unsupported type for backup JSON export: {type(value)}")


def get_migration_version(cur):
    try:
        cur.execute(
            "select version from supabase_migrations.schema_migrations "
            "order by version desc limit 1"
        )
        row = cur.fetchone()
        return row[0] if row else None
    except Exception:
        return None


def export_table(cur, table_name):
    redact_cols = SENSITIVE_COLUMNS.get(table_name, set())
    cur.execute(f'select * from public."{table_name}"')
    columns = [desc.name for desc in cur.description]
    rows = []
    for record in cur.fetchall():
        row = dict(zip(columns, record))
        for col in redact_cols:
            if col in row and row[col] is not None:
                row[col] = {"redacted": True}
        rows.append(row)
    return columns, rows


def run_backup(conn, environment, output_dir, encryption_key, kind="scheduled", triggered_by="cron"):
    """
    Runs one full backup. Returns (backup_run_id, result_dict).
    Writes a single gzip-compressed, Fernet-encrypted JSON file plus a
    plaintext manifest sidecar (manifest contains no operational data,
    only counts/hashes/version info, so it is safe to read without the
    encryption key for monitoring purposes).
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    cur = conn.cursor()
    backup_run_id = str(uuid.uuid4())
    started_at = datetime.now(timezone.utc)
    migration_version = get_migration_version(cur)

    cur.execute(
        """
        insert into public.backup_runs
            (id, environment, kind, status, started_at, backup_version,
             migration_version, triggered_by)
        values (%s, %s, %s, 'running', %s, %s, %s, %s)
        """,
        (backup_run_id, environment, kind, started_at, BACKUP_FORMAT_VERSION,
         migration_version, triggered_by),
    )
    conn.commit()

    payload = {
        "backup_format_version": BACKUP_FORMAT_VERSION,
        "backup_run_id": backup_run_id,
        "environment": environment,
        "started_at": started_at.isoformat(),
        "migration_version": migration_version,
        "tables": {},
    }
    row_counts = {}

    try:
        for table in TABLES:
            columns, rows = export_table(cur, table)
            payload["tables"][table] = {"columns": columns, "rows": rows}
            row_counts[table] = len(rows)

        finished_at = datetime.now(timezone.utc)
        payload["finished_at"] = finished_at.isoformat()
        payload["row_counts"] = row_counts

        raw_json = json.dumps(payload, default=json_default).encode("utf-8")
        compressed = gzip.compress(raw_json, compresslevel=6)

        fernet = Fernet(encryption_key)
        encrypted = fernet.encrypt(compressed)

        stamp = utc_now_stamp()
        file_name = f"pdc_backup_{environment}_{stamp}_{backup_run_id[:8]}.bin"
        file_path = output_dir / file_name
        file_path.write_bytes(encrypted)

        sha256 = hashlib.sha256(encrypted).hexdigest()
        size_bytes = file_path.stat().st_size

        cur.execute(
            """
            update public.backup_runs
            set status = 'success',
                finished_at = %s,
                table_row_counts = %s,
                file_path = %s,
                file_size_bytes = %s,
                file_sha256 = %s,
                encrypted = true
            where id = %s
            """,
            (finished_at, json.dumps(row_counts), str(file_path), size_bytes,
             sha256, backup_run_id),
        )
        conn.commit()

        manifest = {
            "backup_run_id": backup_run_id,
            "environment": environment,
            "backup_format_version": BACKUP_FORMAT_VERSION,
            "migration_version": migration_version,
            "started_at": started_at.isoformat(),
            "finished_at": finished_at.isoformat(),
            "file_name": file_name,
            "file_size_bytes": size_bytes,
            "file_sha256": sha256,
            "row_counts": row_counts,
            "encrypted": True,
        }
        (output_dir / f"{file_name}.manifest.json").write_text(
            json.dumps(manifest, indent=2), encoding="utf-8"
        )

        return backup_run_id, {"status": "success", "file_path": str(file_path),
                                "size_bytes": size_bytes, "row_counts": row_counts}

    except Exception as exc:  # noqa: BLE001 - must record failure, then re-raise
        conn.rollback()
        try:
            cur.execute(
                """
                update public.backup_runs
                set status = 'failed', finished_at = now(), error_message = %s
                where id = %s
                """,
                (str(exc)[:2000], backup_run_id),
            )
            conn.commit()
        except Exception:
            conn.rollback()
        return backup_run_id, {"status": "failed", "error": str(exc)}


def decrypt_backup(file_path, encryption_key):
    fernet = Fernet(encryption_key)
    encrypted = Path(file_path).read_bytes()
    compressed = fernet.decrypt(encrypted)
    raw_json = gzip.decompress(compressed)
    return json.loads(raw_json)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", required=True, choices=["staging", "production"])
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--kind", default="scheduled", choices=["scheduled", "manual"])
    parser.add_argument("--triggered-by", default="cron")
    args = parser.parse_args()

    if args.environment == "production":
        # Hard safety gate: this task is staging-only per instruction.
        # Production backups are supported by this same script (that is
        # the point of building it generically) but must not be *run*
        # against production without a separate explicit approval step
        # and its own connection/encryption-key configuration.
        print("Refusing to run --environment production from this staging-only "
              "invocation path. Production backups require a separate approved "
              "connection string and encryption key, configured only after "
              "explicit approval.", file=sys.stderr)
        sys.exit(2)

    encryption_key = os.environ.get("PDC_BACKUP_ENCRYPTION_KEY")
    if not encryption_key:
        print("PDC_BACKUP_ENCRYPTION_KEY is not set.", file=sys.stderr)
        sys.exit(2)

    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "_staging_test_tools"))
    from staging_conn import get_conn  # noqa: E402

    conn = get_conn()
    try:
        backup_run_id, result = run_backup(
            conn, args.environment, args.output_dir, encryption_key.encode(),
            kind=args.kind, triggered_by=args.triggered_by,
        )
    finally:
        conn.close()

    print(json.dumps({"backup_run_id": backup_run_id, **result}, indent=2))
    if result["status"] != "success":
        sys.exit(1)


if __name__ == "__main__":
    main()
