"""
Real tests for scripts/build_production_artifact.py -- exercises the
actual module functions (imports and calls them directly against a
temp artifact directory), not a mock. Verifies the independent-review
remediation requirement that every one of these conditions is FATAL
(non-zero exit / raises the check into the failures list), not merely
a printed warning.
"""
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import build_production_artifact as artifact_builder


class BuildProductionArtifactValidatorTests(unittest.TestCase):
    def setUp(self):
        # Use a dedicated temp artifact dir so this test never touches
        # the real _build/production-artifact used by manual runs.
        self.temp_dir = artifact_builder.REPO_ROOT / "_build" / "test_production_artifact_tmp"
        if self.temp_dir.exists():
            shutil.rmtree(self.temp_dir)
        self.temp_dir.mkdir(parents=True, exist_ok=True)
        self._original_artifact_dir = artifact_builder.ARTIFACT_DIR
        artifact_builder.ARTIFACT_DIR = self.temp_dir

    def tearDown(self):
        artifact_builder.ARTIFACT_DIR = self._original_artifact_dir
        if self.temp_dir.exists():
            shutil.rmtree(self.temp_dir)

    def test_missing_registration_module_is_a_hard_failure(self):
        (self.temp_dir / "index.html").write_text("<html><body>no registration here</body></html>", encoding="utf-8")
        problems = artifact_builder.confirm_registration_and_user_management_present()
        self.assertTrue(problems, "expected missing registration module to be reported as a real problem, not silently passed")

    def test_registration_module_present_and_wired_passes(self):
        (self.temp_dir / "pdc-auth-registration-production.js").write_text("// stub", encoding="utf-8")
        (self.temp_dir / "index.html").write_text(
            '<html><body><script src="pdc-auth-registration-production.js"></script>'
            '<div id="user-management">User Management</div></body></html>',
            encoding="utf-8",
        )
        problems = artifact_builder.confirm_registration_and_user_management_present()
        self.assertEqual(problems, [])

    def test_missing_shared_data_flags_is_a_hard_failure(self):
        (self.temp_dir / "pdc-supabase-config.js").write_text(
            "window.PDC_SUPABASE_CONFIG = { projectRef: 'x' };", encoding="utf-8"
        )
        problems = artifact_builder.confirm_shared_data_flags_enabled()
        self.assertEqual(len(problems), 2, f"expected both flags to be reported missing, got: {problems}")

    def test_shared_data_flags_present_passes(self):
        (self.temp_dir / "pdc-supabase-config.js").write_text(
            "window.PDC_SUPABASE_CONFIG = { workshop: { sharedData: true }, "
            "vehicleLifecycle: { sharedData: true } };",
            encoding="utf-8",
        )
        problems = artifact_builder.confirm_shared_data_flags_enabled()
        self.assertEqual(problems, [])

    def test_staging_project_ref_anywhere_is_fatal(self):
        (self.temp_dir / "leaky.js").write_text("const ref = 'cdsmnqxtyyoeoznmbidd';", encoding="utf-8")
        fatal, _ = artifact_builder.scan_artifact()
        self.assertTrue(any("staging Supabase project ref" in f for f in fatal))

    def test_secret_pattern_anywhere_is_fatal(self):
        # Fake secret built from non-contiguous fragments so this test
        # file's own source text never contains a literal
        # "sb_secret_..." token (which would otherwise cause the
        # independent-review export tool's own content scan to flag
        # this test file itself as a leaked secret).
        fake_secret = "sb_" + "secret" + "_abcdefghijklmnop"
        (self.temp_dir / "leaky2.js").write_text(f"const key = '{fake_secret}';", encoding="utf-8")
        fatal, _ = artifact_builder.scan_artifact()
        self.assertTrue(any("Supabase secret/service-role key" in f for f in fatal))

    def test_bare_localhost_reference_is_fatal_outside_allowed_files(self):
        (self.temp_dir / "leaky3.js").write_text("fetch('http://localhost:3000/api')", encoding="utf-8")
        fatal, _ = artifact_builder.scan_artifact()
        self.assertTrue(any("localhost" in f for f in fatal))

    def test_localhost_in_allowed_vendor_file_is_not_fatal(self):
        vendor_dir = self.temp_dir / "vendor" / "supabase"
        vendor_dir.mkdir(parents=True, exist_ok=True)
        (vendor_dir / "supabase-2.110.5.js").write_text(
            "// SDK dev-mode text mentions localhost for local development guidance", encoding="utf-8"
        )
        fatal, _ = artifact_builder.scan_artifact()
        self.assertEqual(fatal, [])

    def test_missing_referenced_asset_is_a_hard_failure(self):
        (self.temp_dir / "index.html").write_text(
            '<html><body><script src="does-not-exist.js"></script></body></html>', encoding="utf-8"
        )
        problems = artifact_builder.confirm_all_referenced_assets_exist()
        self.assertTrue(any("does-not-exist.js" in p for p in problems))

    def test_named_asset_exception_is_not_a_hard_failure(self):
        (self.temp_dir / "index.html").write_text(
            '<html><body><a href="random-100-vehicles.csv" download>x</a></body></html>', encoding="utf-8"
        )
        problems = artifact_builder.confirm_all_referenced_assets_exist()
        self.assertEqual(problems, [])

    def test_real_repo_build_currently_fails_because_stage_3_4_are_incomplete(self):
        # This is intentional and documents the honest current state:
        # the validator must fail today, because a production-safe
        # registration module and the shared-data feature flags do not
        # exist yet. If this test ever starts failing because the real
        # build passes, that is real progress -- update this test at
        # that point to assert PASS instead, alongside the actual
        # Stage 3/4 completion commit.
        artifact_builder.ARTIFACT_DIR = self._original_artifact_dir
        copied, missing = artifact_builder.build_artifact()
        self.assertIn("pdc-auth-registration-production.js", missing)
        registration_problems = artifact_builder.confirm_registration_and_user_management_present()
        flag_problems = artifact_builder.confirm_shared_data_flags_enabled()
        self.assertTrue(registration_problems)
        self.assertTrue(flag_problems)


if __name__ == "__main__":
    unittest.main()
