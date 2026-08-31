import unittest

from backend.pdc_email_ai_successor_acceptance import run_synthetic_acceptance


class SyntheticAcceptanceTests(unittest.TestCase):
    def test_synthetic_acceptance_proves_replay_partial_isolation_and_disable(self):
        result = run_synthetic_acceptance()
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["atomic_multi_action"], "SUCCESS")
        self.assertTrue(result["exact_replay_zero_duplicate_effects"])
        self.assertTrue(result["unrelated_vehicle_isolation"])
        self.assertEqual(result["partial_action"], "PARTIAL_FAILURE")
        self.assertEqual(result["disable_fail_closed"], "successor_disabled")
        self.assertFalse(result["production_writes"])
        self.assertFalse(result["outbound_email"])


if __name__ == "__main__":
    unittest.main()
