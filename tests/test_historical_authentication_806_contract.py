from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830223000_806_canonical_frozen_authentication_tuple_successor.sql"


class HistoricalAuthentication806ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_805_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 28)
        for marker in (
            "20260830222000",
            "805_proposal_evidence_tuple_contained_successor",
            "20260830223000",
            "806_canonical_frozen_authentication_tuple_successor",
            "pdc_806_current_head_or_containment_guard_failed",
            "pdc_806_canonicalizer_postcondition_failed",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_only_aligned_is_stripped_and_all_boundaries_use_helper(self):
        self.assertIn("return v-'aligned'", self.lower)
        for marker in (
            "pdc_historical_authentication_canonical_806(p_authentication)",
            "pdc_historical_authentication_canonical_806(v_request->'authentication')",
            "jsonb_set(p_request,'{authentication}'",
        ):
            self.assertIn(marker.lower(), self.lower)
        for signature in (
            "pdc_historical_writer_authorized_777",
            "submit_pdc_historical_reconciliation_793_proposal_review_succes",
            "submit_pdc_historical_reconciliation_778_pre796",
            "submit_pdc_historical_reconciliation_778_pre797",
            "submit_pdc_historical_reconciliation_778",
        ):
            start = self.lower.index(f"create or replace function public.{signature.lower()}")
            end = self.lower.index("revoke all on function public.", start)
            self.assertIn("pdc_historical_authentication_canonical_806", self.lower[start:end])

    def test_unknown_or_malformed_authentication_is_not_accepted(self):
        for marker in (
            "jsonb_typeof(v) is distinct from 'object'",
            "v_keys is distinct from array['aligned'",
            "jsonb_typeof(v->'aligned') is distinct from 'boolean'",
            "if v_keys is distinct from",
            "pdc_806_function_security_prestate_failed",
            "pdc_806_function_security_postcondition_failed",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("update public.pdc_ai_intake_proposals", self.lower)
        self.assertNotIn("delete from public.pdc_ai_intake_proposals", self.lower)
        self.assertNotIn("update public.pdc_email_source_claims", self.lower)
        self.assertNotIn("delete from public.pdc_email_source_claims", self.lower)

    def test_normal_runtime_and_security_boundaries_remain_pinned(self):
        for marker in (
            "verify_pdc_historical_runtime_binding_authenticated_802",
            "pdc_monitor_stage_activation_writers",
            "pdc_email_monitor_authenticated_enqueue_trigger_controls_675",
            "pdc_production_environment_sentinel",
            "pdc_historical_reconciliation_writer_authorizations_773",
            "grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to authenticated",
            "grant execute on function public.pdc_historical_authentication_canonical_806(jsonb) to postgres",
        ):
            self.assertIn(marker.lower(), self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
