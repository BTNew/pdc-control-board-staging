import json
import unittest
from pathlib import Path


class VehicleIntelligenceFixtureTests(unittest.TestCase):
    def setUp(self):
        self.path = Path(__file__).resolve().parent / "test_fixtures" / "vehicle_intelligence_emails.json"
        self.rows = json.loads(self.path.read_text(encoding="utf-8"))

    def test_fixture_ids_and_message_ids_are_unique(self):
        fixture_ids = [row["fixture_id"] for row in self.rows]
        message_ids = [row["message_id"] for row in self.rows]
        self.assertEqual(len(fixture_ids), len(set(fixture_ids)))
        self.assertEqual(len(message_ids), len(set(message_ids)))

    def test_every_fixture_is_synthetic_and_non_production(self):
        for row in self.rows:
            joined = json.dumps(row).lower()
            self.assertIn("synthetic", joined)
            self.assertIn("example.invalid", joined)
            self.assertNotIn("@gmail.com", joined)
            self.assertNotIn("@outlook.com", joined)
            self.assertNotIn("@toyota.com", joined)

    def test_required_fields_exist(self):
        required_top = {
            "fixture_id", "mailbox_key", "message_id", "thread_id", "internet_message_id",
            "sender_name", "sender_email", "recipient_mailbox", "subject", "received_at",
            "parsed_text", "expected",
        }
        for row in self.rows:
            self.assertTrue(required_top.issubset(row.keys()))
            expected = row["expected"]
            self.assertIn("primary_identifier", expected)
            self.assertIn("categories", expected)
            self.assertIn("review_required", expected)
            self.assertIsInstance(expected["categories"], list)
            self.assertGreater(len(expected["categories"]), 0)

    def test_fixture_set_covers_stage_one_scenarios(self):
        fixture_ids = {row["fixture_id"] for row in self.rows}
        self.assertTrue({
            "stock-parts-in-stock-001",
            "vin-parts-delay-relative-001",
            "thread-context-jobcard-001",
            "ambiguous-stock-customer-001",
            "dispatch-tracking-001",
            "salesperson-eta-request-001",
        }.issubset(fixture_ids))


if __name__ == "__main__":
    unittest.main()
