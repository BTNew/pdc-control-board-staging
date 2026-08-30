from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830242000_821_historical_proposal_freshness_successor.sql"


class HistoricalActivationFreshness821ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_auto_activation_expiry_is_historical_authorization_gated(self):
        self.assertIn(
            "or (v_proposal.source_received_at<clock_timestamp()-interval '30 days' and not public.pdc_historical_writer_authorized_773(v_proposal.source_hash,v_proposal.source_uid,lower(btrim(coalesce(v_proposal.sender_address,''))),v_proposal.authentication,public.normalize_vehicle_stock_number(v_proposal.stock_number))) then",
            self.sql,
        )
        self.assertIn("pdc_monitor_staging_guard", self.sql)
        self.assertIn("pdc_production_environment_sentinel", self.sql)
        self.assertIn("revoke all on function public.pdc_auto_apply_ai_intake_activation_internal_pre310", self.sql)
        self.assertIn("grant execute on function public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean) to postgres", self.sql)
        self.assertNotIn("update public.pdc_historical_reconciliation_writer_authorizations_773", self.sql)
        self.assertNotIn("delete from public.pdc_historical_reconciliation_writer_authorizations_773", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
