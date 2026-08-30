from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830252000_831_historical_navision_refresh_successor.sql"


class HistoricalNavisionRefresh831ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()
        cls.body = cls.sql.split("as $function$", 1)[1].split("$function$", 1)[0]

    def test_approved_refresh_wrapper_replaces_direct_pre171_call(self):
        self.assertIn("reconcile_navision_operational_record_pre_700(v_record.id,p_actor_id,v_actor_email)", self.body)
        self.assertNotIn("reconcile_navision_operational_record_pre171(v_record.id,p_actor_id,v_actor_email)", self.body)
        self.assertIn("pdc_831_navision_refresh_postcondition_failed", self.sql)

    def test_partial_apply_continuation_guard_is_exact(self):
        self.assertIn("<>4", self.sql)
        self.assertIn("<>20", self.sql)
        for uid in ("1:133", "1:137", "1:168", "1:172"):
            self.assertIn(uid, self.sql)
        self.assertNotIn("'1:134'", self.sql.split("do $guard$", 1)[1].split("end $guard$", 1)[0])

    def test_no_immutable_authorization_mutation_or_outbound(self):
        self.assertNotIn("update public.pdc_historical_reconciliation_writer_authorizations_773", self.sql)
        self.assertNotIn("delete from public.pdc_historical_reconciliation_writer_authorizations_773", self.sql)
        self.assertNotIn("send email", self.sql)
        self.assertNotIn("imap", self.sql)


if __name__ == "__main__":
    unittest.main(verbosity=2)
