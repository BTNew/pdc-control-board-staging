from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import unittest

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_507_COMPATIBILITY_LIVE_TESTS") == "1"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_507_COMPATIBILITY_LIVE_TESTS=1 for authorised staging integration")
class MonitorCompatibility507LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location(
            "bootstrap", r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py"
        )
        bootstrap = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bootstrap)
        values = json.loads(
            bootstrap.unprotect(
                Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()
            ).decode()
        )
        bootstrap.validate(values)
        os.environ.update({key: values[key] for key in ("PDC_STAGING_DATABASE_URL", "PDC_STAGING_SSLROOTCERT", "PDC_STAGING_SSLROOTCERT_SHA256")})
        from scripts.pdc_staging_runtime import trusted_sslrootcert

        parts = __import__("urllib.parse", fromlist=["urlsplit"]).urlsplit(values["PDC_STAGING_DATABASE_URL"])
        cls.conn = psycopg2.connect(
            host=parts.hostname,
            port=parts.port or 5432,
            user=parts.username,
            password=parts.password,
            dbname="postgres",
            sslmode="verify-full",
            sslrootcert=trusted_sslrootcert(),
            connect_timeout=15,
            application_name="pdc507_terminal_live_test",
        )
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def call_reader(self, claims, event=25751401):
        with self.conn.cursor() as cur:
            cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps(claims),))
            cur.execute("select public.read_pdc_uid514_transaction_receipt_257(%s)", (event,))
            return cur.fetchone()[0]

    def test_exact_contained_sales_reader_is_terminal_without_physical_work(self):
        result = self.call_reader({
            "sub": "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "email": "sales@broometoyota.com.au",
            "role": "authenticated",
        })
        self.assertTrue(result["ok"])
        self.assertTrue(result["terminal"])
        self.assertEqual(result["code"], "uid514_staging_commissioned_terminal")
        self.assertEqual(result["recovery_event_id"], 25751401)
        self.assertEqual(result["folder"], "Inbox")
        self.assertEqual(result["uidvalidity"], 1)
        self.assertEqual(result["uid"], 514)
        self.assertTrue(result["synthetic_staging_commissioning"])
        self.assertFalse(result["physical_mailbox_fetch"])
        self.assertFalse(result["mailbox_flags_changed"])
        self.assertEqual(result["vehicle_operations"], 0)
        self.assertEqual(result["operation_lines"], 0)
        for field in ("operational", "activation_ready", "writer_active", "planner_commissioned", "production_writes"):
            self.assertFalse(result[field])

    def test_other_identity_and_event_remain_denied(self):
        with self.assertRaises(psycopg2.Error) as raised:
            self.call_reader({
                "sub": "557dba7f-fd70-4b9e-aa7b-b83b717682a7",
                "email": "administrator2@staging.pdc-workshop.example.com",
                "role": "authenticated",
            })
        self.assertEqual(raised.exception.pgcode, "42501")
        self.assertIn("PDC_314_MONITOR_DEDICATED_IDENTITY_REQUIRED", str(raised.exception))
        self.conn.rollback()

        with self.assertRaises(psycopg2.Error) as raised:
            self.call_reader({
                "sub": "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
                "email": "sales@broometoyota.com.au",
                "role": "authenticated",
            }, event=25751402)
        self.assertEqual(raised.exception.pgcode, "22023")
        self.assertIn("PDC_261_UID514_SCOPE_INVALID", str(raised.exception))
        self.conn.rollback()

    def test_receipt_is_unique_immutable_private_and_contained(self):
        with self.conn.cursor() as cur:
            cur.execute(
                """select count(*) from public.pdc_uid514_staging_commissioning_terminal_receipts_507
                   where recovery_event_id=25751401 and actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'
                     and gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
                     and release_name='pdc-monitor-staging-m502-2026.08.44'
                     and terminal_status='staging_commissioned'
                     and synthetic_staging_commissioning and not physical_mailbox_fetch
                     and not mailbox_flags_changed and vehicle_operations=0 and operation_lines=0
                     and not operational and not activation_ready and not writer_active
                     and not planner_commissioned and not production_writes"""
            )
            receipt_count = cur.fetchone()[0]
            cur.execute(
                """select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401"""
            )
            real_auth_count = cur.fetchone()[0]
            cur.execute(
                """select (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_staging_commissioning_terminal_receipts_507'::regclass),
                    (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_staging_commissioning_history_507'::regclass),
                    has_table_privilege('authenticated','public.pdc_uid514_staging_commissioning_terminal_receipts_507','select'),
                    has_table_privilege('authenticated','public.pdc_uid514_staging_commissioning_history_507','select'),
                    (select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
                    (select count(*) from public.monitored_mailboxes where active)"""
            )
            security = cur.fetchone()
        self.assertEqual(receipt_count, 1)
        self.assertEqual(real_auth_count, 0)
        self.assertEqual(security, (True, True, False, False, 0, 0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
