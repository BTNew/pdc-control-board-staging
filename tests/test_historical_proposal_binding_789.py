from __future__ import annotations

import importlib.util
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
CALLER = ROOT / "pdc_historical_778_caller.py"
IMPORTER = ROOT / "pdc_full_inbox_typed_import.py"
M789 = ROOT / "supabase/staging_only/20260830190000_789_historical_proposal_binding_successor.sql"
ROWS = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-778-rows.json")


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class HistoricalProposalBinding789Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.caller = load(CALLER, "historical_proposal_binding_caller")
        sys.modules["pdc_historical_778_caller"] = cls.caller
        cls.importer = load(IMPORTER, "historical_proposal_binding_importer")

    def test_migration_is_append_only_after_788_and_has_immutable_binding_contract(self):
        sql = M789.read_text(encoding="utf-8").lower()
        self.assertEqual(len(parse_sql(M789.read_text(encoding="utf-8"))), 24)
        for marker in (
            "20260830185000",
            "pdc_historical_proposal_bindings_789",
            "historical_proposal_tuple_conflict",
            "historical_proposal_terminal_conflict",
            "pending_proposal_observation_mismatch",
            "pdc_789_proposal_binding_immutable",
            "request_sha256",
            "observation_match",
            "proposal_observations",
            "revoke all on table public.pdc_historical_proposal_bindings_789",
            "relforcerowsecurity",
            "pdc_789_current_head_guard_failed",
            "where proposal_id=v_proposal_id for update",
            "historical_proposal_payload_conflict",
            "where source_hash=lower(p_request->>'parent_source_hash')",
            "limit 1 for update",
        ):
            self.assertIn(marker, sql)
        self.assertNotIn("update public.pdc_ai_intake_proposals", sql)
        self.assertNotIn("delete from public.pdc_ai_intake_proposals", sql)
        self.assertNotIn("update public.pdc_historical_proposal_bindings_789", sql)
        self.assertNotIn("delete from public.pdc_historical_proposal_bindings_789", sql)

    def test_frozen_uid_1_21_is_the_regression_input(self):
        document = json.loads(ROWS.read_text(encoding="utf-8"))
        row = next(item for item in document["rows"] if item["provider_uid"] == "1:21")
        request = self.caller.build_historical_request(row)
        self.assertEqual(request["provider_uid"], "1:21")
        self.assertEqual(request["stock_number"], "13042997")
        self.assertEqual(self.caller.canonical_request_digest(request), "fd784959b016976994087545866e346f01b6f05e1e0faf8627bda25ed9e84550")

    def test_bounded_caller_rejects_missing_or_extra_frozen_uid(self):
        document = json.loads(ROWS.read_text(encoding="utf-8"))
        rows = document["rows"]
        with self.assertRaises(self.importer.Historical777Error):
            self.importer.select_authorized_rows(rows[:-1])
        with self.assertRaises(self.importer.Historical777Error):
            self.importer.select_authorized_rows(rows + [dict(rows[0])])

    def test_false_result_is_durable_review_and_nonzero_summary(self):
        document = json.loads(ROWS.read_text(encoding="utf-8"))
        rows = document["rows"]
        with tempfile.TemporaryDirectory() as directory:
            outbox = Path(directory) / "new-789-outbox.sqlite3"
            connection = self.importer.prepare_fresh_outbox(outbox)
            try:
                results = self.importer.run_bounded_historical(
                    rows, connection,
                    lambda request: {"ok": False, "code": "historical_proposal_tuple_conflict", "data": {"review_required": True}}
                    if request["provider_uid"] == "1:21" else {"ok": True, "code": "historical_reconciliation_789_receipt"},
                )
                connection.row_factory = sqlite3.Row
                stored = connection.execute("select state,attempt_count,last_error_code,review_required from historical_778_outbox where provider_uid='1:21'").fetchone()
            finally:
                connection.close()
        uid21 = next(item for item in results if item["provider_uid"] == "1:21")
        self.assertEqual(uid21["state"], "review")
        self.assertEqual(stored["state"], "review")
        self.assertEqual(stored["attempt_count"], 1)
        self.assertEqual(stored["last_error_code"], "historical_proposal_tuple_conflict")
        self.assertEqual(stored["review_required"], 1)
        self.assertEqual(self.importer.summarize_historical_results(results)["exit_code"], 1)

    def test_exact_replay_digest_and_request_are_unchanged(self):
        document = json.loads(ROWS.read_text(encoding="utf-8"))
        row = next(item for item in document["rows"] if item["provider_uid"] == "1:21")
        first = self.caller.build_historical_request(row)
        second = self.caller.build_historical_request(row)
        self.assertEqual(first["canonical_request_utf8"], second["canonical_request_utf8"])
        self.assertEqual(self.caller.canonical_request_digest(first), self.caller.canonical_request_digest(second))


if __name__ == "__main__":
    unittest.main(verbosity=2)
