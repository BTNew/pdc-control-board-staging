from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830245000_824_historical_vehicle_creation_successor.sql"


class HistoricalActivationCreation824ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_no_vehicle_historical_branch_reconciles_before_postcondition(self):
        self.assertIn("reconcile_navision_operational_record_pre171(v_record.id,p_actor_id,v_actor_email)", self.sql)
        self.assertIn("pdc_ai_intake_135_postcondition_failed", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
