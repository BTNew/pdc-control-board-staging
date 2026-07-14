import tempfile
import unittest
from pathlib import Path

import email_board_publisher as publisher


class EmailBoardPublisherTests(unittest.TestCase):
    def test_structured_parts_updates_are_review_only(self):
        record = {
            "id": "email-1",
            "sender_email": "parts@example.com",
            "received_at": "2026-07-14T01:00:00Z",
            "subject": "Parts update",
            "parsed_text": (
                "Stock: 12666620\nParts: complete\nNotes: Towbar kit arrived\n\n"
                "Stock: 13010530\nParts: stoppage\nReason: Supplier backorder\nETA: 25/07/2026\n"
            ),
        }
        proposals = publisher.parse_parts_review_actions(record)
        self.assertEqual(len(proposals), 2)
        self.assertEqual(proposals[0]["action"], "complete")
        self.assertEqual(proposals[0]["notes"], "Towbar kit arrived")
        self.assertEqual(proposals[1]["action"], "stoppage")
        self.assertEqual(proposals[1]["reason"], "Supplier backorder")
        self.assertEqual(proposals[1]["eta"], "25/07/2026")

    def test_unstructured_email_creates_no_action(self):
        self.assertEqual(publisher.parse_parts_review_actions({"id": "x", "parsed_text": "Please check this job"}), [])

    def test_generated_payload_keeps_reviews_separate(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "email-board-data.js"
            reviews = [{"id": "e:1234:parts:complete", "stock": "1234", "action": "complete"}]
            self.assertTrue(publisher.write_generated(path, [], reviews))
            loaded = publisher.read_existing_generated(path)
            self.assertEqual(loaded["vehicles"], [])
            self.assertEqual(loaded["reviews"], reviews)
            self.assertFalse(publisher.write_generated(path, [], reviews))


if __name__ == "__main__":
    unittest.main()
