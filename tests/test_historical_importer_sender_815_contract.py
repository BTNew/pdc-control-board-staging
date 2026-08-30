from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830236000_815_historical_importer_sender_binding_successor.sql"


class HistoricalImporterSender815ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        cls.body = cls.lower.split("as $function$", 1)[1].split("revoke all on function", 1)[0]

    def test_append_only_814_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 12)
        for marker in (
            "20260830235000",
            "814_historical_enqueue_status_drift_successor",
            "20260830236000",
            "815_historical_importer_sender_binding_successor",
            "pdc_815_current_head_or_importer_prestate_failed",
            "pdc_815_historical_importer_sender_postcondition_failed",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_only_historical_sender_fallback_binding_changes(self):
        self.assertEqual(self.body.count("h.sender_email=lower(coalesce(v_intake.sender_email,''))"), 2)
        self.assertNotIn("h.sender_email=v_sender", self.body)
        self.assertIn("pdc_historical_provider_observations_778", self.body)
        self.assertIn("pdc_historical_writer_authorized_773", self.body)
        self.assertIn("monitored_mailbox_binding_mismatch", self.body)

    def test_security_and_normal_path_are_preserved(self):
        for marker in (
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "revoke all on function public.import_pdc_jobcard_attachment_canonical",
            "grant execute on function public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) to postgres",
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
