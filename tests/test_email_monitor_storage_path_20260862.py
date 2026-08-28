from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import sys
import types
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "backend" / "email_intake_processor_successor_20260862.py"
attachment_content = types.ModuleType("attachment_content")
attachment_content.SUPPORTED_EXTENSIONS = {".pdf"}
attachment_content.validate_attachment = lambda *args, **kwargs: None
sys.modules.setdefault("attachment_content", attachment_content)
jobcard_client = types.ModuleType("pdc_jobcard_runtime_client")
jobcard_client.RpcClient = object
jobcard_client.validate_request = lambda value: value
sys.modules.setdefault("pdc_jobcard_runtime_client", jobcard_client)
sys.path.insert(0, str(MODULE_PATH.parent))

spec = importlib.util.spec_from_file_location("monitor_processor_20260862", MODULE_PATH)
assert spec is not None and spec.loader is not None
processor = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = processor
spec.loader.exec_module(processor)


class StoragePath20260862Tests(unittest.TestCase):
    FIXTURE_HASH = hashlib.sha256(b"fixture").hexdigest()
    VALID_PATH = f"pdc-email-intake-private/{FIXTURE_HASH}/job_card.pdf"

    def test_canonical_path_is_accepted_and_uses_exact_bucket(self):
        self.assertEqual(
            processor.validate_attachment_storage_path(self.VALID_PATH, "job card.pdf", self.FIXTURE_HASH),
            f"{self.FIXTURE_HASH}/job_card.pdf",
        )

    def test_hostile_paths_are_rejected_before_storage_access(self):
        hostile = [
            "",
            "job_card.pdf",
            "https://evil.invalid/pdc-email-intake-private/x/job_card.pdf",
            f"pdc-email-attachments/{self.FIXTURE_HASH}/job_card.pdf",
            f"pdc-email-intake-private/../{self.FIXTURE_HASH}/job_card.pdf",
            f"pdc-email-intake-private\\{self.FIXTURE_HASH}\\job_card.pdf",
            f"pdc-email-intake-private//{self.FIXTURE_HASH}/job_card.pdf",
            f"pdc-email-intake-private/{'a' * 63}/job_card.pdf",
            f"pdc-email-intake-private/{self.FIXTURE_HASH}/../job_card.pdf",
            f"pdc-email-intake-private/{self.FIXTURE_HASH}/job%5Fcard.pdf",
        ]
        client = processor.SupabaseClient("https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon-key", "actor-token")
        try:
            with patch.object(processor.urllib.request, "urlopen") as urlopen:
                for path in hostile:
                    with self.subTest(path=path):
                        with self.assertRaises(RuntimeError):
                            client._download_attachment(path, "job card.pdf", self.FIXTURE_HASH)
                urlopen.assert_not_called()
        finally:
            client.close()

    def test_hash_and_filename_binding_fail_closed_before_storage_access(self):
        cases = [
            (f"pdc-email-intake-private/{'b' * 64}/job_card.pdf", self.FIXTURE_HASH),
            (f"pdc-email-intake-private/{self.FIXTURE_HASH}/other.pdf", self.FIXTURE_HASH),
            (f"pdc-email-intake-private/{self.FIXTURE_HASH}/job_card.pdf", "b" * 64),
        ]
        client = processor.SupabaseClient("https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon-key", "actor-token")
        try:
            with patch.object(processor.urllib.request, "urlopen") as urlopen:
                for path, expected_hash in cases:
                    with self.subTest(path=path, expected_hash=expected_hash):
                        with self.assertRaises(RuntimeError):
                            client._download_attachment(path, "job card.pdf", expected_hash)
                urlopen.assert_not_called()
        finally:
            client.close()

    def test_download_verifies_bytes_against_bound_hash_after_path_validation(self):
        response = Mock(status=200, headers={"Content-Type": "application/pdf"})
        response.read.return_value = b"fixture"
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        client = processor.SupabaseClient("https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon-key", "actor-token")
        try:
            with patch.object(processor.urllib.request, "urlopen", return_value=response) as urlopen:
                local_path = client._download_attachment(self.VALID_PATH, "job card.pdf", self.FIXTURE_HASH)
                self.assertEqual(Path(local_path).read_bytes(), b"fixture")
                request = urlopen.call_args.args[0]
                self.assertIn(f"/storage/v1/object/authenticated/pdc-email-intake-private/{self.FIXTURE_HASH}/job_card.pdf", request.full_url)
        finally:
            client.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
