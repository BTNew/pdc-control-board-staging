from __future__ import annotations

import json
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830224000_807_pre796_766_final_contained_runtime_successor.sql"
REPORT = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-804-final-apply-report.json")


class HistoricalPre796807ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        start = cls.sql.index("CREATE OR REPLACE FUNCTION public.submit_pdc_historical_reconciliation_778_pre796")
        end = cls.sql.index("REVOKE ALL ON FUNCTION public.submit_pdc_historical_reconciliation_778_pre796")
        cls.pre796 = cls.sql[start:end]

    def test_append_only_806_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 13)
        for marker in (
            "20260830223000",
            "806_canonical_frozen_authentication_tuple_successor",
            "20260830224000",
            "807_pre796_766_final_contained_runtime_successor",
            "PDC_807_CURRENT_HEAD_OR_CONTAINMENT_GUARD_FAILED",
            "PDC_807_PRE796_SOURCE_PRESTATE_FAILED",
            "PDC_807_PRE796_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_only_nested_pre796_runtime_guard_changes(self):
        self.assertEqual(self.pre796.lower().count("verify_pdc_historical_runtime_binding_authenticated_802"), 2)
        self.assertNotIn("verify_pdc_monitor_runtime_binding_authenticated_766", self.pre796.lower())
        self.assertIn("pdc_historical_reconciliation_793_proposal_review_succes", self.pre796.lower())
        self.assertIn("historical_proposal_tuple_conflict", self.pre796.lower())
        self.assertIn("historical_reconciliation_782_atomic_rollback", self.pre796.lower())
        self.assertIn("pdc_782_1740_protected_boundary_drift", self.pre796.lower())
        self.assertIn("pdc_788_protected_boundary_drift", self.pre796.lower())

    def test_normal_766_and_security_boundaries_remain_pinned(self):
        self.assertIn("verify_pdc_monitor_runtime_binding_authenticated_766", self.lower)
        for marker in (
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "pdc_monitor_stage_activation_writers",
            "pdc_email_monitor_authenticated_enqueue_trigger_controls_675",
            "pdc_email_monitor_pilot",
            "revoke all on function public.submit_pdc_historical_reconciliation_778_pre796",
            "grant execute on function public.submit_pdc_historical_reconciliation_778_pre796(jsonb) to postgres",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_778_pre796(jsonb) to authenticated", self.lower)
        self.assertNotIn("grant execute on function public.verify_pdc_historical_runtime_binding_authenticated_802(text,text,text,text,text,text,text) to anon", self.lower)

    def test_five_retry_rows_and_ten_business_conflicts_are_not_reclassified(self):
        report = json.loads(REPORT.read_text(encoding="utf-8"))
        rows = report["rows"]
        self.assertEqual(sum(row["code"] == "historical_proposal_tuple_conflict" for row in rows), 10)
        self.assertEqual(sum(row["code"] == "historical_wrapper_preflight_failed" for row in rows), 5)
        self.assertEqual(report["summary"]["accepted"], 0)
        for uid in ("1:133", "1:134", "1:137", "1:168", "1:172"):
            self.assertEqual(next(row for row in rows if row["provider_uid"] == uid)["state"], "retry")
        for marker in ("historical_proposal_tuple_conflict", "review_required", "pdc_historical_reconciliation_writer_authorizations_773"):
            self.assertIn(marker.lower(), self.lower + report.__repr__().lower())

    def test_no_apply_outbox_or_proposal_rewrite(self):
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
