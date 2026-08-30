from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260831011000_835_authenticated_monitor_commissioning_reactivation.sql"


class AuthenticatedMonitorCommissioning835ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_current_head_guard_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 18)
        for marker in (
            "20260831010000",
            "834_monitor_current_head_833_compatibility_successor",
            "20260831011000",
            "835_authenticated_monitor_commissioning_reactivation",
            "pdc_835_exact_833_commissioning_prestate_failed",
            "pdc_835_authenticated_monitor_commissioning_reactivation_postcondition_failed",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)

    def test_exact_mailbox_and_controls_only(self):
        for marker in (
            "12fe383d-5c1e-5801-96e4-f67cf3e3bb57",
            "pdc_pmb_email",
            "pmbcontroller@gmail.com",
            "provider='gmail'",
            "update public.monitored_mailboxes",
            "pdc_email_monitor_authenticated_mailbox_activation_controls_674",
            "pdc_email_monitor_authenticated_enqueue_trigger_controls_675",
            "set enabled=true",
            "event_kind='commissioning_reactivation'",
            "before_mailbox_state",
            "after_mailbox_state",
        ):
            self.assertIn(marker, self.lower)

    def test_security_and_containment(self):
        for marker in (
            "enable row level security",
            "force row level security",
            "revoke all on public.pdc_email_monitor_authenticated_mailbox_reactivation_history_835",
            "not task_enabled",
            "not mailbox_flags_changed",
            "not uid514_processed",
            "not outbound_email_sent",
            "not production_writes",
            "pdc_email_monitor_pilot",
            "not outbound_email_enabled",
            "pdc_production_environment_sentinel",
            "where provider_uid='imap_uid:514'",
            "notify pgrst",
        ):
            self.assertIn(marker, self.lower)
        for forbidden in ("send_email", "imap_bridge", "enable-scheduledtask", "start-scheduledtask"):
            self.assertNotIn(forbidden, self.lower)

    def test_immutable_history_and_no_task_enablement(self):
        self.assertIn("before update or delete", self.lower)
        self.assertIn("pdc_835_authenticated_mailbox_reactivation_history_immutable", self.lower)
        self.assertIn("task_enabled boolean not null check(not task_enabled)", self.lower)
        self.assertIn("mailbox_flags_changed boolean not null check(not mailbox_flags_changed)", self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
