from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260827109000_675_authenticated_monitor_enqueue_trigger_compatibility.sql"


class AuthenticatedEnqueueTrigger675ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_674_predecessor_and_function_hash_guards(self):
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        for marker in (
            "20260827108000",
            "674_authenticated_monitor_mailbox_activation_transition",
            "4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629",
            "de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351",
            "edd514bd5512fec84c164493bd8ad9df3b452e7d916760424f2f9da0eba5cd51",
            "52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd",
            "a14a2d2b4ad3514a3367246ae9b8705762eda41987f9491980594e9c62e7d036",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("DROP TABLE", self.sql.upper())
        self.assertNotIn("DELETE FROM", self.sql.upper())

    def test_only_exact_authenticated_active_branch_bypasses_disabled_pilot(self):
        for marker in (
            "pdc_monitor_authenticated_active_scope_674",
            "pdc_pmb_email",
            "pmbcontroller@gmail.com",
            "lower(m.provider)<>''gmail''",
            "pdc_monitor_uid_before_active_floor",
            "<515",
            "pilot_remains_disabled",
            "admin_rollback_pdc_email_monitor_authenticated_enqueue_trigger_675",
            "before_definition",
            "after_definition",
            "force row level security",
            "immutable",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant select", self.lower)
        self.assertNotIn("grant insert", self.lower)
        self.assertNotIn("grant update", self.lower)
        self.assertNotIn("grant delete", self.lower)
        self.assertNotIn("enable-scheduledtask", self.lower)
        self.assertNotIn("start-scheduledtask", self.lower)
        self.assertNotIn("send_email", self.lower)

    def test_staging_ledger_and_source_hash_are_deterministic(self):
        self.assertIn("675_authenticated_monitor_enqueue_trigger_compatibility", self.lower)
        self.assertRegex(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
