from __future__ import annotations

import json
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830222000_805_proposal_evidence_tuple_contained_successor.sql"
FROZEN = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-795-explicit-frozen-rows.json")
REPORT = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-804-final-apply-report.json")


class HistoricalProposalEvidence805ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        cls.writer = cls.sql[cls.sql.index("CREATE OR REPLACE FUNCTION public.pdc_historical_writer_authorized_777"):cls.sql.index("REVOKE ALL ON FUNCTION public.pdc_historical_writer_authorized_777")]
        cls.review = cls.sql[cls.sql.index("CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_succes"):cls.sql.index("REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_793_proposal_review_succes")]

    def test_append_only_head_guard_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 16)
        for marker in (
            "20260830221000",
            "804_nested_pre797_contained_runtime_802_successor",
            "20260830222000",
            "805_proposal_evidence_tuple_contained_successor",
            "PDC_805_CURRENT_HEAD_OR_CONTAINMENT_GUARD_FAILED",
            "PDC_805_NESTED_SOURCE_PRESTATE_MISMATCH",
            "PDC_805_WRITER_AUTH_POSTCONDITION_FAILED",
            "PDC_805_793_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_nested_777_and_793_use_authenticated_802_without_674(self):
        self.assertEqual(self.writer.lower().count("verify_pdc_historical_runtime_binding_authenticated_802"), 1)
        self.assertEqual(self.review.lower().count("verify_pdc_historical_runtime_binding_authenticated_802"), 1)
        self.assertNotIn("pdc_monitor_authenticated_active_scope_674", self.writer.lower())
        self.assertNotIn("pdc_monitor_authenticated_active_scope_674", self.review.lower())
        for body in (self.writer, self.review):
            self.assertIn("auth.uid()", body.lower())
            self.assertIn("auth.jwt()", body.lower())
            self.assertIn("pdc_monitor_staging_guard", body.lower())
            self.assertIn("pdc_production_environment_sentinel", body.lower())
            self.assertIn("return false", body.lower()) if body is self.writer else self.assertIn("unauthorized", body.lower())

    def test_proposal_conflicts_and_missing_bindings_remain_fail_closed(self):
        for marker in (
            "historical_proposal_tuple_conflict",
            "historical_proposal_payload_conflict",
            "historical_proposal_terminal_conflict",
            "pdc_email_source_claims",
        ):
            self.assertIn(marker.lower(), self.lower + (ROOT / "supabase/staging_only/20260830190000_789_historical_proposal_binding_successor.sql").read_text(encoding="utf-8").lower())
        self.assertNotIn("update public.pdc_ai_intake_proposals", self.lower)
        self.assertNotIn("delete from public.pdc_ai_intake_proposals", self.lower)
        self.assertNotIn("update public.pdc_email_source_claims", self.lower)
        self.assertNotIn("delete from public.pdc_email_source_claims", self.lower)

    def test_grants_and_source_hash_postconditions_are_least_privilege(self):
        for marker in (
            "{postgres=x/postgres}",
            "revoke all on function public.pdc_historical_writer_authorized_777",
            "grant execute on function public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb) to postgres",
            "revoke all on function public.submit_pdc_historical_reconciliation_793_proposal_review_successor",
            "grant execute on function public.submit_pdc_historical_reconciliation_793_proposal_review_successor(jsonb) to postgres",
            "position('pdc_monitor_authenticated_active_scope_674'",
            "position('verify_pdc_historical_runtime_binding_authenticated_802'",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_authoritative_frozen_exports_and_804_classification_are_exact(self):
        frozen = json.loads(FROZEN.read_text(encoding="utf-8"))
        report = json.loads(REPORT.read_text(encoding="utf-8"))
        rows = frozen["rows"]
        self.assertEqual(len(rows), 15)
        self.assertEqual({r["provider_uid"] for r in rows}, {f"1:{uid}" for uid in (21, 22, 23, 26, 40, 57, 85, 93, 95, 96, 133, 134, 137, 168, 172)})
        result_rows = {r["provider_uid"]: r for r in report["rows"]}
        self.assertEqual(sum(r["code"] == "historical_proposal_tuple_conflict" for r in result_rows.values()), 10)
        self.assertEqual(sum(r["code"] == "historical_wrapper_preflight_failed" for r in result_rows.values()), 5)
        self.assertEqual(report["summary"]["rows"], 15)
        self.assertEqual(report["summary"]["accepted"], 0)
        for uid in ("1:133", "1:134", "1:137", "1:168", "1:172"):
            self.assertEqual(result_rows[uid]["state"], "retry")

    def test_no_historical_apply_or_outbox_path_is_added(self):
        for forbidden in ("imap", "send_mail", "send_email", "historical_apply", "create outbox"):
            self.assertNotIn(forbidden, self.sql.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
