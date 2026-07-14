import tempfile
import unittest
from pathlib import Path
from unittest import mock

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

    def test_repair_order_labels_do_not_override_vehicle_or_create_pit_work(self):
        record = {"id": "mail-1", "received_at": "2026-07-14T06:45:02Z"}
        attachments = """
CUSTOMER:\n\n67401
VEHICLE:\n\nMONTH/YEAR:
EWN QC Time Required:
VEHICLE:\n\nRAV4 AWD 2.5L Hyb CVT GX (SS) 7460930 001
STOCK No.: 13037843
JOB CARD No.: J139125129
P.O. No. GP10223986
Customer: North Regional Tafe, North Regional Tafe
M1 Tint
Nudge Bar - Black
WIRE PARKING SENSOR EXTENSION
"""
        vehicle = publisher.parse_vehicle_from_text(record, "Order 13037843", "", attachments)
        self.assertIsNotNone(vehicle)
        self.assertEqual(vehicle.vehicle, "RAV4 AWD 2.5L Hyb CVT GX (SS) 7460930 001")
        self.assertEqual(vehicle.client, "North Regional Tafe")
        self.assertEqual(vehicle.purchaseOrderNumber, "GP10223986")
        self.assertFalse(vehicle.pdcRequiresPitInspection)

    def test_public_vehicle_removes_raw_mailbox_fields(self):
        sanitized = publisher.sanitize_public_vehicle({
            "stock": "13037843",
            "sourceRow": "Email intake",
            "source": "Email intake · mailbox@example.com",
            "notes": "raw email body",
            "sourceEmailSubject": "private subject",
            "sourceEmailSender": "sender@example.com",
        })
        self.assertNotIn("notes", sanitized)
        self.assertNotIn("sourceEmailSubject", sanitized)
        self.assertNotIn("sourceEmailSender", sanitized)
        self.assertEqual(sanitized["source"], "Email intake")
    def test_git_commit_is_scoped_to_generated_paths(self):
        output = publisher.ROOT / "email-board-data.js"
        with mock.patch.object(publisher, "run", side_effect=["", "M email-board-data.js", "", ""]) as run:
            self.assertTrue(publisher.git_commit_push("publish", [output]))
        commit_cmd = run.call_args_list[2].args[0]
        self.assertEqual(commit_cmd[:3], ["git", "commit", "--only"])
        self.assertEqual(commit_cmd[-2:], ["--", "email-board-data.js"])


if __name__ == "__main__":
    unittest.main()
