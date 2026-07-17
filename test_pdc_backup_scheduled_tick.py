"""
Real (non-mocked) unit test for scripts/pdc_backup_scheduled_tick.py's
append_log_line() and the record shape produced by run_scheduled_tick()'s
non-DB-dependent parts. Full end-to-end scheduling (real staging DB) is
covered separately in _staging_test_tools (gitignored, requires a live
staging connection); this test exercises the pure log-writing logic with
real temp files so it can run anywhere, including CI without DB access.
"""
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
from pdc_backup_scheduled_tick import append_log_line  # noqa: E402


def test_append_log_line_creates_file_and_parent_dirs():
    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "nested" / "backup_log.jsonl"
        append_log_line(log_path, {"status": "success", "environment": "staging"})
        assert log_path.exists()
        lines = log_path.read_text(encoding="utf-8").strip().splitlines()
        assert len(lines) == 1
        record = json.loads(lines[0])
        assert record["status"] == "success"
    print("PASS  1a append_log_line creates the file and parent directories")


def test_append_log_line_appends_not_overwrites():
    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "backup_log.jsonl"
        append_log_line(log_path, {"status": "success", "tick": 1})
        append_log_line(log_path, {"status": "failed", "tick": 2})
        append_log_line(log_path, {"status": "success", "tick": 3})
        lines = log_path.read_text(encoding="utf-8").strip().splitlines()
        assert len(lines) == 3, lines
        records = [json.loads(line) for line in lines]
        assert [r["tick"] for r in records] == [1, 2, 3]
        assert [r["status"] for r in records] == ["success", "failed", "success"]
    print("PASS  2a each tick appends a new line without disturbing earlier lines "
          "-- a real success/failure log an administrator can tail")


def test_log_lines_are_valid_json_one_per_line():
    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "backup_log.jsonl"
        # A record containing a nested structure (like the real alert dict)
        append_log_line(log_path, {
            "status": "failed",
            "alert": {"severity": "critical", "consecutive_failures": 4},
            "error": "Fernet key must be 32 url-safe base64-encoded bytes.",
        })
        line = log_path.read_text(encoding="utf-8").strip()
        assert "\n" not in line, "a single record must not span multiple lines"
        record = json.loads(line)
        assert record["alert"]["severity"] == "critical"
    print("PASS  3a each log line is valid, single-line, self-contained JSON "
          "(safe for standard log tailing/parsing tools)")


if __name__ == "__main__":
    test_append_log_line_creates_file_and_parent_dirs()
    test_append_log_line_appends_not_overwrites()
    test_log_lines_are_valid_json_one_per_line()
    print("\nAll scheduled-tick logging tests passed")
