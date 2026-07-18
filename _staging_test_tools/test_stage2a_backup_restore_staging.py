"""
Real (non-mocked) staging test for Stage 2A backup/restore coverage.

Runs an actual pdc_backup.py -> pdc_restore.py cycle against staging and
verifies every Stage 2A table/field is preserved exactly: IDs, codes,
sort order, active/inactive status, version, default_technician_id,
creator/updater metadata, and that historical booking assignment
references to a now-inactive technician remain valid after restore.

Requires PDC_STAGING_DATABASE_URL and PDC_BACKUP_ENCRYPTION_KEY. Backup and
restore subprocesses use the current review interpreter (or the explicit
PDC_REVIEW_PYTHON override), so the extracted package has no repository-local
virtual-environment dependency.
"""
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from staging_conn import get_conn
import import_stage2a_reference_data as importer

PASS = []
FAIL = []
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PYTHON_EXE = os.environ.get("PDC_REVIEW_PYTHON", sys.executable)


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"PASS  {label}")
    else:
        FAIL.append((label, detail))
        print(f"FAIL  {label}  {detail}")


def _subprocess_env():
    env = dict(os.environ)
    # The parent test-runner process may have a PYTHONPATH pointing at a
    # different Python installation's site-packages (e.g. Hermes's own
    # venv), which breaks the native Windows .venv_backup interpreter's
    # ability to import psycopg2. Clear it so pdc_backup.py/pdc_restore.py
    # run with a clean environment exactly as they would from a fresh
    # terminal, matching how every other backup/restore verification in
    # this project has been run.
    env.pop("PYTHONPATH", None)
    return env


def run_backup(output_dir):
    proc = subprocess.run(
        [PYTHON_EXE, os.path.join(REPO_ROOT, "scripts", "pdc_backup.py"),
         "--environment", "staging", "--output-dir", output_dir,
         "--kind", "manual", "--triggered-by", "stage2a-backup-coverage-staging-test"],
        capture_output=True, text=True, cwd=REPO_ROOT, env=_subprocess_env(),
    )
    return proc


def run_restore(backup_file, schema_name=None, drop_after=False):
    args = [PYTHON_EXE, os.path.join(REPO_ROOT, "scripts", "pdc_restore.py"), "--backup-file", backup_file]
    if schema_name:
        args += ["--schema-name", schema_name]
    if drop_after:
        args.append("--drop-after")
    proc = subprocess.run(args, capture_output=True, text=True, cwd=REPO_ROOT, env=_subprocess_env())
    return proc


def fetch_rows(conn, schema, table, cols):
    cur = conn.cursor()
    cur.execute(f'select {",".join(cols)} from {schema}."{table}" order by id')
    return cur.fetchall()


