from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

import psycopg2

RUN_LIVE = os.environ.get("PDC_RUN_673_AUTHENTICATED_EXECUTION_LIVE_TESTS") == "1"
ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_673_AUTHENTICATED_EXECUTION_LIVE_TESTS=1 for authorised staging integration")
class AuthenticatedExecutionSuccessor673LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        spec = __import__("importlib.util", fromlist=["spec_from_file_location"]).spec_from_file_location("bootstrap673", spec_path)
        bootstrap = __import__("importlib.util", fromlist=["module_from_spec"]).module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()).decode())
        bootstrap.validate(values)
        endpoint = __import__("urllib.parse", fromlist=["urlsplit"]).urlsplit(values["PDC_STAGING_DATABASE_URL"])
        os.environ.update({key: values[key] for key in ("PDC_STAGING_DATABASE_URL", "PDC_STAGING_SSLROOTCERT", "PDC_STAGING_SSLROOTCERT_SHA256")})
        from scripts.pdc_staging_runtime import trusted_sslrootcert
        cls.conn = psycopg2.connect(host=endpoint.hostname, port=endpoint.port or 5432, user=endpoint.username, password=endpoint.password, dbname="postgres", sslmode="verify-full", sslrootcert=trusted_sslrootcert(), connect_timeout=15, application_name="pdc673_authenticated_execution_live_test")
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def set_claims(self, sub=ACTOR, email=EMAIL, role="authenticated"):
        with self.conn.cursor() as cur:
            claims = json.dumps({"sub": sub, "email": email, "role": role})
            cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (sub,))
            cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))

    def test_standard_actor_can_call_required_cycle_claim_and_result_surface(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("select public.pdc_monitor_authenticated_active_scope_673(%s)", (GATEWAY,))
            self.assertTrue(cur.fetchone()[0])
            cur.execute("select public.record_pdc_email_monitor_cycle('running',null,null)")
            self.assertTrue(cur.fetchone()[0]["ok"])
            cur.execute("select public.claim_pdc_email_intake_batch(1,%s)", (GATEWAY,))
            result = cur.fetchone()[0]
            self.assertEqual((result["ok"], result["count"]), (True, 0))
            cur.execute("select public.record_pdc_email_monitor_cycle('idle',null,null)")
            self.assertTrue(cur.fetchone()[0]["ok"])
        self.conn.rollback()

    def test_standard_actor_reaches_agentic_guard_without_mutation(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("select public.execute_pdc_agentic_email_action_502('{}'::jsonb)")
            self.assertEqual(cur.fetchone()[0], {"ok": False, "code": "invalid_action"})
            cur.execute("select public.pdc_monitor_authenticated_active_scope_673('wrong-gateway')")
            self.assertFalse(cur.fetchone()[0])
        self.conn.rollback()

    def test_wrong_actor_role_gateway_and_malformed_claim_fail_closed(self):
        self.set_claims("557dba7f-fd70-4b9e-aa7b-b83b717682a7", "administrator2@staging.pdc-workshop.example.com")
        with self.conn.cursor() as cur:
            cur.execute("select public.pdc_monitor_authenticated_active_scope_673(%s)", (GATEWAY,))
            self.assertFalse(cur.fetchone()[0])
        self.conn.rollback()
        self.set_claims(role="pdc_email_monitor")
        with self.conn.cursor() as cur:
            cur.execute("select public.pdc_monitor_authenticated_active_scope_673(%s)", (GATEWAY,))
            self.assertTrue(cur.fetchone()[0])
            with self.assertRaises(psycopg2.Error) as raised:
                cur.execute("select public.claim_pdc_email_intake_batch(0,%s)", (GATEWAY,))
            self.assertEqual(raised.exception.pgcode, "22023")
        self.conn.rollback()

    def test_privilege_and_mime_control_readback_is_narrow_and_idempotent(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("""select
              (select enabled and observed_mime_part_count=7 and retained_authenticated_attachment_count=4 and all_mime_parts_retained and not production_writes and not task_enabled and not mailbox_contacted and not uid514_processed from public.pdc_email_monitor_authenticated_execution_attachment_controls_673 where singleton),
              (select count(*) from public.pdc_email_monitor_authenticated_execution_attachment_history_673 where event_kind='forward_authenticated_execution_attachment'),
              has_function_privilege('authenticated','public.claim_pdc_email_intake_batch(integer,text)','execute'),
              has_function_privilege('authenticated','public.pdc_agentic_apply_action_502(uuid)','execute'),
              has_function_privilege('anon','public.pdc_agentic_apply_action_502(uuid)','execute'),
              has_function_privilege('service_role','public.pdc_agentic_apply_action_502(uuid)','execute'),
              has_table_privilege('authenticated','public.pdc_uid514_attachment_selection_673','select'),
              (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_attachment_selection_673'::regclass)""")
            first = cur.fetchone()
            cur.execute("select public.pdc_monitor_authenticated_active_scope_673(%s)", (GATEWAY,))
            one = cur.fetchone()[0]
            cur.execute("select public.pdc_monitor_authenticated_active_scope_673(%s)", (GATEWAY,))
            two = cur.fetchone()[0]
        self.assertEqual(first, (True, 1, True, True, False, False, False, True))
        self.assertTrue(one and two)
        self.conn.rollback()


if __name__ == "__main__":
    unittest.main(verbosity=2)
