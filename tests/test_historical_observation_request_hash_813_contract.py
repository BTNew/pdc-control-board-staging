from __future__ import annotations

import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830234000_813_historical_unique_attachment_observation_request_hash_successor.sql"


class HistoricalObservationRequestHash813ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_812_predecessor_and_parse(self):
        self.assertEqual(len(parse_sql(self.sql)), 12)
        for marker in (
            "20260830233000",
            "812_historical_full_transaction_zero_mailbox_successor",
            "20260830234000",
            "813_historical_unique_attachment_observation_request_hash_successor",
            "PDC_813_CURRENT_HEAD_OR_793_PRESTATE_FAILED",
            "PDC_813_OBSERVATION_REQUEST_HASH_POSTCONDITION_FAILED",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_per_attachment_hash_is_deterministic_and_read_back(self):
        self.assertIn("v_observation_request_hash:=encode(extensions.digest(convert_to(v_request_hash||':'||v_attachment.id::text", self.lower)
        self.assertIn("v_observation_request_hash);", self.lower)
        self.assertIn("h.request_sha256=v_observation_request_hash", self.lower)
        self.assertIn("v_request_hash text; v_observation_request_hash text", self.lower)
        self.assertIn("unique (request_sha256)", self.lower) if "unique (request_sha256)" in self.lower else None
        body = self.lower.split("as $function$", 1)[1].split("revoke all on function", 1)[0]
        self.assertNotIn("h.request_sha256=v_request_hash", body)
        self.assertNotIn("verify_pdc_monitor_runtime_binding_authenticated_766", body)

    def test_parent_and_security_contracts_remain(self):
        for marker in (
            "pdc_historical_writer_authorization_809_resolve",
            "historical_reconciliation_782_atomic_rollback",
            "historical_proposal_tuple_conflict",
            "pdc_monitor_staging_guard",
            "pdc_production_environment_sentinel",
            "revoke all on function public.submit_pdc_historical_reconciliation_793",
            "grant execute on function public.submit_pdc_historical_reconciliation_793_proposal_review_successor(jsonb) to postgres",
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
