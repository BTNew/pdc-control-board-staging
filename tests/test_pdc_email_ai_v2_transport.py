import tempfile
import unittest
from email.message import EmailMessage
from pathlib import Path

from backend.pdc_email_ai_successor_intake import EvidenceStore
from backend.pdc_email_ai_v2_queue import DurableQueue, QueueConflict, QueueOwnershipError
from backend.pdc_email_ai_v2_shadow import classify_shadow_description, compare_shadow, load_frozen_taxonomy_audit
from backend.pdc_email_ai_v2_transport import MailboxCursor, ReadOnlyImapTransport, build_planner_input


class FakeImap:
    def __init__(self, raw: bytes):
        self.raw = raw
        self.calls = []
        self.selected = None

    def login(self, username, password):
        self.calls.append(("login", username, password))
        return "OK", [b"logged"]

    def select(self, folder, readonly=False):
        self.calls.append(("select", folder, readonly))
        self.selected = folder
        return "OK", [b"1"]

    def response(self, name):
        self.calls.append(("response", name))
        return "OK", [b"1"]

    def uid(self, command, *args):
        uid = args[0] if args else None
        query = args[-1] if args else None
        self.calls.append((command, uid, query))
        if command == "SEARCH":
            return "OK", [b"1"]
        if query == "(FLAGS)":
            return "OK", [(b"1 (FLAGS (\\Seen))", None)]
        return "OK", [(b'1 (UID 1 INTERNALDATE "01-Sep-2026 01:02:03 +0000" FLAGS (\\Seen) BODY[]', self.raw), b")"]

    def close(self):
        self.calls.append(("close",))
        return "OK", []

    def logout(self):
        self.calls.append(("logout",))
        return "BYE", []


def message() -> bytes:
    value = EmailMessage()
    value["From"] = "ops@example.test"
    value["To"] = "pdc@example.test"
    value["Subject"] = "Stock 13017855"
    value["Message-ID"] = "<v2@example.test>"
    value["References"] = "<thread@example.test>"
    value.set_content("Stock 13017855\nReflective Stripes - Yellow")
    value.add_attachment(b"%PDF-1.7", maintype="application", subtype="pdf", filename="job.pdf")
    return value.as_bytes()


class QueueTests(unittest.TestCase):
    def test_claim_heartbeat_expiry_recovery_and_idempotent_enqueue(self):
        now = [1000.0]
        with tempfile.TemporaryDirectory() as temp:
            queue = DurableQueue(Path(temp) / "v2.sqlite", clock=lambda: now[0])
            digest = "a" * 64
            first = queue.enqueue(source_digest=digest, receipt_path="/e/a.json", mailbox="pdc@example.test", folder="Inbox", uidvalidity=1, uid=1)
            duplicate = queue.enqueue(source_digest=digest, receipt_path="/e/a.json", mailbox="pdc@example.test", folder="Inbox", uidvalidity=1, uid=1)
            self.assertFalse(first["duplicate"])
            self.assertTrue(duplicate["duplicate"])
            claim = queue.claim("worker-a", lease_seconds=15)
            self.assertEqual(claim["attempts"], 1)
            queue.heartbeat(claim["item_key"], "worker-a", lease_seconds=15)
            now[0] += 16
            self.assertEqual(queue.recover_expired(), 1)
            recovered = queue.claim("worker-b", lease_seconds=15)
            self.assertEqual(recovered["item_key"], claim["item_key"])
            with self.assertRaises(QueueOwnershipError):
                queue.finish(claim["item_key"], "worker-a", {"ok": True})
            queue.finish(claim["item_key"], "worker-b", {"ok": True})
            self.assertEqual(queue.counts(), {"QUEUED": 0, "RUNNING": 0, "COMPLETED": 1, "REVIEW": 0})

    def test_uidvalidity_change_and_reused_checkpoint_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            queue = DurableQueue(Path(temp) / "v2.sqlite")
            queue.advance_checkpoint(folder="Inbox", uidvalidity=1, uid=4, source_digest="b" * 64)
            with self.assertRaises(QueueConflict):
                queue.advance_checkpoint(folder="Inbox", uidvalidity=2, uid=5, source_digest="c" * 64)
            with self.assertRaises(QueueConflict):
                queue.advance_checkpoint(folder="Inbox", uidvalidity=1, uid=4, source_digest="c" * 64)


