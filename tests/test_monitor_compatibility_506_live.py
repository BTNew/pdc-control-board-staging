from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import unittest

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_506_COMPATIBILITY_LIVE_TESTS") == "1"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_506_COMPATIBILITY_LIVE_TESTS=1 for authorised staging integration")
class MonitorCompatibility506LiveTests(unittest.TestCase):
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
            application_name="pdc506_reader_live_test",
        )
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def call_reader(self, claims):
        with self.conn.cursor() as cur:
            cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps(claims),))
            cur.execute("select public.read_pdc_uid514_transaction_receipt_257(25751401)")
            return cur.fetchone()[0]

    def test_exact_contained_sales_actor_can_read_frozen_uid514_contract(self):
        result = self.call_reader({
            "sub": "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "email": "sales@broometoyota.com.au",
            "role": "authenticated",
        })
        self.assertTrue(result["ok"])
        self.assertEqual(result["code"], "uid514_authorization_pending")
        self.assertEqual(result["recovery_event_id"], 25751401)
        self.assertEqual(result["folder"], "Inbox")
        self.assertFalse(result["terminal"])

    def test_generic_identity_still_uses_existing_dedicated_scope_rejection(self):
        with self.conn.cursor() as cur:
            cur.execute(
                "select id,email from auth.users where email=%s",
                (os.environ["PDC_STAGING_ADMIN_EMAIL"],),
            )
            admin_id, admin_email = cur.fetchone()
        with self.assertRaises(psycopg2.Error) as raised:
            self.call_reader({"sub": str(admin_id), "email": admin_email, "role": "authenticated"})
        self.assertEqual(raised.exception.pgcode, "42501")
        self.assertIn("PDC_314_MONITOR_DEDICATED_IDENTITY_REQUIRED", str(raised.exception))
        self.conn.rollback()

    def test_reader_and_support_tables_keep_least_privilege_boundaries(self):
        with self.conn.cursor() as cur:
            cur.execute(
                """select has_function_privilege('authenticated','public.read_pdc_uid514_transaction_receipt_257(integer)','execute'),
                    has_function_privilege('anon','public.read_pdc_uid514_transaction_receipt_257(integer)','execute'),
                    has_function_privilege('service_role','public.read_pdc_uid514_transaction_receipt_257(integer)','execute'),
                    (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_monitor_uid514_reader_compatibility_history_506'::regclass),
                    (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_monitor_uid514_reader_compatibility_controls_506'::regclass),
                    has_table_privilege('authenticated','public.pdc_monitor_uid514_reader_compatibility_history_506','select'),
                    has_table_privilege('authenticated','public.pdc_monitor_uid514_reader_compatibility_controls_506','select')"""
            )
            row = cur.fetchone()
        self.assertEqual(row, (True, False, False, True, True, False, False))


if __name__ == "__main__":
    unittest.main(verbosity=2)
