from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

import psycopg2

RUN_LIVE = os.environ.get("PDC_RUN_684_AUTHENTICATED_COMPATIBILITY_LIVE_TESTS") == "1"
ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
INTAKE = "102e286d-1799-4c97-8e45-e0da9fb31c63"
ATTACHMENT = "78f14ad0-cff3-40b6-9880-5fcb1f8e635b"
PARENT = "440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280"
JOB_CARD = "9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_684_AUTHENTICATED_COMPATIBILITY_LIVE_TESTS=1 for staging integration")
class AuthenticatedProviderImportAgentic684LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        spec = __import__("importlib.util", fromlist=["spec_from_file_location"]).spec_from_file_location("bootstrap684", spec_path)
        bootstrap = __import__("importlib.util", fromlist=["module_from_spec"]).module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()).decode())
        bootstrap.validate(values)
        endpoint = __import__("urllib.parse", fromlist=["urlsplit"]).urlsplit(values["PDC_STAGING_DATABASE_URL"])
        os.environ.update({key: values[key] for key in ("PDC_STAGING_DATABASE_URL", "PDC_STAGING_SSLROOTCERT", "PDC_STAGING_SSLROOTCERT_SHA256")})
        from scripts.pdc_staging_runtime import trusted_sslrootcert
        cls.conn = psycopg2.connect(host=endpoint.hostname, port=endpoint.port or 5432, user=endpoint.username, password=endpoint.password, dbname="postgres", sslmode="verify-full", sslrootcert=trusted_sslrootcert(), connect_timeout=15, application_name="pdc684_authenticated_compatibility_live_test")
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def tearDown(self):
        self.conn.rollback()

    def set_claims(self, sub=ACTOR, email=EMAIL):
        with self.conn.cursor() as cur:
            cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (sub,))
            cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({"sub": sub, "email": email, "role": "authenticated"}),))

    def claim_and_attest(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("select public.claim_pdc_uid514_recovery_257(%s,25751401)", (GATEWAY,))
            claim = cur.fetchone()[0]
            token = claim["items"][0]["claim_token"]
            cur.execute("select internet_message_id,provider_authentication from public.ai_email_intake where id=%s", (INTAKE,))
            message_id, authentication = cur.fetchone()
            args = (GATEWAY, token, INTAKE, ATTACHMENT, PARENT, JOB_CARD, message_id, "mx.google.com", json.dumps(authentication))
            cur.execute("select public.attest_pdc_monitor_provider_email_observation_684(%s,%s,%s::uuid,%s::uuid,%s,%s,%s,%s,%s::jsonb)", args)
            first = cur.fetchone()[0]
            cur.execute("select public.attest_pdc_monitor_provider_email_observation_684(%s,%s,%s::uuid,%s::uuid,%s,%s,%s,%s,%s::jsonb)", args)
            replay = cur.fetchone()[0]
        return claim, token, first, replay, message_id, authentication

    def test_exact_provider_observation_is_idempotent_and_source_bound(self):
        claim, token, first, replay, message_id, authentication = self.claim_and_attest()
        self.assertEqual(claim["code"], "uid514_claimed")
        self.assertEqual(first["code"], "provider_observation_attested")
        self.assertEqual(replay["code"], "provider_observation_already_attested")
        self.assertEqual(first["data"], replay["data"])
        with self.conn.cursor() as cur:
            evidence = {"intake_id": INTAKE, "source_hash": PARENT, "message_id": message_id, "sender": "oleg.borodavkin@pmgwa.com.au", "received_at": None, "provider_uid": "imap_uid:514", "recipient_mailbox": "pmbcontroller@gmail.com", "provider_authserv_id": "mx.google.com", "provider_authentication": authentication, "gateway_instance_id": GATEWAY, "claim_token": token}
            cur.execute("select received_at from public.ai_email_intake where id=%s", (INTAKE,))
            evidence["received_at"] = cur.fetchone()[0].isoformat()
            cur.execute("select public.pdc_monitor_authenticated_uid514_source_scope_684(%s::jsonb)", (json.dumps(evidence),))
            self.assertTrue(cur.fetchone()[0])

    def test_stale_hours_and_agentic_malformed_inputs_are_rejected_without_vehicle(self):
        _, token, _, _, _, authentication = self.claim_and_attest()
        with self.conn.cursor() as cur:
            cur.execute("select public.import_pdc_monitor_jobcard_attachment_authenticated_684(%s,%s,%s::uuid,%s::uuid,%s,%s,%s::jsonb,%s::jsonb,%s::jsonb,%s::jsonb)", (GATEWAY, token, INTAKE, ATTACHMENT, PARENT, JOB_CARD, json.dumps(authentication), json.dumps({"stock_numbers": ["13016925"], "job_card_number": "J139125482", "conflicts": [], "cancelled": False}), json.dumps(["fabrication", "fitting"]), json.dumps([{"source_row_no": 1, "operation_no": "OP1", "work_key": "owner_supplied_document", "description": "Fill Fuel", "estimated_hours": 0}, {"source_row_no": 2, "operation_no": "OP2", "work_key": "owner_supplied_document", "description": "PDI", "estimated_hours": 0.70}, {"source_row_no": 3, "operation_no": "OP3", "work_key": "fabrication", "description": "HDA Tray", "estimated_hours": 0}, {"source_row_no": 4, "operation_no": "OP4", "work_key": "fitting", "description": "Steel Bull Bar", "estimated_hours": 5.18}, {"source_row_no": 5, "operation_no": "OP5", "work_key": "fitting", "description": "Tow Bar long tongue", "estimated_hours": 13.10}])) )
            stale = cur.fetchone()[0]
            self.assertEqual(stale["code"], "source_layout_or_hours_mismatch")
            self.assertEqual(stale["data"]["source_total_hours"], 7.46)
            self.assertEqual(stale["data"]["stale_expected_hours_rejected"], 13.1)
            for sql, params in (("select public.read_pdc_agentic_email_context_authenticated_684('{}'::jsonb)", ()), ("select public.record_pdc_agentic_email_plan_authenticated_684('{}'::jsonb)", ()), ("select public.execute_pdc_agentic_email_action_authenticated_684('{}'::jsonb)", ()), ("select public.finalize_pdc_agentic_email_plan_authenticated_684('{}'::jsonb)", ())):
                cur.execute(sql, params)
                self.assertEqual(cur.fetchone()[0]["code"], "authenticated_uid514_source_required")
            cur.execute("select count(*) from public.vehicles where public.normalize_vehicle_stock_number(stock_number)='13016925'")
            self.assertEqual(cur.fetchone()[0], 0)

    def test_wrong_actor_and_direct_tables_denied(self):
        self.set_claims("557dba7f-fd70-4b9e-aa7b-b83b717682a7", "administrator2@staging.pdc-workshop.example.com")
        with self.conn.cursor() as cur:
            cur.execute("select public.pdc_monitor_authenticated_uid514_claim_scope_684(%s,%s,%s::uuid,%s::uuid,%s,%s)", (GATEWAY, "00000000-0000-4000-8000-000000000000", INTAKE, ATTACHMENT, PARENT, JOB_CARD))
            self.assertFalse(cur.fetchone()[0]["ok"])
            cur.execute("select has_table_privilege('authenticated','public.pdc_authenticated_provider_import_agentic_compatibility_controls_684','select'),has_table_privilege('authenticated','public.pdc_authenticated_provider_import_agentic_compatibility_history_684','select')")
            self.assertEqual(cur.fetchone(), (False, False))


if __name__ == "__main__":
    unittest.main(verbosity=2)
