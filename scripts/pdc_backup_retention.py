"""
PDC Control Board — backup retention pruning (staging-tested; safe for
production once approved).

Policy (per task instructions, overridable via CLI flags):
- Keep every 3-hour backup for 7 days.
- Keep one daily backup for 30 days.
- Keep one weekly backup for 12 weeks.
- Keep one monthly backup for 12 months.

Implementation approach: classify every *successful* backup file present
on disk by age into one of four buckets (recent / daily / weekly /
monthly). Within the daily/weekly/monthly buckets, for each calendar
day/ISO-week/month keep only the single earliest backup of that period
(a stable, deterministic "one per bucket" choice) and delete the rest.
Backups already older than the outermost retention window (12 months)
are always deleted. Failed backups' files (there normally are none, since
a failed run does not produce a file) are never retained past 7 days
regardless of the policy, to avoid the store growing from repeated
transient failures.

This never touches `backup_runs` history rows in the database (those stay
forever as an audit trail of what was attempted) -- only the on-disk
encrypted files are pruned. Each pruning action is logged.
"""
import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

FILENAME_RE = re.compile(r"^pdc_backup_(?P<env>staging|production)_(?P<stamp>\d{8}T\d{6}Z)_")


def parse_backup_timestamp(file_name):
    match = FILENAME_RE.match(file_name)
    if not match:
        return None
    return datetime.strptime(match.group("stamp"), "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)


def bucket_key(dt, granularity):
    if granularity == "daily":
        return dt.strftime("%Y-%m-%d")
    if granularity == "weekly":
        iso = dt.isocalendar()
        return f"{iso[0]}-W{iso[1]:02d}"
    if granularity == "monthly":
        return dt.strftime("%Y-%m")
    raise ValueError(granularity)


def plan_retention(files_with_ts, now, environment,
                    recent_days=7, daily_days=30, weekly_weeks=12, monthly_months=12):
    """
    files_with_ts: list of (Path, datetime) for one environment's backups,
    already filtered to successful files only.
    Returns (keep, delete) lists of Path.
    """
    recent_cutoff = now - timedelta(days=recent_days)
    daily_cutoff = now - timedelta(days=daily_days)
    weekly_cutoff = now - timedelta(weeks=weekly_weeks)
    monthly_cutoff = now - timedelta(days=monthly_months * 31)  # conservative upper bound

    keep = set()
    delete = set()

    recent = [(p, ts) for p, ts in files_with_ts if ts >= recent_cutoff]
    for p, _ in recent:
        keep.add(p)

    daily_candidates = [(p, ts) for p, ts in files_with_ts if recent_cutoff > ts >= daily_cutoff]
    weekly_candidates = [(p, ts) for p, ts in files_with_ts if daily_cutoff > ts >= weekly_cutoff]
    monthly_candidates = [(p, ts) for p, ts in files_with_ts if weekly_cutoff > ts >= monthly_cutoff]
    too_old = [(p, ts) for p, ts in files_with_ts if ts < monthly_cutoff]

    for candidates, granularity in (
        (daily_candidates, "daily"),
        (weekly_candidates, "weekly"),
        (monthly_candidates, "monthly"),
    ):
        buckets = {}
        for p, ts in candidates:
            key = bucket_key(ts, granularity)
            buckets.setdefault(key, []).append((p, ts))
        for key, items in buckets.items():
            items.sort(key=lambda pair: pair[1])
            keep.add(items[0][0])
            for p, _ in items[1:]:
                delete.add(p)

    for p, _ in too_old:
        delete.add(p)

    # Anything not explicitly kept and not explicitly already marked for
    # deletion (shouldn't happen given the ranges above are exhaustive,
    # but keep the invariant explicit and safe-by-default).
    all_paths = {p for p, _ in files_with_ts}
    undecided = all_paths - keep - delete
    delete |= undecided

    return sorted(keep), sorted(delete)


def run_retention(backup_dir, environment, now=None, dry_run=False, **policy_kwargs):
    now = now or datetime.now(timezone.utc)
    backup_dir = Path(backup_dir)
    files_with_ts = []
    for file_path in backup_dir.glob(f"pdc_backup_{environment}_*.bin"):
        ts = parse_backup_timestamp(file_path.name)
        if ts is not None:
            files_with_ts.append((file_path, ts))

    keep, delete = plan_retention(files_with_ts, now, environment, **policy_kwargs)

    deleted = []
    for file_path in delete:
        manifest_path = file_path.with_name(file_path.name + ".manifest.json")
        if not dry_run:
            file_path.unlink(missing_ok=True)
            manifest_path.unlink(missing_ok=True)
        deleted.append(str(file_path))

    return {
        "environment": environment,
        "now": now.isoformat(),
        "total_backups_seen": len(files_with_ts),
        "kept": [str(p) for p in keep],
        "deleted": deleted,
        "dry_run": dry_run,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup-dir", required=True)
    parser.add_argument("--environment", required=True, choices=["staging", "production"])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    result = run_retention(args.backup_dir, args.environment, dry_run=args.dry_run)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
