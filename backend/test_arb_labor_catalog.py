import unittest

import build_arb_labor_catalog as builder


class ArbLaborCatalogTests(unittest.TestCase):
    def test_accepts_explicit_time_and_verified_fitting_charge(self):
        text = """
TOYOTA
Dealer Fitting Dealer Retail
(SS177HF) Safari Snorkel 578.85 560.00 1138.85 1241.00
(NAC13U) Flush Mount Kit, Add 1.0hr Fitting Time 100.00 100.00
"""
        result = builder.parse_catalog(text)
        self.assertEqual(result["entries"]["SS177HF"]["hours"], 3.5)
        self.assertEqual(result["entries"]["SS177HF"]["page"], 2)
        self.assertEqual(result["entries"]["NAC13U"]["hours"], 1.0)

    def test_rejects_unproved_price_columns_and_marks_conflicting_code_ambiguous(self):
        text = """
(ABC123) Invalid arithmetic 500.00 160.00 999.00 1100.00
(LX110) Vehicle A 803.25 480.00 1283.25 1400.00
(LX110) Vehicle B 803.25 640.00 1443.25 1585.00
"""
        result = builder.parse_catalog(text)
        self.assertNotIn("ABC123", result["entries"])
        self.assertNotIn("LX110", result["entries"])
        self.assertEqual({item["hours"] for item in result["ambiguous"]["LX110"]}, {3.0, 4.0})

    def test_does_not_assign_a_bundle_fitting_charge_to_each_component_code(self):
        result = builder.parse_catalog("(AAA123, BBB456) Combined kit 500.00 320.00 820.00 900.00")
        self.assertNotIn("AAA123", result["entries"])
        self.assertNotIn("BBB456", result["entries"])


if __name__ == "__main__":
    unittest.main()
