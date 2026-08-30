from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830247000_826_historical_vehicle_freshness_successor.sql"


class HistoricalVehicleImporterFreshness826ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_vehicle_importer_freshness_uses_verified_historical_context(self):
        self.assertIn("v_historical_context", self.sql)
        self.assertIn("p_source_received_at<clock_timestamp()-interval '30 days'", self.sql)
        self.assertIn("pdc_historical_writer_authorized_773", self.sql)
        self.assertIn("pdc_826_current_head_or_vehicle_prestate_failed", self.sql)
        self.assertIn("pdc_826_historical_vehicle_freshness_postcondition_failed", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
