from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import unittest

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_HISTORICAL_AUTH_809_LIVE") == "1"
ROOT = Path(__file__).resolve().parents[1]
CALLER = ROOT / "pdc_historical_778_caller.py"
FROZEN = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-795-explicit-frozen-rows.json")
UIDS = ("1:133", "1:134", "1:137", "1:168", "1:172")
EXPECTED = {
    "1:133": ("13047164", "868866bfebe0d8a924bd15ce151d472a8966a739ab8d733ff6d6a4f907a69f69"),
    "1:134": ("13047383", "038180cf1bb30136dbd2d176f45dbb9c4c6cf730cff7a7ed6e59a32dd5f1ec7c"),
    "1:137": ("13047272", "b0dfa4aaaefed0d71f878e8b69adf7459251f79795cff9809009b8418159abff"),
    "1:168": ("13049488", "5df8e4c6ccf29f88eeaca96c8856b2653eff27390e9ca08c872343480358fa09"),
    "1:172": ("13044227", "345ee4f9d9d2a7fa47376d8615e9f05086a5f9f65ce9fa6322df9f726e0dd56e"),
}


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_HISTORICAL_AUTH_809_LIVE=1 for authorised STAGING regression")
class HistoricalAuthorization809LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        boot = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        secret = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
        bootstrap = load_module(boot, "pdc_809_auth_bootstrap")
        access = json.loads(bootstrap.unprotect(secret.read_bytes()).decode())
        cls.conn = psycopg2.connect(access["PDC_STAGING_DATABASE_URL"], sslmode="verify-full", sslrootcert=access["PDC_STAGING_SSLROOTCERT"], application_name="pdc-809-auth-live")
        cls.conn.autocommit = False
        cls.caller = load_module(CALLER, "pdc_809_auth_caller")
        cls.rows = {row["provider_uid"]: row for row in json.loads(FROZEN.read_text(encoding="utf-8"))["rows"]}

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def setUp(self):
        self.cur = self.conn.cursor()
        self.set_claims(self.caller.ACTOR_ID)

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
            "renewals": self.scalar("select count(*) from public.pdc_historical_reconciliation_writer_authorizations_809"),
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
            (request["parent_source_hash"], request["evidence_hash"], request["provider_uid"], request["sender_email"], json.dumps(request["authentication"]), request["source_metadata"]["received_at"], request["subject"], request["action_type"], request["stock_number"], request["summary"], json.dumps(request["observations"])),
        )
        return self.cur.fetchone()[0]

    def test_five_renewal_rows_are_exact_and_unexpired(self):
        self.cur.execute("select provider_uid,stock_number,evidence_hash,supersedes_authorization_id,authorized_actor_id::text,authorized_actor_email,authorized_gateway_instance_id,authorized_at,expires_at from public.pdc_historical_reconciliation_writer_authorizations_809 where active and expires_at>clock_timestamp() order by provider_uid")
        rows = self.cur.fetchall()
        self.assertEqual(len(rows), 5)
        for uid, stock, evidence, old_id, actor, email, gateway, authorized_at, expires_at in rows:
            self.assertEqual((stock, evidence), EXPECTED[uid])
            self.assertEqual((actor, email, gateway), (self.caller.ACTOR_ID, self.caller.ACTOR_EMAIL, self.caller.GATEWAY))
            self.assertLess(authorized_at, expires_at)
            self.assertLessEqual(expires_at, authorized_at + __import__("datetime").timedelta(hours=24))
            self.cur.execute("select count(*) from public.pdc_historical_reconciliation_writer_authorizations_773 where authorization_id=%s", (old_id,))
            self.assertEqual(self.cur.fetchone()[0], 1)

    def test_five_public_notice_replay_paths_are_rollback_only(self):
        before = self.snapshot()
        for uid in UIDS:
            request = self.request(uid)
            self.cur.execute("savepoint pdc809_apply")
            result = self.call_public(request)
            self.assertTrue(result.get("ok"), (uid, result))
            self.assertEqual(result.get("code"), "historical_reconciliation_782_receipt", (uid, result))
            self.assertIn("receipt_id", result.get("data") or {}, (uid, result))
            self.assertIn("proposal_id", result.get("data") or {}, (uid, result))
            first = result
            second = self.call_public(request)
            self.assertTrue(second.get("ok"), (uid, second))
            self.assertEqual(second.get("code"), "historical_reconciliation_782_receipt", (uid, second))
            self.assertEqual((first.get("data") or {}).get("receipt_id"), (second.get("data") or {}).get("receipt_id"), (uid, second))
            self.assertEqual((first.get("data") or {}).get("proposal_id"), (second.get("data") or {}).get("proposal_id"), (uid, second))
            self.cur.execute("rollback to savepoint pdc809_apply")
            self.cur.execute("release savepoint pdc809_apply")
        self.assertEqual(before, self.snapshot())

    def test_malformed_wrong_actor_and_wrong_gateway_fail_closed(self):
        before = self.snapshot()
        request = self.request("1:133")
        bad_auth = dict(request["authentication"])
        bad_auth["sender_domain"] = "invalid.example"
        self.cur.execute("select public.pdc_historical_writer_authorized_777(%s,%s,%s,%s,%s::jsonb,%s,%s::jsonb)", (request["parent_source_hash"], request["evidence_hash"], request["provider_uid"], request["sender_email"], json.dumps(bad_auth), request["stock_number"], json.dumps(request["observations"])))
        self.assertFalse(self.cur.fetchone()[0])
        wrong_gateway = dict(request)
        wrong_gateway["gateway_instance_id"] = "wrong-staging-gateway"
        self.assertIn(self.call_public(wrong_gateway).get("code"), {"historical_manifest_or_runtime_binding_mismatch", "historical_wrapper_preflight_failed", "unauthorized"})
        self.set_claims("00000000-0000-4000-8000-000000000000")
        self.assertEqual(self.call_public(request).get("code"), "unauthorized")
        self.assertEqual(before, self.snapshot())


if __name__ == "__main__":
    unittest.main(verbosity=2)
