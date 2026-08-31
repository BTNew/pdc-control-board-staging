from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/staging_only/20260831390000_860_append_missing_monitor_attachments_on_replay.sql").read_text(encoding="utf-8")
LOWER = SQL.lower()


class MonitorAttachmentReplay860Tests(unittest.TestCase):
    def test_append_only_staging_chain_and_least_privilege(self):
        self.assertEqual(SQL.count("BEGIN;"), 1)
        self.assertEqual(SQL.count("COMMIT;"), 1)
        self.assertIn("20260831380000", SQL)
        self.assertIn("pdc_email_ai_successor_actor_first_gate", LOWER)
        self.assertIn("revoke all on function public.enqueue_pdc_email_intake", LOWER)
        self.assertIn("grant execute on function public.enqueue_pdc_email_intake", LOWER)
        self.assertNotIn("drop table", LOWER)
        self.assertNotIn("delete from", LOWER)
        self.assertIn("pdc_production_environment_sentinel", LOWER.split("create or replace function", 1)[0])

    def test_replay_appends_exact_missing_parts_but_rejects_omissions(self):
        self.assertIn("on replay, do not reject an exact payload that contains newly attested parts", LOWER)
        self.assertIn("on conflict(intake_id,graph_attachment_id)", LOWER)
        self.assertIn("if not v_new and exists(select 1 from public.ai_email_attachments x", LOWER)
        self.assertIn("pdc_monitor_attachment_replay_conflict", LOWER)
        self.assertIn("pdc_monitor_attachment_payload_duplicate", LOWER)
        self.assertIn("x.file_name=btrim(a->>'file_name')", LOWER)
        self.assertIn("x.source_hash=lower(a->>'source_hash')", LOWER)
        self.assertIn("coalesce(x.storage_path,'')=v_storage", LOWER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
