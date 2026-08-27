from __future__ import annotations

import json
import os
from pathlib import Path
import unittest

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_672_AUTHENTICATED_ACTIVE_LIVE_TESTS") == "1"
ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
RELEASE = "pdc-monitor-staging-m502-2026.08.44"
SOURCE = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
MANIFEST = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
PLANNER = "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348"
TRUST = "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227"
VERIFY = "public.verify_pdc_monitor_runtime_binding_authenticated_672(%s,%s,%s,%s,%s,%s,%s)"
READER = "public.read_pdc_uid514_transaction_receipt_authenticated_672(%s)"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_672_AUTHENTICATED_ACTIVE_LIVE_TESTS=1 for authorised staging integration")
class AuthenticatedActiveSuccessor672LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        spec = __import__("importlib.util", fromlist=["spec_from_file_location"]).spec_from_file_location("bootstrap672", spec_path)
        bootstrap = __import__("importlib.util", fromlist=["module_from_spec"]).module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()).decode())
        bootstrap.validate(values)
        import urllib.parse
        endpoint = urllib.parse.urlsplit(values["PDC_STAGING_DATABASE_URL"])
        from scripts.pdc_staging_runtime import trusted_sslrootcert
        os.environ.update({key: values[key] for key in ("PDC_STAGING_DATABASE_URL", "PDC_STAGING_SSLROOTCERT", "PDC_STAGING_SSLROOTCERT_SHA256")})
        cls.conn = psycopg2.connect(host=endpoint.hostname, port=endpoint.port or 5432, user=endpoint.username, password=endpoint.password, dbname="postgres", sslmode="verify-full", sslrootcert=trusted_sslrootcert(), connect_timeout=15, application_name="pdc672_authenticated_active_live_test")
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def set_claims(self, sub=ACTOR, email=EMAIL, role="authenticated"):
        with self.conn.cursor() as cur:
            cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (sub,))
            cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({"sub": sub, "email": email, "role": role}),))

    def attestation(self, gateway=GATEWAY):
        with self.conn.cursor() as cur:
            cur.execute(f"select {VERIFY}", ("active", gateway, RELEASE, SOURCE, MANIFEST, PLANNER, TRUST))
            return cur.fetchone()[0]

    def test_authenticated_attestation_is_http_contract_equivalent_and_idempotent(self):
        self.set_claims()
        first = self.attestation()
        second = self.attestation()
        self.assertEqual(first, second)
        self.assertEqual(first["code"], "runtime_binding_verified_authenticated_672")
        self.assertTrue(first["ok"])
        self.assertEqual(first["jwt_role"], "authenticated")
        self.assertEqual(first["server_application_role"], "importer")
        self.assertTrue(first["writer_active"])
        self.assertTrue(first["planner_commissioned"])
        self.assertFalse(first["production_writes"])
        self.assertFalse(first["task_enabled"])
        self.assertFalse(first["mailbox_contacted"])
        self.assertFalse(first["uid514_processed"])

    def test_authenticated_uid514_reader_is_terminal_read_only(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute(f"select {READER}", (25751401,))
            result = cur.fetchone()[0]
        self.assertEqual(result["code"], "uid514_receipt_terminal")
        self.assertTrue(result["terminal"])
        self.assertEqual((result["mailbox"], result["folder"], result["uidvalidity"], result["uid"]), ("pmbcontroller@gmail.com", "Inbox", 1, 514))
        self.assertEqual((result["observed_mime_part_count"], result["retained_authenticated_attachment_count"]), (7, 4))
        self.assertTrue(result["synthetic_staging_commissioning"])
        self.assertFalse(result["physical_mailbox_fetch"])
        self.assertFalse(result["mailbox_flags_changed"])
        self.assertEqual((result["vehicle_operations"], result["operation_lines"]), (0, 0))

    def test_wrong_actor_role_and_gateway_are_denied(self):
        self.set_claims("557dba7f-fd70-4b9e-aa7b-b83b717682a7", "administrator2@staging.pdc-workshop.example.com")
        with self.assertRaises(psycopg2.Error) as raised:
            self.attestation()
        self.assertEqual(raised.exception.pgcode, "42501")
        self.assertIn("PDC_672_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED", str(raised.exception))
        self.conn.rollback()
        self.set_claims(role="pdc_email_monitor")
        with self.assertRaises(psycopg2.Error) as raised:
            self.attestation()
        self.assertEqual(raised.exception.pgcode, "42501")
        self.assertIn("PDC_672_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED", str(raised.exception))
        self.conn.rollback()
        self.set_claims()
        denied = self.attestation("wrong-gateway")
        self.assertEqual(denied, {"ok": False, "code": "runtime_binding_mismatch", "activation_ready": False, "production_writes": False})

    def test_new_capability_tables_are_private_and_execute_is_narrow(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("""select
              (select count(*) from public.pdc_email_monitor_authenticated_active_capability_controls_672),
              (select count(*) from public.pdc_email_monitor_authenticated_active_capability_history_672),
              has_function_privilege('authenticated','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute'),
              has_function_privilege('authenticated','public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)','execute'),
              has_function_privilege('anon','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute'),
              has_function_privilege('service_role','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute'),
              has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_active_capability_controls_672','select'),
              has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_active_capability_history_672','select'),
              (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_email_monitor_authenticated_active_capability_history_672'::regclass),
              (select count(*) from public.monitored_mailboxes where active),
              (select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)""")
            result = cur.fetchone()
        self.assertEqual(result, (1, 1, True, True, False, False, False, False, True, 0, 1))


if __name__ == "__main__":
    unittest.main(verbosity=2)
