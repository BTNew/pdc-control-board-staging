from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830243000_822_historical_derived_proposal_context_successor.sql"


class HistoricalGenericContext822ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_canonical_child_carries_verified_historical_context(self):
        self.assertIn("pdc.historical_context", self.sql)
        self.assertIn("canonical_source_uid", self.sql)
        self.assertIn("v_proposal.source_received_at<clock_timestamp()-interval '30 days'", self.sql)
        self.assertIn("pdc_historical_writer_authorized_773", self.sql)
        self.assertIn("pdc_822_current_head_or_function_prestate_failed", self.sql)
        self.assertIn("pdc_822_historical_context_postcondition_failed", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
