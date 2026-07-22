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

BACKUP_FORMAT_VERSION = "2"


def durable_replace(source, target):
    """Atomically publish one path with rename durability on this platform."""
    source = Path(source)
    target = Path(target)
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        move_file = ctypes.WinDLL("kernel32", use_last_error=True).MoveFileExW
        move_file.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD]
        move_file.restype = wintypes.BOOL
        movefile_replace_existing = 0x1
        movefile_write_through = 0x8
        if not move_file(str(source), str(target), movefile_replace_existing | movefile_write_through):
            raise ctypes.WinError(ctypes.get_last_error())
        return
    os.replace(source, target)


def fsync_directory(path):
    """Persist POSIX rename metadata; Windows uses MOVEFILE_WRITE_THROUGH."""
    if os.name == "nt":
        return
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    descriptor = os.open(Path(path), flags)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

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
    "vehicle_lifecycle_resolver_revision",
    "vehicle_master_source_records",
    "vehicle_master_operation_receipts",
    "vehicle_master_history",
    "vehicle_master_identity_conflicts",
    # Migration 037: backend-only Navision authority. These tables remain
    # separate from active operational vehicles and are backed up in full.
    "navision_backend_revision",
    "navision_import_batches",
    "navision_backend_records",
    "navision_import_items",
    "navision_operation_receipts",
    "navision_rollback_items",
    "navision_backend_audit",
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
    "workshop_station_revision",
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

NAVISION_BACKUP_TABLES = {
    "navision_backend_revision", "navision_import_batches",
    "navision_backend_records", "navision_import_items",
    "navision_operation_receipts", "navision_rollback_items",
    "navision_backend_audit",
}

AI_EMAIL_BACKUP_TABLES = {
    "ai_trusted_senders", "ai_mapping_rules", "ai_intake_config",
    "ai_email_intake", "ai_email_attachments", "ai_email_analysis_results",
    "ai_extracted_fields", "ai_workshop_commands", "ai_proposed_actions",
    "ai_review_items", "ai_undo_actions", "email_response_drafts",
    "import_runs", "label_print_events",
}

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


def migration_number(version):
    import re
    match = re.match(r"^0*(\d+)", str(version or ""))
    return int(match.group(1)) if match else 0


def export_table(cur, table_name, schema_name="public"):
    redact_cols = SENSITIVE_COLUMNS.get(table_name, set())
    cur.execute(
        "select a.attname "
        "from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=any(i.indkey) "
        "where i.indrelid=%s::regclass and i.indisprimary order by array_position(i.indkey,a.attnum)",
        (f'{schema_name}."{table_name}"',),
    )
    primary_key = [row[0] for row in cur.fetchall()]
    order_clause = " order by " + ", ".join(f'"{column}"' for column in primary_key) if primary_key else ""
    cur.execute(f'select * from "{schema_name}"."{table_name}"{order_clause}')
    columns = [desc.name for desc in cur.description]
    rows = []
    for record in cur.fetchall():
        row = dict(zip(columns, record))
        for col in redact_cols:
            if col in row and row[col] is not None:
                row[col] = {"redacted": True}
        rows.append(row)
    return columns, rows


