import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import vehicle_order_email_monitor as monitor


class _Response:
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class VehicleOrderEmailMonitorTests(unittest.TestCase):
    def test_lock_backend_matches_platform_and_serializes(self):
        expected = "msvcrt" if sys.platform == "win32" else "fcntl"
        self.assertEqual(monitor.LOCK_BACKEND, expected)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "portable.lock"
            first = monitor.acquire_lock(path, 0)
            try:
                with self.assertRaisesRegex(TimeoutError, "still running"):
                    monitor.acquire_lock(path, 0)
            finally:
                monitor.release_lock(first)
            second = monitor.acquire_lock(path, 0)
            monitor.release_lock(second)

    def test_nested_updater_summary(self):
        output = json.dumps({
            "ok": True,
            "email_bridge": json.dumps({"posted": 2, "skipped_processed": 3}),
            "website_publish": json.dumps({
                "changed": True,
                "vehicles_generated": 12,
                "committed_and_pushed": True,
            }),
        })
        self.assertEqual(monitor.summarize_updater(output), {
            "posted": 2,
            "skipped_processed": 3,
            "changed": True,
            "vehicles_generated": 12,
            "committed_and_pushed": True,
        })

    def test_telegram_uses_local_env_without_exposing_secret(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = Path(tmp) / ".env"
            env.write_text(
                "TELEGRAM_BOT_TOKEN=local-secret-token\nTELEGRAM_HOME_CHANNEL=12345\n",
                encoding="utf-8",
            )
            with mock.patch.object(monitor.urllib.request, "urlopen", return_value=_Response()) as opened:
                monitor.send_telegram("test message", env_path=env)
            request = opened.call_args.args[0]
            self.assertIn("local-secret-token", request.full_url)
            self.assertIn(b"chat_id=12345", request.data)
            self.assertIn(b"test+message", request.data)

    def test_success_notifies_only_when_new_mail_was_imported(self):
        updater_output = json.dumps({
            "email_bridge": json.dumps({"posted": 1, "skipped_processed": 0}),
            "website_publish": json.dumps({"changed": True, "vehicles_generated": 4}),
        })
        completed = mock.Mock(returncode=0, stdout=updater_output)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with (
                mock.patch.object(monitor, "LOCK_PATH", root / "monitor.lock"),
                mock.patch.object(monitor, "STATUS_PATH", root / "status.json"),
                mock.patch.object(monitor.subprocess, "run", return_value=completed),
                mock.patch.object(monitor, "send_telegram") as notified,
            ):
                self.assertEqual(monitor.run_monitor(10, 1, 10), 0)
                self.assertTrue(json.loads((root / "status.json").read_text(encoding="utf-8"))["ok"])
                notified.assert_called_once()

    def test_failure_records_status_and_notifies(self):
        completed = mock.Mock(returncode=9, stdout="bounded failure")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with (
                mock.patch.object(monitor, "LOCK_PATH", root / "monitor.lock"),
                mock.patch.object(monitor, "STATUS_PATH", root / "status.json"),
                mock.patch.object(monitor.subprocess, "run", return_value=completed),
                mock.patch.object(monitor, "send_telegram") as notified,
            ):
                self.assertEqual(monitor.run_monitor(10, 1, 10), 1)
                self.assertFalse(json.loads((root / "status.json").read_text(encoding="utf-8"))["ok"])
                notified.assert_called_once()


if __name__ == "__main__":
    unittest.main()
