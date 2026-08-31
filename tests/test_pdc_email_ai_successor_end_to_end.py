import tempfile
import unittest
from email.message import EmailMessage
from pathlib import Path

from backend.pdc_email_ai_successor_acceptance import SyntheticStagingClient
from backend.pdc_email_ai_successor_intake import EvidenceStore
from backend.pdc_email_ai_successor_runtime import process_evidence


class EndToEndAcceptanceTests(unittest.TestCase):
    def test_evidence_to_typed_plan_to_authoritative_readback(self):
        message = EmailMessage()
        message["From"] = "workshop@example.test"
        message["To"] = "pdc@example.test"
        message["Subject"] = "Parts update"
        message["Message-ID"] = "<e2e@example.test>"
        message.set_content("Stock 13000765 parts ETA 15 September 2026.")
        raw = message.as_bytes()
        with tempfile.TemporaryDirectory() as temp:
            receipt = EvidenceStore(Path(temp)).capture(raw, mailbox="pdc@example.test", provider_uid="provider:e2e")
            client = SyntheticStagingClient()
            outcome = process_evidence(
                receipt,
                [{"filename": "notice.pdf", "digest": "c" * 64, "extracted_text": ""}],
                [{
                    "vehicle_id": "22222222-2222-4222-8222-222222222222",
                    "identity": {"stock_number": "13000765", "vin": None, "backend_record_id": None},
                    "version": 9,
                    "state": {},
                }],
                client,
            )
            self.assertTrue(outcome["ok"], outcome)
            self.assertEqual(outcome["readback"]["checks"][0]["actual"], "2026-09-15")
            self.assertFalse(client.production_writes)
            self.assertFalse(client.outbound_email)


if __name__ == "__main__":
    unittest.main()
