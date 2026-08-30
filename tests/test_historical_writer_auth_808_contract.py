from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830225000_808_historical_writer_auth_contained_successor.sql"
REPORT = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-804-final-apply-report.json")


class HistoricalWriterAuth808ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        match = re.search(
            r"(?is)create or replace function public\.pdc_historical_writer_authorized_773\([^)]*\).*?as \$(\w+)\$(.*?)\$\1\$",
            cls.sql,
        )
        if not match:
            raise AssertionError("writer authorization definition missing")
        cls.writer = match.group(2)

    def test_append_only_807_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 12)
        for marker in (
            "20260830224000",
            "807_pre796_766_final_contained_runtime_successor",
            "20260830225000",
            "808_historical_writer_auth_contained_successor",
            "PDC_808_CURRENT_HEAD_OR_WRITER_PRESTATE_FAILED",
            "PDC_808_WRITER_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_only_writer_guard_changes_to_authenticated_802(self):
        self.assertEqual(self.writer.lower().count("verify_pdc_historical_runtime_binding_authenticated_802"), 1)
        self.assertNotIn("pdc_monitor_authenticated_active_scope_674", self.writer.lower())
        for marker in (
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "auth.uid()",
            "authorized_actor_id=auth.uid()",
            "provider_authentication is not distinct from p_authentication",
            "historical_reference_stock_excluded",
            "v_stock='13056899'",
            "pdc_historical_reconciliation_writer_authorizations_773",
        ):
            self.assertIn(marker.lower(), self.writer.lower())

    def test_fail_closed_conflicts_and_no_business_mutation(self):
        for marker in (
            "historical_proposal_tuple_conflict",
            "historical_reference_stock_excluded",
        ):
            self.assertIn(marker.lower(), self.lower)
        for forbidden in (
            "update public.pdc_ai_intake_proposals",
            "delete from public.pdc_ai_intake_proposals",
            "update public.pdc_email_source_claims",
            "delete from public.pdc_email_source_claims",
            "create outbox",
            "send email",
            "imap",
        ):
            self.assertNotIn(forbidden, self.lower)
        report = json.loads(REPORT.read_text(encoding="utf-8"))
        self.assertEqual(sum(row["code"] == "historical_proposal_tuple_conflict" for row in report["rows"]), 10)

    def test_security_and_least_privilege_postconditions_are_pinned(self):
        self.assertIn("revoke all on function public.pdc_historical_writer_authorized_773", self.lower)
        self.assertIn("grant execute on function public.pdc_historical_writer_authorized_773(text,text,text,jsonb,text) to postgres", self.lower)
        self.assertIn("{postgres=x/postgres}", self.lower)
        self.assertIn("2d50ef3031df376a61821332988daf34346bde39504c78757c77fc43c9ca7284", self.lower)
        self.assertIn("c832a015a4ddee1d9f727f7b196a10d4e2fbf9822d559be1d33e4eab6f590ae1", self.lower)
        self.assertIn("select count(*) from public.pdc_historical_reconciliation_writer_authorizations_773 where active", self.lower)
        self.assertIn("select count(*) from public.monitored_mailboxes where active", self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
