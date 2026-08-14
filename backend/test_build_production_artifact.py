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

    def test_missing_administrator_user_management_is_a_hard_failure(self):
        (self.temp_dir / "index.html").write_text("<html><body>no user management here</body></html>", encoding="utf-8")
        (self.temp_dir / "app.js").write_text("", encoding="utf-8")
        (self.temp_dir / "pdc-auth.js").write_text("", encoding="utf-8")
        problems = artifact_builder.confirm_registration_and_user_management_present()
        self.assertTrue(problems, "expected missing administrator User Management to fail closed")

    def test_administrator_user_management_present_and_public_registration_absent_passes(self):
        (self.temp_dir / "index.html").write_text(
            '<html><body><small>Public account registration is disabled.</small>'
            '<button id="nav-user-management" data-view="user-management">User Management</button>'
            '<section id="user-management"><div id="user-management-content"></div></section></body></html>',
            encoding="utf-8",
        )
        (self.temp_dir / "pdc-auth.js").write_text("// no public registration", encoding="utf-8")
        (self.temp_dir / "app.js").write_text(
            "vehicleLifecycleAdministratorActive(); const USER_MANAGEMENT_STATE = {}; "
            "admin_approve_user admin_reject_registration admin_change_role admin_disable_user admin_restore_user",
            encoding="utf-8",
        )
        problems = artifact_builder.confirm_registration_and_user_management_present()
        self.assertEqual(problems, [])

    def test_public_registration_is_a_hard_failure(self):
        (self.temp_dir / "index.html").write_text(
            '<html><body><button id="pdc-show-create-account">Create account</button>'
            '<button id="nav-user-management">User Management</button>'
            '<section id="user-management"></section></body></html>', encoding="utf-8")
        (self.temp_dir / "pdc-auth.js").write_text("client.auth.signUp({})", encoding="utf-8")
        (self.temp_dir / "app.js").write_text(
            "vehicleLifecycleAdministratorActive(); const USER_MANAGEMENT_STATE = {}; "
            "admin_approve_user admin_reject_registration admin_change_role admin_disable_user admin_restore_user",
            encoding="utf-8",
        )
        problems = artifact_builder.confirm_registration_and_user_management_present()
        self.assertTrue(any("public registration" in problem.lower() for problem in problems))

    def test_missing_shared_data_flags_is_a_hard_failure(self):
        (self.temp_dir / "pdc-supabase-config.production.js").write_text(
            "window.PDC_SUPABASE_CONFIG = { projectRef: 'x' };", encoding="utf-8"
        )
        problems = artifact_builder.confirm_shared_data_flags_enabled()
        self.assertEqual(len(problems), 2, f"expected both flags to be reported missing, got: {problems}")

    def test_shared_data_flags_present_passes(self):
        (self.temp_dir / "pdc-supabase-config.production.js").write_text(
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

    def test_localhost_in_qz_desktop_service_vendor_file_is_not_fatal(self):
        vendor_dir = self.temp_dir / "vendor" / "qz"
        vendor_dir.mkdir(parents=True, exist_ok=True)
        (vendor_dir / "qz-tray.js").write_text(
            "const qzDesktopSocket = 'wss://localhost:8181';", encoding="utf-8"
        )
        fatal, _ = artifact_builder.scan_artifact()
        self.assertEqual(fatal, [])

    def test_missing_referenced_asset_is_a_hard_failure(self):
        (self.temp_dir / "index.html").write_text(
            '<html><body><script src="does-not-exist.js"></script></body></html>', encoding="utf-8"
        )
        problems = artifact_builder.confirm_all_referenced_assets_exist()
        self.assertTrue(any("does-not-exist.js" in p for p in problems))

    def test_random_vehicle_fixture_reference_is_a_hard_failure(self):
        (self.temp_dir / "index.html").write_text(
            '<html><body><a href="random-100-vehicles.csv" download>x</a></body></html>', encoding="utf-8"
        )
        problems = artifact_builder.confirm_all_referenced_assets_exist()
        self.assertTrue(any("random-100-vehicles.csv" in p for p in problems))

    def test_missing_lazy_loaded_javascript_is_a_hard_failure(self):
        (self.temp_dir / "index.html").write_text("<html><body></body></html>", encoding="utf-8")
        (self.temp_dir / "app.js").write_text(
            "loadExternalScript(`missing-runtime-service.js?v=1`, 'runtime-service')", encoding="utf-8"
        )
        problems = artifact_builder.confirm_all_referenced_assets_exist()
        self.assertTrue(any("missing-runtime-service.js" in p for p in problems))

    def test_real_repo_build_has_complete_required_source_set(self):
        artifact_builder.ARTIFACT_DIR = self._original_artifact_dir
        copied, missing = artifact_builder.build_artifact()
        self.assertEqual(missing, [])
        registration_problems = artifact_builder.confirm_registration_and_user_management_present()
        flag_problems = artifact_builder.confirm_shared_data_flags_enabled()
        self.assertEqual(registration_problems, [])
        self.assertEqual(flag_problems, [])


if __name__ == "__main__":
    unittest.main()
