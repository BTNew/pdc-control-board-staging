from __future__ import annotations

import json
import os
import unittest
import uuid
from pathlib import Path

import psycopg2

RUN_LIVE = os.environ.get("PDC_RUN_NAVISION_DELIVERY_707_LIVE_TESTS") == "1"
MONITOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
MONITOR_EMAIL = "sales@broometoyota.com.au"
FAKE_RECORD = "00000000-0000-0000-0000-000000000707"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_NAVISION_DELIVERY_707_LIVE_TESTS=1 for authorised staging probes")
class NavisionDelivery707LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        spec = __import__("importlib.util", fromlist=["spec_from_file_location"]).spec_from_file_location("bootstrap707", spec_path)
        bootstrap = __import__("importlib.util", fromlist=["module_from_spec"]).module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()).decode())
        bootstrap.validate(values)
        endpoint = __import__("urllib.parse", fromlist=["urlsplit"]).urlsplit(values["PDC_STAGING_DATABASE_URL"])
        cls.conn = psycopg2.connect(host=endpoint.hostname, port=endpoint.port or 5432, user=endpoint.username, password=endpoint.password, dbname="postgres", sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], connect_timeout=15, application_name="pdc707_navision_delivery_security_live")
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def set_claims(self, sub: str, email: str, app_role: str = ""):
        claims = json.dumps({"sub": sub, "email": email, "role": "authenticated", "pdc_role": app_role})
        with self.conn.cursor() as cur:
            cur.execute("reset role")
            cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (sub,))
            cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))

    def counts(self):
        with self.conn.cursor() as cur:
            cur.execute("reset role")
            cur.execute("select (select count(*) from public.vehicles),(select count(*) from public.pdc_final_pdc_lifecycle_receipts_700),(select count(*) from public.vehicle_movements)")
            return cur.fetchone()

    def call_as_authenticated(self, sql: str, params=()):
        with self.conn.cursor() as cur:
            cur.execute("set local role authenticated")
            cur.execute(sql, params)
            return cur.fetchone()[0]

    def test_generic_authenticated_and_application_roles_are_denied_without_mutation(self):
        before = self.counts()
        for app_role in ("", "viewer", "operator", "administrator"):
            self.set_claims(str(uuid.uuid4()), f"{app_role or 'generic'}@invalid.example", app_role)
            result = self.call_as_authenticated("select public.reconcile_navision_delivery_700(%s)", (FAKE_RECORD,))
            self.assertEqual(result["code"], "monitor_identity_required", app_role)
            self.assertEqual(self.counts(), before, app_role)
        self.conn.rollback()

    def test_exact_monitor_identity_is_allowed_to_reach_non_mutating_record_guard(self):
        self.set_claims(MONITOR_ID, MONITOR_EMAIL)
        before = self.counts()
        result = self.call_as_authenticated("select public.reconcile_navision_delivery_700(%s)", (FAKE_RECORD,))
        self.assertEqual(result["code"], "delivery_record_not_current")
        self.assertEqual(self.counts(), before)
        self.conn.rollback()

    def test_wrong_actor_and_email_are_rejected_before_any_mutation(self):
        self.set_claims(MONITOR_ID, MONITOR_EMAIL)
        before = self.counts()
        result = self.call_as_authenticated(
            "select public.reconcile_navision_operational_record(%s,%s,%s)",
            (FAKE_RECORD, "557dba7f-fd70-4b9e-aa7b-b83b717682a7", "attacker@example.com"),
        )
        self.assertEqual(result["code"], "actor_identity_mismatch")
        self.assertEqual(self.counts(), before)
        self.conn.rollback()

    def test_anon_cannot_execute_delivery_surface(self):
        self.set_claims(str(uuid.uuid4()), "anonymous@invalid.example")
        with self.conn.cursor() as cur:
            cur.execute("set local role anon")
            with self.assertRaises(psycopg2.Error) as raised:
                cur.execute("select public.reconcile_navision_delivery_700(%s)", (FAKE_RECORD,))
            self.assertEqual(raised.exception.pgcode, "42501")
        self.conn.rollback()

    def test_postgrest_surface_and_grants_are_narrow(self):
        self.set_claims(MONITOR_ID, MONITOR_EMAIL)
        with self.conn.cursor() as cur:
            cur.execute("""select
              to_regprocedure('public.reconcile_navision_delivery_700(uuid)') is not null,
              to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') is null,
              has_function_privilege('authenticated','public.reconcile_navision_delivery_700(uuid)','execute'),
              has_function_privilege('anon','public.reconcile_navision_delivery_700(uuid)','execute'),
              has_function_privilege('service_role','public.reconcile_navision_delivery_700(uuid)','execute'),
              has_function_privilege('pdc_email_monitor','public.reconcile_navision_delivery_700(uuid)','execute'),
              has_function_privilege('authenticated','public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)','execute'),
              has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),
              has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),
              has_function_privilege('service_role','public.reconcile_navision_operational_record(uuid,uuid,text)','execute'),
              has_function_privilege('pdc_email_monitor','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')""")
            self.assertEqual(cur.fetchone(), (True, True, True, False, False, False, False, True, False, False, False))
        self.conn.rollback()

    @unittest.skipUnless(os.environ.get("PDC_NAVISION_DELIVERY_707_REPLAY_RECORD_ID"), "provide an existing delivered staging record for replay probe")
    def test_delivered_replay_returns_immutable_receipt(self):
        record_id = os.environ["PDC_NAVISION_DELIVERY_707_REPLAY_RECORD_ID"]
        self.set_claims(MONITOR_ID, MONITOR_EMAIL)
        before = self.counts()
        first = self.call_as_authenticated("select public.reconcile_navision_delivery_700(%s)", (record_id,))
        second = self.call_as_authenticated("select public.reconcile_navision_delivery_700(%s)", (record_id,))
        self.assertTrue(first.get("ok"))
        self.assertTrue(second.get("replay"))
        self.assertEqual(self.counts(), before)
        self.conn.rollback()


if __name__ == "__main__":
    unittest.main(verbosity=2)
