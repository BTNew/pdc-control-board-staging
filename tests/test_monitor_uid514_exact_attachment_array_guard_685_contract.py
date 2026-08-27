from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828060000_685_uid514_exact_attachment_array_guard.sql"
EXPECTED = "f450ac57f1d195ea2a3540b2d54e0aca44ae20c6896d88fc38062af5e1263a04"


class Uid514ExactAttachmentArrayGuard685Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_is_exact_append_only_successor(self):
        self.assertEqual(hashlib.sha256(self.sql.encode()).hexdigest(), EXPECTED)
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        self.assertNotRegex(self.lower, r"\b(drop|delete|truncate)\s+(table|from|function|schema)")
        self.assertNotIn("vjdtsswhroyguxyfjdkt", self.lower)
        for marker in (
            "20260828050000", "20260828060000", "684_authenticated_provider_import_agentic_compatibility",
            "pdc_monitor_authenticated_uid514_claim_scope_684", "c.all_attachment_hashes",
            "c.pdf_hashes", "s.all_attachment_ids", "s.qualifying_attachment_ids",
            "pdc_authenticated_provider_import_agentic_inventory_guard_history_685",
            "pdc_685_exact_684_predecessor_or_uid514_state_mismatch",
            "pdc_685_inventory_guard_history_immutable", "force row level security",
            "observed_mime_part_count", "retained_authenticated_attachment_count",
            "440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280",
            "uid514_processed", "production_writes",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_history_has_exact_predecessor_and_safe_postconditions(self):
        self.assertIn("predecessor_helper_sha256", self.lower)
        self.assertIn("successor_helper_sha256", self.lower)
        self.assertIn("7626fd496feaea6c90bd254dffefd0c36ab18e69403f2b3c7aff38d104e7682b", self.lower)
        self.assertIn("forward_inventory_guard", self.lower)
        self.assertIn("status='failed'", self.lower)
        self.assertIn("queue_attempts=8", self.lower)
        self.assertIn("where singleton and enabled", self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
