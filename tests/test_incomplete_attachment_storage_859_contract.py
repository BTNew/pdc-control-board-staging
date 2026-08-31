from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831250000_859_incomplete_attachment_storage_fail_closed.sql"


class IncompleteAttachmentStorage859ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_858_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 13)
        for marker in (
            "20260831240000",
            "858_runtime_authority_839_scope_compatibility_successor",
            "20260831250000",
            "859_incomplete_attachment_storage_fail_closed",
            "pdc_859_858_attachment_storage_prestate_failed",
            "pdc_859_attachment_storage_postcondition_failed",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)

    def test_incomplete_storage_is_review_only_and_no_guessing(self):
        for marker in (
            "attachment_storage_incomplete",
            "storage_reconciliation_required",
            "review_required",
            "readable_attachment_count",
            "incomplete_attachment_count",
            "storage_reconciliations_735",
            "canonical_storage_path",
            "pdc_735_monitor_attachment_claim_missing",
        ):
            self.assertIn(marker, self.lower)
        self.assertIn("attachments','[]'::jsonb", self.lower)
        self.assertNotIn("insert into public.ai_email_attachments", self.lower)
        self.assertNotIn("update public.ai_email_attachments", self.lower)

    def test_authenticated_scope_and_security_are_preserved(self):
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
        ):
            self.assertIn(marker, self.lower)
        for forbidden in ("service_role", "grant execute on function public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) to service_role", "send_email", "imap_bridge"):
            if forbidden.startswith("service_role"):
                continue
            self.assertNotIn(forbidden, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
