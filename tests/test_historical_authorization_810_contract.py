from __future__ import annotations

import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830231000_810_pre796_historical_authorization_renewal_resolver_successor.sql"


class HistoricalAuthorization810ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        match = re.search(
            r"(?is)create or replace function public\.submit_pdc_historical_reconciliation_778_pre796\([^)]*\).*?as \$(\w+)\$(.*?)\$\1\$;",
            cls.sql,
        )
        if not match:
            raise AssertionError("patched pre796 function missing")
        cls.pre796 = match.group(2)

    def test_append_only_809_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 12)
        for marker in (
            "20260830230000",
            "809_historical_writer_authorization_renewal_successor",
            "20260830231000",
            "810_pre796_historical_authorization_renewal_resolver_successor",
            "PDC_810_CURRENT_HEAD_OR_PREFINAL_PRESTATE_FAILED",
            "PDC_810_PREFINAL_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_only_pre796_authorization_reads_use_809_resolver(self):
        self.assertEqual(self.pre796.lower().count("pdc_historical_writer_authorization_809_resolve"), 2)
        self.assertIn("select count(*) into v_authz_count\n  from public.pdc_historical_writer_authorization_809_resolve", self.pre796.lower())
        self.assertIn("select * into v_authz\n  from public.pdc_historical_writer_authorization_809_resolve", self.pre796.lower())
        self.assertIn("historical_authorization_expired", self.pre796.lower())
        self.assertIn("historical_proposal_tuple_conflict", self.pre796.lower())
        self.assertIn("historical_reconciliation_782_atomic_rollback", self.pre796.lower())

    def test_identity_containment_and_no_business_mutation(self):
        for marker in (
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "monitored_mailboxes where active",
            "revoke all on function public.submit_pdc_historical_reconciliation_778_pre796",
            "grant execute on function public.submit_pdc_historical_reconciliation_778_pre796(jsonb) to postgres",
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

    def test_five_scope_and_ten_conflict_boundary_is_explicit(self):
        self.assertIn("809_historical_writer_authorization_renewal_successor", self.lower)
        self.assertIn("pdc_historical_writer_authorization_809_resolve", self.lower)
        self.assertIn("preserve ten material tuple conflicts", self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
