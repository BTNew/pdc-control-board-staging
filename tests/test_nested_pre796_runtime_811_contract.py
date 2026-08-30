from __future__ import annotations

import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830232000_811_nested_793_runtime_802_response_successor.sql"


class NestedPre796Runtime811ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        match = re.search(
            r"(?is)create or replace function public\.submit_pdc_historical_reconciliation_793_proposal_review_succes\([^)]*\).*?as \$(\w+)\$(.*?)\$\1\$\s*;",
            cls.sql,
        )
        if not match:
            raise AssertionError("patched 793 function missing")
        cls.review = match.group(2)

    def test_append_only_810_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 12)
        for marker in (
            "20260830231000",
            "810_pre796_historical_authorization_renewal_resolver_successor",
            "20260830232000",
            "811_nested_793_runtime_802_response_successor",
            "PDC_811_CURRENT_HEAD_OR_793_PRESTATE_FAILED",
            "PDC_811_793_RUNTIME_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_only_later_nested_runtime_call_changes_to_802(self):
        self.assertEqual(self.review.lower().count("verify_pdc_historical_runtime_binding_authenticated_802"), 2)
        self.assertNotIn("verify_pdc_monitor_runtime_binding_authenticated_766", self.review.lower())
        self.assertIn("historical_runtime_binding_unavailable", self.review.lower())
        for marker in (
            "v_runtime->>'actor_id'",
            "v_runtime->>'actor_email'",
            "v_runtime->>'task_enabled'",
            "v_runtime->>'mailbox_contacted'",
            "v_runtime->>'production_writes'",
            "pdc_historical_writer_authorization_809_resolve",
            "historical_proposal_tuple_conflict",
            "historical_reconciliation_782_atomic_rollback",
        ):
            self.assertIn(marker.lower(), self.review.lower())

    def test_security_and_no_business_mutation(self):
        for marker in (
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "revoke all on function public.submit_pdc_historical_reconciliation_793",
            "grant execute on function public.submit_pdc_historical_reconciliation_793",
        ):
            self.assertIn(marker.lower(), self.lower)
        for forbidden in (
            "update public.pdc_historical_reconciliation_writer_authorizations_773",
            "delete from public.pdc_historical_reconciliation_writer_authorizations_773",
            "update public.pdc_ai_intake_proposals",
            "delete from public.pdc_ai_intake_proposals",
            "create outbox",
            "send email",
            "imap",
        ):
            self.assertNotIn(forbidden, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
