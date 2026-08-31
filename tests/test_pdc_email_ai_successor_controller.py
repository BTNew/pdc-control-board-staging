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


if __name__ == "__main__":
    unittest.main()
