from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830240000_819_historical_importer_auth_sender_final_successor.sql"


class HistoricalImporterAuthSender819ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_817_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 12)
        for marker in (
            "20260830238000",
            "817_historical_importer_sender_binding_final_successor",
            "20260830240000",
            "819_historical_importer_auth_sender_final_successor",
            "pdc_819_current_head_or_importer_prestate_failed",
            "pdc_819_historical_importer_auth_sender_postcondition_failed",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_only_preassignment_historical_auth_sender_changes(self):
        body = self.lower.split("as $function$", 1)[1].split("revoke all on function", 1)[0]
        stale = "public.pdc_historical_writer_authorized_773(v_parent_hash,h.provider_uid,v_sender,v_auth"
        bound = "public.pdc_historical_writer_authorized_773(v_parent_hash,h.provider_uid,lower(coalesce(v_intake.sender_email,'')),v_auth"
        self.assertNotIn(stale, body)
        self.assertEqual(body.count(bound), 2)
        self.assertIn("pdc_historical_provider_observations_778", body)
        self.assertIn("pdc_monitor_authenticated_active_scope_673", body)

    def test_security_and_no_business_mutation(self):
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
