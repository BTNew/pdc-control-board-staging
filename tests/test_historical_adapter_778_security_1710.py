import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830171000_778_historical_reconciliation_security_successor.sql"
CALLER = ROOT / "pdc_historical_778_caller.py"


class HistoricalAdapter778Security1710Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_append_only_live_predecessor_and_security_binding(self):
        for token in (
            "20260830170000", "778_historical_reconciliation_enqueue_adapter",
            "20260830171000", "pdc_monitor_staging_guard()",
            "pdc_monitor_authenticated_active_scope_674",
            "verify_pdc_monitor_runtime_binding_authenticated_766",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "manifest_uidvalidity", "manifest_high_water_uid", "manifest_uid_count",
            "grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to authenticated",
        ):
            self.assertIn(token, self.sql)
        self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to anon", self.sql)
        self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to service_role", self.sql)

    def test_exact_expiry_replay_sender_and_reference_guards(self):
        for token in (
            "e.provider_uid=v_uid", "e.parent_source_hash=v_parent",
            "e.sender_email=v_sender", "e.provider_authentication is not distinct from v_auth",
            "e.authorized_actor_id=v_actor", "e.authorized_gateway_instance_id",
            "authorized_at+interval '24 hours'", "historical_replay_conflict",
            "historical_old_mail_completed", "pdc_778_exact_authorization_failed",
            "sender_sha256=encode(extensions.digest(convert_to(v_sender,'utf8'),'sha256'),'hex')",
            "historical_reference_stock_excluded", "v_uid='1:197'", "v_stock='13056899'",
        ):
            self.assertIn(token, self.sql)

    def test_sibling_isolation_and_fail_closed_canonical_child_processing(self):
        for token in (
            "pdc_historical_provider_observations_778", "attachment_hash",
            "non_job_card_sibling", "ambiguous_job_card",
            "historical_child_sibling_duplicate", "historical_child_vehicle_scope_mismatch",
            "historical_fail_closed", "navision_not_found",
            "import_pdc_jobcard_attachment_canonical", "historical_child_atomic_failure",
            "historical_reconciliation_partial", "no_booking", "no_completion", "no_location_mutation",
        ):
            self.assertIn(token, self.sql)
        self.assertNotIn("insert into public.workshop", self.sql)
        self.assertNotIn("update public.vehicles", self.sql)


class HistoricalCaller778SecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("historical_778", CALLER)
        cls.module = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(cls.module)

    def test_request_has_frozen_runtime_fields_and_uuid_free_children(self):
        row = {
            "manifest_sha256": self.module.MANIFEST_SHA256,
            "provider_uid": "1:22", "parent_source_hash": "a" * 64,
            "sender_email": "andy.weir@broometoyota.com.au",
            "authentication": {"dkim_aligned": False, "dmarc_aligned": False,
                               "gmail_authentication_results": True,
                               "sender_domain": "broometoyota.com.au", "spf_aligned": True},
            "stock_number": "13047257", "source_received_at": "2026-01-01T00:00:00+00:00",
            "subject": "Vehicle", "action_type": "review_only", "summary": "Vehicle",
            "evidence_hash": "e" * 64, "observations": {},
            "source_metadata": {
                "internet_message_id": "<message@example.test>", "graph_message_id": "imap:1:22",
                "received_at": "2026-01-01T00:00:00+00:00", "recipient_mailbox": "pmbcontroller@gmail.com",
                "sender_name": "Andy Weir", "raw_body": "body", "parsed_text": "parsed",
                "provider_authserv_id": "mx.google.com", "attachment_names": ["PickList.pdf", "J139.pdf"],
                "uidvalidity": 1, "uid": 22,
            },
            "attachments": [
                {"filename": "PickList.pdf", "sha256": "b" * 64, "size": 10,
                 "content_type": "application/pdf", "attachment_kind": "non_job_card_sibling"},
                {"filename": "J139.pdf", "sha256": "c" * 64, "size": 10,
                 "content_type": "application/pdf", "attachment_kind": "job_card",
                 "extraction_hash": "d" * 64,
                 "extraction": {"email_vehicle": {"stock_numbers": ["13047257"], "conflicts": [], "cancelled": False},
                                "operation_lines": [], "required_work": ["fitting"]}},
            ],
        }
        request = self.module.build_historical_request(row)
        for key in ("manifest_uidvalidity", "manifest_high_water_uid", "manifest_uid_count",
                    "gateway_instance_id", "release_name", "release_source_sha", "release_manifest_sha256"):
            self.assertIn(key, request)
        self.assertEqual(request["job_card_children"][0]["attachment_hash"], "c" * 64)
        self.assertNotIn("intake_id", request)
        self.assertNotIn("attachment_id", json.dumps(request))

    def test_reference_row_is_filtered_before_rpc(self):
        rows = [{"manifest_sha256": self.module.MANIFEST_SHA256, "provider_uid": "1:197", "stock_number": "13056899"}]
        self.assertEqual(self.module.select_authorized_rows(rows), [])


if __name__ == "__main__":
    unittest.main()
