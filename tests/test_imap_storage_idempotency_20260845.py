from __future__ import annotations

import io
import json
import sys
import types
import urllib.error
import urllib.request
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "backend" / "imap_bridge_successor_20260845.py"
FIXTURE = ROOT / "tests" / "fixtures" / "supabase_storage_key_already_exists_400.json"
# The sealed .44 source carries attachment_content.py; this focused seam test
# supplies only its import contract so it remains runnable in the website repo.
attachment_content = types.ModuleType("attachment_content")
attachment_content.SUPPORTED_EXTENSIONS = {".pdf"}
attachment_content.validate_attachment = lambda *args, **kwargs: None
sys.modules.setdefault("attachment_content", attachment_content)
sys.path.insert(0, str(MODULE_PATH.parent))
import imap_bridge_successor_20260845 as bridge


class StorageIdempotency20260845Tests(unittest.TestCase):
    def _attachment(self, path: Path) -> bridge.AttachmentRecord:
        return bridge.AttachmentRecord(
            filename="job-card.pdf",
            content_type="application/pdf",
            validation_status="verified",
            local_path=str(path),
            source_hash="a" * 64,
        )

    def _error(self, status: int, body: object) -> urllib.error.HTTPError:
        raw = json.dumps(body).encode("utf-8")
        return urllib.error.HTTPError(
            "https://staging.invalid/storage",
            status,
            "storage error",
            {"Content-Type": "application/json"},
            io.BytesIO(raw),
        )

    def test_real_staging_response_fixture_is_idempotent(self):
        fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
        error = self._error(fixture["status"], fixture["body"])
        with TemporaryDirectory() as directory:
            path = Path(directory) / "job-card.pdf"
            path.write_bytes(b"fixture")
            with patch.object(urllib.request, "urlopen", side_effect=error):
                result = bridge._upload_attachment(
                    "https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token", self._attachment(path)
                )
        self.assertEqual(
            result,
            "pdc-email-intake-private/" + "a" * 64 + "/job-card.pdf",
        )

    def test_other_http_400_failures_are_not_replay_success(self):
        for body in (
            {"code": "KeyAlreadyExists", "statusCode": 400},
            {"code": "Unauthorized", "statusCode": 409},
            {"code": "KeyAlreadyExists"},
            {"message": "KeyAlreadyExists", "statusCode": 409},
            {"code": "KeyAlreadyExists", "statusCode": "409"},
        ):
            with self.subTest(body=body), TemporaryDirectory() as directory:
                path = Path(directory) / "job-card.pdf"
                path.write_bytes(b"fixture")
                error = self._error(400, body)
                with patch.object(urllib.request, "urlopen", side_effect=error):
                    with self.assertRaisesRegex(RuntimeError, "Attachment upload failed HTTP 400"):
                        bridge._upload_attachment(
                            "https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token", self._attachment(path)
                        )

    def test_legacy_bare_http_409_is_not_silently_accepted(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "job-card.pdf"
            path.write_bytes(b"fixture")
            with patch.object(urllib.request, "urlopen", side_effect=self._error(409, {"code": "Conflict"})):
                with self.assertRaisesRegex(RuntimeError, "Attachment upload failed HTTP 409"):
                    bridge._upload_attachment(
                        "https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token", self._attachment(path)
                    )

    def test_successful_upload_still_returns_canonical_path(self):
        response = Mock(status=201)
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        with TemporaryDirectory() as directory:
            path = Path(directory) / "job-card.pdf"
            path.write_bytes(b"fixture")
            with patch.object(urllib.request, "urlopen", return_value=response):
                result = bridge._upload_attachment(
                    "https://cdsmnqxtyyoeoznmbidd.supabase.co", "anon", "token", self._attachment(path)
                )
        self.assertTrue(result.endswith("/job-card.pdf"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
