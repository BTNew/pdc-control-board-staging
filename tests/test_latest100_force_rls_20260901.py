from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/staging_only/20260831461000_latest100_force_rls_successor.sql").read_text(encoding="utf-8")
LOWER = SQL.lower()


class Latest100ForceRlsTests(unittest.TestCase):
    def test_exact_append_only_successor(self):
        self.assertEqual(SQL.count("BEGIN;"), 1)
        self.assertEqual(SQL.count("COMMIT;"), 1)
        for marker in ("20260831460000", "latest100_resume_repair", "cdsmnqxtyyoeoznmbidd", "pdc_production_environment_sentinel"):
            self.assertIn(marker.lower(), LOWER)
        self.assertNotIn("drop table", LOWER)
        self.assertNotIn("delete from", LOWER)

    def test_all_email_and_child_receipt_boundaries_are_forced_rls(self):
        for table in (
            "ai_email_intake",
            "ai_email_attachments",
            "pdc_monitor_exact_sender_enrollments",
            "pdc_jobcard_attachment_import_receipts",
            "pdc_jobcard_attachment_source_row_receipts",
        ):
            self.assertIn(f"alter table public.{table} enable row level security", LOWER)
            self.assertIn(f"alter table public.{table} force row level security", LOWER)
            self.assertIn(f"public.{table}", LOWER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
