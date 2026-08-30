from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830220000_803_contained_historical_runtime_802_successor.sql"


class HistoricalRuntime802ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        cls.adapter = cls.sql[cls.sql.index("CREATE OR REPLACE FUNCTION public.verify_pdc_historical_runtime_binding_authenticated_802"):cls.sql.index("REVOKE ALL ON FUNCTION public.verify_pdc_historical_runtime_binding_authenticated_802")]
        cls.wrapper = cls.sql[cls.sql.index("CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778"):cls.sql.index("REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778")]

    def test_successor_is_append_only_and_exactly_pinned_to_802(self):
        self.assertEqual(len(parse_sql(self.sql)), 16)
        for marker in (
            "20260830215000",
            "802_repair_800_idempotency_cardinality",
            "20260830220000",
            "803_contained_historical_runtime_802_successor",
            "pdc-staging-803-contained-historical-runtime-802",
            "pdc_803_exact_802_contained_prestate_mismatch",
            "exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' and version>'20260830215000')",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_contained_adapter_uses_672_not_766_and_requires_zero_mailbox(self):
        for marker in (
            "verify_pdc_monitor_runtime_binding_authenticated_672",
            "historical_runtime_binding_verified_contained_802",
            "historical_runtime_binding_mismatch_802",
            "historical_runtime_containment_mismatch_802",
            "monitored_mailboxes where active",
            "active_mailbox_count',0",
            "pdc_monitor_stage_activation_writers",
            "pdc_email_monitor_authenticated_mailbox_activation_controls_674",
            "pdc_email_monitor_authenticated_enqueue_trigger_controls_675",
            "pdc_email_monitor_pilot",
            "pdc_production_environment_sentinel",
            "auth.uid()",
            "auth.jwt()->>'role'",
            "coalesce(auth.jwt()->>'role','')<>'authenticated'",
            "writer_active',true",
            "task_enabled',false",
            "mailbox_contacted',false",
            "uid514_processed',false",
            "production_writes',false",
        ):
            self.assertIn(marker.lower(), self.adapter.lower())
        self.assertNotIn("verify_pdc_monitor_runtime_binding_authenticated_766", self.adapter)
        self.assertNotIn("insert into", self.adapter.lower())
        self.assertNotIn("update ", self.adapter.lower())
        self.assertNotIn("delete from", self.adapter.lower())

    def test_wrapper_switches_only_the_preflight_authority_and_preserves_797(self):
        self.assertIn("verify_pdc_historical_runtime_binding_authenticated_802", self.wrapper)
        self.assertNotIn("pdc_monitor_authenticated_active_scope_674", self.wrapper)
        for marker in (
            "submit_pdc_historical_reconciliation_778_pre797",
            "pdc_historical_797_complete_domain_snapshot",
            "pdc_797_complete_domain_drift",
            "authoritative_domain_before",
            "pdc_historical_complete_domain_readbacks_797",
            "on conflict(receipt_id) do nothing",
            "historical_reconciliation_782_atomic_rollback",
        ):
            self.assertIn(marker.lower(), self.wrapper.lower())

    def test_negative_identity_mailbox_pilot_and_grant_contracts_are_fail_closed(self):
        for marker in (
            "historical_runtime_binding_mismatch_802",
            "historical_runtime_containment_mismatch_802",
            "pdc_monitor_staging_guard",
            "to_regclass('public.pdc_production_environment_sentinel')",
            "active_mailbox_count',0",
            "(select count(*) from public.monitored_mailboxes where active)<>0",
            "(select count(*) from public.pdc_email_monitor_pilot where singleton and (enabled or automatic_rule_application or automatic_authenticated_jobcards or outbound_email_enabled))<>0",
            "grant execute on function public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) to authenticated",
            "revoke all on function public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) from public,anon,authenticated,service_role,pdc_email_monitor",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant execute on function public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) to anon", self.lower)
        self.assertNotIn("grant execute on function public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) to service_role", self.lower)

    def test_idempotency_and_historical_mutation_remain_in_existing_boundary(self):
        self.assertIn("language plpgsql stable security definer", self.adapter.lower())
        self.assertNotIn("random", self.adapter.lower())
        self.assertNotIn("clock_timestamp", self.adapter.lower())
        self.assertIn("submit_pdc_historical_reconciliation_778_pre797", self.wrapper)
        self.assertIn("on conflict(receipt_id) do nothing", self.wrapper.lower())
        self.assertIn("pdc_historical_reconciliation_778_receipts", self.wrapper)
        self.assertNotIn("insert into public.workshop", self.wrapper.lower())
        self.assertNotIn("update public.vehicles", self.wrapper.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
