import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import scripts.pdc_staging_management_migration as deploy


class StagingManagementMigrationTests(unittest.TestCase):
    def test_exact_production_ref_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "PRODUCTION_TARGET_FORBIDDEN"):
            deploy._validate_target(deploy.PRODUCTION_REF)

    def test_unknown_ref_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "UNKNOWN_TARGET_FORBIDDEN"):
            deploy._validate_target("aaaaaaaaaaaaaaaaaaaa")

    def test_exact_staging_ref_is_accepted(self):
        deploy._validate_target(deploy.STAGING_REF)

    def test_containment_migration_has_required_guards(self):
        path = Path("supabase/staging_only/20260824100000_347_staging_board_containment.sql")
        text = path.read_text(encoding="utf-8")
        required = [
            "project_ref='cdsmnqxtyyoeoznmbidd'",
            "pdc_production_environment_sentinel",
            "enabled=false",
            "active=false",
            "running_status='stopped'",
            "gateway_instance_id=null",
            "qa_website_500",
            "qa_wcb_synthetic",
            "PDC_347_CONTAINMENT_POSTCONDITION_FAILED",
            "pdc_staging_containment_receipts_347",
        ]
        for token in required:
            self.assertIn(token, text)
        self.assertNotIn(deploy.PRODUCTION_REF, text)

    def test_validate_migration_binds_exact_bytes_and_ledger(self):
        path = Path("supabase/staging_only/20260824100000_347_staging_board_containment.sql")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        raw, version, name = deploy._validate_migration(path, digest)
        self.assertEqual(raw, path.read_bytes())
        self.assertEqual(version, "20260824100000")
        self.assertEqual(name, "347_staging_board_containment")

    def test_wrong_hash_fails_closed(self):
        path = Path("supabase/staging_only/20260824100000_347_staging_board_containment.sql")
        with self.assertRaisesRegex(RuntimeError, "SHA256_MISMATCH"):
            deploy._validate_migration(path, "0" * 64)


if __name__ == "__main__":
    unittest.main()
