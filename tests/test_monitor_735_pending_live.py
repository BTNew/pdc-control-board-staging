from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import unittest

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_MONITOR_735_PENDING_LIVE") == "1"
BOOT = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRET = Path("C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_MONITOR_735_PENDING_LIVE=1 for authorised STAGING regression")
class Monitor735PendingLiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        bootstrap = load(BOOT, "monitor_735_pending_bootstrap")
        access = json.loads(bootstrap.unprotect(SECRET.read_bytes()).decode())
        cls.conn = psycopg2.connect(
            access["PDC_STAGING_DATABASE_URL"],
            sslmode="verify-full",
            sslrootcert=access["PDC_STAGING_SSLROOTCERT"],
            application_name="pdc-monitor-735-pending-live",
        )
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def setUp(self):
        self.cur = self.conn.cursor()
        self.cur.execute(
            "select status from public.ai_email_intake where id='0172352b-6045-4ab4-83ba-c8069c9ab8de'::uuid"
        )
        if self.cur.fetchone() is None:
            self.skipTest("affected staging intake is unavailable")
        self.cur.execute(
            "update public.ai_email_intake set status='received',next_attempt_at=clock_timestamp(),locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null,permanent_failure=false,retry_class=null where id='0172352b-6045-4ab4-83ba-c8069c9ab8de'::uuid"
        )
        self.cur.execute(
            "select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)",
            (ACTOR, json.dumps({"sub": ACTOR, "email": EMAIL, "role": "authenticated", "app_role": "importer"})),
        )
        self.cur.execute("set local role authenticated")

    def tearDown(self):
        self.conn.rollback()
        self.cur.close()

    def test_pending_attachment_read_and_result_record_are_scoped_and_rollback_safe(self):
        self.cur.execute(
            "select public.claim_pdc_email_intake_authenticated_exact_732(%s,%s)",
            (10, GATEWAY),
        )
        claim_result = self.cur.fetchone()[0]
        self.assertTrue(claim_result["ok"], claim_result)
        records = claim_result.get("items") or []
        record = next((item for item in records if item.get("id") == "0172352b-6045-4ab4-83ba-c8069c9ab8de"), None)
        if record is None:
            self.skipTest("affected intake was not claimable")
        self.assertEqual(record.get("provider_uid"), "imap_uid:692")
        intake_id = record["id"]
        claim_token = record["claim_token"]
        self.cur.execute(
            "select public.get_pdc_monitor_intake_attachments_735(%s,%s,%s)",
            (intake_id, claim_token, GATEWAY),
        )
        attachment_result = self.cur.fetchone()[0]
        self.assertTrue(attachment_result["ok"], attachment_result)
        self.assertTrue(attachment_result["review_required"], attachment_result)
        self.assertTrue(attachment_result["attachment_storage_incomplete"], attachment_result)
        self.assertEqual(attachment_result["attachments"], [])
        self.assertEqual(attachment_result["incomplete_attachment_count"], 1)
        self.cur.execute(
            "select public.record_pdc_email_intake_result(%s,%s,%s,%s,%s::jsonb,%s,%s,%s,%s::jsonb)",
            (intake_id, claim_token, GATEWAY, True, json.dumps({"code": "review_required"}), "review_required", "review", False, "{}"),
        )
        result = self.cur.fetchone()[0]
        self.assertTrue(result["ok"], result)
        self.cur.execute("savepoint monitor735_negative")
        with self.assertRaises(psycopg2.Error) as denied:
            self.cur.execute(
                "select public.get_pdc_monitor_intake_attachments_735(%s,%s,%s)",
                (intake_id, claim_token, "wrong-gateway"),
            )
        self.assertEqual(denied.exception.pgcode, "42501")
        self.cur.execute("rollback to savepoint monitor735_negative")


if __name__ == "__main__":
    unittest.main(verbosity=2)
