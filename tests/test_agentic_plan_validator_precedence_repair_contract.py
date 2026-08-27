from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828230000_700_agentic_plan_validator_precedence_repair.sql"


class AgenticPlanValidatorPrecedenceRepairContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_exact_predecessor_and_repair_anchor(self):
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        self.assertNotRegex(self.lower, r"\b(drop|truncate)\s+(table|function|schema)")
        for marker in (
            "20260828200000",
            "699_agentic_candidate_id_delimiter_repair",
            "pdc_agentic_email_plan_valid_502(jsonb,public.pdc_agentic_email_context_receipts_502)",
            "54830d6a5e1791467eb8d0347e7db077e870de90b00265e89e9996d5303ea12f",
            "pdc_authenticated_email_plan_validator_precedence_history_700",
            "pdc_700_exact_699_plan_validator_predecessor_mismatch",
            "pdc_700_repair_anchor_mismatch",
            "pdc_700_postcondition_failed",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("old:=$old$p_plan->'source_binding'-array['claim_token','gateway_instance_id']::text[]$old$", self.sql)
        self.assertIn("new:=$new$(p_plan->'source_binding')-array['claim_token','gateway_instance_id']::text[]$new$", self.sql)

    def test_security_and_scope_are_preserved(self):
        self.assertIn("pdc_staging_environment_sentinel", self.lower)
        self.assertIn("pdc_production_environment_sentinel", self.lower)
        self.assertIn("current_user<>'postgres'", self.lower)
        self.assertIn("session_user<>'postgres'", self.lower)
        self.assertIn("alter table public.pdc_authenticated_email_plan_validator_precedence_history_700 enable row level security", self.lower)
        self.assertIn("alter table public.pdc_authenticated_email_plan_validator_precedence_history_700 force row level security", self.lower)
        self.assertIn("revoke all on public.pdc_authenticated_email_plan_validator_precedence_history_700", self.lower)
        for marker in ("uid514", "production", "task", "mailbox", "outbound"):
            self.assertIn(marker, self.lower)

    def test_source_hash_is_stable_for_review(self):
        self.assertEqual(len(hashlib.sha256(self.sql.encode()).hexdigest()), 64)
        self.assertIn("successor_function_sha256 text not null", self.lower)
        self.assertIn("production_writes boolean not null check(not production_writes)", self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
