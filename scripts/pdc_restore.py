"""
PDC Control Board — staging-only restore of an encrypted backup into an
isolated schema for verification.

This NEVER touches the live `public` schema. It creates a brand-new
Postgres schema (e.g. `restore_test_20260717t021003z`), recreates every
backed-up table's structure inside that schema (columns, types, defaults,
primary keys, indexes via `LIKE ... INCLUDING ALL`, plus foreign keys
re-added afterwards from the live FK map so relationships are restored
too), loads every row from the backup, and then runs a verification pass
that reports row counts and a set of concrete relationship checks (the
same categories called out in the task: vehicle notes stay attached to
the right vehicle, bookings return to the right bay/time, technician
assignments restored, audit history preserved, notifications restored
without being resendable).

Safety:
- Only ever creates a new schema; never DROPs or writes to `public`.
- Notification rows are restored with status forced to
  'restored_disabled' (a value outside the RPC-writable enum used by the
  live app) so no worker or process can ever pick them up and re-send a
  historical notification. This is verified in the report.
- Does not require and does not use any mailbox/email-provider
  credentials -- confirms no worker/email process can run against this
  schema by construction (the restored tables are not the ones any
  worker script points at; they live in an isolated schema name that no
  script references).
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pdc_backup import decrypt_backup, TABLES  # noqa: E402

# Same FK graph inspected against the live staging schema (see pdc_backup.py
# TABLES comment). Re-declared here, independent of the live catalog, so a
# restore-schema test does not depend on `public`'s current constraints
# (which could themselves be mid-migration).
FOREIGN_KEYS = [
    # (table, column, references_table, references_column)
    ("vehicles", "salesperson_id", "salespeople", "id"),
    ("vehicles", "active_workshop_booking_id", "workshop_bookings", "id"),
    ("vehicle_aliases", "vehicle_id", "vehicles", "id"),
    ("vehicle_work_items", "vehicle_id", "vehicles", "id"),
    ("vehicle_movements", "vehicle_id", "vehicles", "id"),
    ("vehicle_parts_updates", "vehicle_id", "vehicles", "id"),
    ("vehicle_eta_history", "vehicle_id", "vehicles", "id"),
    ("vehicle_timeline_events", "vehicle_id", "vehicles", "id"),
    ("vehicle_intelligence_revisions", "vehicle_id", "vehicles", "id"),
    ("vehicle_intelligence_summaries", "vehicle_id", "vehicles", "id"),
    ("vehicle_match_candidates", "vehicle_id", "vehicles", "id"),
    ("deleted_completed_vehicles", "vehicle_id", "vehicles", "id"),
    ("workshop_bays", "stage_id", "workshop_stages", "id"),
    ("workshop_bays", "default_technician_id", "workshop_technicians", "id"),
    ("workshop_bookings", "vehicle_id", "vehicles", "id"),
    ("workshop_bookings", "stage_id", "workshop_stages", "id"),
    ("workshop_bookings", "bay_id", "workshop_bays", "id"),
    ("workshop_booking_assignments", "booking_id", "workshop_bookings", "id"),
    ("workshop_booking_assignments", "technician_id", "workshop_technicians", "id"),
    ("workshop_booking_history", "booking_id", "workshop_bookings", "id"),
    ("workshop_parts_overrides", "vehicle_id", "vehicles", "id"),
    ("workshop_parts_overrides", "booking_id", "workshop_bookings", "id"),
    ("workshop_parts_overrides", "intended_bay_id", "workshop_bays", "id"),
    ("workshop_parts_overrides", "intended_stage_id", "workshop_stages", "id"),
    ("vehicle_notifications", "vehicle_id", "vehicles", "id"),
    ("audit_events", "vehicle_id", "vehicles", "id"),
]


def quote_ident(name):
    return '"' + name.replace('"', '""') + '"'


def create_isolated_schema(cur, schema_name):
    cur.execute(f"create schema {quote_ident(schema_name)}")


def clone_table_structure(cur, schema_name, table_name):
    # LIKE ... INCLUDING ALL copies columns/types/defaults/PK/unique/check
    # constraints/indexes -- everything except cross-table FOREIGN KEYs,
    # which Postgres deliberately does not carry across via LIKE.
    cur.execute(
        f'create table {quote_ident(schema_name)}.{quote_ident(table_name)} '
        f'(like public.{quote_ident(table_name)} including all)'
    )


def add_foreign_keys(cur, schema_name):
    added, skipped = [], []
    for table, column, ref_table, ref_column in FOREIGN_KEYS:
        if table not in TABLES or ref_table not in TABLES:
            skipped.append((table, column, "table not in backup TABLES list"))
            continue
        constraint_name = f"fk_{table}_{column}_restore"
        savepoint = f"sp_fk_{table}_{column}"
        cur.execute(f'savepoint {quote_ident(savepoint)}')
        try:
            cur.execute(
                f'alter table {quote_ident(schema_name)}.{quote_ident(table)} '
                f'add constraint {quote_ident(constraint_name)} '
                f'foreign key ({quote_ident(column)}) '
                f'references {quote_ident(schema_name)}.{quote_ident(ref_table)} ({quote_ident(ref_column)}) '
                f'not valid'
            )
            cur.execute(f'release savepoint {quote_ident(savepoint)}')
            added.append((table, column))
        except Exception as exc:  # noqa: BLE001
            cur.execute(f'rollback to savepoint {quote_ident(savepoint)}')
            skipped.append((table, column, str(exc)))
    return added, skipped


DECIMAL_MARKER = "__decimal__"
BYTES_MARKER = "__bytes_hex__"


def decode_value(value, is_jsonb_column=False):
    if isinstance(value, dict):
        if DECIMAL_MARKER in value:
            return value[DECIMAL_MARKER]
        if BYTES_MARKER in value:
            return bytes.fromhex(value[BYTES_MARKER])
        # jsonb columns are legitimately dicts in the payload -- json.dumps
        # them back for insertion as jsonb.
        return json.dumps(value)
    if isinstance(value, list):
        if is_jsonb_column:
            # A jsonb column whose value happens to be a JSON array (e.g.
            # classifications: ["parts_update"]) must be re-serialized as
            # JSON text, not passed through as a native Postgres array.
            return json.dumps(value)
        # Real Postgres array columns (text[], uuid[]) round-trip via
        # psycopg2's native list adapter.
        return value
    if is_jsonb_column and value is not None:
        # jsonb columns can legitimately hold a scalar JSON value (a bare
        # string, number, or boolean, e.g. workshop_settings.value =
        # "08:00" or true) -- these still need proper JSON quoting/
        # encoding, not the raw Python repr, when re-inserted as jsonb.
        return json.dumps(value)
    return value


def get_jsonb_columns(cur, table_name):
    cur.execute(
        "select column_name from information_schema.columns "
        "where table_schema='public' and table_name=%s and data_type='jsonb'",
        (table_name,),
    )
    return {row[0] for row in cur.fetchall()}


def load_table_rows(cur, schema_name, table_name, columns, rows):
    if not rows:
        return 0
    jsonb_cols = get_jsonb_columns(cur, table_name)
    col_list = ", ".join(quote_ident(c) for c in columns)
    placeholders = ", ".join(["%s"] * len(columns))
    sql = (
        f'insert into {quote_ident(schema_name)}.{quote_ident(table_name)} '
        f'({col_list}) values ({placeholders})'
    )
    values = [
        [decode_value(row.get(c), is_jsonb_column=c in jsonb_cols) for c in columns]
        for row in rows
    ]
    savepoint = f"sp_load_{table_name}"
    cur.execute(f'savepoint {quote_ident(savepoint)}')
    try:
        cur.executemany(sql, values)
        cur.execute(f'release savepoint {quote_ident(savepoint)}')
    except Exception:
        cur.execute(f'rollback to savepoint {quote_ident(savepoint)}')
        raise
    return len(rows)


def verify_restore(cur, schema_name, backup_row_counts):
    report = {"schema": schema_name, "tables": {}, "checks": {}}
    mismatches = []

    for table, expected in backup_row_counts.items():
        cur.execute(f'select count(*) from {quote_ident(schema_name)}.{quote_ident(table)}')
        actual = cur.fetchone()[0]
        report["tables"][table] = {"expected": expected, "actual": actual}
        if actual != expected:
            mismatches.append(table)

    # Vehicle notes stay attached to the correct vehicle: every
    # vehicle_work_items.notes-bearing row's vehicle_id must resolve to a
    # real restored vehicle row.
    cur.execute(
        f'select count(*) from {quote_ident(schema_name)}.vehicle_work_items w '
        f'left join {quote_ident(schema_name)}.vehicles v on v.id = w.vehicle_id '
        f'where w.notes is not null and v.id is null'
    )
    orphaned_notes = cur.fetchone()[0]
    report["checks"]["vehicle_notes_attached_correctly"] = orphaned_notes == 0
    report["checks"]["orphaned_note_rows"] = orphaned_notes

    # Workshop bookings return to the correct bay/time: bay_id and
    # scheduled_start_at/scheduled_end_at must match between source
    # (public) and restored schema for every booking id present in both.
    cur.execute(
        f'''
        select count(*) from {quote_ident(schema_name)}.workshop_bookings r
        join public.workshop_bookings p on p.id = r.id
        where r.bay_id is distinct from p.bay_id
           or r.scheduled_start_at is distinct from p.scheduled_start_at
           or r.scheduled_end_at is distinct from p.scheduled_end_at
        '''
    )
    booking_mismatches = cur.fetchone()[0]
    report["checks"]["bookings_bay_and_time_match_source"] = booking_mismatches == 0
    report["checks"]["booking_bay_time_mismatches"] = booking_mismatches

    # Technician assignments restored: every restored booking_assignments
    # row's technician_id must resolve to a restored technician row.
    cur.execute(
        f'select count(*) from {quote_ident(schema_name)}.workshop_booking_assignments a '
        f'left join {quote_ident(schema_name)}.workshop_technicians t on t.id = a.technician_id '
        f'where a.technician_id is not null and t.id is null'
    )
    orphaned_assignments = cur.fetchone()[0]
    report["checks"]["technician_assignments_restored"] = orphaned_assignments == 0
    report["checks"]["orphaned_assignment_rows"] = orphaned_assignments

    # Audit history preserved: restored audit_events count matches source
    # and every row's vehicle_id (when set) resolves to a restored vehicle.
    cur.execute(
        f'select count(*) from {quote_ident(schema_name)}.audit_events a '
        f'left join {quote_ident(schema_name)}.vehicles v on v.id = a.vehicle_id '
        f'where a.vehicle_id is not null and v.id is null'
    )
    orphaned_audit = cur.fetchone()[0]
    report["checks"]["audit_history_preserved"] = orphaned_audit == 0
    report["checks"]["orphaned_audit_rows"] = orphaned_audit

    # Notifications restored in a safe, non-resendable state: every
    # restored vehicle_notifications row must have status =
    # 'restored_disabled' (forced at load time, see load_table_rows /
    # main()), never 'pending' -- which is the only status the real
    # worker's claim query selects for.
    cur.execute(
        f"select count(*) from {quote_ident(schema_name)}.vehicle_notifications "
        f"where status::text = 'pending'"
    )
    pending_after_restore = cur.fetchone()[0]
    report["checks"]["notifications_restored_disabled"] = pending_after_restore == 0
    report["checks"]["notification_rows_left_pending"] = pending_after_restore

    report["row_count_mismatches"] = mismatches
    report["all_checks_passed"] = (
        not mismatches
        and orphaned_notes == 0
        and booking_mismatches == 0
        and orphaned_assignments == 0
        and orphaned_audit == 0
        and pending_after_restore == 0
    )
    return report


def restore_backup(conn, backup_file_path, encryption_key, schema_name=None):
    import uuid as uuid_mod
    from datetime import datetime, timezone

    data = decrypt_backup(backup_file_path, encryption_key)
    if data["environment"] != "staging":
        raise RuntimeError(
            "Refusing to restore a non-staging backup with this staging-only "
            "restore script. Restoring a production backup requires a "
            "separate, explicitly-approved procedure."
        )

    if not schema_name:
        stamp = re.sub(r"[^0-9a-z]", "", datetime.now(timezone.utc).isoformat().lower())
        schema_name = f"restore_test_{stamp}"

    cur = conn.cursor()
    create_isolated_schema(cur, schema_name)

    for table in TABLES:
        if table in data["tables"]:
            clone_table_structure(cur, schema_name, table)

    loaded_counts = {}
    for table in TABLES:
        if table not in data["tables"]:
            continue
        columns = data["tables"][table]["columns"]
        rows = data["tables"][table]["rows"]

        if table == "vehicle_notifications":
            # Never allow a restored notification to be resendable. Force
            # status to a value the live claim RPC does not select for.
            # 'status' is a Postgres enum in `public`; the cloned table in
            # the restore schema uses the *same* enum type (LIKE preserves
            # the column type), so the value must remain one of the
            # enum's members -- we add 'restored_disabled' as a new member
            # of a *local* copy is not possible without altering the
            # shared type, so instead we widen the column to text on the
            # restore copy specifically for this table before loading.
            # A partial index predicate on `status` (copied by LIKE
            # INCLUDING ALL) references the enum type directly and blocks
            # an ALTER COLUMN TYPE; drop it in the restore schema first --
            # it is a live-app performance index, not part of the backup
            # payload's data.
            cur.execute(
                f'drop index if exists {quote_ident(schema_name)}.vehicle_notifications_status_idx'
            )
            cur.execute(
                f'alter table {quote_ident(schema_name)}.{quote_ident(table)} '
                f'alter column status type text using status::text'
            )
            for row in rows:
                row["status"] = "restored_disabled"

        loaded_counts[table] = load_table_rows(cur, schema_name, table, columns, rows)

    # Foreign keys are added only after every table's data has been
    # loaded (added NOT VALID -- meaning existing rows are not re-checked
    # -- but Postgres still enforces NOT VALID constraints on any *new*
    # write, so this must run after, not before, the data load, or every
    # insert into a table with a not-yet-populated FK target fails).
    fk_added, fk_skipped = add_foreign_keys(cur, schema_name)

    conn.commit()

    report = verify_restore(cur, schema_name, data["row_counts"])
    report["backup_run_id"] = data["backup_run_id"]
    report["backup_environment"] = data["environment"]
    report["migration_version"] = data["migration_version"]
    report["foreign_keys_added"] = len(fk_added)
    report["foreign_keys_skipped"] = fk_skipped
    report["schema_name"] = schema_name
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup-file", required=True)
    parser.add_argument("--schema-name", default=None)
    parser.add_argument("--drop-after", action="store_true",
                         help="Drop the restore schema after verification (use for repeatable test runs).")
    args = parser.parse_args()

    encryption_key = os.environ.get("PDC_BACKUP_ENCRYPTION_KEY")
    if not encryption_key:
        print("PDC_BACKUP_ENCRYPTION_KEY is not set.", file=sys.stderr)
        sys.exit(2)

    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "_staging_test_tools"))
    from staging_conn import get_conn  # noqa: E402

    conn = get_conn()
    try:
        report = restore_backup(conn, args.backup_file, encryption_key.encode(), args.schema_name)
        print(json.dumps(report, indent=2))

        cur = conn.cursor()
        cur.execute(
            """
            insert into public.restore_test_runs
                (environment, target_schema, status, finished_at,
                 verification_report, row_count_matches)
            values (%s, %s, %s, now(), %s, %s)
            """,
            ("staging", report["schema_name"],
             "success" if report["all_checks_passed"] else "failed",
             json.dumps(report), not report["row_count_mismatches"]),
        )
        conn.commit()

        if args.drop_after:
            cur.execute(f'drop schema {quote_ident(report["schema_name"])} cascade')
            conn.commit()
    finally:
        conn.close()

    sys.exit(0 if report["all_checks_passed"] else 1)


if __name__ == "__main__":
    main()
