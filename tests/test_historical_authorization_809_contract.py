from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830230000_809_historical_writer_authorization_renewal_successor.sql"
REPORT = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-808-final-apply-report.json")


class HistoricalAuthorization809ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        match = re.search(
            r"(?is)create or replace function public\.submit_pdc_historical_reconciliation_793_proposal_review_succes\([^)]*\).*?as \$(\w+)\$(.*?)\$\1\$;",
            cls.sql,
        )
        if not match:
            raise AssertionError("patched 793 function missing")
        cls.review = match.group(2)

    def test_append_only_808_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 24)
        for marker in (
            "20260830225000",
            "808_historical_writer_auth_contained_successor",
            "20260830230000",
            "809_historical_writer_authorization_renewal_successor",
            "PDC_809_CURRENT_HEAD_OR_PROPOSAL_PRESTATE_FAILED",
            "PDC_809_RENEWAL_OR_PROPOSAL_RESOLVER_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_exact_five_renewals_and_expiry_are_narrowly_bound(self):
        for uid, stock, evidence in (
            ("1:133", "13047164", "868866bfebe0d8a924bd15ce151d472a8966a739ab8d733ff6d6a4f907a69f69"),
            ("1:134", "13047383", "038180cf1bb30136dbd2d176f45dbb9c4c6cf730cff7a7ed6e59a32dd5f1ec7c"),
            ("1:137", "13047272", "b0dfa4aaaefed0d71f878e8b69adf7459251f79795cff9809009b8418159abff"),
            ("1:168", "13049488", "5df8e4c6ccf29f88eeaca96c8856b2653eff27390e9ca08c872343480358fa09"),
            ("1:172", "13044227", "345ee4f9d9d2a7fa47376d8615e9f05086a5f9f65ce9fa6322df9f726e0dd56e"),
        ):
            self.assertIn(f"('{uid}','{stock}','{evidence}'", self.lower)
        for marker in (
            "supersedes_authorization_id",
            "expires_at>authorized_at",
            "expires_at<=authorized_at+interval '24 hours'",
            "authorized_actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'",
            "authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'",
            "renewal_reason='craig-authorized staging renewal of expired exact frozen proposal-notice authorization'",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_793_uses_successor_resolver_and_preserves_conflicts(self):
        self.assertEqual(self.review.lower().count("pdc_historical_writer_authorization_809_resolve"), 2)
        self.assertIn("select count(*) into v_authz_count\n  from public.pdc_historical_writer_authorization_809_resolve", self.review.lower())
        self.assertIn("select * into v_authz\n  from public.pdc_historical_writer_authorization_809_resolve", self.review.lower())
        self.assertIn("historical_proposal_tuple_conflict", self.lower)
        report = json.loads(REPORT.read_text(encoding="utf-8"))
        self.assertEqual(sum(row["code"] == "historical_proposal_tuple_conflict" for row in report["rows"]), 10)
        self.assertEqual(sum(row["provider_uid"] in {"1:21", "1:22", "1:23", "1:26", "1:40", "1:57", "1:85", "1:93", "1:95", "1:96"} for row in report["rows"]), 10)

    def test_immutable_history_security_and_no_prohibited_paths(self):
        for marker in (
            "on delete restrict",
            "alter table public.pdc_historical_reconciliation_writer_authorizations_809 enable row level security",
            "alter table public.pdc_historical_reconciliation_writer_authorizations_809 force row level security",
            "pdc_historical_writer_authorizations_809_immutable",
            "revoke all on table public.pdc_historical_reconciliation_writer_authorizations_809",
            "grant execute on function public.pdc_historical_writer_authorization_809_resolve",
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
        for uid in ("1:21", "1:22", "1:23", "1:26", "1:40", "1:57", "1:85", "1:93", "1:95", "1:96"):
            self.assertIn(uid, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
