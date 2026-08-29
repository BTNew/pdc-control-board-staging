import importlib.util
import unittest
from pathlib import Path
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "supabase/staging_only/20260830173000_782_historical_reconciliation_current_head_security_successor.sql"
CALLER = ROOT / "pdc_historical_778_caller.py"


class HistoricalAdapter782ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = SQL.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()
        cls.caller = CALLER.read_text(encoding="utf-8").lower()

    def test_candidate_exists_and_parses(self):
        self.assertTrue(SQL.is_file())
        self.assertGreaterEqual(len(parse_sql(self.sql)), 10)

    def test_exact_current_head_and_dependency_pin(self):
        for marker in (
            "lock table supabase_migrations.schema_migrations in exclusive mode",
            "20260830172000",
            "778_historical_reconciliation_receipt_and_occurrence_repair",
            "statements=array[",
            "6497f2ba7ad244ea414f26d80400a3fa4bff2bf090746fdaa4cad800cbe53cfb",
            "f4f6f14d094afc04c110c72ca6d6d2c642bf6bf2fa8a96f59d3115793a6accd8",
            "f73dd525e5dc6caccde4d5658bea8a2cabd95ec7f55898b792e5984568de5950",
            "9bd5a567213e77dd4fb3ff45fa7031443444707505e576a3c17ace1c7c6699dd",
            "ff68e5580c8a77701eb5f92ef6a0b6ad99a44f0036185e60900a4292775870f1",
            "owner",
            "proconfig",
            "aclexplode",
            "pdc_782_dependency_contract_drift",
            "pdc_782_trigger_contract_drift",
        ):
            self.assertIn(marker, self.lower)

    def test_exact_job_card_kind_ordinal_hash_binding(self):
        for marker in (
            "pdc_historical_job_card_attachments_782",
            "attachment_kind",
            "attachment_ordinal",
            "pdc_782_job_card_kind_mismatch",
            "pdc_782_child_occurrence_mismatch",
            "pdc_782_child_cardinality_failed",
            "extraction_hash",
            "pdc_782_child_attachment_nonunique",
        ):
            self.assertIn(marker, self.lower)

    def test_atomic_post_enqueue_and_authoritative_state(self):
        for marker in (
            "pdc_782_enqueue_failed",
            "pdc_782_intake_binding_failed",
            "pdc_782_attachment_binding_failed",
            "pdc_782_parent_observation_failed",
            "pdc_782_child_import_failed",
            "pdc_782_protected_boundary_drift",
            "pdc_782_authoritative_state_failed",
            "exception when others",
            "pdc_historical_782_boundary_snapshot",
            "booking_created',v_booking_created",
            "completion_created',v_completion_created",
            "location_scheduled',v_location_scheduled",
            "parts_changed',v_parts_changed",
        ):
            self.assertIn(marker, self.lower)
        self.assertNotIn("booking_created',false", self.lower)
        self.assertNotIn("completion_created',false", self.lower)
        self.assertNotIn("location_scheduled',false", self.lower)

    def test_security_lifetime_replay_and_scope(self):
        for marker in (
            "authorized_at+interval '24 hours'",
            "historical_authorization_expired",
            "historical_replay_conflict",
            "pdc_782_old_mail_completed",
            "pdc_778_exact_authorization_failed",
            "13056899",
            "1:197",
            "manifest_uidvalidity",
            "manifest_high_water_uid",
            "manifest_uid_count",
            "read_pdc_historical_reconciliation_778_receipt",
            "revoke all on function public.submit_pdc_historical_reconciliation_778(jsonb)",
            "grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to authenticated",
        ):
            self.assertIn(marker, self.lower)

    def test_caller_binds_manifest_kind_and_occurrence(self):
        for marker in ("attachment_kind", "ordinal", "attachment_ordinal"):
            self.assertIn(marker, self.caller)
        self.assertIn('"attachment_kind": kind', self.caller)

    def test_frozen_row_level_children_are_rehydrated(self):
        spec = importlib.util.spec_from_file_location("historical_778", CALLER)
        module = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(module)
        row = {
            "manifest_sha256": module.MANIFEST_SHA256,
            "provider_uid": "1:22",
            "parent_source_hash": "a" * 64,
            "sender_email": "andy.weir@broometoyota.com.au",
            "authentication": {"gmail_authentication_results": True},
            "stock_number": "13047257",
            "source_received_at": "2026-01-01T00:00:00+00:00",
            "source_metadata": {"received_at": "2026-01-01T00:00:00+00:00", "attachment_names": ["Pick.pdf"]},
            "subject": "Vehicle", "action_type": "review_only", "summary": "Vehicle",
            "evidence_hash": "e" * 64, "observations": {},
            "attachments": [{"attachment_kind": "job_card", "content_type": "application/pdf", "filename": "Pick.pdf", "ordinal": 1, "sha256": "c" * 64, "size": 10}],
            "job_card_children": [{"attachment_hash": "c" * 64, "attachment_kind": "job_card", "extraction_hash": "d" * 64, "extraction": {"email_vehicle": {"job_card_number": "J1"}}}],
        }
        request = module.build_historical_request(row)
        self.assertEqual(len(request["job_card_children"]), 1)
        self.assertEqual(request["job_card_children"][0]["attachment_ordinal"], 1)
        self.assertEqual(request["job_card_children"][0]["extraction"]["email_vehicle"]["job_card_number"], "J1")


if __name__ == "__main__":
    unittest.main()
