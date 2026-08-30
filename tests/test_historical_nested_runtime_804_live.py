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
            cur.execute("select public.submit_pdc_historical_reconciliation_778(%s::jsonb)", (json.dumps({}),))
            result = cur.fetchone()[0]
        after = {
            "receipts": self.scalar("select count(*) from public.pdc_historical_reconciliation_778_receipts"),
            "observations": self.scalar("select count(*) from public.pdc_historical_provider_observations_778"),
            "readbacks": self.scalar("select count(*) from public.pdc_historical_complete_domain_readbacks_797"),
            "mailboxes": self.scalar("select count(*) from public.monitored_mailboxes where active"),
        }
        self.assertNotEqual(result.get("code"), "unauthorized")
        self.assertIn(result.get("code"), {"historical_reconciliation_782_atomic_rollback", "historical_reconciliation_preflight_failed", "historical_reconciliation_validation_failed"})
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
