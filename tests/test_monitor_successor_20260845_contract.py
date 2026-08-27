from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


class MonitorSuccessor20260845ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.active_bootstrap = (SCRIPTS / "pdc_monitor_active_bootstrap_20260845.ps1").read_text(encoding="utf-8").lower()
        cls.active_dispatch = (SCRIPTS / "pdc_monitor_active_dispatch_20260845.ps1").read_text(encoding="utf-8").lower()
        cls.verify_bootstrap = (SCRIPTS / "pdc_monitor_verifyonly_bootstrap_20260845.ps1").read_text(encoding="utf-8").lower()
        cls.verify_runner = (SCRIPTS / "pdc_monitor_verifyonly_runner_20260845.ps1").read_text(encoding="utf-8").lower()
        cls.installer = (SCRIPTS / "install_pdc_monitor_successor_20260845.ps1").read_text(encoding="utf-8").lower()
        cls.rollback = (SCRIPTS / "rollback_pdc_monitor_successor_20260845.ps1").read_text(encoding="utf-8").lower()

    def test_successor_artifacts_are_present_and_hashable(self):
        for path in (
            SCRIPTS / "build_pdc_monitor_successor_20260845.py",
            SCRIPTS / "verify_pdc_monitor_successor_20260845.py",
            ROOT / "backend/imap_bridge_successor_20260845.py",
            ROOT / "tests/fixtures/supabase_storage_key_already_exists_400.json",
        ):
            self.assertTrue(path.is_file(), path)
            self.assertRegex(hashlib.sha256(path.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")

    def test_storage_response_is_exact_and_fail_closed(self):
        bridge = (ROOT / "backend/imap_bridge_successor_20260845.py").read_text(encoding="utf-8")
        self.assertIn("exc.code != 400", bridge)
        self.assertIn('body.get("code") == "KeyAlreadyExists"', bridge)
        self.assertIn('body.get("statusCode") == 409', bridge)
        self.assertNotIn("if exc.code != 409", bridge)
        self.assertIn("if not _is_storage_existing_object_response(exc, error_body)", bridge)

    def test_verifyonly_has_independent_successor_anchor(self):
        self.assertIn("verifyonly_runner_sha256", self.verify_bootstrap)
        self.assertIn("verifyonly_bootstrap_sha256", self.verify_runner)
        self.assertIn("assert-hash $bootstrap (trust 'verifyonly_bootstrap_sha256')", self.verify_runner)
        self.assertNotIn("authenticated_dispatch_bootstrap_sha256", self.verify_runner)
        self.assertNotIn("bootstrap-verifyonly-20260828", self.verify_runner)
        self.assertNotIn("verifyonly_bootstrap_active_sha256", self.verify_runner)

    def test_active_and_verifyonly_routes_do_not_share_anchor(self):
        self.assertIn("active_dispatch_sha256", self.active_bootstrap)
        self.assertIn("verifyonly_runner_sha256", self.verify_bootstrap)
        self.assertIn("active_bootstrap_sha256", self.installer)
        self.assertIn("verifyonly_bootstrap_sha256", self.installer)
        self.assertNotIn("authenticated_dispatch_bootstrap_sha256", self.verify_runner)
        self.assertNotIn("authenticated_dispatch_bootstrap_sha256", self.verify_bootstrap)

    def test_successor_is_parent_bound_and_staging_only(self):
        for source in (self.active_dispatch, self.verify_runner, self.installer, self.rollback):
            for marker in ("2026.08.45", "2026.08.44", "production"):
                self.assertIn(marker, source)
        for marker in ("pdc-monitor-staging", "local service", "limited", "pt5m", "task_must_remain_disabled"):
            self.assertIn(marker, self.installer)
        self.assertIn("parent_manifest_sha256", self.active_dispatch)
        self.assertIn("parent_static", self.active_dispatch)
        self.assertIn("backups\\20260845", self.installer)
        self.assertIn("task_must_remain_disabled", self.installer)
        self.assertIn("disable-scheduledtask", self.rollback)
        self.assertNotIn("register-scheduledtask", self.installer)
        self.assertNotIn("start-scheduledtask", self.installer)

    def test_active_onecycle_and_dryrun_are_bounded(self):
        self.assertIn("onecycle", self.active_bootstrap)
        self.assertIn("dryrun", self.active_bootstrap)
        self.assertIn("active_dispatch_blocked", self.active_dispatch)
        self.assertIn("--mode monitor", self.active_dispatch)
        self.assertIn("global\\pdcmonitorstagingsuccessoractivedispatch", self.active_dispatch)
        self.assertIn("pythonnousersite", self.active_dispatch)
        self.assertIn("remove-item env:pythonpath", self.active_dispatch)


if __name__ == "__main__":
    unittest.main(verbosity=2)
