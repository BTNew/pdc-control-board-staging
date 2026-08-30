from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import unittest

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_HISTORICAL_PROPOSAL_805_LIVE") == "1"
ROOT = Path(__file__).resolve().parents[1]
CALLER = ROOT / "pdc_historical_778_caller.py"
FROZEN = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-795-explicit-frozen-rows.json")


def load_caller():
    spec = importlib.util.spec_from_file_location("historical_805_caller", CALLER)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_HISTORICAL_PROPOSAL_805_LIVE=1 for authorised STAGING regression")
class HistoricalProposalEvidence805LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        boot = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        secret = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
        spec = importlib.util.spec_from_file_location("pdc_805_bootstrap", boot)
        bootstrap = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        access = json.loads(bootstrap.unprotect(secret.read_bytes()).decode())
        cls.conn = psycopg2.connect(
            access["PDC_STAGING_DATABASE_URL"],
            sslmode="verify-full",
            sslrootcert=access["PDC_STAGING_SSLROOTCERT"],
            application_name="pdc-805-proposal-evidence-live",
        )
        cls.conn.autocommit = False
        cls.caller = load_caller()
        cls.rows = {row["provider_uid"]: row for row in json.loads(FROZEN.read_text(encoding="utf-8"))["rows"]}
        cls.actor = cls.caller.ACTOR_ID
        cls.claims = json.dumps({"sub": cls.actor, "email": cls.caller.ACTOR_EMAIL, "role": "authenticated", "app_role": "importer"})

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def setUp(self):
        self.cur = self.conn.cursor()
        self.cur.execute("select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)", (self.actor, self.claims))

    def tearDown(self):
        self.conn.rollback()
        self.cur.close()

    def scalar(self, sql):
        self.cur.execute(sql)
        return self.cur.fetchone()[0]

    def snapshot(self):
        return {
            "proposals": self.scalar("select count(*) from public.pdc_ai_intake_proposals"),
            "source_claims": self.scalar("select count(*) from public.pdc_email_source_claims"),
            "history": self.scalar("select count(*) from public.pdc_ai_intake_history"),
            "intakes": self.scalar("select count(*) from public.ai_email_intake"),
            "attachments": self.scalar("select count(*) from public.ai_email_attachments"),
            "receipts": self.scalar("select count(*) from public.pdc_historical_reconciliation_778_receipts"),
            "observations": self.scalar("select count(*) from public.pdc_historical_provider_observations_778"),
        }

    def call_proposal_preflight(self, uid):
        request = self.caller.build_historical_request(self.rows[uid])
        self.assertNotIn("aligned", request["authentication"])
        self.cur.execute(
            "select public.pdc_historical_writer_authorized_777(%s,%s,%s,%s,%s::jsonb,%s,%s::jsonb)",
            (
                request["parent_source_hash"], request["evidence_hash"], request["provider_uid"],
                request["sender_email"], json.dumps(request["authentication"]), request["stock_number"],
                json.dumps(request["observations"]),
            ),
        )
        authorized = self.cur.fetchone()[0]
        self.cur.execute(
            "select public.submit_pdc_ai_intake_observation_pre135(%s,%s,%s,%s,%s::jsonb,%s::timestamptz,%s,%s,%s,%s,%s::jsonb)",
            (
                request["parent_source_hash"], request["evidence_hash"], request["provider_uid"],
                request["sender_email"], json.dumps(request["authentication"]), request["source_metadata"]["received_at"],
                request["subject"], request["action_type"], request["stock_number"], request["summary"],
                json.dumps(request["observations"]),
            ),
        )
        return authorized, self.cur.fetchone()[0]

    def test_conflict_is_typed_and_missing_binding_is_append_only_idempotent(self):
        before = self.snapshot()
        conflict_request = self.caller.build_historical_request(self.rows["1:21"])
        self.cur.execute("select public.submit_pdc_historical_reconciliation_778(%s::jsonb)", (json.dumps(conflict_request),))
        conflict = self.cur.fetchone()[0]
        self.assertEqual(conflict.get("code"), "historical_proposal_tuple_conflict")
        self.assertTrue((conflict.get("data") or {}).get("review_required"))
        self.assertEqual(before, self.snapshot())

        authorized, first = self.call_proposal_preflight("1:133")
        self.assertTrue(authorized)
        self.assertTrue(first.get("ok"))
        self.assertIn(first.get("code"), {"noticed", "already_noticed"})
        self.assertIsNotNone((first.get("data") or {}).get("proposal_id"))
        after_first = self.snapshot()

        authorized_again, second = self.call_proposal_preflight("1:133")
        self.assertTrue(authorized_again)
        self.assertTrue(second.get("ok"))
        self.assertEqual(second.get("code"), "already_noticed")
        self.assertEqual((second.get("data") or {}).get("proposal_id"), (first.get("data") or {}).get("proposal_id"))
        self.assertEqual(after_first, self.snapshot())

    def test_malformed_frozen_evidence_is_denied_without_state_change(self):
        before = self.snapshot()
        request = self.caller.build_historical_request(self.rows["1:133"])
        bad_auth = dict(request["authentication"])
        bad_auth["sender_domain"] = "invalid.example"
        self.cur.execute(
            "select public.pdc_historical_writer_authorized_777(%s,%s,%s,%s,%s::jsonb,%s,%s::jsonb)",
            (
                request["parent_source_hash"], request["evidence_hash"], request["provider_uid"],
                request["sender_email"], json.dumps(bad_auth), request["stock_number"], json.dumps(request["observations"]),
            ),
        )
        self.assertFalse(self.cur.fetchone()[0])
        self.assertEqual(before, self.snapshot())


if __name__ == "__main__":
    unittest.main(verbosity=2)
