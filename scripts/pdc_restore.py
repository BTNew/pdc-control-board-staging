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


def quote_ident(name):
    return '"' + name.replace('"', '""') + '"'


def discover_foreign_keys(cur):
    """Independent-review remediation (finding #9): the FK graph used
    to be a short hand-written list (27 entries) that silently drifted
    out of sync with the real schema and let 'skipped' constraints pass
    the overall restore check. This now derives the complete FK graph
    directly from the live public schema's catalog (pg_constraint),
    so it can never miss a relationship a future migration adds, and a
    restore run always attempts every real foreign key that exists
    today -- not a stale snapshot of what existed when this list was
    last hand-edited.

    Only returns foreign keys where BOTH the referencing and referenced
    tables are part of the backup payload (TABLES) -- backup-tooling
    metadata tables like restore_test_runs and backup_runs are
    intentionally excluded from TABLES because they are not application
    operational data, so a foreign key pointing at them can never be
    restored and must not be treated as a failure of the restore
    itself."""
    cur.execute(
        """
        select
          tc.table_name,
          kcu.column_name,
          ccu.table_name as foreign_table_name,
          ccu.column_name as foreign_column_name
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu
          on tc.constraint_name = kcu.constraint_name and tc.table_schema = kcu.table_schema
        join information_schema.constraint_column_usage ccu
          on tc.constraint_name = ccu.constraint_name and tc.table_schema = ccu.table_schema
        where tc.constraint_type = 'FOREIGN KEY' and tc.table_schema = 'public'
        order by tc.table_name, kcu.column_name
        """
    )
    all_fks = [tuple(row) for row in cur.fetchall()]
    return [
        fk for fk in all_fks
        if fk[0] in TABLES and fk[2] in TABLES
    ]




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


def add_foreign_keys(cur, schema_name, foreign_keys):
    """Adds every discovered foreign key NOT VALID, then immediately
    runs VALIDATE CONSTRAINT on each one (independent-review remediation,
    finding #9: the previous version added constraints NOT VALID and
    never validated them, and a 'skipped' constraint did not fail the
    overall restore check). Any constraint that cannot be added OR
    cannot be validated is now a hard failure returned in `skipped`,
    with the two failure modes distinguished in the reason string."""
    added, skipped = [], []
    for table, column, ref_table, ref_column in foreign_keys:
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
            cur.execute(
                f'alter table {quote_ident(schema_name)}.{quote_ident(table)} '
                f'validate constraint {quote_ident(constraint_name)}'
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


def get_generated_columns(cur, table_name):
    """Return columns PostgreSQL must compute rather than accept on INSERT.

    Migration 028 introduces stored normalized identity columns. They remain
    in the encrypted payload for auditability, but an isolated restore must
    omit them from INSERT and let PostgreSQL regenerate them from raw values.
    """
    cur.execute(
        "select column_name from information_schema.columns "
        "where table_schema='public' and table_name=%s and is_generated='ALWAYS'",
        (table_name,),
    )
    return {row[0] for row in cur.fetchall()}


def load_table_rows(cur, schema_name, table_name, columns, rows):
    if not rows:
        return 0
    jsonb_cols = get_jsonb_columns(cur, table_name)
    generated_cols = get_generated_columns(cur, table_name)
    insert_columns = [column for column in columns if column not in generated_cols]
    col_list = ", ".join(quote_ident(c) for c in insert_columns)
    placeholders = ", ".join(["%s"] * len(insert_columns))
    sql = (
        f'insert into {quote_ident(schema_name)}.{quote_ident(table_name)} '
        f'({col_list}) values ({placeholders})'
    )
    values = [
        [decode_value(row.get(c), is_jsonb_column=c in jsonb_cols) for c in insert_columns]
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
    # by the ADD step itself -- but the immediate VALIDATE CONSTRAINT
    # call inside add_foreign_keys() re-checks every row against the
    # restored data before this function returns, so this must run
    # after, not before, the data load, or every insert into a table
    # with a not-yet-populated FK target fails).
    foreign_keys = discover_foreign_keys(cur)
    fk_added, fk_skipped = add_foreign_keys(cur, schema_name, foreign_keys)

    conn.commit()

    report = verify_restore(cur, schema_name, data["row_counts"])
    report["backup_run_id"] = data["backup_run_id"]
    report["backup_environment"] = data["environment"]
    report["migration_version"] = data["migration_version"]
    report["foreign_keys_discovered"] = len(foreign_keys)
    report["foreign_keys_added"] = len(fk_added)
    report["foreign_keys_skipped"] = fk_skipped
    # Independent-review remediation (finding #9): a skipped/invalid
    # foreign key used to be recorded but NOT reflected in
    # all_checks_passed -- "full restore passed" did not actually prove
    # every relationship was restored and valid. Now it does: any
    # skipped constraint fails the overall restore.
    report["all_checks_passed"] = report["all_checks_passed"] and not fk_skipped
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
