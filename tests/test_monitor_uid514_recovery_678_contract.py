from __future__ import annotations

import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260827112000_678_uid514_authorize_attachment_count_repair.sql"


class Uid514AuthorizeRepair678ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_677_and_function_hash_guards(self):
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        for marker in (
            "20260827111000",
            "677_uid514_exact_recovery_successor",
            "0f93e7bc36549e14f4a5231e57a2a23b1168f6d2a32d3f4678da811cdca77955",
            "fe30c884f0db02f7d31d629e12af0e29bcdd2505a6451b2873f05364c5727e69",
            "eb91ff09afac2c66d2abf461b57dd9c8d1c6fc5aac13843d74c0ce192b8dd88a",
            "ef925445ee7ccfd3dbfeba4c2e437e4c49e477269137ac5bbd1e744d9cf56962",
            "4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629",
            "de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351",
            "ad921292bdafb3bfc25413df8c1faa803442f0c645799aac3cd42af76b0da85f",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)

    def test_only_attachment_count_literal_is_repaired(self):
        self.assertIn("\\'13016925\\',\\'j139125482\\',4)", self.lower)
        self.assertIn("\\'13016925\\',\\'j139125482\\',7)", self.lower)
        self.assertIn("predecessor_authorize_sha256", self.lower)
        self.assertIn("successor_authorize_sha256", self.lower)
        self.assertIn("uid514_recovery_authorize_repair_history_678", self.lower)
        self.assertIn("force row level security", self.lower)
        for marker in ("440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280", "25751401", "not task_enabled", "not mailbox_contacted", "not uid514_processed", "not production_writes"):
            self.assertIn(marker.lower(), self.lower)
        self.assertRegex(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
