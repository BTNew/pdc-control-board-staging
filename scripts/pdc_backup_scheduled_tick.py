"""
PDC Control Board — server-side scheduled backup entry point.

This is the single script a scheduler (cron / systemd timer / Windows
Task Scheduler / Supabase Edge cron / any server-side scheduler) should
invoke every 3 hours. It is intentionally a thin wrapper around
pdc_backup_run.py (duplicate-safe, alerting) + pdc_backup_retention.py
(policy-based pruning), so the whole "one tick" of the backup system is
one process invocation with one exit code and one log line, which is
what a real scheduler integration needs.

Server-side, not browser-dependent: reads all configuration from
environment variables / a local secrets file, never from anything the
browser controls. Safe to run unattended and repeatedly -- overlapping
invocations are refused (see pdc_backup_run.py's running-lock check
against backup_runs), so a scheduler firing twice in quick succession
(e.g. daylight-saving edge case, manual + scheduled trigger overlapping)
cannot corrupt or duplicate a backup.

Logging: writes one JSON line per run to --log-file (append mode) with a
stable schema (timestamp, environment, status, run_id, size, error,
alert). This is the "clear success or failure log" required by the task.
Also prints the same JSON to stdout so a scheduler's own log capture
(e.g. Windows Task Scheduler's captured output, or a cron mail) shows it
too.

Exit codes:
  0 = backup succeeded, or was skipped because another run was already
      in progress (not an error condition for a scheduler)
  1 = backup failed
  2 = configuration error (missing encryption key, bad arguments)
"""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pdc_backup_run import run_guarded_backup  # noqa: E402
from pdc_backup_retention import run_retention  # noqa: E402


def append_log_line(log_file, record):
    log_file = Path(log_file)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    with log_file.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, default=str) + "\n")


def run_scheduled_tick(environment, output_dir, log_file,
                        stale_after_minutes=30, alert_threshold=3,
                        retention_kwargs=None):
    started_at = datetime.now(timezone.utc)
    backup_outcome = run_guarded_backup(
        environment, output_dir, None,
        kind="scheduled", triggered_by="scheduler",
        stale_after_minutes=stale_after_minutes,
        alert_threshold=alert_threshold,
    )

    retention_outcome = None
    # Only prune after a real (non-skipped) attempt, successful or not --
    # a skip means nothing changed, so there is nothing new to reconsider
    # for retention this tick.
    if not backup_outcome.get("skipped"):
        retention_outcome = run_retention(output_dir, environment, dry_run=False, **(retention_kwargs or {}))

    finished_at = datetime.now(timezone.utc)
    backup_result = backup_outcome.get("backup_result", {})
    status = "skipped" if backup_outcome.get("skipped") else backup_result.get("status", "unknown")

    record = {
        "tick_started_at": started_at.isoformat(),
        "tick_finished_at": finished_at.isoformat(),
        "environment": environment,
        "status": status,
        "backup_run_id": backup_result.get("backup_run_id"),
        "size_bytes": backup_result.get("size_bytes"),
        "error": backup_result.get("error"),
        "skipped_reason": backup_outcome.get("reason"),
        "consecutive_failures": backup_outcome.get("consecutive_failures"),
        "alert": backup_outcome.get("alert"),
        "retention_deleted_count": len(retention_outcome["deleted"]) if retention_outcome else None,
        "retention_kept_count": len(retention_outcome["kept"]) if retention_outcome else None,
    }
    append_log_line(log_file, record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", required=True, choices=["staging", "production"])
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--stale-after-minutes", type=int, default=30)
    parser.add_argument("--alert-threshold", type=int, default=3)
    args = parser.parse_args()

    if args.environment == "production":
        print("Refusing to run a scheduled production backup from this "
              "staging-only entry point. Production scheduling requires a "
              "separate, explicitly-approved invocation.", file=sys.stderr)
        sys.exit(2)

    record = run_scheduled_tick(
        args.environment, args.output_dir, args.log_file,
        stale_after_minutes=args.stale_after_minutes,
        alert_threshold=args.alert_threshold,
    )
    print(json.dumps(record, indent=2, default=str))

    if record["alert"]:
        # Non-fatal for the scheduler (the backup this tick may still have
        # succeeded) but surfaced loudly on stderr so a scheduler's failure
        # notification path (e.g. Task Scheduler "on failure" action, or a
        # cron MAILTO) has something to alert an administrator with even
        # though the process itself exits 0/1 based on backup status only.
        print(f"ALERT: {record['alert']['message']}", file=sys.stderr)

    if record["status"] == "failed":
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
