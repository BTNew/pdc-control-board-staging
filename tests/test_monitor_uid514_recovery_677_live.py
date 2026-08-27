from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_UID514_RECOVERY_677_LIVE_TESTS") == "1"
ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
EMAIL = "sales@broometoyota.com.au"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
EVENT = 25751401

ATTACHMENTS = [
    ("image001.jpg", "image/jpeg", 161949, "7bc4e2dec9b1c405098f1ca7b4c646bf3262158e328f9f548abb855b8ef2f21a"),
    ("image002.png", "image/png", 119426, "ffaa2bfbca036f9dbcbe10de9a43f8a141fd2a84f9fea75c0e114b96b87b4cf3"),
    ("image.png", "image/png", 220912, "c60dae99a28cdccdee51f5bdffa43382d9b7eb31af690c31caedcc8d4f66cf40"),
    ("J139125482 - _13016925.pdf", "application/pdf", 72551, "9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4"),
    ("131 Parts Order - 13016925 - Hilux SCC WM - HERMAL Pty Ltd.pdf", "application/pdf", 50134, "66b790ba3a72760e00a034bf7f5cf5a7e1defe5d6947373216f8c8dc4ed8acff"),
    ("PMG Sublet Order - 13016925 - Hilux SCC WM - HERMAL Pty Ltd.pdf", "application/pdf", 49944, "b297f4f9070f6c78c88aae099630b78bb5157c3094c45a30b5cfef0f263ac3b1"),
    ("PD Document 48298_PDCheckform.pdf", "application/pdf", 17398, "ea248634b8610f757907c519ea2f7ba243fb1602c8114cbde947707aff8407ae"),
]
PARENT = "440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280"


