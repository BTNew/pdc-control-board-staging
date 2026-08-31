from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831270000_861_null_storage_predicate_successor.sql"


class NullStoragePredicate861ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_860_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 13)
        for marker in (
            "20260831260000",
            "860_quarantined_attachment_review_projection",
            "20260831270000",
            "861_null_storage_predicate_successor",
            "pdc_861_860_null_storage_prestate_failed",
            "pdc_861_null_storage_postcondition_failed",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)

    def test_null_regex_results_are_explicitly_false(self):
        self.assertIn("coalesce(r.canonical_storage_path~", self.lower)
        self.assertIn("coalesce(a.storage_path~", self.lower)
        self.assertIn("not (r.outcome='canonical_verified'", self.lower)
        self.assertIn("attachment_storage_incomplete", self.lower)
        self.assertIn("review_required", self.lower)

    def test_exact_scope_and_fail_closed_controls_remain(self):
        for marker in (
            "pdc_email_monitor_runtime_authorized_502",
            "pdc_monitor_authenticated_active_scope_839",
            "claim_token",
            "gateway_instance_id",
            "locked_at>=clock_timestamp()-interval '10 minutes'",
            "security definer",
            "revoke all on function public.get_pdc_monitor_intake_attachments_735",
            "grant execute on function public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) to authenticated",
            "board_mutated',false",
            "mailbox_flags_changed',false",
            "uid514_processed',false",
            "production_writes',false",
            "pdc_production_environment_sentinel",
            "not outbound_email_enabled",
            "notify pgrst",
        ):
            self.assertIn(marker, self.lower)
        for forbidden in ("send_email", "imap_bridge", "grant execute on function public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) to service_role"):
            self.assertNotIn(forbidden, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
