from __future__ import annotations

import ast
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "scripts/run_authenticated_acceptance_campaign_686_staging.py"


class AuthenticatedAcceptanceHarnessContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = HARNESS.read_text(encoding="utf-8")
        cls.tree = ast.parse(cls.source)

    def test_uses_live_candidate_generator_and_reviewed_planner(self):
        self.assertIn("pdc_agentic_email_instruction_candidates_502", self.source)
        self.assertIn("run_planner(planner_candidates", self.source)
        self.assertIn("fixture[\"claim_token\"]", self.source)
        self.assertNotIn("actionable_by_text", self.source)
        self.assertNotIn("hashlib.sha256((candidate[\"evidence_ref\"]", self.source)

    def test_preserves_dependency_execution_order_and_replay(self):
        self.assertIn('"parts_eta_set": 0', self.source)
        self.assertIn('"parts_complete": 1', self.source)
        self.assertIn('"sublet_booking_date_set": 2', self.source)
        self.assertIn("execution_actions = sorted", self.source)
        self.assertIn("final_replay", self.source)
        self.assertIn("expected_action_count = sum(len(case[\"actions\"]) for case in results)", self.source)
        self.assertNotIn('"action_receipts") != 14', self.source)

    def test_real_684_wrapper_sequence_is_present(self):
        for marker in (
            "read_pdc_agentic_email_context_authenticated_684",
            "record_pdc_agentic_email_plan_authenticated_684",
            "execute_pdc_agentic_email_action_authenticated_684",
            "pdc_agentic_apply_action_authenticated_684",
            "finalize_pdc_agentic_email_plan_authenticated_684",
            "cleanup_pdc_authenticated_acceptance_campaign_686",
        ):
            self.assertIn(marker, self.source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
