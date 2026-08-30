from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import unittest

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_HISTORICAL_RUNTIME_804_LIVE") == "1"
ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EMAIL = "sales@broometoyota.com.au"
INVALID_REQUEST = {
    "action_type": "review_only",
    "attachment_manifest": [],
    "authentication": {
        "dkim_aligned": False,
        "dmarc_aligned": False,
        "gmail_authentication_results": True,
        "sender_domain": "broometoyota.com.au",
        "spf_aligned": True,
    },
    "canonical_request_utf8": "",
    "evidence_hash": "e" * 64,
    "gateway_instance_id": "pdc-monitor-staging-sales-uid509-v1",
    "job_card_children": [],
    "manifest_high_water_uid": 685,
    "manifest_sha256": "aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018",
    "manifest_uid_count": 669,
    "manifest_uidvalidity": 1,
    "observations": {},
    "parent_source_hash": "b" * 64,
    "provider_uid": "1:999999",
    "release_manifest_sha256": "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
    "release_name": "pdc-monitor-staging-m502-2026.08.44",
    "release_source_sha": "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
    "sender_email": EMAIL,
    "source_metadata": {
        "attachment_names": [],
        "graph_message_id": "imap:1:999999",
        "internet_message_id": "<historical-999999@example.test>",
        "parsed_text": "",
        "provider_authserv_id": "mx.google.com",
        "raw_body": "",
        "received_at": "2026-08-30T12:00:00+00:00",
        "recipient_mailbox": "pmbcontroller@gmail.com",
        "sender_name": "Test sender",
        "uid": 999999,
        "uidvalidity": 1,
    },
    "stock_number": "13047257",
    "subject": "Invalid contained-runtime regression",
    "summary": "Invalid contained-runtime regression",
}


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_HISTORICAL_RUNTIME_804_LIVE=1 for authorised STAGING regression")
class HistoricalNestedRuntime804LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        boot = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        sec = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
        spec = importlib.util.spec_from_file_location("bootstrap804", boot)
        bootstrap = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(sec.read_bytes()).decode())
        bootstrap.validate(values)
        cls.conn = psycopg2.connect(
            values["PDC_STAGING_DATABASE_URL"],
            sslmode="verify-full",
            sslrootcert=values["PDC_STAGING_SSLROOTCERT"],
            application_name="pdc804_nested_runtime_live_test",
        )
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def set_claims(self):
        with self.conn.cursor() as cur:
            cur.execute(
                "select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)",
                (ACTOR, json.dumps({"sub": ACTOR, "email": EMAIL, "role": "authenticated"})),
            )

    def scalar(self, sql):
        with self.conn.cursor() as cur:
            cur.execute(sql)
            return cur.fetchone()[0]

    def test_public_wrapper_passes_nested_auth_and_reaches_validation(self):
        self.set_claims()
        before = {
            "receipts": self.scalar("select count(*) from public.pdc_historical_reconciliation_778_receipts"),
            "observations": self.scalar("select count(*) from public.pdc_historical_provider_observations_778"),
            "readbacks": self.scalar("select count(*) from public.pdc_historical_complete_domain_readbacks_797"),
            "mailboxes": self.scalar("select count(*) from public.monitored_mailboxes where active"),
        }
        with self.conn.cursor() as cur:
            cur.execute("select public.submit_pdc_historical_reconciliation_778(%s::jsonb)", (json.dumps(INVALID_REQUEST),))
            result = cur.fetchone()[0]
        after = {
            "receipts": self.scalar("select count(*) from public.pdc_historical_reconciliation_778_receipts"),
            "observations": self.scalar("select count(*) from public.pdc_historical_provider_observations_778"),
            "readbacks": self.scalar("select count(*) from public.pdc_historical_complete_domain_readbacks_797"),
            "mailboxes": self.scalar("select count(*) from public.monitored_mailboxes where active"),
        }
        self.assertEqual(result.get("code"), "historical_wrapper_preflight_failed")
        self.assertEqual(before, after)
        self.assertEqual(after["mailboxes"], 0)

    def test_adapter_replay_is_equal_and_wrong_gateway_is_denied(self):
        self.set_claims()
        args = (
            "active", "pdc-monitor-staging-sales-uid509-v1", "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b", "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348", "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227",
        )
        with self.conn.cursor() as cur:
            cur.execute("select public.verify_pdc_historical_runtime_binding_authenticated_802(%s,%s,%s,%s,%s,%s,%s)", args)
            first = cur.fetchone()[0]
            cur.execute("select public.verify_pdc_historical_runtime_binding_authenticated_802(%s,%s,%s,%s,%s,%s,%s)", args)
            second = cur.fetchone()[0]
            wrong = list(args); wrong[1] = "wrong-gateway"
            cur.execute("select public.verify_pdc_historical_runtime_binding_authenticated_802(%s,%s,%s,%s,%s,%s,%s)", tuple(wrong))
            denied = cur.fetchone()[0]
        self.assertEqual(first, second)
        self.assertTrue(first["ok"])
        self.assertFalse(first["mailbox_active"])
        self.assertEqual(first["active_mailbox_count"], 0)
        self.assertFalse(denied["ok"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
