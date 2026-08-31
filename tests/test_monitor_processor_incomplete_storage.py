from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys
import types
import unittest
from unittest.mock import Mock


ROOT = Path(__file__).resolve().parents[1]
PROCESSOR = ROOT / "backend/email_intake_processor_successor_20260861.py"


def load_processor():
    stub = types.ModuleType("backend.pdc_jobcard_runtime_client")
    stub.RpcClient = object
    stub.validate_request = lambda request: request
    sys.modules[stub.__name__] = stub
    spec = importlib.util.spec_from_file_location("monitor_processor_storage", PROCESSOR)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class MonitorProcessorIncompleteStorageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.processor = load_processor()

    def test_failed_storage_attachment_is_retained_as_failed_evidence_without_download(self):
        client = self.processor.SupabaseClient("https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token")
        try:
            client.rpc = Mock(return_value={
                "ok": True,
                "attachments": [
                    {"id": "a-valid", "file_name": "valid.pdf", "source_hash": "a" * 64, "storage_path": "pdc-email-intake-private/" + "a" * 64 + "/valid.pdf"},
                    {"id": "a-failed", "file_name": "failed.png", "source_hash": "b" * 64, "storage_path": None},
                ],
            })
            client._download_attachment = Mock(return_value="C:/temp/valid.pdf")
            evidence = client.attachments("intake", "claim")
            self.assertEqual(len(evidence), 2)
            self.assertEqual(client._download_attachment.call_count, 1)
            failed = next(item for item in evidence if item.attachment_id == "a-failed")
            self.assertEqual(failed.storage_path, "")
            self.assertEqual(failed.extraction_status, "failed")
            self.assertIn("review required", failed.extraction_error)
        finally:
            client.close()

    def test_canonical_jobcard_rejects_incomplete_storage_evidence(self):
        proposal = SimpleNamespace(evidence=[{"storage_path": "", "extraction_status": "failed"}])
        with self.assertRaisesRegex(RuntimeError, "complete attachment storage evidence"):
            self.processor.canonical_jobcard_request({}, proposal)


if __name__ == "__main__":
    unittest.main(verbosity=2)
