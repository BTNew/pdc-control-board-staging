from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831260000_860_quarantined_attachment_review_projection.sql"


class QuarantinedAttachmentReview860ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_859_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 13)
        for marker in (
            "20260831250000",
            "859_runtime_766_compatibility_and_attachment_path_successor",
            "20260831260000",
            "860_quarantined_attachment_review_projection",
            "pdc_860_859_quarantined_attachment_prestate_failed",
            "pdc_860_quarantined_attachment_postcondition_failed",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)

    def test_quarantined_paths_are_review_only(self):
        for marker in (
            "attachment_storage_incomplete",
            "review_required",
            "incomplete_attachment_count",
            "readable_attachment_count",
            "storage_reconciliations_735",
            "attachments','[]'::jsonb",
            "board_mutated',false",
            "mailbox_flags_changed',false",
            "uid514_processed',false",
            "production_writes',false",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("insert into public.ai_email_attachments", self.lower)
        self.assertNotIn("update public.ai_email_attachments", self.lower)

    def test_scope_acl_and_production_exclusion_are_preserved(self):
        for marker in (
            "pdc_email_monitor_runtime_authorized_502",
            "pdc_monitor_authenticated_active_scope_839",
            "claim_token",
            "gateway_instance_id",
            "locked_at>=clock_timestamp()-interval '10 minutes'",
            "security definer",
            "revoke all on function public.get_pdc_monitor_intake_attachments_735",
            "grant execute on function public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) to authenticated",
            "pdc_production_environment_sentinel",
            "not outbound_email_enabled",
            "notify pgrst",
        ):
            self.assertIn(marker, self.lower)
        for forbidden in ("send_email", "imap_bridge", "grant execute on function public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) to service_role"):
            self.assertNotIn(forbidden, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
