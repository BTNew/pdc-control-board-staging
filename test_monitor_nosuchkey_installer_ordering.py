from __future__ import annotations

import hashlib
import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DESKTOP = Path(r"C:/Users/nwmgr/Desktop/PDCMonitor-Install-20260869")
ELEVATED = DESKTOP / "PDCMonitor-Install-20260869-Elevated.ps1"
INSTALLER = ROOT / "scripts/install_pdc_monitor_successor_20260869.ps1"
ROLLBACK = ROOT / "scripts/rollback_pdc_monitor_successor_20260869.ps1"


class NoSuchKeyInstallerOrderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.elevated = ELEVATED.read_text(encoding="utf-8")
        cls.installer = INSTALLER.read_text(encoding="utf-8")
        cls.rollback = ROLLBACK.read_text(encoding="utf-8")

    def test_temporary_sid_access_is_scoped_and_removed(self):
        text = self.elevated.lower()
        for marker in (
            "temporarysid",
            "installersha",
            "verifiersha",
            "installsucceeded",
            "temp-grant",
            "temporaryaclsnapshots",
            "remove-tempgrant",
            "finally",
        ):
            self.assertIn(marker, text)
        self.assertNotIn("takeown", text)
        self.assertNotIn("/reset", text)
        self.assertNotIn("takeown", text)
        self.assertNotIn("'/t'", text)
        self.assertNotIn("enable-scheduledtask", text)
        self.assertNotIn("start-scheduledtask", text)

    def test_verifier_runs_after_installer_with_temporary_access(self):
        text = self.elevated.lower()
        installer_at = text.index("$installer -installroot")
        verifier_at = text.index("$verifier --bundle")
        cleanup_at = text.index("foreach($path in $temporaryaclpaths)")
        self.assertLess(installer_at, verifier_at)
        self.assertLess(verifier_at, cleanup_at)
        self.assertIn("--bundle $bundle", text)
        self.assertIn("hash $installer", text)
        self.assertIn("hash $verifier", text)
        self.assertIn("$verifyexit", text)
        self.assertIn("$acl.areaccessrulesprotected", text)
        self.assertIn("$script:cleanupfailed=$true", text)
        compact = re.sub(r"\s+", "", text)
        self.assertIn("remove-tempgrant$path", compact)
        self.assertIn("if($installsucceeded-and$target", compact)
        self.assertIn("set-acl-literalpath$path-aclobject$temporaryaclsnapshots[$path]", compact)

    def test_installer_and_rollback_keep_disabled_task_boundary(self):
        installer = self.installer.lower()
        rollback = self.rollback.lower()
        for text in (installer, rollback):
            self.assertIn("pdc-pmb-email-monitor-staging", text)
            self.assertIn("local service", text)
            self.assertIn("limited", text)
            self.assertIn("pt5m", text)
            self.assertIn("mailbox_contacted=$false", text)
            self.assertIn("production_contacted=$false", text)
        self.assertIn("task.state -ne 'disabled'", installer)
        self.assertIn("disable-scheduledtask", rollback)
        for forbidden in ("enable-scheduledtask", "start-scheduledtask", "register-scheduledtask"):
            self.assertNotIn(forbidden, installer)

    def test_redacted_artifacts_are_hashable_without_execution(self):
        for path in (ELEVATED, INSTALLER, ROLLBACK):
            self.assertTrue(path.is_file(), path)
            self.assertGreater(path.stat().st_size, 0)
            self.assertRegex(hashlib.sha256(path.read_bytes()).hexdigest(), r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