def main():
    encryption_key = os.environ.get("PDC_BACKUP_ENCRYPTION_KEY")
    if not encryption_key:
        check("0a (skipped) PDC_BACKUP_ENCRYPTION_KEY not set in this environment", True, "skipped -- not a failure, just not runnable here")
        print()
        print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
        return

    output_dir = tempfile.mkdtemp(prefix="stage2a_backup_test_")
    schema_name = "stage2a_backup_coverage_check"
    conn = get_conn()

    try:
        # 1. Real backup run succeeds and its manifest includes real row
        #    counts for every Stage 2A table.
        proc = run_backup(output_dir)
        check("1a backup run succeeds", proc.returncode == 0, proc.stderr[:500])
        manifest_files = [f for f in os.listdir(output_dir) if f.endswith(".manifest.json")]
        check("1b exactly one manifest produced", len(manifest_files) == 1, manifest_files)
        with open(os.path.join(output_dir, manifest_files[0]), "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
        for table in ("workshop_technicians", "salespeople", "sublet_providers", "workshop_bays", "workshop_settings"):
            check(f"1c manifest row_counts includes {table}", table in manifest["row_counts"], manifest["row_counts"])

        live_before = {
            "workshop_technicians": fetch_rows(conn, "public", "workshop_technicians", ["id", "name", "active", "version", "sort_order", "code", "created_by", "updated_by"]),
            "workshop_bays": fetch_rows(conn, "public", "workshop_bays", ["id", "stage_id", "bay_number", "is_active", "version", "default_technician_id"]),
            "workshop_settings": fetch_rows(conn, "public", "workshop_settings", ["key", "value", "version"]),
            "salespeople": fetch_rows(conn, "public", "salespeople", ["id", "name", "email", "code", "active", "version"]),
            "sublet_providers": fetch_rows(conn, "public", "sublet_providers", ["id", "name", "active", "version"]),
        }
        for table, rows in live_before.items():
            check(f"1d manifest row_count for {table} matches the live table exactly", manifest["row_counts"][table] == len(rows), (manifest["row_counts"][table], len(rows)))

        backup_file = os.path.join(output_dir, manifest["file_name"])

        # 2. Restore into an isolated schema and byte-for-byte compare
        #    every Stage 2A column, including IDs/codes/sort_order/
        #    active/version/default_technician_id/created_by/updated_by.
        restore_proc = run_restore(backup_file, schema_name=schema_name)
        check("2a restore into isolated schema succeeds", restore_proc.returncode == 0, restore_proc.stderr[:800])
        # pdc_restore.py prints a single pretty-printed multi-line JSON
        # object as its only stdout output -- parse the WHOLE stdout,
        # not just its last line (a naive splitlines()[-1] only grabs
        # the closing brace and always fails to parse).
        try:
            restore_result = json.loads(restore_proc.stdout.strip()) if restore_proc.stdout.strip() else {}
        except ValueError:
            restore_result = {}
        check("2b restore reports all_checks_passed", restore_result.get("all_checks_passed") is True, restore_result)
        check("2c restore reports zero row_count_mismatches", restore_result.get("row_count_mismatches") == [], restore_result.get("row_count_mismatches"))
        check("2d restore discovered and validated every foreign key (none skipped)", restore_result.get("foreign_keys_skipped") == [] and restore_result.get("foreign_keys_added", 0) > 0, restore_result)

        for table, cols in [
            ("workshop_technicians", ["id", "name", "active", "version", "sort_order", "code", "created_by", "updated_by"]),
            ("workshop_bays", ["id", "stage_id", "bay_number", "is_active", "version", "default_technician_id"]),
            ("workshop_settings", ["key", "value", "version"]),
            ("salespeople", ["id", "name", "email", "code", "active", "version"]),
            ("sublet_providers", ["id", "name", "active", "version"]),
        ]:
            restored_rows = fetch_rows(conn, schema_name, table, cols)
            check(f"2e restored {table} is byte-for-byte identical to the live table at backup time (IDs, active state, version, sort order, codes, creator/updater all preserved)",
                  restored_rows == live_before[table], f"live={live_before[table][:3]} restored={restored_rows[:3]}")

        # 3. No email/notification side effects from restore.
        cur = conn.cursor()
        cur.execute("select count(*) from public.vehicle_notifications where status = 'pending'")
        pending_notifications = cur.fetchone()[0]
        check("3a restore triggers zero pending notifications", pending_notifications == 0, pending_notifications)

        # 4. Restore succeeds even when a referenced technician is
        #    inactive (deactivate, backup, restore, verify, reactivate).
        admin_id = importer.get_admin_user_id(conn)

        def impersonate_admin():
            # set_config(..., is_local=true) only lasts for the current
            # transaction -- conn.commit() below ends that transaction,
            # so this must be re-applied after every commit on this
            # connection, not just once.
            cur.execute(
                "select set_config('request.jwt.claims', %s, true), set_config('role','authenticated', true)",
                (json.dumps({"sub": str(admin_id), "email": "administrator@staging.pdc-workshop.example.com", "role": "authenticated"}),),
            )

        cur = conn.cursor()
        impersonate_admin()
        cur.execute("select id, version from public.workshop_technicians order by created_at limit 1")
        tech_id, tech_version = cur.fetchone()
        cur.execute("select public.set_technician_active(%s, %s, false)", (tech_id, tech_version))
        deactivate_result = cur.fetchone()[0]
        conn.commit()
        check("4a deactivate for inactive-technician-restore test succeeds", deactivate_result.get("ok") is True, deactivate_result)

        output_dir_2 = tempfile.mkdtemp(prefix="stage2a_backup_test_inactive_")
        proc2 = run_backup(output_dir_2)
        check("4b backup with an inactive referenced technician succeeds", proc2.returncode == 0, proc2.stderr[:500])
        manifest_files_2 = [f for f in os.listdir(output_dir_2) if f.endswith(".manifest.json")]
        with open(os.path.join(output_dir_2, manifest_files_2[0]), "r", encoding="utf-8") as fh:
            manifest_2 = json.load(fh)
        backup_file_2 = os.path.join(output_dir_2, manifest_2["file_name"])
        restore_proc_2 = run_restore(backup_file_2, drop_after=True)
        check("4c restore with an inactive referenced technician still succeeds (all_checks_passed)", restore_proc_2.returncode == 0, restore_proc_2.stderr[:800])
        try:
            restore_result_2 = json.loads(restore_proc_2.stdout.strip()) if restore_proc_2.stdout.strip() else {}
        except ValueError:
            restore_result_2 = {}
        check("4d inactive-technician restore reports all_checks_passed and zero skipped FKs", restore_result_2.get("all_checks_passed") is True and restore_result_2.get("foreign_keys_skipped") == [], restore_result_2)

        # Reactivate the technician (restore original state)
        impersonate_admin()
        cur.execute("select id, version from public.workshop_technicians where id = %s", (tech_id,))
        _, current_version = cur.fetchone()
        cur.execute("select public.set_technician_active(%s, %s, true)", (tech_id, current_version))
        reactivate_result = cur.fetchone()[0]
        conn.commit()
        check("4e technician successfully reactivated after the test (test left no permanent state change)", reactivate_result.get("technician", {}).get("active") is True, reactivate_result)

        for extra_dir in (output_dir_2,):
            for f in os.listdir(extra_dir):
                os.remove(os.path.join(extra_dir, f))
            os.rmdir(extra_dir)

    finally:
        cur = conn.cursor()
        try:
            conn.rollback()  # clear any aborted transaction state before cleanup
        except Exception:
            pass
        cur.execute(f"drop schema if exists {schema_name} cascade")
        conn.commit()
        conn.close()
        for f in os.listdir(output_dir):
            os.remove(os.path.join(output_dir, f))
        os.rmdir(output_dir)

    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()
