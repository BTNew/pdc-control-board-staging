import unittest
from pathlib import Path


class ControllerContractTests(unittest.TestCase):
    def test_controller_is_staging_bound_and_readback_bound(self):
        source = (Path(__file__).resolve().parents[1] / "scripts" / "apply_pdc_email_ai_successor_staging.py").read_text(encoding="utf-8")
        self.assertIn("PDC_STAGING_DATABASE_URL", source)
        self.assertIn("PDC_STAGING_SSLROOTCERT", source)
        self.assertIn("PDC_SUCCESSOR_NON_STAGING_TARGET", source)
        self.assertIn("PDC_SUCCESSOR_PRODUCTION_SENTINEL_PRESENT", source)
        self.assertIn("PDC_SUCCESSOR_UNEXPECTED_LIVE_HEAD", source)
        self.assertIn("PDC_SUCCESSOR_POST_APPLY_READBACK_FAILED", source)
        self.assertIn("apply_pdc_email_ai_transaction_successor(jsonb)", source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)
        self.assertNotIn("PDC_PRODUCTION", source)

    def test_contract_repair_controller_is_separate_and_current_head_bound(self):
        path = Path(__file__).resolve().parents[1] / "scripts" / "apply_pdc_email_ai_successor_contract_repair_staging.py"
        source = path.read_text(encoding="utf-8")
        self.assertIn("20260831310000", source)
        self.assertIn("20260831320000", source)
        self.assertIn("PDC_APPROVE_STAGING_MIGRATION_862", source)
        self.assertIn("PDC_SUCCESSOR_REPAIR_POST_APPLY_READBACK_FAILED", source)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", source)


if __name__ == "__main__":
    unittest.main()
