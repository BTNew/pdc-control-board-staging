from __future__ import annotations

import base64
import hashlib
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "backend/attachment_content.py"
BUILDER = ROOT / "scripts/build_pdc_monitor_successor_20260867.py"
VERIFIER = ROOT / "scripts/verify_pdc_monitor_successor_20260867.py"
INSTALLER = ROOT / "scripts/install_pdc_monitor_successor_20260867.ps1"

# A small structurally valid JPEG. It is intentionally supplied under the
# provider-reported MIME image/jpeg but with the preserved original image.png name.
JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAACAAMDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD8+qKKK+oPnD//2Q=="
)


def load_source():
    spec = importlib.util.spec_from_file_location("attachment_content_successor_20260868", SOURCE)
    if spec is None or spec.loader is None:
        raise RuntimeError("attachment content source could not be loaded")
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class AttachmentContentSuccessor20260868Tests(unittest.TestCase):
    def test_preserved_png_name_accepts_only_verified_jpeg_with_reported_jpeg_mime(self):
        module = load_source()
        result = module.validate_attachment("image.png", "image/jpeg", JPEG)
        self.assertTrue(result.ok, result)
        self.assertEqual(result.canonical_mime, "image/jpeg")
        self.assertEqual(result.detected_extension, ".jpg")
        self.assertEqual(result.status, "verified")
        self.assertEqual(result.reason, "")

    def test_same_bytes_are_rejected_when_provider_mime_is_not_jpeg(self):
        module = load_source()
        result = module.validate_attachment("image.png", "image/png", JPEG)
        self.assertFalse(result.ok)
        self.assertIn("attachment_extension_content_mismatch", result.reason)

    def test_png_content_is_not_accepted_as_jpeg_under_preserved_name(self):
        module = load_source()
        # A valid PNG signature without a complete image must remain invalid.
        result = module.validate_attachment("image.png", "image/jpeg", b"\x89PNG\r\n\x1a\n")
        self.assertFalse(result.ok)
        self.assertIn("attachment_content_invalid", result.reason)

    def test_unknown_extension_remains_unsupported_even_for_verified_jpeg(self):
        module = load_source()
        result = module.validate_attachment("image.heic", "image/jpeg", JPEG)
        self.assertFalse(result.ok)
        self.assertEqual(result.status, "unsupported")
        self.assertIn("unsupported_attachment_type", result.reason)

    def test_hash_and_storage_leaf_contract_can_preserve_original_filename(self):
        module = load_source()
        result = module.validate_attachment("image.png", "image/jpeg", JPEG)
        self.assertTrue(result.ok)
        digest = hashlib.sha256(JPEG).hexdigest()
        storage_path = f"pdc-email-intake-private/{digest}/image.png"
        self.assertEqual(storage_path.rsplit("/", 1)[-1], "image.png")
        self.assertEqual(digest, "d1135f63d703a7f6a078cbc69541da7f32d4dcaebb1e11ea38787d9cce1ec9d6")
        self.assertEqual(result.canonical_mime, "image/jpeg")

    def test_parent_bound_builder_verifier_and_disabled_installer_are_staging_only(self):
        builder = BUILDER.read_text(encoding="utf-8").lower()
        verifier = VERIFIER.read_text(encoding="utf-8").lower()
        installer = INSTALLER.read_text(encoding="utf-8").lower()
        for marker in (
            "2026.08.67", "2026.08.65", "release-manifest.json",
            "attachment_content.py", "expected_staging_project_ref",
            "production_contacted", "mailbox_contacted", "uid514_processed",
        ):
            self.assertIn(marker, builder)
            self.assertIn(marker, verifier)
        self.assertIn("exact .65 parent release required", builder)
        self.assertIn("successor complete inventory mismatch", verifier)
        self.assertIn("task_must_remain_disabled", verifier)
        for marker in ("pdcmonitorstagingattachmentsuccessorinstall", "task_must_remain_disabled", "2026.08.65", "2026.08.67", "production_contacted"):
            self.assertIn(marker, installer)
        for forbidden in ("enable-scheduledtask", "start-scheduledtask", "register-scheduledtask", "imaplib.imap4", "urlopen"):
            self.assertNotIn(forbidden, builder + installer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
