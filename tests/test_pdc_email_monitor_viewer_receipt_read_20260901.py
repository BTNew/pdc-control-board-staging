from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/staging_only/20260831450000_pdc_email_monitor_viewer_receipt_read_successor.sql").read_text(encoding="utf-8")
LOWER = SQL.lower()


class PdcEmailMonitorViewerReceiptReadTests(unittest.TestCase):
    def test_exact_staging_successor_and_identity_guard(self):
        self.assertEqual(SQL.count("BEGIN;"), 1)
        self.assertEqual(SQL.count("COMMIT;"), 1)
        self.assertIn("20260831440000", SQL)
        self.assertIn("pdc_email_canonical_import_activation_context", LOWER)
        self.assertIn("cdsmnqxtyyoeoznmbidd", LOWER)
        self.assertIn("95131ea9-647f-4461-b5b9-573d22b8824c", LOWER)
        self.assertIn("pmbcontroller+pdc-viewer-staging-20260830@gmail.com", LOWER)
        self.assertIn("pdc_production_environment_sentinel", LOWER)
        self.assertNotIn("drop table", LOWER)
        self.assertNotIn("delete from", LOWER)

    def test_viewer_capability_does_not_become_writer_or_table_dml(self):
        self.assertIn("pdc_monitor_canonical_import_capabilities_20260831", LOWER)
        self.assertIn("canonical_attachment_import_only", LOWER)
        self.assertNotIn("insert into public.pdc_monitor_stage_activation_writers", LOWER)
        self.assertNotIn("update public.pdc_monitor_stage_activation_writers", LOWER)
        self.assertNotIn("grant execute on function public.read_pdc_jobcard_attachment_import_receipt(uuid) to service_role", LOWER)
        self.assertIn("grant execute on function public.read_pdc_jobcard_attachment_import_receipt(uuid)\n  to authenticated", LOWER)
        self.assertIn("revoke all on function public.read_pdc_jobcard_attachment_import_receipt(uuid)", LOWER)

    def test_child_receipt_invariants_remain_attachment_scoped_and_immutable(self):
        for marker in (
            "unique (actor_id, intake_id, attachment_id)",
            "unique (canonical_source_hash)",
            "unique (parent_source_hash)",
            "pdc_jobcard_attachment_import_receipts_immutable",
            "pdc_jobcard_attachment_source_row_receipts_immutable",
            "relrowsecurity",
            "relforcerowsecurity",
            "pdc_20260831450000_postcondition_failed",
        ):
            self.assertIn(marker, LOWER)
        self.assertIn("exists (\n       select 1 from pg_constraint", LOWER)
        self.assertIn("or exists (\n       select 1 from pg_constraint", LOWER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
