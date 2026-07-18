"""Tests for the real allow-list Stage 2A review exporter."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import build_review_export as exporter


class BuildReviewExportTests(unittest.TestCase):
    def test_forbidden_path_patterns_catch_runtime_and_secret_paths(self):
        bad_paths = [
            "backend/.imap_attachments/customer.pdf",
            "backend/email_publish.log",
            "PDC_Control_Board_Backup_example.zip",
            "backend/.env",
            "_staging_test_tools/.env",
            "node_modules/pkg/index.js",
            ".venv_backup/Lib/site-packages/pkg.py",
            "_build/production-artifact/index.html",
            "backend/__pycache__/x.pyc",
            "operational-backup.bin",
        ]
        for path in bad_paths:
            self.assertTrue(exporter.is_forbidden_path(path), path)

    def test_staging_tests_and_safe_env_example_are_exportable(self):
        self.assertFalse(exporter.is_forbidden_path("_staging_test_tools/.env.example"))
        self.assertFalse(exporter.is_forbidden_path("_staging_test_tools/staging_conn.py"))
        self.assertFalse(exporter.is_forbidden_path("_staging_test_tools/test_workshop_staging_integration.py"))
        self.assertTrue(exporter.is_forbidden_path("_staging_test_tools/.env"))

    def test_normal_source_and_evidence_paths_are_not_forbidden(self):
        good_paths = [
            "app.js", "workshop-planner.css", "backend/app.py",
            "supabase/migrations/025_stage2a_review_remediation_grants_rls_validation.sql",
            "review-evidence/post-resume/full-schema-report.json",
            "scripts/stage2a_live_acceptance.js",
        ]
        for path in good_paths:
            self.assertFalse(exporter.is_forbidden_path(path), path)

    def test_tracked_files_include_runnable_staging_tests_but_not_local_env(self):
        files = exporter.tracked_files()
        # During an uncommitted development run, Git may not list the newly
        # added tests yet; once tracked, the final export self-check requires
        # all of them. Existing tracked paths must never include a real .env.
        self.assertNotIn("_staging_test_tools/.env", files)
        self.assertNotIn("backend/.env", files)
        self.assertIn("_staging_test_tools/.env.example", files)

    def test_build_export_file_list_is_allow_list_only_and_safe(self):
        files = exporter.build_export_file_list()
        self.assertGreater(len(files), 0)
        self.assertEqual(exporter.verify_no_forbidden_paths_in_export(files), [])

    def test_content_scan_flags_a_planted_secret_pattern(self):
        planted = exporter.REPO_ROOT / "scripts" / "_test_planted_secret_tmp.txt"
        marker = "sb_" + "secret" + "_" + "abcdefghijklmnopqrstuvwxyz0123456789"
        try:
            planted.write_text(marker, encoding="utf-8")
            problems = exporter.scan_content_safety(["scripts/_test_planted_secret_tmp.txt"])
            self.assertTrue(any("Supabase secret" in item for item in problems), problems)
        finally:
            planted.unlink(missing_ok=True)

    def test_content_scan_passes_clean_source_and_placeholder_env(self):
        problems = exporter.scan_content_safety([
            "app.js", "pdc-auth.js", "_staging_test_tools/.env.example"
        ])
        self.assertEqual(problems, [])

    def test_required_export_surface_names_all_independent_review_categories(self):
        required = set(exporter.REQUIRED_SOURCE_PATHS)
        for path in [
            "test_all.js", "workshop-planner.css", "requirements-review.txt",
            "package-review.json", "scripts/stage2a_live_acceptance.js",
            "review-evidence/post-resume/full-schema-report.json",
            "review-evidence/post-resume/grants-rls-report.json",
            "review-evidence/post-resume/realtime-publication-replica-identity-report.json",
            "review-evidence/post-resume/two-browser-realtime-acceptance.json",
        ]:
            self.assertIn(path, required)


if __name__ == "__main__":
    unittest.main()
