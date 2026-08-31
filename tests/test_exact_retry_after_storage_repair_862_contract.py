from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831280000_862_exact_retry_after_storage_repair.sql"


class ExactRetryAfterStorageRepair862ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_861_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 18)
        for marker in (
            "20260831270000",
            "861_null_storage_predicate_successor",
            "20260831280000",
            "862_exact_retry_after_storage_repair",
            "pdc_862_exact_861_requeue_prestate_failed",
            "pdc_862_exact_requeue_postcondition_failed",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)

    def test_exact_intake_and_no_evidence_mutation(self):
        for marker in (
            "0172352b-6045-4ab4-83ba-c8069c9ab8de",
            "imap_uid:692",
            "cdc66328f62d3eac365127763ac13ed01da83fe16ca951029d17360db6553565",
            "queue_attempts=2",
            "source_evidence_unchanged",
            "attachments_unchanged",
            "pdc_monitor_exact_requeue_history_862",
            "before_state",
            "after_state",
            "where i.id=v_id",
            "i.source_hash='cdc66328f62d3eac365127763ac13ed01da83fe16ca951029d17360db6553565'",
            "for update",
            "status='received'",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("update public.ai_email_attachments", self.lower)
        self.assertNotIn("delete from public.ai_email_attachments", self.lower)

    def test_security_and_monitor_controls_remain_fail_closed(self):
        for marker in (
            "enable row level security",
            "force row level security",
            "revoke all on public.pdc_monitor_exact_requeue_history_862",
            "not task_enabled",
            "not mailbox_flags_changed",
            "not uid514_processed",
            "not outbound_email_sent",
            "not production_writes",
            "monitored_mailboxes where active",
            "pdc_email_monitor_pilot",
            "not outbound_email_enabled",
            "pdc_production_environment_sentinel",
            "notify pgrst",
        ):
            self.assertIn(marker, self.lower)
        for forbidden in ("send_email", "imap_bridge", "enable-scheduledtask", "start-scheduledtask"):
            self.assertNotIn(forbidden, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
