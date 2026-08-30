from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830251000_830_historical_operation_hours_evidence_successor.sql"


class HistoricalOperationHours830ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        cls.body = cls.lower.split("as $function$", 1)[1].split("$function$", 1)[0]

    def test_parses_and_pins_828_predecessor(self):
        self.assertEqual(len(parse_sql(self.sql)), 15)
        for marker in (
            "20260830249000", "828_historical_replay_order_successor",
            "20260830251000", "830_historical_operation_hours_evidence_successor",
            "pdc_830_current_head_or_operation_hours_prestate_failed",
            "pdc_830_operation_hours_evidence_postcondition_failed",
        ):
            self.assertIn(marker, self.lower)

    def test_unknown_hours_are_not_coalesced_to_zero(self):
        self.assertNotIn("coalesce(sum((x->>'estimated_hours')::numeric),0)", self.body)
        self.assertIn("sum((x->>'estimated_hours')::numeric) filter (where jsonb_typeof(x->'estimated_hours')='number')", self.body)
        self.assertIn("v_hours_sum:=v_known_hours_sum", self.body)
        self.assertIn("v_unknown_hours_count", self.body)
        self.assertIn("v_hours_coverage", self.body)
        self.assertIn("estimated_hours_sum drop not null", self.lower)

    def test_explicit_zero_and_null_are_distinct(self):
        self.assertIn("jsonb_typeof(x->'estimated_hours')='number'", self.body)
        self.assertIn("jsonb_typeof(x->'estimated_hours')='null'", self.body)
        self.assertIn("'hours_knowledge_status',case when v_unknown_hours_count=0 then 'complete' when v_known_hours_count=0 then 'all_unknown' else 'partial' end", self.body)
        self.assertIn("known_hours_sum", self.body)
        self.assertIn("known_hours_count", self.body)

    def test_security_and_containment_preserved(self):
        for marker in (
            "pdc_monitor_staging_guard", "pdc_production_environment_sentinel",
            "revoke all on function public.import_pdc_jobcard_attachment_canonical",
            "grant execute on function public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) to postgres",
            "pdc_historical_reconciliation_writer_authorizations_809",
            "no historical apply outbox mailbox task outbound or production operation",
        ):
            self.assertIn(marker, self.lower)
        for forbidden in (
            "update public.pdc_historical_reconciliation_writer_authorizations_773",
            "delete from public.pdc_historical_reconciliation_writer_authorizations_773",
            "create outbox", "send email", "imap",
        ):
            self.assertNotIn(forbidden, self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
