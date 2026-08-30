from __future__ import annotations

import unittest
from pathlib import Path
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830254000_833_historical_operation_hours_correction_successor.sql"

class HistoricalOperationHours833ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_parses_and_pins_current_partial_state(self):
        self.assertEqual(len(parse_sql(self.sql)), 21)
        for marker in ("20260830252000", "831_historical_navision_refresh_successor", "20260830254000", "pdc_833_operation_hours_overlay_postcondition_failed"):
            self.assertIn(marker, self.sql)
        self.assertIn("count(*) from public.pdc_historical_reconciliation_778_receipts)<>5", self.sql)
        self.assertIn("count(*) from public.pdc_historical_provider_observations_778)<>24", self.sql)

    def test_preserves_unknown_and_explicit_zero_semantics(self):
        self.assertIn("authoritative_estimated_hours_sum numeric(10,2)", self.sql)
        self.assertIn("known_hours_sum numeric(10,2)", self.sql)
        self.assertIn("unknown_hours_count integer not null", self.sql)
        self.assertIn("hours_coverage numeric(6,5)", self.sql)
        self.assertIn("authoritative_estimated_hours_sum is null", self.sql)
        self.assertIn("legacy_estimated_hours_sum=0", self.sql)
        self.assertIn("estimated_hours',ol.estimated_hours", self.sql)

    def test_immutable_security_and_no_outbound(self):
        for marker in ("on delete restrict", "enable row level security", "force row level security", "revoke all on table", "revoke all on function public.submit_pdc_historical_reconciliation_778"):
            self.assertIn(marker, self.sql)
        for forbidden in ("update public.pdc_historical_reconciliation_778_receipts", "delete from public.pdc_historical_reconciliation_778_receipts", "send email", "imap", "create outbox"):
            self.assertNotIn(forbidden, self.sql)

if __name__ == "__main__":
    unittest.main(verbosity=2)
