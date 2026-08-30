from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830221000_804_nested_pre797_contained_runtime_802_successor.sql"


class HistoricalNestedRuntime804ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        cls.pre796 = cls.sql[cls.sql.index("CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778_pre796"):cls.sql.index("REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre796")]
        cls.pre797 = cls.sql[cls.sql.index("CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778_pre797"):cls.sql.index("REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre797")]

    def test_append_only_802_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 16)
        for marker in (
            "20260830220000",
            "803_contained_historical_runtime_802_successor",
            "20260830221000",
            "804_nested_pre797_contained_runtime_802_successor",
            "pdc_804_exact_803_contained_prestate_mismatch",
            "pdc_804_nested_source_prestate_mismatch",
            "pdc_804_postcondition_failed",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_both_nested_preflights_use_contained_802_and_remove_674(self):
        for nested in (self.pre796, self.pre797):
            self.assertEqual(nested.lower().count("verify_pdc_historical_runtime_binding_authenticated_802"), 1)
            self.assertNotIn("pdc_monitor_authenticated_active_scope_674", nested.lower())
            self.assertIn("pdc_monitor_staging_guard", nested.lower())
            self.assertIn("pdc_production_environment_sentinel", nested.lower())
            self.assertIn("unauthorized", nested.lower())
        self.assertIn("submit_pdc_historical_reconciliation_778_pre796(p_request)", self.pre797)
        self.assertIn("pdc_788_protected_boundary_drift", self.pre796.lower())
        self.assertIn("pdc_796_protected_domain_drift", self.pre797.lower())
        self.assertIn("historical_reconciliation_782_atomic_rollback", self.pre797.lower())

    def test_negative_malformed_identity_and_containment_guards_remain(self):
        for marker in (
            "auth.uid()<>",
            "auth.jwt()->>'email'",
            "verify_pdc_historical_runtime_binding_authenticated_802",
            "pdc_804_exact_803_contained_prestate_mismatch",
            "pdc_804_nested_source_prestate_mismatch",
            "pdc_804_postcondition_failed",
            "monitored_mailboxes where active",
            "pdc_email_monitor_pilot",
            "pdc_email_monitor_authenticated_mailbox_activation_controls_674",
            "pdc_email_monitor_authenticated_enqueue_trigger_controls_675",
            "historical_replay_conflict",
            "pdc_796_identity_conflict",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_778_pre796(jsonb) to authenticated", self.lower)
        self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_778_pre797(jsonb) to authenticated", self.lower)
        self.assertNotIn("grant execute on function public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) to anon", self.lower)
        self.assertNotIn("grant execute on function public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) to service_role", self.lower)

    def test_nested_idempotency_and_evidence_path_are_preserved(self):
        for marker in (
            "pdc_historical_reconciliation_778_receipts",
            "canonical_request_utf8",
            "historical_replay_conflict",
            "pdc_788_protected_boundary_drift",
            "pdc_historical_canonical_request_788",
            "submit_pdc_historical_reconciliation_793_proposal_review_succes",
        ):
            self.assertIn(marker.lower(), self.pre796.lower())
        for marker in (
            "v_replay",
            "v_existing_request_hash",
            "pdc_historical_reconciliation_778_receipts",
            "canonical_request_utf8",
            "pdc_historical_796_domain_snapshot",
            "pdc_796_protected_domain_drift",
            "pdc_796_domain_readback_failed",
        ):
            self.assertIn(marker.lower(), self.pre797.lower())
        self.assertNotIn("create table", self.pre796.lower())
        self.assertNotIn("create table", self.pre797.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