class TransportTests(unittest.TestCase):
    def test_read_only_body_peek_capture_queue_and_checkpoint(self):
        raw = message()
        fake = FakeImap(raw)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            queue = DurableQueue(root / "queue.sqlite")
            transport = ReadOnlyImapTransport(EvidenceStore(root / "evidence"), queue, client_factory=lambda *args, **kwargs: fake)
            rows = transport.poll(host="imap.example.test", username="pdc@example.test", password="secret", cursors=[MailboxCursor("Inbox", 1, 0)])
            self.assertEqual(len(rows), 1)
            self.assertTrue(rows[0]["flags_unchanged"])
            self.assertEqual(queue.counts()["QUEUED"], 1)
            self.assertEqual(queue.checkpoint("Inbox")["high_water_uid"], 1)
            self.assertIn(("select", '"Inbox"', True), fake.calls)
            fetch_queries = [call[2] for call in fake.calls if call[0] == "FETCH"]
            self.assertTrue(any("BODY.PEEK[]" in query for query in fetch_queries))
            self.assertFalse(any("STORE" in str(call).upper() for call in fake.calls))
            receipt = next((root / "evidence" / "receipts").glob("*.json"))
            self.assertTrue(receipt.is_file())

    def test_planner_input_retains_correspondence_and_each_attachment(self):
        raw = message()
        with tempfile.TemporaryDirectory() as temp:
            receipt = EvidenceStore(Path(temp)).capture(raw, mailbox="pdc@example.test", provider_uid="imap:Inbox:1:1", transport_metadata={"read_only": True})
            digest = receipt["attachments"][0]["digest"]
            planner_input = build_planner_input(receipt, [{"digest": digest, "filename": "job.pdf", "extraction_status": "READY", "extracted_text": "FMG GVM decals"}])
            self.assertIn("Reflective Stripes", planner_input["correspondence"])
            self.assertEqual(planner_input["attachments"][0]["evidence_ref"], f"attachment:{digest}")
            self.assertTrue(planner_input["instruction_accounting"]["unclassified_text_must_be_preserved"])

    def test_unsupported_attachment_is_retained_in_source_only(self):
        value = EmailMessage()
        value["From"] = "ops@example.test"
        value["To"] = "pdc@example.test"
        value.set_content("untrusted attachment")
        value.add_attachment(b"MZ", maintype="application", subtype="x-msdownload", filename="payload.exe")
        with tempfile.TemporaryDirectory() as temp:
            receipt = EvidenceStore(Path(temp)).capture(value.as_bytes(), mailbox="pdc@example.test", provider_uid="provider:exe")
            self.assertEqual(receipt["attachments"][0]["status"], "REJECTED_UNSUPPORTED")
            self.assertNotIn("path", receipt["attachments"][0])
            self.assertEqual(list((Path(temp) / "attachments").rglob("*")), [])


class ShadowTests(unittest.TestCase):
    def test_frozen_handoff_is_verified_and_mixed_fmg_gvm_is_not_hoist(self):
        frozen = load_frozen_taxonomy_audit()
        self.assertEqual(frozen["audit"]["scope"]["physical_messages"], 100)
        result = classify_shadow_description("FMG Signage 75mm Safety stripping, FMG Logo's, ID, Tare,GVM,GCM Decals")
        self.assertIsNone(result["work_group"])
        self.assertEqual(result["disposition"], "REVIEW")
        self.assertEqual(result["reason"], "mixed_fmg_signage_gvm_decal_not_hoist")

    def test_frozen_required_fixture_families_and_full_instruction_accounting(self):
        frozen = load_frozen_taxonomy_audit()["audit"]
        fixtures = frozen["required_regression_fixtures"]
        comparison = compare_shadow([
            {"description": row["description"], "stock": row["stock"], "job_card": row["job_card"], "source_hash": "d" * 64}
            for row in fixtures
        ])
        self.assertEqual(comparison["instruction_count"], len(fixtures))
        self.assertTrue(comparison["all_instructions_accounted"])
        self.assertFalse(comparison["operational_writes_attempted"])
        by_description = {row["description"]: row for row in comparison["decisions"]}
        self.assertEqual(by_description["FMG Signage 75mm Safety stripping, FMG Logo's, ID, Tare,GVM,GCM Decals"]["disposition"], "REVIEW")
        self.assertEqual(by_description["1.0 KG FIRE EXTINGUISHER"]["v2_work_group"], "FABRICATION")
        self.assertEqual(by_description["OME 3550Kg Nitro+ GVM Basic Includes Wheel Alignment"]["v2_work_group"], "HOIST")
        self.assertEqual(by_description["Reflective Stripes - Yellow"]["disposition"], "REVIEW")
        self.assertEqual(by_description["Reflective Stripes - Yellow; SUBLET"]["disposition"], "REVIEW")

    def test_explicit_sublet_evidence_is_required(self):
        result = classify_shadow_description("Reflective Stripes - Yellow", explicit_job_card_sublet=True)
        self.assertEqual(result["work_group"], "SUBLET")
        self.assertEqual(result["disposition"], "PLANNED")


if __name__ == "__main__":
    unittest.main()
