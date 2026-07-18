"""
Real (non-mocked) unit tests for scripts/pdc_backup_retention.py. Creates
real temp files with real backup-style filenames spanning realistic ages,
runs the actual plan_retention()/run_retention() functions, and asserts
on the real keep/delete decisions.
"""
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
from pdc_backup_retention import plan_retention, run_retention, bucket_key  # noqa: E402


def make_ts(now, days_ago=0, hours_ago=0):
    return now - timedelta(days=days_ago, hours=hours_ago)


def stamp(dt):
    return dt.strftime("%Y%m%dT%H%M%SZ")


def test_recent_backups_all_kept():
    now = datetime(2026, 7, 17, 12, 0, 0, tzinfo=timezone.utc)
    files = [
        (Path(f"pdc_backup_staging_{stamp(make_ts(now, hours_ago=h))}_aaaaaaaa.bin"), make_ts(now, hours_ago=h))
        for h in (0, 3, 6, 24, 48, 24 * 6)
    ]
    keep, delete = plan_retention(files, now, "staging")
    assert set(keep) == {p for p, _ in files}, keep
    assert delete == []
    print("PASS  1a all backups within the 7-day recent window are kept")


def test_daily_bucket_keeps_one_per_day():
    now = datetime(2026, 7, 17, 12, 0, 0, tzinfo=timezone.utc)
    day10 = make_ts(now, days_ago=10)
    files = [
        (Path(f"pdc_backup_staging_{stamp(day10)}_aaaaaaa1.bin"), day10),
        (Path(f"pdc_backup_staging_{stamp(day10 + timedelta(hours=3))}_aaaaaaa2.bin"), day10 + timedelta(hours=3)),
        (Path(f"pdc_backup_staging_{stamp(day10 + timedelta(hours=6))}_aaaaaaa3.bin"), day10 + timedelta(hours=6)),
    ]
    keep, delete = plan_retention(files, now, "staging")
    assert len(keep) == 1, keep
    assert len(delete) == 2, delete
    # the earliest of the day is kept (deterministic)
    assert keep[0].name.endswith("aaaaaaa1.bin")
    print("PASS  2a exactly one backup per day is kept beyond the recent window, earliest wins")


def test_weekly_and_monthly_buckets():
    now = datetime(2026, 7, 17, 12, 0, 0, tzinfo=timezone.utc)
    week5 = make_ts(now, days_ago=35)  # falls in the weekly window (30-84 days)
    month5 = make_ts(now, days_ago=150)  # falls in the monthly window (84-372 days)
    files = [
        (Path(f"pdc_backup_staging_{stamp(week5)}_bbbbbbb1.bin"), week5),
        (Path(f"pdc_backup_staging_{stamp(week5 + timedelta(days=1))}_bbbbbbb2.bin"), week5 + timedelta(days=1)),
        (Path(f"pdc_backup_staging_{stamp(month5)}_ccccccc1.bin"), month5),
        (Path(f"pdc_backup_staging_{stamp(month5 + timedelta(days=5))}_ccccccc2.bin"), month5 + timedelta(days=5)),
    ]
    keep, delete = plan_retention(files, now, "staging")
    assert len(keep) == 2, keep
    assert len(delete) == 2, delete
    print("PASS  3a one weekly and one monthly backup kept per bucket")


def test_backups_older_than_12_months_are_deleted():
    now = datetime(2026, 7, 17, 12, 0, 0, tzinfo=timezone.utc)
    ancient = make_ts(now, days_ago=400)
    files = [(Path(f"pdc_backup_staging_{stamp(ancient)}_ddddddd1.bin"), ancient)]
    keep, delete = plan_retention(files, now, "staging")
    assert keep == [], keep
    assert len(delete) == 1, delete
    print("PASS  4a backups beyond the 12-month monthly retention window are deleted")


def test_run_retention_dry_run_does_not_delete_files():
    now = datetime(2026, 7, 17, 12, 0, 0, tzinfo=timezone.utc)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        old_ts = make_ts(now, days_ago=400)
        file_name = f"pdc_backup_staging_{stamp(old_ts)}_eeeeeee1.bin"
        (tmp_path / file_name).write_bytes(b"fake-encrypted-content")
        (tmp_path / f"{file_name}.manifest.json").write_text("{}")

        result = run_retention(tmp_path, "staging", now=now, dry_run=True)
        assert result["deleted"] == [str(tmp_path / file_name)], result
        assert (tmp_path / file_name).exists(), "dry-run must not actually delete the file"
    print("PASS  5a dry-run reports deletions without touching the filesystem")


def test_run_retention_real_deletion():
    now = datetime(2026, 7, 17, 12, 0, 0, tzinfo=timezone.utc)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        old_ts = make_ts(now, days_ago=400)
        recent_ts = make_ts(now, hours_ago=1)
        old_name = f"pdc_backup_staging_{stamp(old_ts)}_fffffff1.bin"
        recent_name = f"pdc_backup_staging_{stamp(recent_ts)}_fffffff2.bin"
        (tmp_path / old_name).write_bytes(b"x")
        (tmp_path / f"{old_name}.manifest.json").write_text("{}")
        (tmp_path / recent_name).write_bytes(b"x")
        (tmp_path / f"{recent_name}.manifest.json").write_text("{}")

        result = run_retention(tmp_path, "staging", now=now, dry_run=False)
        assert not (tmp_path / old_name).exists(), "old backup file should be deleted"
        assert not (tmp_path / f"{old_name}.manifest.json").exists(), "old manifest should be deleted"
        assert (tmp_path / recent_name).exists(), "recent backup file must survive"
    print("PASS  6a real run actually deletes pruned files and their manifests, keeps recent ones")


def test_environments_are_isolated_never_mixed():
    now = datetime(2026, 7, 17, 12, 0, 0, tzinfo=timezone.utc)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        recent_ts = make_ts(now, hours_ago=1)
        staging_name = f"pdc_backup_staging_{stamp(recent_ts)}_ggggggg1.bin"
        prod_name = f"pdc_backup_production_{stamp(recent_ts)}_ggggggg2.bin"
        (tmp_path / staging_name).write_bytes(b"x")
        (tmp_path / prod_name).write_bytes(b"x")

        staging_result = run_retention(tmp_path, "staging", now=now, dry_run=True)
        assert staging_result["total_backups_seen"] == 1, staging_result
        assert str(tmp_path / staging_name) in staging_result["kept"]
        print("PASS  7a retention run scoped to 'staging' never touches production-named backups")


if __name__ == "__main__":
    test_recent_backups_all_kept()
    test_daily_bucket_keeps_one_per_day()
    test_weekly_and_monthly_buckets()
    test_backups_older_than_12_months_are_deleted()
    test_run_retention_dry_run_does_not_delete_files()
    test_run_retention_real_deletion()
    test_environments_are_isolated_never_mixed()
    print("\nAll backup retention tests passed")
