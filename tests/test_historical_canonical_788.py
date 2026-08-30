import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CALLER = ROOT / "pdc_historical_778_caller.py"


def load_caller():
    spec = importlib.util.spec_from_file_location("historical_788_caller", CALLER)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class HistoricalCanonical788Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = load_caller()

    def row(self):
        return {
            "manifest_sha256": self.m.MANIFEST_SHA256,
            "manifest_uidvalidity": 1,
            "manifest_high_water_uid": 685,
            "manifest_uid_count": 669,
            "provider_uid": "1:22",
            "parent_source_hash": "a" * 64,
            "sender_email": "andy.weir@broometoyota.com.au",
            "authentication": {"gmail_authentication_results": True, "dkim_aligned": False, "dmarc_aligned": False, "sender_domain": "broometoyota.com.au", "spf_aligned": True},
            "stock_number": "13047257",
            "source_received_at": "2026-01-01T00:00:00+00:00",
            "source_metadata": {
                "received_at": "2026-01-01T00:00:00+00:00", "attachment_names": ["Pick.pdf"],
                "graph_message_id": "imap:1:22", "internet_message_id": "<m@example.test>",
                "parsed_text": "", "provider_authserv_id": "mx.google.com", "raw_body": "",
                "recipient_mailbox": "pmbcontroller@gmail.com", "sender_name": "Andy", "uid": 22, "uidvalidity": 1,
            },
            "subject": "Véhicule", "action_type": "review_only", "summary": "Vehicle evidence",
            "evidence_hash": "e" * 64, "observations": {},
            "attachments": [{"attachment_kind": "job_card", "content_type": "application/pdf", "filename": "Pick.pdf", "ordinal": 1, "sha256": "c" * 64, "size": 10}],
            "job_card_children": [{"attachment_hash": "c" * 64, "attachment_kind": "job_card", "extraction_hash": "d" * 64, "extraction": {"email_vehicle": {"job_card_number": "J1"}}}],
        }

    def test_utf8_is_length_prefixed_by_bytes_and_null_differs_from_empty(self):
        self.assertIn(b"1:x=2:", self.m._canonical_field("x", "é"))
        self.assertNotEqual(self.m._canonical_field("x", None), self.m._canonical_field("x", ""))

    def test_fixed_order_is_stable_and_digest_changes_on_occurrence_or_kind(self):
        request = self.m.build_historical_request(self.row())
        original = self.m.canonical_request_digest(request)
        reordered = dict(reversed(list(request.items())))
        self.assertEqual(original, self.m.canonical_request_digest(reordered))
        request["attachment_manifest"][0]["ordinal"] = 2
        self.assertNotEqual(original, self.m.canonical_request_digest(request))
        request = self.m.build_historical_request(self.row())
        request["attachment_manifest"][0]["attachment_kind"] = "non_job_card_sibling"
        self.assertNotEqual(original, self.m.canonical_request_digest(request))

    def test_canonical_echo_is_exact_and_includes_runtime_actor_manifest_and_children(self):
        request = self.m.build_historical_request(self.row())
        echoed = request["canonical_request_utf8"]
        for marker in ("contract_version", "actor_id", "runtime_task_enabled", "manifest_sha256", "observations_jsonb", "attachment[1].ordinal", "child[1].attachment_kind", "child[1].extraction_jsonb"):
            self.assertIn(marker, echoed)
        request["canonical_request_utf8"] = echoed.replace("runtime_task_enabled", "runtime_task_enabled_drift", 1)
        self.assertNotEqual(request["canonical_request_utf8"], self.m.canonical_request_bytes(request).decode("utf-8"))

    def test_request_canonical_digest_omits_no_caller_supplied_digest(self):
        request = self.m.build_historical_request(self.row())
        self.assertNotIn("request_sha256", request)
        self.assertNotIn("observation_sha256", request)
        self.assertEqual(self.m.canonical_request_digest(request), self.m._sha256(self.m.canonical_request_bytes(request)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
