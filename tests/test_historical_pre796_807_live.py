from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import unittest

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_HISTORICAL_PRE796_807_LIVE") == "1"
ROOT = Path(__file__).resolve().parents[1]
CALLER = ROOT / "pdc_historical_778_caller.py"
FROZEN = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-795-explicit-frozen-rows.json")
MISSING_UIDS = ("1:133", "1:134", "1:137", "1:168", "1:172")


def load_caller():
    spec = importlib.util.spec_from_file_location("historical_807_caller", CALLER)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_HISTORICAL_PRE796_807_LIVE=1 for authorised STAGING regression")
class HistoricalPre796807LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        boot = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        secret = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
        spec = importlib.util.spec_from_file_location("pdc_807_bootstrap", boot)
        bootstrap = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        access = json.loads(bootstrap.unprotect(secret.read_bytes()).decode())
        cls.conn = psycopg2.connect(
            access["PDC_STAGING_DATABASE_URL"],
            sslmode="verify-full",
            sslrootcert=access["PDC_STAGING_SSLROOTCERT"],
            application_name="pdc-807-pre796-live",
        )
        cls.conn.autocommit = False
        cls.caller = load_caller()
        cls.rows = {row["provider_uid"]: row for row in json.loads(FROZEN.read_text(encoding="utf-8"))["rows"]}
        cls.actor = cls.caller.ACTOR_ID

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def setUp(self):
        self.cur = self.conn.cursor()
        self.set_claims(self.actor)

    def tearDown(self):
        self.conn.rollback()
        self.cur.close()

    def set_claims(self, actor):
        self.cur.execute(
            "select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)",
            (actor, json.dumps({"sub": actor, "email": self.caller.ACTOR_EMAIL, "role": "authenticated", "app_role": "importer"})),
        )

    def scalar(self, sql):
        self.cur.execute(sql)
        return self.cur.fetchone()[0]

    def snapshot(self):
        return {
            "proposals": self.scalar("select count(*) from public.pdc_ai_intake_proposals"),
            "claims": self.scalar("select count(*) from public.pdc_email_source_claims"),
            "history": self.scalar("select count(*) from public.pdc_ai_intake_history"),
            "intakes": self.scalar("select count(*) from public.ai_email_intake"),
            "attachments": self.scalar("select count(*) from public.ai_email_attachments"),
            "receipts": self.scalar("select count(*) from public.pdc_historical_reconciliation_778_receipts"),
            "observations": self.scalar("select count(*) from public.pdc_historical_provider_observations_778"),
            "readbacks": self.scalar("select count(*) from public.pdc_historical_complete_domain_readbacks_797"),
            "mailboxes": self.scalar("select count(*) from public.monitored_mailboxes where active"),
        }

    def request(self, uid):
        return self.caller.build_historical_request(self.rows[uid])

    def call_public(self, request):
        self.cur.execute("select public.submit_pdc_historical_reconciliation_778(%s::jsonb)", (json.dumps(request),))
        return self.cur.fetchone()[0]

    def call_pre135(self, request):
        self.cur.execute(
            "select public.submit_pdc_ai_intake_observation_pre135(%s,%s,%s,%s,%s::jsonb,%s::timestamptz,%s,%s,%s,%s,%s::jsonb)",
            (
                request["parent_source_hash"], request["evidence_hash"], request["provider_uid"],
                request["sender_email"], json.dumps(request["authentication"]), request["source_metadata"]["received_at"],
                request["subject"], request["action_type"], request["stock_number"], request["summary"],
                json.dumps(request["observations"]),
            ),
        )
        return self.cur.fetchone()[0]

    def test_all_five_public_paths_pass_nested_766_gate_and_notice_replay_is_idempotent(self):
        before = self.snapshot()
        public_results = []
        for uid in MISSING_UIDS:
            self.cur.execute("savepoint pdc807_public")
            result = self.call_public(self.request(uid))
            public_results.append({"uid": uid, "code": result.get("code"), "ok": result.get("ok")})
            self.cur.execute("rollback to savepoint pdc807_public")
            self.cur.execute("release savepoint pdc807_public")
        self.assertTrue(all(row["code"] != "historical_wrapper_preflight_failed" for row in public_results), public_results)
        self.assertTrue(all(row["code"] != "unauthorized" for row in public_results), public_results)
        self.assertEqual(before, self.snapshot())

        for uid in MISSING_UIDS:
            request = self.request(uid)
            self.cur.execute("savepoint pdc807_notice")
            self.cur.execute(
                "select public.pdc_historical_writer_authorized_777(%s,%s,%s,%s,%s::jsonb,%s,%s::jsonb)",
                (
                    request["parent_source_hash"], request["evidence_hash"], request["provider_uid"],
                    request["sender_email"], json.dumps(request["authentication"]), request["stock_number"],
                    json.dumps(request["observations"]),
                ),
            )
            self.assertTrue(self.cur.fetchone()[0], uid)
            first = self.call_pre135(request)
            second = self.call_pre135(request)
            self.assertTrue(first.get("ok"), (uid, first))
            self.assertTrue(second.get("ok"), (uid, second))
            self.assertEqual(second.get("code"), "already_noticed", (uid, second))
            self.assertEqual((first.get("data") or {}).get("proposal_id"), (second.get("data") or {}).get("proposal_id"))
            self.cur.execute("rollback to savepoint pdc807_notice")
            self.cur.execute("release savepoint pdc807_notice")
        self.assertEqual(before, self.snapshot())

    def test_malformed_auth_and_wrong_actor_are_denied_without_drift(self):
        before = self.snapshot()
        request = self.request("1:133")
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
        self.set_claims("00000000-0000-4000-8000-000000000000")
        result = self.call_public(request)
        self.assertEqual(result.get("code"), "unauthorized")
        self.assertEqual(before, self.snapshot())


if __name__ == "__main__":
    unittest.main(verbosity=2)
