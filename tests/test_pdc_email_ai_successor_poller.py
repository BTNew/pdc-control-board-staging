import unittest
from pathlib import Path


class PollerContractTests(unittest.TestCase):
    def test_successor_poller_is_read_only_and_not_business_processor(self):
        path = Path(__file__).resolve().parents[1] / "backend" / "pdc_email_ai_successor_poller.py"
        source = path.read_text(encoding="utf-8")
        self.assertIn("readonly=True", source)
        self.assertIn("--enable", source)
        self.assertIn("EvidenceStore", source)
        self.assertNotIn("client.uid(\"STORE\"", source)
        self.assertNotIn("supabase_client", source.lower())
        self.assertNotIn("apply_pdc_", source)
        self.assertNotIn("update_pdc_", source)

    def test_default_poller_does_not_contact_mailbox(self):
        path = Path(__file__).resolve().parents[1] / "backend" / "pdc_email_ai_successor_poller.py"
        source = path.read_text(encoding="utf-8")
        self.assertIn('if not args.enable:', source)
        self.assertIn('"contacted_mailbox": False', source)


if __name__ == "__main__":
    unittest.main()
