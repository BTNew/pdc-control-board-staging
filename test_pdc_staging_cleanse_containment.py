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

    def test_cleanse_migration_is_exact_backup_bound_and_least_privilege(self):
        path = Path("supabase/staging_only/20260824110000_348_one_shot_staging_board_cleanse.sql")
        text = path.read_text(encoding="utf-8")
        required = [
            "73196732f8f0ebe25fa5853a7557d1bbf9c9dd64202ce3ae352865bc80f9f552",
            "548f20c7489266055db67ea15310ebce00ff836f026c4275fbb48c15c1909407",
            "47372294375d9c6787fb8bd01521a763969a2b4d298acb9d1c1a71e72bd912e3",
            "v_raw_bytes constant bigint:=19382148",
            "pdc_admin_run_staging_cleanse_348()",
            "pdc_staging_cleanse_receipts_348",
            "v_replay_before is distinct from v_replay_after",
            "revoke execute on function public.purge_all_staging_board_vehicles(text,text)",
            "PDC_348_CLEANSE_POSTCONDITION_FAILED",
        ]
        for token in required:
            self.assertIn(token, text)
        self.assertNotIn(deploy.PRODUCTION_REF, text)
        self.assertNotIn("grant insert", text.lower())
        self.assertNotIn("grant update", text.lower())
        self.assertNotIn("grant delete", text.lower())

    def test_retirement_migration_revokes_all_mutation_entrypoints(self):
        path = Path("supabase/staging_only/20260824120000_349_retire_staging_cleanse_authority.sql")
        text = path.read_text(encoding="utf-8")
        for signature in [
            "pdc_admin_run_staging_cleanse_348()",
            "purge_all_staging_board_vehicles(text,text)",
            "purge_vehicle_from_board(uuid,integer,text)",
        ]:
            self.assertIn("revoke all on function public." + signature, text)
        self.assertIn("get_pdc_staging_cleanse_status_349()", text)
        self.assertIn("cleanse_execute_authenticated", text)
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
