from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/staging_only/20260831400000_861_quarantine_missing_monitor_storage_objects.sql").read_text(encoding="utf-8")
LOWER = SQL.lower()


class MonitorAttachmentStorage861Tests(unittest.TestCase):
    def test_projection_is_append_only_and_authenticated(self):
        self.assertEqual(SQL.count("BEGIN;"), 1)
        self.assertEqual(SQL.count("COMMIT;"), 1)
        self.assertIn("20260831390000", SQL)
        self.assertIn("860_append_missing_monitor_attachments_on_replay", LOWER)
        self.assertIn("storage.objects", LOWER)
        self.assertIn("review_required", LOWER)
        self.assertIn("attachment_storage_incomplete", LOWER)
        self.assertIn("board_mutated',false", LOWER)
        self.assertIn("mailbox_flags_changed',false", LOWER)
        self.assertNotIn("drop table", LOWER)
        self.assertNotIn("delete from", LOWER)

    def test_missing_object_is_not_returned_as_downloadable_attachment(self):
        self.assertIn("o.name is not null", LOWER)
        self.assertIn("not(r.outcome='permanent_fail_closed'", LOWER)
        self.assertIn("storage_reconciliation_required", LOWER)
        self.assertIn("grant execute on function public.get_pdc_monitor_intake_attachments_735", LOWER)
        self.assertIn("revoke all on function public.get_pdc_monitor_intake_attachments_735", LOWER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
