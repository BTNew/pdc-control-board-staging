import hashlib
import json
import tempfile
import unittest
from email.message import EmailMessage
from pathlib import Path

from backend.pdc_email_ai_successor_intake import (
    EvidenceStore,
    bounded_retry_delay,
    capture_rfc822_evidence,
)


class IntakeTests(unittest.TestCase):
    def make_message(self, filename="job-card.pdf", payload=b"%PDF-1.7 synthetic"):
        message = EmailMessage()
        message["From"] = "workshop@example.test"
        message["To"] = "pdc@example.test"
        message["Subject"] = "Synthetic evidence"
        message["Message-ID"] = "<message-123@example.test>"
        message["References"] = "<thread-9@example.test>"
        message.set_content("Complete correspondence body, including every instruction.")
        message.add_attachment(payload, maintype="application", subtype="pdf", filename=filename)
        return message.as_bytes()

    def test_capture_retains_original_email_attachment_digests_and_thread_metadata(self):
        raw = self.make_message()
        with tempfile.TemporaryDirectory() as temp:
            receipt = EvidenceStore(Path(temp)).capture(
                raw,
                mailbox="pdc@example.test",
                provider_uid="provider:123",
                received_at="2026-08-31T01:00:00+00:00",
            )
            self.assertEqual(receipt["source_digest"], hashlib.sha256(raw).hexdigest())
            self.assertEqual(receipt["thread_id"], "<thread-9@example.test>")
            self.assertEqual(receipt["status"], "RECEIVED")
            self.assertEqual(len(receipt["attachments"]), 1)
            attachment = receipt["attachments"][0]
            self.assertEqual(attachment["digest"], hashlib.sha256(b"%PDF-1.7 synthetic").hexdigest())
            root = Path(temp).resolve()
            self.assertEqual((root / receipt["source_path"]).read_bytes(), raw)
            self.assertEqual((root / attachment["path"]).read_bytes(), b"%PDF-1.7 synthetic")
            self.assertIn("Complete correspondence body", receipt["correspondence"])

    def test_same_source_is_idempotent_and_does_not_duplicate_files_or_receipts(self):
        raw = self.make_message()
        with tempfile.TemporaryDirectory() as temp:
            store = EvidenceStore(Path(temp))
            first = store.capture(raw, mailbox="pdc@example.test", provider_uid="provider:123")
            second = store.capture(raw, mailbox="pdc@example.test", provider_uid="provider:123")
            self.assertEqual(first["receipt_id"], second["receipt_id"])
            self.assertTrue(second["duplicate"])
            receipts = list((Path(temp) / "receipts").glob("*.json"))
            self.assertEqual(len(receipts), 1)
            self.assertEqual(len([path for path in (Path(temp) / "attachments").rglob("*") if path.is_file()]), 1)

    def test_untrusted_filename_is_confined_and_never_becomes_a_path(self):
        raw = self.make_message("../../outside.sh")
        evidence = capture_rfc822_evidence(raw, mailbox="pdc@example.test", provider_uid="provider:124")
        self.assertEqual(len(evidence["attachments"]), 1)
        filename = evidence["attachments"][0]["filename"]
        self.assertNotIn("/", filename)
        self.assertNotIn("\\", filename)
        self.assertFalse(filename.startswith("."))

    def test_retry_delay_is_bounded_and_deterministic(self):
        self.assertEqual(bounded_retry_delay(0), 1)
        self.assertEqual(bounded_retry_delay(1), 2)
        self.assertEqual(bounded_retry_delay(20), 300)
        self.assertEqual(bounded_retry_delay(99), 300)


if __name__ == "__main__":
    unittest.main()
