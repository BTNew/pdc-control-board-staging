from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "backend/email_intake_processor_successor_20260871.py"


def load_processor():
    spec = importlib.util.spec_from_file_location("email_intake_processor_storage_quarantine_20260871", SOURCE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


EXACT = {
    "ok": True,
    "contract": "pdc_email_monitor_attachments_735",
    "scope": "authenticated-active-839",
    "review_required": True,
    "attachment_storage_incomplete": True,
    "storage_reconciliation_required": True,
    "attachment_count": 2,
    "readable_attachment_count": 1,
    "incomplete_attachment_count": 1,
    "board_mutated": False,
    "mailbox_flags_changed": False,
    "uid514_processed": False,
    "production_writes": False,
}


class MonitorAuthenticatedStorageQuarantine20260871Tests(unittest.TestCase):
    def test_exact_authenticated_missing_object_quarantines_before_projection(self):
        module = load_processor()
        client = module.SupabaseClient.__new__(module.SupabaseClient)
        client.gateway_instance_id = "pdc-monitor-staging-sales-uid509-v1"
        client.rpc = Mock(return_value=EXACT)
        with self.assertRaises(module.HistoricalStorageQuarantine) as caught:
            client.attachments("intake", "claim")
        self.assertEqual(caught.exception.details["incomplete_attachment_count"], 1)

    def test_near_miss_does_not_quarantine_or_suppress_download(self):
        module = load_processor()
        client = module.SupabaseClient.__new__(module.SupabaseClient)
        client.gateway_instance_id = "pdc-monitor-staging-sales-uid509-v1"
        client.rpc = Mock(return_value={
            **EXACT,
            "scope": "authenticated-active-838",
            "attachments": [{"id": "a", "file_name": "file.jpg", "source_hash": "h", "storage_path": "p"}],
        })
        client._download_attachment = Mock(return_value="/verified/file.jpg")
        rows = client.attachments("intake", "claim")
        self.assertEqual(rows[0].storage_path, "/verified/file.jpg")

    def test_exhaustion_or_zero_count_does_not_quarantine(self):
        module = load_processor()
        client = module.SupabaseClient.__new__(module.SupabaseClient)
        client.gateway_instance_id = "pdc-monitor-staging-sales-uid509-v1"
        client.rpc = Mock(return_value={**EXACT, "incomplete_attachment_count": 0, "attachments": []})
        client._download_attachment = Mock(return_value="/verified/file.jpg")
        with self.assertRaises(IndexError):
            client.attachments("intake", "claim")[0]
        client._download_attachment.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
