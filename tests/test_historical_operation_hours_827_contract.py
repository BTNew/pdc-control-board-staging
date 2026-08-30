from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830248000_827_historical_operation_hours_successor.sql"


class HistoricalOperationHours827ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_all_unknown_hours_coalesce_before_not_null_receipt(self):
        self.assertIn("coalesce(sum((x->>'estimated_hours')::numeric),0)", self.sql)
        self.assertIn("estimated_hours_sum", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