def deterministic_table_hash(columns, rows):
    canonical_rows = []
    for row in rows:
        ordered = {column: row.get(column) for column in columns}
        canonical_rows.append(json.dumps(ordered, default=json_default, sort_keys=True, separators=(",", ":")))
    canonical_rows.sort()
    payload = ("\n".join(canonical_rows)).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def export_schema_metadata(cur, schema_name, table_names):
    """Return exact deterministic structural evidence carried inside format-v2 backups."""
    metadata = {}
    for table in table_names:
        cur.execute(
            """
            select a.attname as column_name,
                   format_type(a.atttypid, a.atttypmod) as formatted_type,
                   i.data_type, i.udt_schema, i.udt_name, i.is_nullable,
                   pg_get_expr(d.adbin, d.adrelid, true) as column_default,
                   i.is_identity, i.identity_generation,
                   i.is_generated, i.generation_expression,
                   i.collation_name, i.character_maximum_length,
                   i.numeric_precision, i.numeric_scale
            from pg_attribute a
            join pg_class t on t.oid=a.attrelid
            join pg_namespace n on n.oid=t.relnamespace
            join information_schema.columns i
              on i.table_schema=n.nspname and i.table_name=t.relname and i.column_name=a.attname
            left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
            where n.nspname=%s and t.relname=%s and a.attnum>0 and not a.attisdropped
            order by a.attnum
            """, (schema_name, table),
        )
        columns = [dict(zip([d.name for d in cur.description], row)) for row in cur.fetchall()]
        cur.execute(
            """
            select c.conname, c.contype, c.convalidated, c.condeferrable,
                   c.condeferred, pg_get_constraintdef(c.oid, true) as definition
            from pg_constraint c join pg_class t on t.oid=c.conrelid
            join pg_namespace n on n.oid=t.relnamespace
            where n.nspname=%s and t.relname=%s order by c.conname
            """, (schema_name, table),
        )
        constraints = [dict(zip([d.name for d in cur.description], row)) for row in cur.fetchall()]
        cur.execute(
            """
            select i.relname as name, x.indisunique, x.indisprimary,
                   x.indisvalid, x.indisready,
                   exists(select 1 from pg_constraint c where c.conindid=i.oid) as constraint_owned,
                   pg_get_indexdef(i.oid) as definition
            from pg_index x join pg_class t on t.oid=x.indrelid
            join pg_namespace n on n.oid=t.relnamespace
            join pg_class i on i.oid=x.indexrelid
            where n.nspname=%s and t.relname=%s order by i.relname
            """, (schema_name, table),
        )
        indexes = [dict(zip([d.name for d in cur.description], row)) for row in cur.fetchall()]
        cur.execute(
            """
            select s.sequencename as name, a.attname as column_name, s.data_type,
                   s.start_value, s.min_value, s.max_value, s.increment_by,
                   s.cycle, s.cache_size, s.last_value
            from pg_class t join pg_namespace n on n.oid=t.relnamespace
            join pg_attribute a on a.attrelid=t.oid and a.attnum>0 and not a.attisdropped
            join pg_depend dep on dep.refobjid=t.oid and dep.refobjsubid=a.attnum and dep.deptype in ('a','i')
            join pg_class seq on seq.oid=dep.objid and seq.relkind='S'
            join pg_sequences s on s.schemaname=n.nspname and s.sequencename=seq.relname
            where n.nspname=%s and t.relname=%s order by s.sequencename
            """, (schema_name, table),
        )
        sequences = [dict(zip([d.name for d in cur.description], row)) for row in cur.fetchall()]
        for sequence in sequences:
            schema_ident = '"' + schema_name.replace('"', '""') + '"'
            sequence_ident = '"' + sequence["name"].replace('"', '""') + '"'
            cur.execute(f"select last_value, is_called from {schema_ident}.{sequence_ident}")
            sequence["last_value"], sequence["is_called"] = cur.fetchone()
        structure = {"columns": columns, "constraints": constraints, "indexes": indexes, "sequences": sequences}
        metadata[table] = {
            **structure,
            "sha256": hashlib.sha256(json.dumps(structure, default=json_default, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest(),
        }
    return metadata


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
    file_path = None
    manifest_path = None
    artifact_tmp = None
    manifest_tmp = None
    publication_complete = False
    success_commit_attempted = False

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

    # Every table and every schema object must come from one MVCC snapshot.
    # This statement is deliberately the first command after the status-row
    # commit. The migration ledger is then re-read inside the same snapshot.
    cur.execute("set transaction isolation level repeatable read")
    migration_version = get_migration_version(cur)
    cur.execute(
        "update public.backup_runs set migration_version=%s where id=%s",
        (migration_version, backup_run_id),
    )

    payload = {
        "backup_format_version": BACKUP_FORMAT_VERSION,
        "backup_run_id": backup_run_id,
        "environment": environment,
        "started_at": started_at.isoformat(),
        "migration_version": migration_version,
        "tables": {},
        "table_hashes": {},
        "schema_objects": {},
    }
    row_counts = {}

    try:
        # The source tree may already know about the next additive table while
        # the required pre-migration backup is still taken at the previous
        # ledger version. Export the ordered intersection with the concrete
        # database schema; record absent inventory entries in the manifest.
        cur.execute(
            """
            select table_name
            from information_schema.tables
            where table_schema = 'public' and table_name = any(%s)
            """,
            (TABLES,),
        )
        existing_tables = {row[0] for row in cur.fetchall()}
        payload_tables = [table for table in TABLES if table in existing_tables]
        missing_tables = [table for table in TABLES if table not in existing_tables]
        payload["not_present_tables"] = missing_tables
        missing_navision = sorted(NAVISION_BACKUP_TABLES.intersection(missing_tables))
        if migration_number(migration_version) >= 37 and missing_navision:
            raise RuntimeError(
                "Migration-037 backup is incomplete; required Navision tables are missing: "
                + ", ".join(missing_navision)
            )
        missing_ai_email = sorted(AI_EMAIL_BACKUP_TABLES.intersection(missing_tables))
        if migration_number(migration_version) >= 14 and missing_ai_email:
            raise RuntimeError(
                "AI-email backup is incomplete; required dependency tables are missing: "
                + ", ".join(missing_ai_email)
            )

        for table in payload_tables:
            columns, rows = export_table(cur, table)
            payload["tables"][table] = {"columns": columns, "rows": rows}
            row_counts[table] = len(rows)
            payload["table_hashes"][table] = deterministic_table_hash(columns, rows)

        payload["schema_objects"] = export_schema_metadata(cur, "public", payload_tables)
        if set(payload["table_hashes"]) != set(payload["tables"]) or set(payload["schema_objects"]) != set(payload["tables"]):
            raise RuntimeError("Format-2 backup evidence does not cover every payload table")

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
        manifest_path = output_dir / f"{file_name}.manifest.json"
        sha256 = hashlib.sha256(encrypted).hexdigest()
        size_bytes = len(encrypted)

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
            "table_hashes": payload["table_hashes"],
            "schema_object_hashes": {
                table: details["sha256"] for table, details in payload["schema_objects"].items()
            },
            "not_present_tables": missing_tables,
            "encrypted": True,
        }
        manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")

        # Publish only complete, fsync'd files. The database is never marked
        # successful until both atomic replacements have completed.
        temp_token = uuid.uuid4().hex
        artifact_tmp = output_dir / f".{file_name}.{temp_token}.tmp"
        manifest_tmp = output_dir / f".{file_name}.manifest.{temp_token}.tmp"
        for temp_path, content in ((artifact_tmp, encrypted), (manifest_tmp, manifest_bytes)):
            with temp_path.open("xb") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
        durable_replace(artifact_tmp, file_path)
        durable_replace(manifest_tmp, manifest_path)
        fsync_directory(output_dir)
        publication_complete = True

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
        success_commit_attempted = True
        conn.commit()

        return backup_run_id, {"status": "success", "file_path": str(file_path),
                                "size_bytes": size_bytes, "row_counts": row_counts}

    except Exception as exc:  # noqa: BLE001 - failure must remain structured
        rollback_error = None
        try:
            conn.rollback()
        except Exception as rollback_exc:  # a disconnected ambiguous commit cannot roll back
            rollback_error = rollback_exc
        for temp_path in (artifact_tmp, manifest_tmp):
            if temp_path is not None:
                try:
                    temp_path.unlink(missing_ok=True)
                except OSError:
                    pass
        if not success_commit_attempted:
            for published_path in (file_path, manifest_path):
                if published_path is not None:
                    try:
                        published_path.unlink(missing_ok=True)
                    except OSError:
                        pass
        else:
            # A commit exception has an indeterminate server outcome. Keep the
            # complete artifact pair and do not overwrite a possibly-successful
            # row with a speculative failure status.
            return backup_run_id, {
                "status": "failed",
                "error": "Backup success commit outcome is unknown; complete artifact pair retained for reconciliation",
                "connection_error": str(exc),
                "rollback_error": str(rollback_error) if rollback_error is not None else None,
            }
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
            try:
                conn.rollback()
            except Exception:
                pass
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
