from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830235000_814_historical_enqueue_status_drift_successor.sql"


class HistoricalEnqueueStatus814ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_813_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 12)
        for marker in (
            "20260830234000",
            "813_historical_unique_attachment_observation_request_hash_successor",
            "20260830235000",
            "814_historical_enqueue_status_drift_successor",
            "PDC_814_CURRENT_HEAD_OR_HELPER_PRESTATE_FAILED",
            "PDC_814_HISTORICAL_STATUS_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_only_historical_status_update_is_removed(self):
        self.assertIn("create or replace function public.enqueue_pdc_historical_email_intake_812(", self.lower)
        body = self.lower.split("as $function$", 1)[1].split("revoke all on function", 1)[0]
        self.assertNotIn("update public.pdc_email_monitor_status set updated_at=clock_timestamp() where singleton", body)
        self.assertIn("pdc_monitor_authenticated_active_scope_673", body)
        self.assertIn("pdc_historical_writer_authorization_809_resolve", body)
        self.assertIn("pdc_historical_enqueue_authorization_failed", body)

    def test_normal_live_path_and_security_remain_separate(self):
        self.assertIn("normal live enqueue", self.lower)
        for marker in (
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "revoke all on function public.enqueue_pdc_historical_email_intake_812",
            "grant execute on function public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb) to postgres",
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
