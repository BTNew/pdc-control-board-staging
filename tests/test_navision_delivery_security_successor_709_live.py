from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import unittest
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import psycopg2
from psycopg2.extras import Json, register_uuid

register_uuid()


RUN_LIVE = os.environ.get("PDC_RUN_NAVISION_DELIVERY_709_LIVE_TESTS") == "1"
MONITOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
MONITOR_EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_NAVISION_DELIVERY_709_LIVE_TESTS=1 for authorised staging probes")
class NavisionDelivery709LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        spec = importlib.util.spec_from_file_location("bootstrap709", spec_path)
        bootstrap = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(
            bootstrap.unprotect(
                Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()
            ).decode()
        )
        bootstrap.validate(values)
        cls.conn = psycopg2.connect(
            values["PDC_STAGING_DATABASE_URL"],
            host=None,
            connect_timeout=15,
            application_name="pdc709_delivery_security_live",
            sslmode="verify-full",
            sslrootcert=values["PDC_STAGING_SSLROOTCERT"],
        )
        cls.conn.autocommit = False

    def setUp(self):
        self.conn.rollback()

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def set_claims(self, sub: str, email: str, pdc_role: str = "importer"):
        claims = json.dumps({"sub": sub, "email": email, "role": "authenticated", "pdc_role": pdc_role})
        with self.conn.cursor() as cur:
            cur.execute("reset role")
            cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (sub,))
            cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))

    def as_role(self, role: str):
        self.conn.cursor().execute(f"set local role {role}")

    def call(self, sql: str, params=()):
        with self.conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()[0]

    def count_state(self, vehicle_id: str):
        with self.conn.cursor() as cur:
            cur.execute(
                """select
                  (select count(*) from public.pdc_final_pdc_lifecycle_receipts_700 where vehicle_id=%s),
                  (select count(*) from public.vehicle_movements where vehicle_id=%s),
                  (select count(*) from public.audit_events where vehicle_id=%s),
                  (select lifecycle_state::text from public.vehicles where id=%s),
                  (select current_location from public.vehicles where id=%s),
                  (select dealer_transit_duration_seconds from public.vehicles where id=%s)""",
                (vehicle_id, vehicle_id, vehicle_id, vehicle_id, vehicle_id, vehicle_id),
            )
            return cur.fetchone()

    def seed_delivery_fixture(self, suffix: str):
        vehicle_id = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), f"vehicle:{suffix}")
        record_id = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), f"record:{suffix}")
        batch_id = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), f"batch:{suffix}")
        stock = f"999709{suffix[-2:]}"
        now = datetime.now(timezone.utc)
        with self.conn.cursor() as cur:
            cur.execute("reset role")
            cur.execute("select set_config('pdc.hermes_test_wrapper_vehicle_365',%s,true)", (str(vehicle_id),))
            cur.execute(
                """insert into public.vehicles(
                  id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,
                  visible_on_board,current_location,rft_transferred_at,rft_collected_at,
                  rft_collected_by,source_payload,version,source_system,source_batch_id,source_record_id,
                  date_to_rft,rft_transport_booked_at,rft_transport_booked_by,
                  dealer_transit_started_at,created_by,updated_by)
                values(%s,%s,%s,%s,'rft',false,'Collected',%s,%s,%s,'{}',1,
                  'hermes_test_709','14450',%s,%s,%s,%s,%s,%s,%s)""",
                (
                    vehicle_id,
                    f"HERMES-TEST-PERM-{suffix}",
                    stock,
                    f"HERMES-TEST-JOB-{suffix}",
                    now - timedelta(minutes=4),
                    now - timedelta(minutes=2),
                    MONITOR_ID,
                    f"HERMES-TEST-709-{suffix}",
                    date.today(),
                    now - timedelta(minutes=3),
                    MONITOR_ID,
                    now - timedelta(minutes=2),
                    MONITOR_ID,
                    MONITOR_ID,
                ),
            )
            cur.execute(
                """insert into public.navision_import_batches(
                  id,idempotency_key,request_hash,source_name,source_timestamp,source_hash,
                  preview_hash,base_revision,result_revision,status,total_rows,receipt,
                  actor_id,actor_email,source_system,dealer_code)
                values(%s,%s,%s,%s,%s,%s,%s,1,1,'applied',1,%s,%s,%s,'microsoft_navision','14450')""",
                (batch_id, f"HERMES-TEST-709-BATCH-{suffix}", "e" * 64, "HERMES-TEST-709", now, "f" * 64, "a" * 64, Json({"synthetic_only": True}), MONITOR_ID, MONITOR_EMAIL),
            )
            cur.execute(
                """insert into public.navision_backend_records(
                  id,source_record_id,row_hash,normalized_data,raw_evidence,
                  canonical_vehicle_id,first_seen_batch_id,last_seen_batch_id,source_system,
                  dealer_code,record_status)
                values(%s,%s,%s,%s,%s,%s,%s,%s,'microsoft_navision','14450','current')""",
                (
                    record_id,
                    f"HERMES-TEST-709-RECORD-{suffix}",
                    "a" * 64,
                    Json({"batch": stock, "toyotaStatus": "Delivered - At Dealer"}),
                    Json({"source": "HERMES-TEST-709"}),
                    vehicle_id,
                    batch_id,
                    batch_id,
                ),
            )
            cur.execute(
                """insert into public.navision_board_activations(
                  backend_record_id,activation_source,activated_stock_number,activated_by,
                  activated_by_email,canonical_vehicle_id,active)
                values(%s,'approved_email_build',%s,%s,%s,%s,true)""",
                (record_id, stock, MONITOR_ID, MONITOR_EMAIL, vehicle_id),
            )
            for action in ("qc_signed_off", "rft_booked", "collected"):
                receipt_id = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), f"receipt:{suffix}:{action}")
                idem = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), f"idem:{suffix}:{action}")
                cur.execute(
                    """insert into public.pdc_final_pdc_lifecycle_receipts_700(
                      receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,
                      request_sha256,request_payload,before_state,after_state,evidence,response)
                    values(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (
                        receipt_id,
                        vehicle_id,
                        action,
                        MONITOR_ID,
                        MONITOR_EMAIL,
                        idem,
                        "b" * 64,
                        Json({"contract": "HERMES-TEST-709"}),
                        Json({"source": "HERMES-TEST-709"}),
                        Json({"source": "HERMES-TEST-709"}),
                        Json({"synthetic_only": True}),
                        Json({"ok": True, "code": action}),
                    ),
                )
        return vehicle_id, record_id

    def test_catalog_inventory_and_all_hostile_surfaces_are_closed(self):
        self.set_claims(str(uuid.uuid4()), "generic-709@example.invalid", "")
        before = self.count_state(str(uuid.uuid4()))
        with self.conn.cursor() as cur:
            cur.execute(
                """select signature,has_defaults,execute_public,execute_anon,execute_authenticated,
                           execute_service_role,execute_pdc_email_monitor
                   from public.pdc_navision_delivery_security_inventory_709
                  where phase='post' order by signature"""
            )
            inventory = cur.fetchall()
            self.assertGreaterEqual(len(inventory), 2)
            for signature, defaults, x_public, x_anon, x_auth, x_service, x_monitor in inventory:
                canonical = signature.startswith("public.reconcile_navision_delivery_700(") or signature.startswith("public.reconcile_navision_operational_record(")
                if canonical:
                    self.assertFalse(defaults)
                    self.assertFalse(x_public)
                    self.assertFalse(x_anon)
                    self.assertTrue(x_auth)
                    self.assertFalse(x_service)
                    self.assertFalse(x_monitor)
                else:
                    self.assertFalse(x_public or x_anon or x_auth or x_service or x_monitor, signature)

            cur.execute(
                """select proname,phase,execute_service_role,execute_authenticated
                     from public.pdc_navision_delivery_prefixed_family_inventory_713
                    where proname='reconcile_navision_operational_record_pre134'
                    order by phase"""
            )
            pre134 = cur.fetchall()
            self.assertEqual(len(pre134), 2)
            self.assertEqual(pre134[0][1:], ("post", False, False))
            self.assertEqual(pre134[1][1:], ("pre", True, False))

        for pdc_role in ("", "viewer", "operator", "administrator"):
            self.set_claims(str(uuid.uuid4()), f"{pdc_role or 'generic'}-709@example.invalid", pdc_role)
            result = self.call("select public.reconcile_navision_delivery_700(%s)", (str(uuid.uuid4()),))
            self.assertEqual(result["code"], "monitor_identity_required", pdc_role)

        self.set_claims(MONITOR_ID, MONITOR_EMAIL)
        result = self.call(
            "select public.reconcile_navision_operational_record(%s,%s,%s)",
            (str(uuid.uuid4()), str(uuid.uuid4()), "wrong-actor@example.invalid"),
        )
        self.assertEqual(result["code"], "actor_identity_mismatch")
        self.assertEqual(self.call("select public.reconcile_navision_delivery_700(%s)", (str(uuid.uuid4()),))["code"], "delivery_record_not_current")

        with self.conn.cursor() as cur:
            for role, sql, params in (
                ("anon", "select public.reconcile_navision_delivery_700(%s)", (str(uuid.uuid4()),)),
                ("service_role", "select public.reconcile_navision_delivery_700(%s)", (str(uuid.uuid4()),)),
                ("authenticated", "select public.reconcile_navision_delivery_700(%s,%s,%s)", (str(uuid.uuid4()), None, None)),
                ("authenticated", "select public.reconcile_navision_operational_record(%s)", (str(uuid.uuid4()),)),
                ("authenticated", "select public.reconcile_navision_operational_record(%s,%s)", (str(uuid.uuid4()), None)),
            ):
                cur.execute("savepoint hostile_surface")
                try:
                    cur.execute(f"set local role {role}")
                    with self.assertRaises(psycopg2.Error) as raised:
                        cur.execute(sql, params)
                    self.assertIn(raised.exception.pgcode, ("42501", "42883"), (role, sql, raised.exception))
                finally:
                    cur.execute("rollback to savepoint hostile_surface")
                    cur.execute("release savepoint hostile_surface")
        self.conn.rollback()

    def test_exact_canonical_delivery_succeeds_once_and_replays_without_duplicate_audit(self):
        vehicle_id, record_id = self.seed_delivery_fixture("01")
        self.set_claims(MONITOR_ID, MONITOR_EMAIL)
        before = self.count_state(str(vehicle_id))
        first = self.call("select public.reconcile_navision_delivery_700(%s)", (str(record_id),))
        self.assertTrue(first["ok"], first)
        self.assertEqual(first["code"], "delivered_at_dealer_completed")
        after_first = self.count_state(str(vehicle_id))
        second = self.call("select public.reconcile_navision_delivery_700(%s)", (str(record_id),))
        self.assertTrue(second["ok"], second)
        self.assertTrue(second.get("replay"), second)
        after_second = self.count_state(str(vehicle_id))
        self.assertEqual(after_first, after_second)
        self.assertEqual(after_second[0], before[0] + 1)
        self.assertEqual(after_second[1], before[1] + 1)
        self.assertEqual(after_second[2], before[2] + 1)
        self.assertEqual(after_second[3:5], ("completed", "Completed"))
        self.assertGreaterEqual(after_second[5], 0)
        self.conn.rollback()

    def test_exact_body_location_routes_to_canonical_and_eta_path_remains_non_delivery(self):
        delivery_vehicle, delivery_record = self.seed_delivery_fixture("02")
        self.set_claims(MONITOR_ID, MONITOR_EMAIL)
        now = datetime.now(timezone.utc).replace(microsecond=0)
        body_source_id = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), "body:02")
        intake_id = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), "intake:02")
        claim_token = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), "claim:02")
        clause = "99970902 Delivered - At Dealer"
        self.seed_body_source(body_source_id, intake_id, claim_token, clause, now)
        request_sha = self.body_request_hash(body_source_id, intake_id, claim_token, clause, now, "99970902", "Delivered - At Dealer")
        exact = self.call(
            "select public.process_pdc_monitor_body_location_20260821033000(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
            (str(intake_id), str(claim_token), GATEWAY, str(body_source_id), 1, len(clause), hashlib.sha256(clause.encode()).hexdigest(), "99970902", None, now, request_sha),
        )
        self.assertTrue(exact["ok"], exact)
        self.assertEqual(exact["code"], "location_receipt", exact)
        self.assertEqual(exact["data"]["outcome"], "applied", exact)
        self.assertEqual(exact["data"]["reason"], "delivery_routed_to_canonical_700", exact)
        self.assertEqual(exact["data"]["after_data"]["current_location"], "Completed", exact)
        state = self.count_state(str(delivery_vehicle))
        self.assertEqual(state[3:5], ("completed", "Completed"))
        self.assertEqual(state[0], 4)

        # Independent non-delivery fixture proves the retained ETA branch still writes IT.
        eta_vehicle = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), "eta-03")
        eta_body_source = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), "body:03")
        eta_intake = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), "intake:03")
        eta_claim = uuid.uuid5(uuid.UUID("70900000-0000-5000-8000-000000000709"), "claim:03")
        eta = date(2099, 12, 31)
        eta_clause = "99970903 ETA 2099-12-31"
        self.seed_eta_vehicle(eta_vehicle)
        self.seed_body_source(eta_body_source, eta_intake, eta_claim, eta_clause, now)
        eta_sha = self.body_request_hash(eta_body_source, eta_intake, eta_claim, eta_clause, now, "99970903", "ETA", eta)
        eta_result = self.call(
            "select public.process_pdc_monitor_body_location_20260821033000(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
            (str(eta_intake), str(eta_claim), GATEWAY, str(eta_body_source), 1, len(eta_clause), hashlib.sha256(eta_clause.encode()).hexdigest(), "99970903", eta, now, eta_sha),
        )
        self.assertTrue(eta_result["ok"], eta_result)
        self.assertEqual(eta_result["code"], "location_receipt", eta_result)
        self.assertEqual(eta_result["data"]["outcome"], "applied", eta_result)
        self.assertEqual(eta_result["data"]["reason"], "eta_to_it_pre_yh_unlocked", eta_result)
        self.assertEqual(eta_result["data"]["after_data"]["current_location"], "IT", eta_result)
        with self.conn.cursor() as cur:
            cur.execute("select lifecycle_state::text,current_location from public.vehicles where id=%s", (str(eta_vehicle),))
            self.assertEqual(cur.fetchone(), ("active", "IT"))
        self.conn.rollback()

    def seed_body_source(self, body_source_id, intake_id, claim_token, clause, received_at):
        body_sha = hashlib.sha256(clause.encode()).hexdigest()
        with self.conn.cursor() as cur:
            cur.execute("reset role")
            cur.execute(
                """insert into public.ai_email_intake(
                  id,status,graph_message_id,received_at,raw_body,parsed_text,
                  locked_at,locked_by,claim_token,gateway_instance_id)
                values(%s,'processing'::public.ai_intake_status,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (intake_id, f"HERMES-TEST-709-{body_source_id}", received_at, clause, clause, received_at, MONITOR_ID, claim_token, GATEWAY),
            )
            cur.execute(
                """insert into public.pdc_full_inbox_body_sources_20260821033000(
                  body_source_id,contract_version,actor_id,actor_email,intake_id,claim_token,
                  gateway_instance_id,parent_source_hash,body_sha256,body_text,current_authored_text,
                  current_authored_sha256,message_received_at,request_sha256)
                values(%s,'20260821033000.1',%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (body_source_id, MONITOR_ID, MONITOR_EMAIL, intake_id, claim_token, GATEWAY, "c" * 64, body_sha, clause, clause, body_sha, received_at, hashlib.sha256((str(body_source_id) + clause).encode()).hexdigest()),
            )

    def seed_eta_vehicle(self, vehicle_id):
        with self.conn.cursor() as cur:
            cur.execute("reset role")
            cur.execute("select set_config('pdc.hermes_test_wrapper_vehicle_365',%s,true)", (str(vehicle_id),))
            cur.execute(
                """insert into public.vehicles(
                  id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,
                  visible_on_board,current_location,source_payload,version,source_system,source_batch_id,source_record_id)
                values(%s,%s,'99970903',%s,'active',true,'Other','{}',1,
                  'hermes_test_709','HERMES-TEST-709',%s)""",
                (vehicle_id, f"HERMES-TEST-PERM-ETA-03", "HERMES-TEST-JOB-ETA-03", "HERMES-TEST-709-ETA-03"),
            )

    def body_request_hash(self, body_source_id, intake_id, claim_token, clause, received_at, stock, status, eta=None):
        with self.conn.cursor() as cur:
            cur.execute(
                """select encode(extensions.digest(convert_to(jsonb_build_object(
                  'contract_version','20260821033000.location.1','actor_id',%s::uuid,
                  'intake_id',%s::uuid,'body_source_id',%s::uuid,'claim_token',%s::uuid,
                  'gateway_instance_id',%s,'clause_start',1,'clause_end',%s,
                  'clause_sha256',%s,'stock_number',public.normalize_vehicle_stock_number(%s),
                  'asserted_status',%s,'asserted_eta_iso',case when %s::date is null then null else to_char(%s::date,'YYYY-MM-DD') end,
                  'message_received_at_utc',public.pdc_full_inbox_utc_text_20260821033000(%s::timestamptz))::text,'UTF8'),'sha256'),'hex')""",
                (MONITOR_ID, intake_id, body_source_id, claim_token, GATEWAY, len(clause), hashlib.sha256(clause.encode()).hexdigest(), stock, status, eta, eta, received_at),
            )
            return cur.fetchone()[0]


if __name__ == "__main__":
    unittest.main(verbosity=2)
