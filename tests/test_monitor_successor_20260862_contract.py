from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
MIGRATION = ROOT / "supabase/staging_only/20260829010000_735_email_monitor_storage_reconcile_requeue_successor.sql"


class MonitorSuccessor20260862ContractTests(unittest.TestCase):
    def test_successor_artifacts_are_present_and_hashable(self):
        for path in (
            ROOT / "backend/email_intake_processor_successor_20260862.py",
            ROOT / "backend/imap_bridge_successor_20260862.py",
            ROOT / "backend/pdc_jobcard_runtime_client_successor_20260862.py",
            SCRIPTS / "build_pdc_monitor_successor_20260862.py",
            SCRIPTS / "verify_pdc_monitor_successor_20260862.py",
            SCRIPTS / "install_pdc_monitor_successor_20260862.ps1",
            MIGRATION,
        ):
            self.assertTrue(path.is_file(), path)
            self.assertRegex(hashlib.sha256(path.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")

    def test_processor_rejects_hostile_paths_before_urlopen(self):
        source = (ROOT / "backend/email_intake_processor_successor_20260862.py").read_text(encoding="utf-8")
        self.assertIn("validate_attachment_storage_path", source)
        self.assertIn('if "\\\\" in storage_path or "://" in storage_path or "%" in storage_path', source)
        self.assertIn("len(parts) != 3", source)
        self.assertIn('bucket != STORAGE_BUCKET or object_hash != expected_hash', source)
        self.assertNotIn('legacy_prefix = "pdc-email-intake-private/"', source)
        self.assertIn('get_pdc_monitor_intake_attachments_735', source)

    def test_database_successor_is_append_only_and_exactly_scoped(self):
        source = MIGRATION.read_text(encoding="utf-8")
        for marker in (
            "20260829000000",
            "d89a3bbd-590b-493b-84a8-ce557bbfe512",
            "6836f01c-080f-4289-90a4-df8667a49ac9",
            "pdc_email_monitor_storage_reconciliations_735",
            "pdc_email_monitor_requeue_receipts_735",
            "admin_requeue_pdc_email_intake_735",
            "get_pdc_monitor_intake_attachments_735",
            "permanent_fail_closed",
            "original_storage_path_retained",
        ):
            self.assertIn(marker, source)
        self.assertNotIn("update public.ai_email_attachments", source.lower())
        self.assertNotIn("pdc_email_monitor_requeue_receipts(\n", source)
        self.assertIn("revoke all on table", source.lower())
        self.assertIn("from public,anon,authenticated,service_role", source.lower())

    def test_controls_are_disabled_and_split(self):
        active = (SCRIPTS / "pdc_monitor_active_dispatch_20260862.ps1").read_text(encoding="utf-8").lower()
        verify = (SCRIPTS / "pdc_monitor_verifyonly_runner_20260862.ps1").read_text(encoding="utf-8").lower()
        installer = (SCRIPTS / "install_pdc_monitor_successor_20260862.ps1").read_text(encoding="utf-8").lower()
        self.assertIn("2026.08.62", active)
        self.assertIn("2026.08.62", verify)
        self.assertIn("grandparent_manifest_sha256", active)
        self.assertIn("grandparent_manifest_sha256", verify)
        self.assertIn("task_must_remain_disabled", installer)
        self.assertNotIn("enable-scheduledtask", installer)
        self.assertNotIn("start-scheduledtask", installer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