def payload() -> tuple[str, str]:
    message = {
        "graph_message_id": "imap:uid514-recovery-677-rehearsal",
        "internet_message_id": "<uid514-recovery-677-rehearsal@example.invalid>",
        "provider_uid": "imap_uid:514",
        "source_hash": PARENT,
        "subject": "Re: New vehicle order for 13016925 - PMG Build",
        "sender_email": "oleg.borodavkin@pmgwa.com.au",
        "sender_name": "Oleg Borodavkin",
        "received_at": "2026-08-14T06:22:52+00:00",
        "raw_body": "synthetic rolled-back UID514 recovery rehearsal",
        "parsed_text": "synthetic rolled-back UID514 recovery rehearsal",
        "attachment_names": [item[0] for item in ATTACHMENTS],
        "recipient_mailbox": "pmbcontroller@gmail.com",
        "provider_authserv_id": "mx.google.com",
        "provider_authentication": {
            "dkim_aligned": True,
            "dmarc_aligned": False,
            "gmail_authentication_results": True,
            "sender_domain": "pmgwa.com.au",
            "spf_aligned": False,
        },
    }
    attachments = [
        {
            "file_name": name,
            "content_type": content_type,
            "reported_content_type": content_type,
            "size_bytes": size,
            "source_hash": digest,
            "storage_path": f"pdc-email-intake-private/uid514/{digest}/{name}",
            "validation_status": "verified",
            "validation_error": "",
        }
        for name, content_type, size, digest in ATTACHMENTS
    ]
    return json.dumps(message), json.dumps(attachments)


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_UID514_RECOVERY_677_LIVE_TESTS=1 for authorised staging integration")
class Uid514ExactRecovery677LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        spec = __import__("importlib.util", fromlist=["spec_from_file_location"]).spec_from_file_location("bootstrap677", spec_path)
        bootstrap = __import__("importlib.util", fromlist=["module_from_spec"]).module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()).decode())
        bootstrap.validate(values)
        endpoint = __import__("urllib.parse", fromlist=["urlsplit"]).urlsplit(values["PDC_STAGING_DATABASE_URL"])
        os.environ.update({key: values[key] for key in ("PDC_STAGING_DATABASE_URL", "PDC_STAGING_SSLROOTCERT", "PDC_STAGING_SSLROOTCERT_SHA256")})
        from scripts.pdc_staging_runtime import trusted_sslrootcert
        cls.conn = psycopg2.connect(host=endpoint.hostname, port=endpoint.port or 5432, user=endpoint.username, password=endpoint.password, dbname="postgres", sslmode="verify-full", sslrootcert=trusted_sslrootcert(), connect_timeout=20, application_name="uid514_recovery_677_live_test")
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

    def scalar(self, sql: str, *args):
        with self.conn.cursor() as cur:
            cur.execute(sql, args)
            return cur.fetchone()[0]

    def test_exact_enqueue_claim_attachment_replay_and_rollback_rehearsal(self):
        self.set_claims()
        message, attachments = payload()
        self.assertEqual(self.scalar("select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'"), 0)
        with self.conn.cursor() as cur:
            cur.execute("select public.enqueue_pdc_uid514_recovery_677(%s::jsonb,%s::jsonb,%s)", (message, attachments, EVENT))
            first = cur.fetchone()[0]
        self.assertEqual((first["ok"], first["code"], first["idempotent"], first["observed_mime_part_count"], first["retained_authenticated_attachment_count"]), (True, "uid514_recovery_enqueued", False, 7, 4))
        intake_id = first["intake_id"]
        self.assertEqual(self.scalar("select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'"), 1)
        self.assertEqual(self.scalar("select count(*) from public.ai_email_attachments where intake_id=%s", intake_id), 7)
        self.assertEqual(self.scalar("select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401"), 1)
        self.assertEqual(self.scalar("select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401"), 1)
        self.assertEqual(self.scalar("select count(*) from public.vehicles where stock_number='13016925'"), 0)

        with self.conn.cursor() as cur:
            cur.execute("select public.enqueue_pdc_uid514_recovery_677(%s::jsonb,%s::jsonb,%s)", (message, attachments, EVENT))
            replay = cur.fetchone()[0]
        self.assertEqual((replay["ok"], replay["code"], replay["idempotent"], replay["intake_id"]), (True, "uid514_recovery_replayed", True, intake_id))
        self.assertEqual(self.scalar("select count(*) from public.ai_email_attachments where intake_id=%s", intake_id), 7)
        self.assertEqual(self.scalar("select count(*) from public.pdc_uid514_recovery_history_677 where event_kind='forward_uid514_recovery'"), 2)

        with self.conn.cursor() as cur:
            cur.execute("select public.claim_pdc_uid514_recovery_257(%s,%s)", (GATEWAY, EVENT))
            claim = cur.fetchone()[0]
            self.assertEqual((claim["ok"], claim["count"]), (True, 1))
            item = claim["items"][0]
            cur.execute("select public.get_pdc_monitor_intake_attachments(%s,%s,%s)", (intake_id, item["claim_token"], GATEWAY))
            attachment_read = cur.fetchone()[0]
            self.assertEqual((attachment_read["ok"], len(attachment_read["attachments"])), (True, 7))
            cur.execute("select public.record_pdc_email_intake_result(%s,%s,%s,%s,%s::jsonb,%s,%s,%s,%s::jsonb)", (intake_id, item["claim_token"], GATEWAY, False, json.dumps({"code": "synthetic_rehearsal_rollback"}), "synthetic_rehearsal", "synthetic rollback", True, "{}"))
            self.assertTrue(cur.fetchone()[0]["ok"])

        def expect_error(sql: str, args: tuple, marker: str):
            with self.conn.cursor() as cur:
                cur.execute("savepoint uid514_negative")
                try:
                    cur.execute(sql, args)
                    self.fail(f"expected {marker}")
                except psycopg2.Error as exc:
                    self.assertIn(marker, str(exc))
                finally:
                    cur.execute("rollback to savepoint uid514_negative")
                    cur.execute("release savepoint uid514_negative")

        expect_error("select public.enqueue_pdc_uid514_recovery_677(%s::jsonb,%s::jsonb,%s)", (message, attachments, 25751402), "PDC_677_UID514_RECOVERY_SCOPE_INVALID")
        expect_error("select public.claim_pdc_uid514_recovery_257(%s,%s)", ("wrong-gateway", EVENT), "PDC_261_UID514_RUNTIME_UNBOUND")
        self.set_claims("557d7ba7-fd70-4b9e-aa7b-b83b717682a7", "administrator2@staging.pdc-workshop.example.com")
        expect_error("select public.enqueue_pdc_uid514_recovery_677(%s::jsonb,%s::jsonb,%s)", (message, attachments, EVENT), "PDC_677_UID514_RECOVERY_PAYLOAD_INVALID")
        self.set_claims()
        self.assertFalse(self.scalar("select has_function_privilege('anon','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute')"))
        self.assertFalse(self.scalar("select has_function_privilege('service_role','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute')"))

        admin = self.scalar("select r.auth_user_id::text||'|'||lower(r.email) from public.pdc_user_roles r where r.active and r.account_status='approved' and r.role::text='administrator' order by r.auth_user_id limit 1")
        admin_id, admin_email = admin.split("|", 1)
        self.set_claims(admin_id, admin_email)
        with self.conn.cursor() as cur:
            cur.execute("savepoint uid514_rollback")
            cur.execute("select public.admin_rollback_pdc_uid514_recovery_677(%s)", ("synthetic full-chain rollback rehearsal",))
            rolled = cur.fetchone()[0]
            self.assertEqual((rolled["ok"], rolled["code"], rolled["idempotent"]), (True, "pdc_uid514_recovery_rolled_back_677", False))
            self.set_claims()
            with self.assertRaises(psycopg2.Error) as raised:
                cur.execute("select public.claim_pdc_uid514_recovery_257(%s,%s)", (GATEWAY, EVENT))
            self.assertIn("PDC_677_UID514_RECOVERY_DISABLED", str(raised.exception))
            cur.execute("rollback to savepoint uid514_rollback")
            cur.execute("release savepoint uid514_rollback")

        self.set_claims()
        self.assertEqual(self.scalar("select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'"), 1)
        self.assertEqual(self.scalar("select count(*) from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401"), 1)
        self.assertEqual(self.scalar("select count(*) from public.pdc_uid514_attachment_selection_673 where recovery_event_id=25751401"), 1)
        self.assertEqual(self.scalar("select count(*) from public.vehicles where stock_number='13016925'"), 0)
        self.conn.rollback()


if __name__ == "__main__":
    unittest.main(verbosity=2)
