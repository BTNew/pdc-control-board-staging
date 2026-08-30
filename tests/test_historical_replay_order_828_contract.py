from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830249000_828_historical_replay_order_successor.sql"


class HistoricalReplayOrder828ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.body = cls.sql.split("as $function$", 1)[1].split("$function$", 1)[0]

    def test_receipt_replay_precedes_terminal_proposal_conflict(self):
        self.assertIn("from public.pdc_historical_reconciliation_778_receipts", self.body)
        self.assertIn("historical_proposal_terminal_conflict", self.body)
        self.assertLess(
            self.body.index("from public.pdc_historical_reconciliation_778_receipts"),
            self.body.index("historical_proposal_terminal_conflict"),
        )
        self.assertIn("historical_replay_conflict", self.body)
        self.assertIn("pdc_828_historical_replay_order_postcondition_failed", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
