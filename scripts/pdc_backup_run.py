"""
PDC Control Board — backup run wrapper with duplicate-run guard and
repeated-failure alerting.

Wraps a single invocation of pdc_backup.py:
1. Refuses to start a new backup if another backup for the same
   environment is still marked 'running' in backup_runs and started less
   than `--stale-after-minutes` ago (duplicate-safe: a second scheduled
   trigger firing while the first is still in flight is a no-op, not a
   second concurrent dump).
2. Runs the backup.
3. After the run, counts the most recent consecutive 'failed' runs for
   the environment. If that count reaches `--alert-threshold`, writes an
   alert record and prints/returns an alert payload the caller (e.g. a
   cron job's notification channel) can deliver to an administrator.
   This script does not send the alert itself (no email/SMS credentials
   here) -- it decides *whether* to alert and produces the exact message,
   leaving delivery to whatever channel is already approved for
   administrator alerts (e.g. the same cron/notification mechanism used
   elsewhere in this project).
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path


def get_conn_module():
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from scripts.pdc_staging_runtime import get_conn  # noqa: E402
    return get_conn


def is_another_backup_already_running(conn, environment, stale_after_minutes):
    cur = conn.cursor()
    cur.execute(
        """
        select id, started_at from public.backup_runs
        where environment = %s and status = 'running'
          and started_at > now() - (%s || ' minutes')::interval
        order by started_at desc limit 1
        """,
        (environment, str(stale_after_minutes)),
    )
    return cur.fetchone()


def count_consecutive_recent_failures(conn, environment):
    cur = conn.cursor()
    cur.execute(
        """
        select status from public.backup_runs
        where environment = %s and status in ('success', 'failed')
        order by started_at desc
        limit 20
        """,
        (environment,),
    )
    count = 0
    for (status,) in cur.fetchall():
        if status == "failed":
            count += 1
        else:
            break
    return count


def run_guarded_backup(environment, output_dir, encryption_key_env_value,
                        kind="scheduled", triggered_by="cron",
                        stale_after_minutes=30, alert_threshold=3,
                        python_executable=None, backup_script=None):
    get_conn = get_conn_module()
    conn = get_conn()
    try:
        existing = is_another_backup_already_running(conn, environment, stale_after_minutes)
        if existing:
            return {
                "skipped": True,
                "reason": "another backup run is already in progress",
                "existing_run_id": str(existing[0]),
                "existing_started_at": existing[1].isoformat(),
            }
    finally:
        conn.close()

    python_executable = python_executable or sys.executable
    backup_script = backup_script or str(Path(__file__).resolve().parent / "pdc_backup.py")
    proc = subprocess.run(
        [python_executable, backup_script,
         "--environment", environment,
         "--output-dir", str(output_dir),
         "--kind", kind,
         "--triggered-by", triggered_by],
        capture_output=True, text=True,
    )
    try:
        backup_result = json.loads(proc.stdout.strip().splitlines()[-1]) if proc.stdout.strip() else {}
    except (ValueError, IndexError):
        backup_result = {}
    # If stdout wasn't a single JSON line (pdc_backup.py always prints one
    # pretty-printed JSON object -- parse the whole stdout instead).
    if not backup_result and proc.stdout.strip():
        try:
            backup_result = json.loads(proc.stdout)
        except ValueError:
            backup_result = {"raw_stdout": proc.stdout}

    conn = get_conn()
    try:
        consecutive_failures = count_consecutive_recent_failures(conn, environment)
    finally:
        conn.close()

    alert = None
    if consecutive_failures >= alert_threshold:
        alert = {
            "severity": "critical",
            "environment": environment,
            "consecutive_failures": consecutive_failures,
            "message": (
                f"PDC Control Board {environment} backup has failed "
                f"{consecutive_failures} times in a row. Last error: "
                f"{backup_result.get('error', 'unknown')}. An administrator "
                f"must investigate before the retention window loses "
                f"coverage."
            ),
        }

    return {
        "skipped": False,
        "backup_result": backup_result,
        "process_exit_code": proc.returncode,
        "process_stderr": proc.stderr[-2000:] if proc.stderr else "",
        "consecutive_failures": consecutive_failures,
        "alert": alert,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", required=True, choices=["staging", "production"])
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--kind", default="scheduled", choices=["scheduled", "manual"])
    parser.add_argument("--triggered-by", default="cron")
    parser.add_argument("--stale-after-minutes", type=int, default=30)
    parser.add_argument("--alert-threshold", type=int, default=3)
    args = parser.parse_args()

    result = run_guarded_backup(
        args.environment, args.output_dir, None,
        kind=args.kind, triggered_by=args.triggered_by,
        stale_after_minutes=args.stale_after_minutes,
        alert_threshold=args.alert_threshold,
    )
    print(json.dumps(result, indent=2, default=str))

    if result.get("skipped"):
        sys.exit(0)
    if result["backup_result"].get("status") != "success":
        sys.exit(1)


if __name__ == "__main__":
    main()
