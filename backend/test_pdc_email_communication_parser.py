import unittest

try:
    from backend.pdc_email_communication_parser import MAX_TEXT_CHARS, parse_communication_actions
except ModuleNotFoundError:
    from pdc_email_communication_parser import MAX_TEXT_CHARS, parse_communication_actions


class CommunicationParserTests(unittest.TestCase):
    def test_parts_complete_exact_vehicle(self):
        result = parse_communication_actions("Stock 12657478. Parts Complete.")
        self.assertTrue(result["auto_applicable"])
        self.assertEqual(result["actions"][0]["action_type"], "parts_complete")

    def test_parts_incomplete_is_not_applied(self):
        result = parse_communication_actions("Stock 12657478. Parts are not complete.")
        self.assertFalse(result["auto_applicable"])
        self.assertEqual(result["actions"], [])
        self.assertIn("parts_completion_negated_or_uncertain", result["review_reasons"])
        for text in (
            "Stock 12657478. Parts aren't complete.",
            "Stock 12657478. Parts will be complete tomorrow.",
            "Stock 12657478. Parts are almost complete.",
            "Stock 12657478. Are parts complete?",
            "Stock 12657478. Parts 90% complete.",
            "Stock 12657478. Parts are ready to order.",
        ):
            with self.subTest(text=text):
                candidate = parse_communication_actions(text)
                self.assertFalse(candidate["auto_applicable"])
                self.assertNotIn("parts_complete", [a.get("action_type") for a in candidate["actions"]])

    def test_sublet_australian_date(self):
        result = parse_communication_actions("JC J139124136 - Sublet booked for 14/08/2026.")
        self.assertTrue(result["auto_applicable"])
        self.assertEqual(result["actions"][0]["booking_date"], "2026-08-14")

    def test_sublet_iso_date(self):
        result = parse_communication_actions("Stock 12657478. Sublet booking scheduled 2026-08-15.")
        self.assertTrue(result["auto_applicable"])
        self.assertEqual(result["actions"][0]["booking_date"], "2026-08-15")

    def test_sublet_written_date(self):
        result = parse_communication_actions("Stock 12657478. Sublet booked 16 August 2026.")
        self.assertTrue(result["auto_applicable"])
        self.assertEqual(result["actions"][0]["booking_date"], "2026-08-16")

    def test_relative_sublet_date_requires_review(self):
        result = parse_communication_actions("Stock 12657478. Sublet booked tomorrow.")
        self.assertFalse(result["auto_applicable"])
        self.assertIn("sublet_booking_date_missing_or_ambiguous", result["review_reasons"])
        for text in (
            "Stock 12657478. Sublet not booked for 14/08/2026.",
            "Stock 12657478. Sublet will be booked for 14/08/2026.",
            "Stock 12657478. Proposed sublet booking 14/08/2026.",
            "Stock 12657478. Can sublet be booked for 14/08/2026?",
        ):
            with self.subTest(text=text):
                candidate = parse_communication_actions(text)
                self.assertFalse(candidate["auto_applicable"])
                self.assertNotIn("set_sublet_booking_date", [a.get("action_type") for a in candidate["actions"]])

    def test_long_range_tank_adds_unscheduled_fitting_work(self):
        result = parse_communication_actions("Stock 12657478. Please add long range tank to this job.")
        self.assertTrue(result["auto_applicable"])
        action = result["actions"][0]
        self.assertEqual(action["action_type"], "add_accessory_work")
        self.assertEqual(action["description"], "Long range tank")
        self.assertEqual(action["work_key"], "fitting")
        self.assertNotIn("booking_date", action)

    def test_known_electrical_accessory(self):
        result = parse_communication_actions("Job Card J139124136. Add UHF to this vehicle.")
        self.assertTrue(result["auto_applicable"])
        self.assertEqual(result["actions"][0]["work_key"], "electrical")

    def test_unknown_accessory_requires_review(self):
        result = parse_communication_actions("Stock 12657478. Please add custom mystery package to this job.")
        self.assertFalse(result["auto_applicable"])
        self.assertIn("accessory_not_in_approved_vocabulary", result["review_reasons"])

    def test_remove_accessory_does_not_add(self):
        result = parse_communication_actions("Stock 12657478. Please remove and add long range tank to this job.")
        self.assertFalse(result["auto_applicable"])
        self.assertEqual(result["actions"], [])

    def test_missing_identity_fails_closed(self):
        result = parse_communication_actions("Parts complete.")
        self.assertFalse(result["auto_applicable"])
        self.assertIn("vehicle_identity_missing", result["review_reasons"])

    def test_ambiguous_stock_fails_closed(self):
        result = parse_communication_actions("Stock 12657478 and Stock 99999999. Parts complete.")
        self.assertFalse(result["auto_applicable"])
        self.assertIn("vehicle_identity_ambiguous", result["review_reasons"])

    def test_duplicate_same_identity_is_not_ambiguous(self):
        result = parse_communication_actions("Stock 12657478. Stock 12657478 parts complete.")
        self.assertTrue(result["auto_applicable"])
        self.assertEqual(result["identity"]["stock_numbers"], ["12657478"])

    def test_multiple_actions_preserve_source_order(self):
        result = parse_communication_actions(
            "Stock 12657478. Parts complete. Sublet booked 14/08/2026. Please add long range tank to this job."
        )
        self.assertTrue(result["auto_applicable"])
        self.assertEqual([item["source_action_no"] for item in result["actions"]], [1, 2, 3])
        self.assertEqual(len(result["actions"]), 3)

    def test_unbounded_or_binary_text_fails_closed(self):
        self.assertFalse(parse_communication_actions("x" * (MAX_TEXT_CHARS + 1))["auto_applicable"])
        self.assertFalse(parse_communication_actions("Stock 12657478\x00 Parts complete")["auto_applicable"])


if __name__ == "__main__":
    unittest.main()
