import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "staging_only" / "20260830170000_778_historical_reconciliation_enqueue_adapter.sql"
CALLER = ROOT / "pdc_full_inbox_typed_import.py"


class HistoricalAdapter778SqlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8").lower()

    def test_successor_is_staging_guarded_and_predecessor_bound(self):
        sql = self.sql
        for token in (
            "20260830166000", "777_historical_reconciliation_canonical_adapter_repair2",
            "pdc_monitor_staging_guard()", "pdc_monitor_authenticated_active_scope_674",
            "pdc_email_monitor_current_head_compatibility_controls_766",
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "pdc-monitor-staging-sales-uid509-v1",
            "aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018",
            "13056899", "1:197", "production_environment_sentinel",
        ):
            self.assertIn(token, sql)
        self.assertIn("create function public.submit_pdc_historical_reconciliation_778", sql)
        self.assertIn("grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to authenticated", sql)
        self.assertEqual(sql.count("insert into supabase_migrations.schema_migrations"), 1)
        self.assertNotIn("grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to anon", sql)

    def test_request_is_uuid_free_and_attachment_hash_keyed(self):
        sql = self.sql
        for token in (
            "enqueue_pdc_email_intake(p_message,p_attachments)",
            "attachment_hash", "pdc_historical_provider_observations_778",
            "job_card_children", "derived_attachment_id", "select id into v_attachment_id",
            "non_job_card_sibling", "pdc_historical_writer_authorized_773",
            "import_pdc_jobcard_attachment_canonical", "submit_pdc_ai_intake_observation_pre135",
            "import_pdc_authenticated_email_operations_with_hours",
        ):
            self.assertIn(token, sql)
        self.assertNotIn("v_request->>'intake_id'", sql)
        self.assertNotIn("v_child->>'attachment_id'", sql)

    def test_exact_gate_and_immutable_no_side_effect_receipts_are_present(self):
        sql = self.sql
        for token in (
            "e.provider_uid=v_provider_uid", "e.parent_source_hash=v_parent_source_hash",
            "e.sender_email=v_sender", "e.provider_authentication is not distinct from v_authentication",
            "public.normalize_vehicle_stock_number(e.stock_number)=v_stock",
            "v_provider_uid='1:197'", "v_stock='13056899'",
            "booking_created", "completion_created", "location_scheduled",
            "no_booking", "no_completion", "no_location_mutation",
            "before update or delete", "historical_replay_conflict",
        ):
            self.assertIn(token, sql)
        self.assertNotIn("insert into public.workshop", sql)
        self.assertNotIn("update public.workshop", sql)
        self.assertNotIn("update public.vehicles", sql)


class HistoricalCaller778Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("pdc_full_inbox_typed_import", CALLER)
        cls.module = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(cls.module)

    def test_caller_uses_exact_frozen_cohort_and_no_invented_ids(self):
        rows = [
            {"manifest_sha256": manifest, "provider_uid": "1:21", "stock_number": "13042997"}
            for manifest in (self.module.MANIFEST_SHA256, "bad")
        ]
        rows.append({"manifest_sha256": self.module.MANIFEST_SHA256, "provider_uid": "1:197", "stock_number": "13056899"})
        self.assertEqual([r["provider_uid"] for r in self.module.select_authorized_rows(rows)], ["1:21"])

        row = {
            "manifest_sha256": self.module.MANIFEST_SHA256,
            "provider_uid": "1:22", "parent_source_hash": "a" * 64,
            "sender_email": "andy.weir@broometoyota.com.au",
            "authentication": {"dkim_aligned": False, "dmarc_aligned": False,
                               "gmail_authentication_results": True,
                               "sender_domain": "broometoyota.com.au", "spf_aligned": True},
            "stock_number": "13047257",
            "source_received_at": "2026-01-01T00:00:00+00:00",
            "subject": "Vehicle", "action_type": "historical_reconciliation",
            "summary": "Vehicle", "evidence_hash": "e" * 64,
            "observations": {"stock": "13047257"},
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
                 "extraction": {"contract_version": "pmb-email-work-v2", "email_vehicle": {
                     "customer_name": "Customer", "vehicle_description": "Hilux", "job_card_number": "J1",
                     "stock_numbers": ["13047257"], "vins": ["MR0TESTVIN0000001"],
                 }, "operation_lines": [{"operation_no": "OP1", "description": "Known zero", "estimated_hours": 0}],
                 "required_work": ["fitting"]}},
            ],
        }
        request = self.module.build_historical_request(row)
        self.assertEqual(set(request), {
            "action_type", "attachment_manifest", "authentication", "evidence_hash", "job_card_children",
            "manifest_high_water_uid", "manifest_sha256", "manifest_uid_count", "manifest_uidvalidity",
            "gateway_instance_id", "release_manifest_sha256", "release_name", "release_source_sha",
            "observations", "parent_source_hash", "provider_uid", "sender_email", "source_metadata",
            "stock_number", "subject", "summary",
        })
        self.assertNotIn("intake_id", request)
        self.assertNotIn("attachment_id", json.dumps(request))
        self.assertEqual(request["source_metadata"]["internet_message_id"], "<message@example.test>")
        self.assertEqual(request["attachment_manifest"][0]["sha256"], "b" * 64)
        self.assertEqual(request["job_card_children"][0]["attachment_hash"], "c" * 64)
        self.assertEqual(request["job_card_children"][0]["extraction"]["operation_lines"][0]["estimated_hours"], 0)


if __name__ == "__main__":
    unittest.main()
