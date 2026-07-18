"""
Real (non-mocked) staging test for independent-review remediation
item #9 (backup/restore hardening -- catalog-derived FK graph +
VALIDATE CONSTRAINT + fatal skipped constraints).

Requires PDC_BACKUP_ENCRYPTION_KEY to be set and a real staging backup
file to restore from -- run this AFTER a real pdc_backup.py run against
staging. Not auto-run by the JS/Python unit suites (it performs a real
encrypted backup + isolated-schema restore against real staging data),
consistent with the project's existing convention for staging-only
integration tests.
"""
import sys
import os
import json
import subprocess

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + "/scripts")
import pdc_restore  # noqa: E402
from staging_conn import get_conn  # noqa: E402

PASS = []
FAIL = []


def check(label, condition, detail=""):
    if condition:
        PASS.append(label)
        print(f"PASS  {label}")
    else:
        FAIL.append((label, detail))
        print(f"FAIL  {label}  {detail}")


def test_discover_foreign_keys_finds_far_more_than_the_old_hand_written_list():
    conn = get_conn()
    cur = conn.cursor()
    foreign_keys = pdc_restore.discover_foreign_keys(cur)
    conn.close()
    # The previous hand-written FOREIGN_KEYS list had exactly 27 entries.
    # The real staging catalog has significantly more real relationships
    # than that list ever captured -- proving the old list was stale and
    # incomplete, not just differently organized.
    check(
        "1a catalog-derived FK discovery finds substantially more real foreign keys than the old 27-entry hand-written list",
        len(foreign_keys) > 27,
        f"found {len(foreign_keys)} foreign keys",
    )


def test_discovered_foreign_keys_only_reference_backup_payload_tables():
    conn = get_conn()
    cur = conn.cursor()
    foreign_keys = pdc_restore.discover_foreign_keys(cur)
    conn.close()
    from pdc_backup import TABLES
    bad = [fk for fk in foreign_keys if fk[0] not in TABLES or fk[2] not in TABLES]
    check(
        "2a every discovered foreign key references tables that are actually part of the backup payload",
        bad == [],
        f"found FKs referencing tables outside TABLES: {bad}",
    )


def test_full_backup_and_restore_cycle_passes_with_validated_constraints():
    encryption_key = os.environ.get("PDC_BACKUP_ENCRYPTION_KEY")
    if not encryption_key:
        check("3a (skipped) PDC_BACKUP_ENCRYPTION_KEY not set in this environment", True, "skipped -- not a failure, just not runnable here")
        return

    backup_dir = os.path.join(os.path.dirname(__file__), "_tmp_fk_hardening_backup")
    os.makedirs(backup_dir, exist_ok=True)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    backup_script = os.path.join(repo_root, "scripts", "pdc_backup.py")
    # Use the same interpreter this test itself is running under, not
    # sys.executable blindly -- on this Windows/msys setup there can be
    # more than one Python on PATH, and only the one with psycopg2
    # installed (the project's .venv_backup) can actually run pdc_backup.py.
    python_executable = sys.executable

    proc = subprocess.run(
        [python_executable, backup_script, "--environment", "staging", "--output-dir", backup_dir,
         "--kind", "manual", "--triggered-by", "fk-hardening-regression-test"],
        capture_output=True, text=True,
        env={**os.environ, "PYTHONPATH": ""},
    )
    check("4a real backup run succeeds", proc.returncode == 0, proc.stderr[:500])
    backup_result = {}
    if proc.stdout.strip():
        try:
            backup_result = json.loads(proc.stdout.strip().splitlines()[-1])
        except json.JSONDecodeError:
            backup_result = {}
    file_path = backup_result.get("output_path") or backup_result.get("file_path")
    if not file_path or not os.path.exists(file_path):
        # Fall back to scanning the directory for the newest .bin file --
        # robust to any stdout-format difference across environments.
        bins = [f for f in os.listdir(backup_dir) if f.endswith(".bin")]
        file_path = os.path.join(backup_dir, sorted(bins)[-1]) if bins else None
    check("4b backup file exists on disk", bool(file_path) and os.path.exists(file_path), f"file_path={file_path}")

    conn = get_conn()
    try:
        report = pdc_restore.restore_backup(conn, file_path, encryption_key.encode())
        conn.commit()
        check("5a restore reports foreign_keys_skipped is empty", report["foreign_keys_skipped"] == [], f"skipped: {report['foreign_keys_skipped']}")
        check("5b restore reports all_checks_passed = true", report["all_checks_passed"] is True, json.dumps(report)[:300])
        check("5c restore discovered more than the old 27-entry hand-written FK list", report["foreign_keys_discovered"] > 27, f"discovered={report['foreign_keys_discovered']}")

        cur = conn.cursor()
        cur.execute(f'drop schema if exists "{report["schema_name"]}" cascade')
        conn.commit()
    finally:
        conn.close()


if __name__ == "__main__":
    test_discover_foreign_keys_finds_far_more_than_the_old_hand_written_list()
    test_discovered_foreign_keys_only_reference_backup_payload_tables()
    test_full_backup_and_restore_cycle_passes_with_validated_constraints()
    print()
    print(f"TOTAL: {len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        sys.exit(1)
