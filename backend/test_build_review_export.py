"""
Real tests for scripts/build_review_export.py -- exercises the actual
module logic (imports and calls the real functions), not a mock.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import build_review_export as exporter


class BuildReviewExportTests(unittest.TestCase):
    def test_forbidden_path_patterns_catch_known_bad_paths(self):
        bad_paths = [
            "backend/.imap_attachments/foo.pdf",
            "backend/email_publish.log",
            "PDC_Control_Board_Backup_010e954_2026-07-10_04-54-15.zip",
            "backend/.env",
            "_staging_test_tools/staging_rest.py",
            "node_modules/foo/index.js",
            ".venv_backup/Lib/site-packages/foo.py",
            "backend/__pycache__/foo.cpython-311.pyc",
        ]
        for p in bad_paths:
            self.assertTrue(
                exporter.is_forbidden_path(p),
                f"expected {p!r} to be flagged as forbidden",
            )

    def test_forbidden_path_patterns_do_not_flag_normal_source_files(self):
        good_paths = [
            "app.js",
            "pdc-auth.js",
            "pdc-auth-registration.js",
            "supabase/migrations/018_account_registration_and_approval.sql",
            "scripts/build_production_artifact.py",
            "docs/production-migration-cutover-plan.md",
            "backend/.env.example",
        ]
        for p in good_paths:
            self.assertFalse(
                exporter.is_forbidden_path(p),
                f"expected {p!r} to NOT be flagged as forbidden",
            )

    def test_tracked_files_excludes_known_bad_untracked_paths(self):
        files = exporter.tracked_files()
        joined = "\n".join(files)
        self.assertNotIn(".imap_attachments", joined)
        self.assertNotIn("email_publish.log", joined)
        self.assertNotIn("_staging_test_tools", joined)
        self.assertNotIn("PDC_Control_Board_Backup_010e954", joined)

    def test_build_export_file_list_is_allow_list_only_and_safe(self):
        file_list = exporter.build_export_file_list()
        self.assertGreater(len(file_list), 0)
        problems = exporter.verify_no_forbidden_paths_in_export(file_list)
        self.assertEqual(problems, [], f"forbidden paths leaked into export: {problems}")

    def test_content_scan_flags_a_planted_secret_pattern(self):
        # Use a real temp file inside the repo so scan_content_safety's
        # relative-path resolution behaves exactly as it does in
        # production use, then clean it up.
        planted = exporter.REPO_ROOT / "scripts" / "_test_planted_secret_tmp.txt"
        try:
            planted.write_text("sb_secret_abcdefghijklmnopqrstuvwxyz0123456789", encoding="utf-8")
            rel = "scripts/_test_planted_secret_tmp.txt"
            problems = exporter.scan_content_safety([rel])
            self.assertTrue(
                any("sb_secret_" in p for p in problems),
                f"expected a planted sb_secret_ pattern to be caught, got: {problems}",
            )
        finally:
            planted.unlink(missing_ok=True)

    def test_content_scan_passes_clean_files(self):
        problems = exporter.scan_content_safety(["app.js", "pdc-auth.js"])
        self.assertEqual(problems, [])

    def test_main_exits_zero_on_the_real_repo(self):
        file_list = exporter.build_export_file_list()
        forbidden = exporter.verify_no_forbidden_paths_in_export(file_list)
        content_problems = exporter.scan_content_safety(file_list)
        self.assertEqual(forbidden, [])
        self.assertEqual(content_problems, [])


if __name__ == "__main__":
    unittest.main()
