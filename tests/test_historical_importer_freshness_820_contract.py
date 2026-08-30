from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830241000_820_historical_importer_freshness_successor.sql"


class HistoricalImporterFreshness820ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.body = cls.sql.split("as $function$", 1)[1].split("revoke all on function", 1)[0]

    def test_historical_authorization_gates_extended_freshness(self):
        self.assertIn(
            "or (v_intake.received_at<clock_timestamp()-interval '30 days' and not public.pdc_historical_writer_authorized_773(v_parent_hash,coalesce(v_intake.provider_uid,''),v_sender,v_auth,v_email_vehicle->'stock_numbers'->>0))",
            self.body,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
