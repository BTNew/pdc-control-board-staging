from __future__ import annotations

import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830233000_812_historical_full_transaction_zero_mailbox_successor.sql"


class HistoricalFullTransaction812ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_811_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 18)
        for marker in (
            "20260830232000",
            "811_nested_793_runtime_802_response_successor",
            "20260830233000",
            "812_historical_full_transaction_zero_mailbox_successor",
            "PDC_812_CURRENT_HEAD_OR_793_PRESTATE_FAILED",
            "PDC_812_RUNTIME_OR_IMPORT_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_historical_enqueue_is_exact_zero_mailbox_adapter(self):
        self.assertIn("create or replace function public.enqueue_pdc_historical_email_intake_812(", self.lower)
        self.assertIn("pdc_monitor_authenticated_active_scope_673(null)", self.lower)
        self.assertIn("pdc_historical_writer_authorization_809_resolve", self.lower)
        self.assertIn("not active", self.lower)
        self.assertIn("monitored_mailbox_id", self.lower)
        self.assertIn("null,v_recipient", self.lower)
        self.assertIn("pdc_historical_enqueue_authorization_failed", self.lower)

    def test_importer_exception_is_narrow_and_historical_bound(self):
        self.assertIn("coalesce(v_intake.monitored_mailbox_id,'12fe383d-5c1e-5801-96e4-f67cf3e3bb57'::uuid)", self.lower)
        self.assertIn("v_intake.monitored_mailbox_id is null", self.lower)
        self.assertIn("pdc_historical_provider_observations_778", self.lower)
        self.assertIn("pdc_monitor_authenticated_active_scope_673(null)", self.lower)
        self.assertIn("pdc_historical_writer_authorized_773", self.lower)
        self.assertIn("monitored_mailbox_binding_mismatch", self.lower)

    def test_793_call_site_and_security_are_preserved(self):
        self.assertIn("public.enqueue_pdc_historical_email_intake_812(", self.lower)
        self.assertIn("historical_manifest_sha256", self.lower)
        self.assertIn("historical_evidence_hash", self.lower)
        self.assertIn("pdc_historical_writer_authorization_809_resolve", self.lower)
        for marker in (
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "revoke all on function public.enqueue_pdc_historical_email_intake_812",
            "grant execute on function public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb) to postgres",
            "revoke all on function public.import_pdc_jobcard_attachment_canonical",
            "revoke all on function public.submit_pdc_historical_reconciliation_793",
        ):
            self.assertIn(marker.lower(), self.lower)
        for forbidden in (
            "update public.pdc_historical_reconciliation_writer_authorizations_773",
            "delete from public.pdc_historical_reconciliation_writer_authorizations_773",
            "create outbox",
            "send email",
            "imap",
        ):
            self.assertNotIn(forbidden, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
