from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828240000_701_agentic_plan_validator_evidence_ref_precedence_repair.sql"


class AgenticPlanValidatorEvidenceRefRepairContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_exact_predecessor_and_anchors(self):
        self.assertEqual(hashlib.sha256(self.sql.encode()).hexdigest(), "3abf85f77591f677f54b38a0dc1db6c0483e31749c58e3eae0ea0610228a2a02")
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        self.assertNotRegex(self.lower, r"\b(drop|truncate)\s+(table|function|schema)")
        for marker in (
            "20260828230000",
            "700_agentic_plan_validator_precedence_repair",
            "7726eb8b97ba6ce622b26120f2132866c88f5fa6273e100e74e64b53c4cc2600",
            "pdc_authenticated_email_plan_validator_evidence_ref_history_701",
            "pdc_701_exact_700_plan_validator_predecessor_mismatch",
            "pdc_701_repair_anchor_mismatch",
            "pdc_701_postcondition_failed",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("old_attachment:=$old$'attachment:'||a->>'attachment_id'$old$", self.sql)
        self.assertIn("new_attachment:=$new$('attachment:'||(a->>'attachment_id'))$new$", self.sql)
        self.assertIn("old_thread:=$old$'thread:'||h->>'message_id'$old$", self.sql)
        self.assertIn("new_thread:=$new$('thread:'||(h->>'message_id'))$new$", self.sql)

    def test_security_and_no_operational_scope(self):
        for marker in (
            "pdc_staging_environment_sentinel",
            "pdc_production_environment_sentinel",
            "current_user<>'postgres'",
            "session_user<>'postgres'",
            "force row level security",
            "production_writes boolean not null check(not production_writes)",
            "uid514",
            "vehicles",
            "work",
            "sublet",
            "task",
            "mailbox",
            "outbound",
        ):
            self.assertIn(marker, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
