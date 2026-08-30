from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830244000_823_historical_parent_fan_in_successor.sql"


class HistoricalGenericParentExclusion823ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_only_authorized_parent_is_excluded_from_same_stock_conflict(self):
        self.assertIn("v_historical_context->>'parent_source_hash'=q.source_hash", self.sql)
        self.assertIn("v_historical_context->>'provider_uid'=q.source_uid", self.sql)
        self.assertIn("same_stock_evidence_conflict", self.sql)
        self.assertIn("pdc_823_current_head_or_pre310_prestate_failed", self.sql)
        self.assertIn("pdc_823_historical_parent_postcondition_failed", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
